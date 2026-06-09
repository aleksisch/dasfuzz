#!/usr/bin/env bash
# Minimize das_classify's crash groups with afl-tmin, using a PER-CLASS oracle
# (class_oracle.sh) that checks the exact failure the group was classified by —
# so the minimized file is guaranteed to still reproduce that class:
#   crash         -> daslang (in the group's mode) faults
#   aot_cxx_error -> daslang -aot output fails clang -fsyntax-only
#   assert        -> daslang aborts on an assertion
# (das_fuzz's broad "any crash" drifts to a different bug; this doesn't.)
#
# The oracle reads the testcase from STDIN (no @@ -> no afl temp-file race) and
# exits 99 on reproduce (AFL_CRASH_EXITCODE=99). Non-instrumented, so no
# AFL_MAP_SIZE needed.
#
# Reads:  <results>/<KIND>/<sig>/{sample.input,signature.txt}
# Writes: <out>/<KIND>/<sig>.das
#
# Usage:  ./minimize_groups.sh [results_dir] [out_dir]
# Env:    BIN DASROOT TMIN_BIN JOBS T_MS WALL MEM_LIMIT  (sane defaults below)
set -uo pipefail
cd "$(dirname "$0")"

RESULTS="${1:-crash_groups_das}"
OUT="${2:-minimized}"
export BIN="${BIN:-$HOME/daScript2/daScript/bin/daslang_static}"
export DASROOT="${DASROOT:-$HOME/daScript2/daScript}"
TMIN="${TMIN_BIN:-$HOME/work/AFLplusplus/afl-tmin}"
JOBS="${JOBS:-4}"
export T_MS="${T_MS:-30000}" WALL="${WALL:-600}"
export MEM_LIMIT="${MEM_LIMIT:-500M}" TIMEOUT="${TIMEOUT:-30}"
ORACLE="$PWD/class_oracle.sh"

[[ -d "$RESULTS" ]] || { echo "no results dir: $RESULTS" >&2; exit 1; }
[[ -x "$BIN" ]]     || { echo "daslang not found: $BIN" >&2; exit 1; }
[[ -x "$TMIN" ]]    || { echo "afl-tmin not found: $TMIN" >&2; exit 1; }
[[ -f "$ORACLE" ]]  || { echo "class_oracle.sh missing next to this script" >&2; exit 1; }
chmod +x "$ORACLE" 2>/dev/null || true

# AFL_NO_FORKSRV=1: the oracle is a plain script (no afl instrumentation), so
# afl-tmin must execve it per run instead of expecting a forkserver handshake.
export AFL_NO_AFFINITY=1 AFL_SKIP_CPUFREQ=1 AFL_QUIET=1 AFL_CRASH_EXITCODE=99 AFL_NO_FORKSRV=1
ulimit -c 0   # no multi-GB cores filling disk
export TMIN OUT ORACLE
echo ">> jobs=$JOBS  $RESULTS -> $OUT  (per-class oracle)"

minone() {
    local g="$1" sig kind mode in o osz nsz rc
    in="$g/sample.input"
    [[ -s "$in" ]] || { echo "skip  $g (no sample.input)"; return 0; }
    sig=$(basename "$g"); kind=$(basename "$(dirname "$g")")
    o="$OUT/$kind/$sig.das"; mkdir -p "$OUT/$kind"
    [[ -s "$o" ]] && { echo "skip  $kind/$sig (done)"; return 0; }

    # mode: aot_cxx_error is always aot; others read mode= from signature.txt.
    if [[ "$kind" == aot_cxx_error ]]; then mode=aot
    else mode=$(sed -n 's/^mode=\([a-z]*\).*/\1/p' "$g/signature.txt" 2>/dev/null); fi
    [[ -n "$mode" ]] || mode=sim
    [[ "$mode" == plain ]] && mode=sim

    KIND="$kind" timeout "$WALL" "$TMIN" -m none -t "$T_MS" \
        -i "$in" -o "$o" -- "$ORACLE" "$mode" >/dev/null 2>&1
    rc=$?
    if [[ -s "$o" ]]; then
        osz=$(stat -c%s "$in"); nsz=$(stat -c%s "$o")
        echo "done  $kind/$sig [$mode]  ${osz}B -> ${nsz}B"
    else
        echo "FAIL  $kind/$sig [$mode]  (tmin rc=$rc: not reproduced / timeout)"
    fi
}
export -f minone

find "$RESULTS" -mindepth 2 -maxdepth 2 -type d -print0 \
    | xargs -0 -P "$JOBS" -n1 -I{} bash -c 'minone "$@"' _ {}

echo ">> done. minimized repros in: $OUT/<KIND>/<sig>.das"
