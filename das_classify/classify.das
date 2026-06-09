// classify.das — classify many daScript inputs and group failures.
//
// For each input file the driver shells out to daslang_static as the oracle:
//   1. run `-jit`; if it prints a CRASH marker  -> crash (mode=jit)
//   2. else run `-aot`; if that crashes         -> crash (mode=aot)
//   3. else exit 0                              -> normal
//   4. else (nonzero, no crash)                 -> compile/runtime error
// Crashers are re-run under gdb (only crashers — two-tier) to capture a
// backtrace; the top frames become the grouping signature.
//
// Why shell to daslang instead of calling compile_da_script in-process:
// the fuzzer's crashes live in the JIT/AOT codegen pipeline (e.g. a null
// TypeDecl deref in const-folding). The in-process rtti compile() stops at
// the type error *before* those passes run, so it never reproduces them.
// Subprocess also isolates the crash — it kills the child, not this driver.
//
// Inputs are complete .das programs (the fuzz corpus). Parallelised over the
// daslib/jobque_boost thread pool.
//
// Run:
//   daslang_static -dasroot <root> classify.das -- <input_dir> [out_dir] [binary] [dasroot]
// e.g.
//   D2=$HOME/daScript2/daScript2
//   $D2/bin/daslang_static -dasroot $D2 das_classify/classify.das -- crashes_flat

options gen2

require daslib/fio
require daslib/jobque_boost
require daslib/strings_boost
require daslib/clargs
require strings

// ---- command-line args (daslib/clargs generates the parser) ----------------
[CommandLineArgs]
struct Args {
    @clarg_positional
    @clarg_doc = "directory of .das inputs to classify"
    input_dir : string

    @clarg_doc = "output directory for grouped results"
    out : string = "crash_groups_das"

    @clarg_doc = "daslang_static binary (full build, has popen_argv)"
    bin : string = "/home/alexey-churkin/daScript2/daScript/bin/daslang_static"

    @clarg_doc = "daslang root, passed as -dasroot (must match bin)"
    dasroot : string = "/home/alexey-churkin/daScript2/daScript"
}

// Args is threaded into the worker functions as a parameter (NOT via globals):
// jobque clones each job's context and re-runs global initializers, so a global
// set in main would reset to its initializer inside a job. Captured params clone
// correctly. GDB/CLANG/TIMEOUT/TOP_N/MEM_LIMIT are literal consts — clone-safe.
let GDB     = "gdb"
let CLANG   = "clang++"
let TIMEOUT = 30.0
let TOP_N   = 5
let MEM_LIMIT = 524288000               // 500 MB MemoryMax (cgroup) per child

struct Res {
    path : string
    kind : string   // normal | compile_error | crash | timeout
    mode : string   // jit | aot | ""
    sig  : string
}

// ---- small helpers ---------------------------------------------------------

def contains(arr : array<string>; s : string) : bool {
    for (x in arr) {
        if (x == s) { return true }
    }
    return false
}

def basename(p : string) : string {
    let parts <- split(p, "/")
    return empty(parts) ? p : parts[length(parts) - 1]
}

// Cap the child's physical memory via a transient cgroup (systemd scope) so
// memory-exhausting inputs get OOM-killed (rc 9) instead of taking down the
// host. RLIMIT_AS is unusable here — the 180MB static binary needs more than
// 500MB of *virtual* address space just to start. MemoryMax limits RSS.
def limited(cmd : array<string>) : array<string> {
    // CollectMode=inactive-or-failed: a scope whose child is OOM-killed lands in
    // 'failed' state, which systemd keeps forever by default — at thousands of
    // runs those linger and eventually wedge the user manager. This GC's them.
    var out <- ["systemd-run", "--user", "--scope", "--quiet",
                "-p", "CollectMode=inactive-or-failed",
                "-p", "MemoryMax={MEM_LIMIT}", "-p", "MemorySwapMax=0", "--"]
    for (c in cmd) { out |> push(c) }
    return <- out
}

def is_crash(out : string) : bool {
    return find(out, "CRASH:") >= 0 || find(out, "Program received signal") >= 0
}

// Internal compiler invariant failures: DAS_VERIFY trips ("verify failed: ...")
// or the env Initialize/Shutdown balance check fires at exit. These exit nonzero
// with NO signal and NO "CRASH:" marker, so is_crash misses them and they'd be
// silently lumped into compile_error fuzzer-noise — but they are real bugs.
def is_assert(out : string) : bool {
    return find(out, "verify failed:") >= 0 || find(out, "Initialize/Shutdown not balanced") >= 0
}

// Signature for an assert: the "verify failed: <cond>, <file>:<line>" lines with
// the absolute path reduced to a basename so it groups across machines.
def normalize_assert(out : string) : string {
    var msgs : array<string>
    for (ln in split(out, "\n")) {
        let i = find(ln, "verify failed:")
        if (i >= 0) {
            var m = strip(slice(ln, i))
            let c = find(m, ", ")               // "..., <abspath>:<line>" -> basename
            if (c >= 0) { m = "{slice(m, 0, c)}, {basename(strip(slice(m, c + 2)))}" }
            if (!contains(msgs, m)) { msgs |> push(m) }
        }
        if (length(msgs) >= 3) { break }
    }
    if (empty(msgs) && find(out, "Initialize/Shutdown not balanced") >= 0) {
        msgs |> push("env Initialize/Shutdown not balanced")
    }
    if (empty(msgs)) { msgs |> push("ASSERT_UNKNOWN") }
    return join(msgs, " || ")
}

// Reduce one gdb backtrace line to a stable frame key; "" if not a frame.
// Two gdb formats, depending on whether the build carries source-line info:
//   with debug lines:  "#N 0x.. in FUNC (args) at file:line"   -> "func@file:line"
//   stripped library:  "#N 0x.. in FUNC () from lib.so"        -> "FUNC"
// Without the second case, a stripped .so (e.g. liblibDaScriptDyn_runtime.so)
// yields no " at " on any line, every frame parses to "", and gdb_sig collapses
// to the constant "UNPARSED" -> unrelated crashes merge into one group.
def extract_frame(line : string) : string {
    let s = strip(line)
    if (!starts_with(s, "#")) { return "" }
    let inpos = find(line, " in ")
    let atpos = find(line, " at ")
    if (atpos < 0) {
        // No source location. Key on the demangled signature between " in " and
        // the " from <lib>" suffix, dropping gdb's trailing " ()" no-args marker.
        if (inpos < 0) { return "" }
        var fn = slice(line, inpos + 4)
        let frompos = find(fn, " from ")
        if (frompos >= 0) { fn = slice(fn, 0, frompos) }
        fn = strip(fn)
        let n = length(fn)
        if (n >= 3 && slice(fn, n - 3) == " ()") { fn = strip(slice(fn, 0, n - 3)) }
        return fn
    }
    let paren = find(line, " (")
    var fn = ""
    if (inpos >= 0 && (paren < 0 || inpos < paren)) {
        let endf = (paren >= 0 && paren > inpos) ? paren : length(line)
        fn = slice(line, inpos + 4, endf)
    } else {
        let dsp = find(line, "  ")            // two spaces after the frame number
        let start = dsp >= 0 ? dsp + 2 : 0
        let endf = (paren >= 0 && paren > start) ? paren : length(line)
        fn = slice(line, start, endf)
    }
    var pl = slice(line, atpos + 4)           // "path:line ..." after " at "
    let sp = find(pl, " ")
    if (sp >= 0) { pl = slice(pl, 0, sp) }
    return "{strip(fn)}@{basename(pl)}"
}

// Group bad AOT C++ by clang's "error:" lines (drop the file:line:col prefix).
def normalize_clang(out : string) : string {
    var msgs : array<string>
    for (ln in split(out, "\n")) {
        let i = find(ln, "error:")
        if (i >= 0) {
            let m = strip(slice(ln, i))
            if (!contains(msgs, m)) { msgs |> push(m) }
        }
        if (length(msgs) >= 3) { break }
    }
    if (empty(msgs)) { msgs |> push("AOT_CXX_UNKNOWN") }
    return join(msgs, " || ")
}

// daslang argv for a given run mode. -aot is a leading subcommand:
//   daslang -aot <in> <out.cpp> -dasroot <root>
// whereas plain/jit take -dasroot/-jit before the script.
def das_argv(cfg : Args; path : string; mode : string) : array<string> {
    if (mode == "aot") {
        return <- [cfg.bin, "-aot", path, "{cfg.out}/.aot_tmp/{hash(path)}.cpp", "-dasroot", cfg.dasroot]
    } elif (mode == "jit") {
        return <- [cfg.bin, "-dasroot", cfg.dasroot, "-jit", path]
    }
    return <- [cfg.bin, "-dasroot", cfg.dasroot, path]      // plain
}

// Re-run a confirmed crasher under gdb and build a top-N frame signature.
def gdb_sig(cfg : Args; path : string; mode : string) : string {
    var args <- [GDB, "-batch", "-nx", "-q",
                 "-ex", "set pagination off",
                 "-ex", "handle SIGPIPE nostop noprint pass",
                 "-ex", "run", "-ex", "bt 64", "-ex", "quit", "--args"]
    for (c in das_argv(cfg, path, mode)) { args |> push(c) }
    var out : string
    // Cap the whole gdb+child subtree: gdb re-runs the crasher, and a
    // memory-exhausting input here escapes the cap otherwise (gdb forks the
    // child, the scope captures the subtree). gdb itself is tiny.
    run_and_capture(limited(args), out, TIMEOUT + TIMEOUT)
    if (find(out, "Program received signal") < 0) { return "mode={mode}|NO_CRASH" }
    var frames : array<string>
    for (ln in split(out, "\n")) {
        let fr = extract_frame(ln)
        if (!empty(fr) && !contains(frames, fr)) {
            frames |> push(fr)
            if (length(frames) >= TOP_N) { break }
        }
    }
    if (empty(frames)) { return "mode={mode}|UNPARSED" }
    let body = join(frames, "|")
    return "mode={mode}|{body}"
}

def classify_one(cfg : Args; path : string) : Res {
    var r : Res
    r.path = path
    r.kind = "normal"

    // Try plain -> jit -> aot, stopping at the first mode that crashes.
    var sawOom = false
    var sawTimeout = false
    var plainRc = 0
    var plainOut = ""
    var idx = 0
    for (mode in ["plain", "jit", "aot"]) {
        var out : string
        let rc = run_and_capture(limited(das_argv(cfg, path, mode)), out, TIMEOUT)
        if (idx == 0) { plainRc = rc; plainOut = out }
        idx++
        if (is_crash(out)) {
            r.kind = "crash"; r.mode = mode; r.sig = gdb_sig(cfg, path, mode); return r
        }
        if (is_assert(out)) {
            r.kind = "assert"; r.mode = mode; r.sig = normalize_assert(out); return r
        }
        if (rc == popen_timed_out) { sawTimeout = true }
        if (rc == 9) { sawOom = true }          // SIGKILL == cgroup OOM
    }

    // No daslang crash. Compile the generated AOT C++ ("link" step): bad
    // codegen produces invalid C++ that clang rejects even though daslang
    // didn't crash. Mirrors das_fuzz's clang -fsyntax-only AOT check.
    let cpp = "{cfg.out}/.aot_tmp/{hash(path)}.cpp"
    if (stat(cpp).is_valid) {
        var cout : string
        let crc = run_and_capture(limited([CLANG, "-std=c++17", "-fsyntax-only",
                    "-I", "{cfg.dasroot}/include",
                    "-I", "{cfg.dasroot}/3rdparty/fmt/include",
                    "-I", "{cfg.dasroot}/modules/dasUnitTest", cpp]), cout, TIMEOUT)
        if (crc == 9) { sawOom = true }
        elif (crc == popen_timed_out) { sawTimeout = true }
        elif (crc != 0) {
            r.kind = "aot_cxx_error"; r.mode = "aot"; r.sig = normalize_clang(cout); return r
        }
    }

    if (sawOom)     { r.kind = "oom";     r.sig = "oom";     return r }
    if (sawTimeout) { r.kind = "timeout"; r.sig = "timeout"; return r }
    if (plainRc == 0) { return r }              // normal
    // Fail-to-compile is expected fuzzer noise — counted, not collected.
    r.kind = "compile_error"
    return r
}

def write_group(out : string; kind : string; sig : string; members : array<string>) : string {
    let id = "{hash(sig)}"
    let gdir = "{out}/{kind}/{id}"
    mkdir(gdir)
    fwrite("{gdir}/signature.txt", "{sig}\n")
    var ml = ""
    for (m in members) { ml += "{m}\n" }
    fwrite("{gdir}/members.txt", ml)
    if (!empty(members)) {
        fwrite("{gdir}/sample.input", fread(members[0]))
    }
    return "{kind}\t{id}\t{length(members)}\t{sig}"
}

[export]
def main {
    // clargs auto-generates --help/-h and the usage text from Args.
    // Returns -1 on clean parse, 0 if help was shown, 1 on parse error.
    var cfg = Args()
    if (parse_args_with_help(cfg, "das_classify/classify.das") != -1) { return }
    let input_dir = cfg.input_dir
    let out = cfg.out

    var files : array<string>
    dir(input_dir) $(name) {
        if (name != "." && name != "..") {
            files |> push("{input_dir}/{name}")
        }
    }
    print("inputs: {length(files)}\n")
    if (empty(files)) { return }

    mkdir(out)
    mkdir("{out}/.aot_tmp")
    mkdir("{out}/crash")
    mkdir("{out}/aot_cxx_error")
    mkdir("{out}/assert")

    var results : array<Res>
    with_job_que() {
        with_channel(length(files)) $(ch) {
            for (f in files) {
                new_job() @() {
                    let r = classify_one(cfg, f)
                    ch |> push_clone(r)
                    ch |> notify_and_release
                }
            }
            ch |> for_each_clone() $(r : Res#) {
                var c : Res
                c.path = clone_string(r.path)
                c.kind = clone_string(r.kind)
                c.mode = clone_string(r.mode)
                c.sig  = clone_string(r.sig)
                results |> push(c)
                if (length(results) % 50 == 0) {
                    print("progress: {length(results)}/{length(files)}\n")
                }
            }
        }
    }

    var crash_g  : table<string; array<string>>
    var aot_g    : table<string; array<string>>
    var assert_g : table<string; array<string>>
    var normals : array<string>
    var timeouts : array<string>
    var ooms : array<string>
    var cerr_count = 0          // expected fuzzer noise — counted, not collected
    for (r in results) {
        if (r.kind == "crash") {
            crash_g[r.sig] |> push(r.path)
        } elif (r.kind == "aot_cxx_error") {
            aot_g[r.sig] |> push(r.path)
        } elif (r.kind == "assert") {
            assert_g[r.sig] |> push(r.path)
        } elif (r.kind == "timeout") {
            timeouts |> push(r.path)
        } elif (r.kind == "oom") {
            ooms |> push(r.path)
        } elif (r.kind == "compile_error") {
            cerr_count++
        } else {
            normals |> push(r.path)
        }
    }

    var idx : array<string>
    idx |> push("kind\tid\tcount\tsignature")
    var crash_keys : array<string>
    for (k in keys(crash_g)) { crash_keys |> push(k) }
    for (sig in crash_keys) {
        idx |> push(write_group(out, "crash", sig, crash_g[sig]))
    }
    var aot_keys : array<string>
    for (k in keys(aot_g)) { aot_keys |> push(k) }
    for (sig in aot_keys) {
        idx |> push(write_group(out, "aot_cxx_error", sig, aot_g[sig]))
    }
    var assert_keys : array<string>
    for (k in keys(assert_g)) { assert_keys |> push(k) }
    for (sig in assert_keys) {
        idx |> push(write_group(out, "assert", sig, assert_g[sig]))
    }
    fwrite("{out}/index.tsv", join(idx, "\n") + "\n")
    fwrite("{out}/normal_list.txt", join(normals, "\n") + "\n")
    fwrite("{out}/timeouts.txt", join(timeouts, "\n") + "\n")
    fwrite("{out}/oom_list.txt", join(ooms, "\n") + "\n")

    print("normal={length(normals)}  compile_errors={cerr_count}  aot_cxx_error_groups={length(aot_g)}  assert_groups={length(assert_g)}  crash_groups={length(crash_g)}  timeouts={length(timeouts)}  oom={length(ooms)}\n")
    print("output in {out}/\n")
}
