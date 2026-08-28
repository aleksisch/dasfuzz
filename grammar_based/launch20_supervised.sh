#!/bin/bash
# Launch 20 AFL++ instances, each under a supervised restart loop.
#
# Why supervised: libgrammarmutator-type.so null-derefs (same site, offset
# 0x9360d) and takes the host afl-fuzz process down with it -- custom mutators
# run in-process. Observed 5 deaths in 7 minutes. AFL_AUTORESUME=1 makes an
# immediate restart resume that instance's own state, so the loop costs
# seconds of throughput instead of waiting for the periodic watchdog.
set -euo pipefail
cd "$(dirname "$0")"
SRC=$PWD
N=${N:-20}
SESSION=${SESSION:-fuzz}
OUT=${OUT:-$SRC/out_clean}
SEEDS=${SEEDS:-/dev/shm/das_seeds}
CORPUS=${CORPUS:-/dev/shm/das_corpus}
BIN=$SRC/build_afl/das_fuzz
MUT=$SRC/modules/Grammar-Mutator/src
AFL=${AFL:-$HOME/work/AFLplusplus/afl-fuzz}

export LD_LIBRARY_PATH=$MUT
export TREES_PATH=${TREES_PATH:-/dev/shm/das_trees}
export AFL_CUSTOM_MUTATOR_LIBRARY=$MUT/libgrammarmutator-type.so
export AFL_CUSTOM_MUTATOR_ONLY=1
export AFL_SKIP_CPUFREQ=1
export AFL_NO_AFFINITY=1
export AFL_AUTORESUME=1
export AFL_IMPORT_FIRST=1

for dep in "$BIN" "$AFL" "$AFL_CUSTOM_MUTATOR_LIBRARY" "$SEEDS" "$TREES_PATH"; do
    [[ -e $dep ]] || { echo "missing: $dep" >&2; exit 1; }
done
tmux has-session -t "$SESSION" 2>/dev/null && { echo "session $SESSION exists; kill it first" >&2; exit 1; }
mkdir -p "$OUT"

# $1 = instance id, $2 = afl args -> a self-restarting supervised command
sup() {
    local id=$1; shift
    echo "while true; do for p in \$(pgrep -x das_fuzz); do [ \"\$(ps -o ppid= -p \$p 2>/dev/null | tr -d ' ')\" = 1 ] && kill -9 \$p 2>/dev/null; done; $AFL $* -o $OUT -- $BIN; echo \"\$(date -Is) $id exited rc=\$? - restarting\" >> $SRC/restarts.log; sleep 15; done"
}

tmux new-session -d -s "$SESSION" -n fuzzer01 "$(sup fuzzer01 -t 3000 -M fuzzer01 -i "$CORPUS")"

SCHED=(fast coe explore exploit rare seek lin quad mmopt)
for i in $(seq 2 "$N"); do
    id=$(printf "fuzzer%02d" "$i")
    p=${SCHED[$(( (i-2) % ${#SCHED[@]} ))]}
    tmux new-window -d -t "$SESSION:$i" -n "$id" "$(sup "$id" -t 3000 -p "$p" -S "$id" -i "$SEEDS")"
done
echo "launched $N supervised instances in tmux session $SESSION"
