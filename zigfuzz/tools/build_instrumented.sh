#!/bin/bash
# Build an AFL-instrumented zig compiler.
#
# `zig build` cannot do this on 0.17.0: Compile.zig declares
# sanitize_coverage_trace_pc_guard but the 0.17.0 build system serialises a
# module configuration instead of passing CLI flags, so the field is never
# plumbed through to the compiler. The invocation below is the one `zig build
# --verbose` emits for `--name zig`, with the instrumentation added by hand.
#
# -fllvm is required: the self-hosted backend accepts
# -fsanitize-coverage-trace-pc-guard and silently ignores it (0 edges), while the
# LLVM backend emits the calls. sancov_stub.o supplies __sancov_lowest_stack,
# which the pass references and AFL's runtime does not define.
set -eu
Z=$(cd "$(dirname "$0")/.." && pwd)
T=${T:-$Z/toolchain/zig-x86_64-linux-0.17.0/zig}
A=${A:-$HOME/work/AFLplusplus}
OPT=${OPT:--Osafe}
OUT=${OUT:-$Z/zig-afl/bin/zig}

cd "$Z/src/zig"
OPTIONS=$(ls -t .zig-cache/o/*/options.zig 2>/dev/null | head -1)
[ -n "$OPTIONS" ] || { echo "no options.zig in .zig-cache; run 'zig build -Dno-bin' first" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"

exec "$T" build-exe \
    -fllvm --stack 48234496 -fno-sanitize-thread "$OPT" \
    -fsanitize-coverage-trace-pc-guard \
    "$A/afl-compiler-rt.o" "$Z/tools/sancov_stub.o" -lc \
    --dep build_options -Mroot=src/main.zig "-Mbuild_options=$OPTIONS" \
    --cache-dir .zig-cache --global-cache-dir "$HOME/.cache/zig" \
    --build-root . --name zig \
    --zig-lib-dir "$Z/toolchain/zig-x86_64-linux-0.17.0/lib/" \
    "-femit-bin=$OUT"
