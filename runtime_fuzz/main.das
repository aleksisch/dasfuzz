options gen2
options persistent_heap
options gc

require daslib/strings_boost
require daslib/random
require daslib/fio
require daslib/clargs

require bricks
require assembler
require executor

// --- Configuration ---

[CommandLineArgs]
struct Config {
    @clarg_skip
    p_blk : float = 0.16

    @clarg_doc = "Max statements per test (default: 8)"
    i_max : int = 8

    @clarg_doc = "Number of test cases (default: 10000)"
    num_tests : int = 10000

    @clarg_doc = "Random seed (default: time-based)"
    seed : int = 0

    @clarg_doc = "Crash output directory (default: crashes)"
    crash_dir : string = "crashes"

    @clarg_name = "bin"
    @clarg_doc = "Path to daslang binary (default: bin/daslang)"
    daslang_bin : string = "bin/daslang"

    @clarg_name = "timeout"
    @clarg_doc = "Execution timeout in ms (default: 5000)"
    timeout_ms : int = 5000

    @clarg_doc = "Print generated programs"
    verbose : bool = false

    @clarg_doc = "Flag GC-leak stdout markers as findings (noisy)"
    detect_leaks : bool = false

    @clarg_doc = "Emit-only mode: write generated programs to this directory"
    emit_dir : string = ""

    @clarg_doc = "Number of programs to emit in emit-only mode"
    emit_count : int = 0
}

[export]
def main() {
    var r <- parse_args(type<Config>)
    if (r |> is_err) {
        print("error: {r |> unwrap_err}\n\n")
        print_help(get_command_info(type<Config>), "runtime_fuzz/main.das")
        return
    }
    var cfg <- r |> move_unwrap
    let s = cfg.seed != 0 ? cfg.seed : int(ref_time_ticks())
    rng_seed = random_seed(s)
    var pool : BrickPool
    init_arithmetic_bricks(pool)
    print("Brick pool: {length(pool.bricks)} bricks\n")
    // Emit-only mode: generate programs to disk for an external batch runner
    // (batch_hunt.sh runs many per daslang process to amortize startup). No execution here.
    if (cfg.emit_dir != "") {
        mkdir(cfg.emit_dir)
        for (i in range(cfg.emit_count)) {
            var program = assemble(pool, cfg.i_max, cfg.p_blk)
            // Inject a provenance marker as the first line of main(): each program
            // prints "#F p_<i>" before its result, so a differential that runs many
            // programs in one process can align outputs BY PROGRAM (not by line) and
            // attribute any divergence to a file. Without this, variable-length output
            // (e.g. logging bricks) misaligns a naive line-diff and fakes divergences.
            program = program |> replace("def main() \{\n", "def main() \{\n    print(\"#F p_{i}\\n\")\n")
            fopen("{cfg.emit_dir}/p_{i}.das", "wb") <| $(f) {
                fwrite(f, program)
            }
        }
        print("Emitted {cfg.emit_count} programs to {cfg.emit_dir}\n")
        return
    }
    var total_crashes = 0
    var total_compile_errors = 0
    var total_mismatches = 0
    var total_timeouts = 0
    var total_runtime_errors = 0
    var total_jit_compile_fails = 0
    var total_ok = 0
    mkdir(cfg.crash_dir)
    for (test_id in range(cfg.num_tests)) {
        let program = assemble(pool, cfg.i_max, cfg.p_blk)
        if (cfg.verbose) {
            print("=== Test {test_id} ===\n{program}\n")
        }
        let result = execute(program, cfg.daslang_bin, cfg.timeout_ms, cfg.detect_leaks)
        if (result == ExecResult.CRASH) {
            total_crashes++
            let crash_file = "{cfg.crash_dir}/crash_{test_id}.das"
            fopen(crash_file, "wb") <| $(f) {
                fwrite(f, program)
            }
            print("[CRASH] Test {test_id} -> {crash_file}\n")
        } elif (result == ExecResult.HASH_MISMATCH) {
            total_mismatches++
            let mismatch_file = "{cfg.crash_dir}/mismatch_{test_id}.das"
            fopen(mismatch_file, "wb") <| $(f) {
                fwrite(f, program)
            }
            print("[MISMATCH] Test {test_id} -> interp vs jit differ -> {mismatch_file}\n")
        } elif (result == ExecResult.RUNTIME_ERROR) {
            total_runtime_errors++
            let rt_file = "{cfg.crash_dir}/runtime_{test_id}.das"
            fopen(rt_file, "wb") <| $(f) {
                fwrite(f, program)
            }
            print("[RUNTIME] Test {test_id} -> sanitizer/leak marker -> {rt_file}\n")
        } elif (result == ExecResult.JIT_COMPILE_FAIL) {
            total_jit_compile_fails++
            let jit_file = "{cfg.crash_dir}/jitfail_{test_id}.das"
            fopen(jit_file, "wb") <| $(f) {
                fwrite(f, program)
            }
            print("[JIT-FAIL] Test {test_id} -> interp ok, JIT rejected -> {jit_file}\n")
        } elif (result == ExecResult.COMPILE_ERROR) {
            total_compile_errors++
        } elif (result == ExecResult.TIMEOUT) {
            total_timeouts++
        } else {
            total_ok++
        }
        if ((test_id + 1) % 100 == 0) {
            print("Progress: {test_id + 1}/{cfg.num_tests} | ok={total_ok} err={total_compile_errors} crash={total_crashes} mismatch={total_mismatches} rterr={total_runtime_errors} jitfail={total_jit_compile_fails} timeout={total_timeouts}\n")
        }
    }
    print("\n=== Done ===\n")
    print("Total: {cfg.num_tests} | OK: {total_ok} | Compile errors: {total_compile_errors} | Crashes: {total_crashes} | Mismatches: {total_mismatches} | Runtime errors: {total_runtime_errors} | JIT compile fails: {total_jit_compile_fails} | Timeouts: {total_timeouts}\n")
}
