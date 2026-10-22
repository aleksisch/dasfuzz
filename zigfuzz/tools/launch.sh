#!/bin/bash
# Launch an AFL++ campaign against the instrumented zig compiler.
#
# The target is `zig ast-check @@`: parser + AstGen only, ~7ms a run. Sema costs
# 0.8s a run, which is 100x the budget per execution, so it is left to an
# offline second stage over the saved corpus rather than put in the fuzz loop.
set -eu
SRC=$(cd "$(dirname "$0")/.." && pwd)
AFL=${AFL:-$HOME/work/AFLplusplus/afl-fuzz}
BIN=${BIN:-$SRC/zig-afl/bin/zig}
MUT=$SRC/modules/Grammar-Mutator/src
SEEDS=${SEEDS:-$SRC/seeds}
TREES=${TREES:-$SRC/trees}
OUT=${OUT:-$SRC/out/campaign}
N=${N:-4}

[ -x "$BIN" ] || { echo "no instrumented zig at $BIN" >&2; exit 1; }
[ -d "$SEEDS" ] && [ -n "$(ls -A "$SEEDS" 2>/dev/null)" ] || { echo "no seeds in $SEEDS" >&2; exit 1; }
mkdir -p "$OUT"

# Measured with AFL_DUMP_MAP_SIZE=1 against the instrumented binary. Without
# it afl-fuzz refuses to start ("required size is very large"), and in the
# daScript campaign a missing AFL_MAP_SIZE made afl-cmin silently write an
# empty corpus, so it is pinned rather than left to autodetect.
export AFL_MAP_SIZE=${AFL_MAP_SIZE:-625511}
# core_pattern is now "core". It used to pipe crashes to apport, which made a
# SIGABRT take 1.17s to be reaped instead of 0.0018s and had afl-fuzz file real
# crashes as "results in a timeout" (verified by A/B on a deliberately crashing
# target). The preload stays: PR_SET_DUMPABLE(0) means the kernel writes no core
# file at all, so a crash costs nothing and the disk -- 98% full -- stays that
# way. It does not affect instrumentation; showmap captures 710 tuples either
# way. If core_pattern ever goes back to a pipe (a reboot restores apport),
# afl-fuzz will refuse to start rather than silently mislabel crashes.
export AFL_PRELOAD="$SRC/tools/nodump.so"
# Governor is ondemand and changing it needs root; costs speed, not accuracy.
export AFL_SKIP_CPUFREQ=1
export AFL_AUTORESUME=1 AFL_IMPORT_FIRST=1 AFL_FAST_CAL=1
export AFL_TESTCACHE_SIZE=500
export AFL_CUSTOM_MUTATOR_LIBRARY="$MUT/libgrammarmutator-zig.so"
export AFL_CUSTOM_MUTATOR_ONLY=1
export LD_LIBRARY_PATH="$MUT${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export TREES_PATH="$TREES"
# The compiler writes a cache; give each instance its own so they do not collide.
tmux kill-session -t zigfuzz 2>/dev/null || true

for i in $(seq 1 "$N"); do
    id=$(printf 'zf%02d' "$i")
    if [ "$i" = 1 ]; then role="-M $id"; else role="-S $id"; fi
    cache="$SRC/caches/$id"
    mkdir -p "$cache"
    cmd="ZIG_LOCAL_CACHE_DIR=$cache ZIG_GLOBAL_CACHE_DIR=$cache \
         $AFL -t 5000 -m none $role -i $SEEDS -o $OUT -- $BIN ast-check @@"
    loop="while true; do $cmd; echo \"\$(date -Is) $id exited rc=\$?\" >> $SRC/restarts.log; sleep 10; done"
    if [ "$i" = 1 ]; then
        tmux new-session -d -s zigfuzz -n "$id" "$loop"
    else
        tmux new-window -t zigfuzz -n "$id" "$loop"
    fi
done
echo "launched $N instances in tmux session zigfuzz (out=$OUT)"
