#!/bin/bash
# Kill AFL instances that have stopped making progress.
#
# launch.sh wraps each instance in `while true; do afl-fuzz ...; sleep 10; done`,
# which restarts an instance that EXITS. It does nothing for one that hangs:
# zf01 (the -M main) spun at 96% CPU for 50 minutes without advancing
# .cur_input or writing fuzzer_stats, so afl-fuzz itself was looping rather
# than executing the target -- most likely inside the custom mutator. The
# supervisor never noticed because the process was still alive.
#
# fuzzer_stats is written every ~60s by a healthy instance, so an mtime older
# than STALL_S means the instance is wedged. SIGKILL makes the supervising
# loop restart it.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$SRC/out/campaign}
STALL_S=${STALL_S:-600}     # frozen mid-execution = hung
START_S=${START_S:-3600}    # still loading the corpus = be patient
LOG=$SRC/watchdog.log

now=$(date +%s)
for d in "$OUT"/*/; do
    id=$(basename "$d")
    # Liveness comes from .cur_input, not fuzzer_stats. AFL rewrites .cur_input
    # for EVERY execution, the dry run included; it only writes fuzzer_stats
    # once calibration is over. Calibrating this 18k-entry corpus takes far
    # longer than STALL_S, so judging by fuzzer_stats killed zf01 and zf03
    # mid-calibration and put them in a kill -> restart -> recalibrate loop
    # that never finished. .cur_input frozen while the process burns CPU is
    # exactly the signature of the hang this watchdog exists for.
    # Two different states need two different patiences.
    #
    # .cur_input exists => the instance reached the execution loop, and AFL
    # rewrites it on every single exec. Frozen for STALL_S there is a hang.
    #
    # .cur_input missing => still starting up: reading an 18k-entry queue and
    # the matching trees, which is CPU-bound and slow. Measured: zf01/02/03 sat
    # at 76-84% CPU with no .cur_input at all, which the earlier version read as
    # "stalled" and killed -- so they restarted, began the same load again, and
    # never once reached the fuzzing loop. Give startup its own, much longer
    # budget instead of sharing the hang threshold.
    probe="$d/.cur_input"
    if [ -f "$probe" ]; then
        limit=$STALL_S
    else
        probe="$d/fuzzer_stats"
        limit=$START_S
        [ -f "$probe" ] || continue
    fi
    age=$(( now - $(stat -c %Y "$probe") ))
    [ "$age" -lt "$limit" ] && continue
    # Only ever an afl-fuzz process. `pgrep -f -- "-[MS] $id"` also matches the
    # supervising `while true; do afl-fuzz ...; done` shell, and killing that
    # shell removes the thing that would restart the instance -- when the shell
    # owning the tmux session died it took every other window with it and the
    # whole campaign stopped. Enumerate afl-fuzz by name, then read argv.
    pid=""
    for p in $(pgrep -x afl-fuzz); do
        tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -qE -- "-[MS] $id( |$)" && { pid=$p; break; }
    done
    [ -n "$pid" ] || continue
    # A just-restarted instance inherits the previous run's fuzzer_stats and
    # does not rewrite it until calibration ends, so by mtime alone it looks
    # stalled from the moment it starts -- this killed a healthy zf01 seconds
    # after launch. Trust the age of the process, not just of the file.
    uptime_s=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$uptime_s" ] || continue
    [ "$uptime_s" -lt "$limit" ] && continue
    echo "$(date -Is) $id stalled ${age}s (pid $pid, up ${uptime_s}s) - killing so the supervisor restarts it" >> "$LOG"
    kill -9 "$pid" 2>/dev/null
done
