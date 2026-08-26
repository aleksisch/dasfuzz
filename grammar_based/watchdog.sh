#!/bin/bash
# Restart any AFL instance whose tmux window is no longer running afl-fuzz.
# Safe: AFL_AUTORESUME=1 makes a restart resume that instance's own state.
#
# Why instances die: a null-pointer deref inside libgrammarmutator-type.so.
# Custom mutators are loaded in-process by afl-fuzz, so a fault in the mutator
# kills the fuzzer itself (confirmed in dmesg: "segfault at 0 ... in
# libgrammarmutator-type.so"). Rare, but silent -- it leaves an idle tmux
# window and you lose that instance's throughput without any error surfacing.
cd "$(dirname "$0")" || exit 1
SRC=$PWD
MUT=$SRC/modules/Grammar-Mutator/src
AFL=${AFL:-$HOME/work/AFLplusplus/afl-fuzz}
SCHED=(fast coe explore exploit rare seek lin quad mmopt)
LOG=$SRC/watchdog.log

for i in $(seq 1 20); do
    id=$(printf "fuzzer%02d" "$i")
    tmux list-windows -t fuzz -F "#{window_name}" 2>/dev/null | grep -qx "$id" || continue
    # a live instance has a running afl-fuzz whose cmdline names it
    if pgrep -fa afl-fuzz 2>/dev/null | grep -qE -- "-[MS] $id( |$)"; then
        continue
    fi
    if [ "$i" = 1 ]; then
        cmd="$AFL -t 3000 -M fuzzer01 -i /dev/shm/das_corpus -o $SRC/out_clean -- $SRC/build_afl/das_fuzz"
    else
        p=${SCHED[$(( (i-2) % 9 ))]}
        cmd="$AFL -t 3000 -p $p -S $id -i /dev/shm/das_seeds -o $SRC/out_clean -- $SRC/build_afl/das_fuzz"
    fi
    echo "$(date -Is) restarting $id" >> "$LOG"
    tmux send-keys -t "fuzz:$id" "LD_LIBRARY_PATH=$MUT TREES_PATH=/dev/shm/das_trees AFL_CUSTOM_MUTATOR_LIBRARY=$MUT/libgrammarmutator-type.so AFL_CUSTOM_MUTATOR_ONLY=1 AFL_SKIP_CPUFREQ=1 AFL_AUTORESUME=1 AFL_IMPORT_FIRST=1 $cmd" C-m
    echo "restarted $id"
done
