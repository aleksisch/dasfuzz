#!/bin/bash
# Launch 20 parallel AFL++ fuzzers (1 main + 19 secondary) in tmux.
# Shared output dir: ./out. Reattach: `tmux attach -t fuzz`.
set -euo pipefail

N=${N:-20}
SESSION=${SESSION:-fuzz}
SRC=${SRC:-/src}
OUT=${OUT:-./out}
SEEDS=${SEEDS:-./seeds}
TREES=${TREES:-./trees}
BIN=${BIN:-$SRC/build/das_fuzz}
MUT_DIR=$SRC/modules/Grammar-Mutator
AFL=${AFL:-/AFLplusplus/afl-fuzz}

export LD_LIBRARY_PATH=$MUT_DIR
export TREES_PATH=$TREES
export AFL_CUSTOM_MUTATOR_LIBRARY=$MUT_DIR/libgrammarmutator-type.so
export AFL_CUSTOM_MUTATOR_ONLY=1
export AFL_AUTORESUME=1

for dep in "$BIN" "$AFL" "$AFL_CUSTOM_MUTATOR_LIBRARY" "$SEEDS" "$TREES"; do
    [[ -e $dep ]] || { echo "missing: $dep" >&2; exit 1; }
done
command -v tmux >/dev/null || { echo "tmux not installed" >&2; exit 1; }

mkdir -p "$OUT"

if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "session '$SESSION' exist. kill or pick other SESSION=" >&2
    exit 1
fi

tmux new-session -d -s "$SESSION" -n fuzzer01 \
    "$AFL -t 2000 -M fuzzer01 -i $SEEDS -o $OUT -- $BIN; exec bash"

for i in $(seq 2 "$N"); do
    id=$(printf "fuzzer%02d" "$i")
    tmux new-window -d -t "$SESSION:$i" -n "$id" \
        "$AFL -t 2000 -S $id -i $SEEDS -o $OUT -- $BIN; exec bash"
done

echo "launched $N fuzzers in tmux session '$SESSION'"
echo "attach:   tmux attach -t $SESSION"
echo "status:   /AFLplusplus/afl-whatsup $OUT"
echo "stop all: tmux kill-session -t $SESSION"
