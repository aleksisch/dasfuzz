#!/usr/bin/env bash
# Per-class afl-tmin oracle. We KNOW each group's failure kind from its folder,
# so we minimize against that exact check instead of das_fuzz's broad "any
# crash" (which drifts). Reads the testcase from STDIN (afl-tmin feeds stdin when
# the target line has no @@) -> no .afl-temp file race. Memory-capped with
# `ulimit -v` -> no systemd/dbus. Exits 99 on reproduce (AFL_CRASH_EXITCODE=99),
# 0 otherwise.
#
# Args:  class_oracle.sh <mode>          mode = aot | jit | sim
#   (afl-tmin runs `-- ./class_oracle.sh <mode>` and pipes the testcase to stdin)
# Env (set by the runner):
#   KIND       crash | aot_cxx_error | assert
#   MODE       fallback if no CLI arg (aot | jit | sim)
#   BIN        daslang_static
#   DASROOT    -dasroot value
#   SIG        optional grep -E pattern the failure output must contain
#              (pins the specific bug so minimization can't drift to another)
#   MEM_LIMIT  ulimit -v cap, e.g. 500M   (default 500M)
#   TIMEOUT    per-run seconds            (default 30)
#   CLANG      clang++ (default)
set -u

: "${KIND:?KIND unset}"; : "${BIN:?BIN unset}"; : "${DASROOT:?DASROOT unset}"
MODE="${1:-${MODE:-sim}}"; SIG="${SIG:-}"
[[ "$MODE" == sim ]] && MODE=plain        # "sim" = interpreter = plain daslang run
MEM_LIMIT="${MEM_LIMIT:-500M}"; TIMEOUT="${TIMEOUT:-30}"; CLANG="${CLANG:-clang++}"
MEM_KB=$(( ${MEM_LIMIT%M} * 1024 ))

DAS=$(mktemp --suffix=.das); CPP=$(mktemp --suffix=.cpp)
trap 'rm -f "$DAS" "$CPP"' EXIT
cat > "$DAS"                         # testcase from stdin
[[ -s "$DAS" ]] || exit 0

# daslang argv for the run mode (matches classify.das das_argv()).
case "$MODE" in
    aot) set -- "$BIN" -aot "$DAS" "$CPP" -dasroot "$DASROOT" ;;
    jit) set -- "$BIN" -dasroot "$DASROOT" -jit "$DAS" ;;
    *)   set -- "$BIN" -dasroot "$DASROOT" "$DAS" ;;
esac

OUT=$( ( ulimit -v "$MEM_KB"; exec timeout "$TIMEOUT" "$@" ) 2>&1 ); rc=$?

case "$KIND" in
  aot_cxx_error)
    # daslang -aot must succeed and emit C++; the bug is clang rejecting it.
    [[ -s "$CPP" ]] || exit 0
    COUT=$(timeout "$TIMEOUT" "$CLANG" -std=c++17 -fsyntax-only \
            -I "$DASROOT/include" -I "$DASROOT/3rdparty/fmt/include" \
            -I "$DASROOT/modules/dasUnitTest" "$CPP" 2>&1)
    crc=$?
    (( crc != 0 )) || exit 0                              # compiled clean -> no bug
    [[ -z "$SIG" ]] || grep -qE "$SIG" <<<"$COUT" || exit 0
    exit 99 ;;

  crash)
    # Fault signal (rc>=128) but NOT our mem-cap SIGKILL (137) or timeout (124),
    # or daslang's own crash marker. Mirrors is_crash() in classify.das.
    if { (( rc >= 128 && rc != 137 && rc != 124 )) \
         || grep -qE "CRASH:|Program received signal" <<<"$OUT"; }; then
        [[ -z "$SIG" ]] || grep -qE "$SIG" <<<"$OUT" || exit 0
        exit 99
    fi
    exit 0 ;;

  assert)
    # daslang's verify()/assert prints "verify failed: ..." (or "assertion ...")
    # and exits rc=1 — NOT SIGABRT. Match the message, not the code (rc=1 is also
    # a plain compile error). SIG pins the specific assertion to avoid drift.
    if grep -qiE "verify failed|assertion|: assert" <<<"$OUT"; then
        [[ -z "$SIG" ]] || grep -qE "$SIG" <<<"$OUT" || exit 0
        exit 99
    fi
    exit 0 ;;

  *) echo "unknown KIND=$KIND" >&2; exit 0 ;;
esac
