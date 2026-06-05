# das_classify

Classify many daScript inputs and group failures by signature — written in daScript.

Lives at the repo root (sibling to `grammar_based/` and `runtime_fuzz/`) because
it is **common to all fuzzers** — point it at any fuzzer's crash directory.

`classify.das` walks an input directory and, per file, shells out to
`daslang_static` as the oracle (parallelised over the `daslib/jobque_boost`
thread pool):

1. try **plain → jit → aot** in order (`daslang <f>`, `-jit`, `-aot <f> <out.cpp>`);
   the first mode that prints a `CRASH:` marker → **crash** (mode tagged in the signature)
2. else compile the generated AOT C++ with `clang++ -std=c++17 -fsyntax-only`
   ("link" step). clang rejects it → **aot_cxx_error** (bad codegen that didn't
   crash daslang). Mirrors `das_fuzz`'s libclang AOT check (commit a8f0687).
3. else plain exit 0 → **normal**
4. SIGKILL (rc 9) from the memory cap → **oom**
5. popen timeout → **timeout**
6. else (nonzero, no crash) → **compile_error** — expected fuzzer noise, only
   counted in the summary, not collected or grouped into folders

The `-aot` flag is a leading subcommand: `daslang -aot <in> <out.cpp> -dasroot
<root>` (not `-dasroot ... -aot`, which errors with `unknown command line
option aot`). The generated `.cpp` is self-contained (emits the daScript header
preamble), so clang compiles it with just the daScript/fmt/dasUnitTest `-I`
paths. `-fsyntax-only` (not a full link) matches das_fuzz and is far faster while
still catching invalid generated C++.

Each daslang child runs inside a transient cgroup (`systemd-run --user --scope
-p MemoryMax=500M -p MemorySwapMax=0`, see `MEM_LIMIT`) so memory-exhausting
inputs get OOM-killed instead of taking down the host. `RLIMIT_AS`/`ulimit -v`
is **not** usable here — the 180MB static binary needs >500MB of *virtual*
address space just to start; `MemoryMax` limits RSS, which is what we want. This
needs a systemd **user** session (D-Bus); on a headless/container host without
one, swap `limited()` for a cgroup the environment provides. gdb runs are not
capped (gdb + the 180MB binary exceed 500MB, and gdb only runs on real segfault
crashers, never the OOM ones).

Crashers (only) are re-run under `gdb -batch ... bt 64`; the top `TOP_N=5`
`func@file:line` frames (deduped) form the grouping signature — same scheme as
`group_crashes_gdb.sh`. Compile errors group by their `error[NNNNN]:` message.

## Why not in-process `compile_da_script`?

The fuzz crashes live in the JIT/AOT **codegen** pipeline (e.g. a null
`TypeDecl` deref in const-folding: `TypeDecl::isHandle (this=0x0)`). The
in-process rtti `compile()` stops at the type error *before* those passes run —
even with `cop.aot = true` — so it never reproduces them and would misclassify
every codegen-crasher as a plain compile error. Subprocess `-jit`/`-aot` also
isolates the crash (kills the child, not this driver).

## Run

Args are parsed by `daslib/clargs` (`[CommandLineArgs]` struct): `input_dir` is a
required positional; `--out`, `--bin`, `--dasroot` are optional flags with defaults.

```sh
# from the repo root (dasfuzz/)
D2=$HOME/daScript2/daScript2          # has popen_argv + matching daslib
$D2/bin/daslang_static -dasroot $D2 \
    das_classify/classify.das -- <input_dir> [--out DIR] [--bin PATH] [--dasroot PATH]

# example: grammar fuzzer crashes
$D2/bin/daslang_static -dasroot $D2 \
    das_classify/classify.das -- grammar_based/crashes_flat --out=grammar_based/crash_groups_das

# example: runtime fuzzer crashes (same tool, different input dir)
$D2/bin/daslang_static -dasroot $D2 \
    das_classify/classify.das -- runtime_fuzz/<crash_dir> --out=runtime_crash_groups
```

Note: use `daslang_static` (full build with the `popen_argv` builtin), **not**
the `bin/daslang` stub, and pass `-dasroot` so `require daslib/...` resolves.

clargs auto-generates `--help`/`-h` and the usage text. Caveat: the `daslang`
interpreter intercepts `-h`/`--help` for its own banner, so the generated help
only surfaces when the tool is built as a standalone `-exe`; the parse-error path
(e.g. missing `input_dir`) works under the interpreter.

## Output (`out_dir`, default `crash_groups_das/`)

```
index.tsv                       kind  id  count  signature
normal_list.txt                 inputs that compiled+ran clean
timeouts.txt
oom_list.txt                    inputs OOM-killed at the 500M cap
crash/<id>/signature.txt        gdb top-N frames (mode=plain|jit|aot prefix)
crash/<id>/members.txt          all inputs in this group
crash/<id>/sample.input         a representative input
aot_cxx_error/<id>/...           same layout, grouped by clang error: message
                                (compile_error is only counted, never written)
```

`id` is the hex hash of the signature. Tune `TIMEOUT` / `TOP_N` and the default
`BIN`/`DASROOT` at the top of `classify.das`.
