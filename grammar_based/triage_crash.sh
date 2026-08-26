#!/usr/bin/env bash
# Classify a das_fuzz crash input against the known daslang AOT bugs.
# Usage: ./triage_crash.sh <crash-file>
# Prints: KNOWN#1 nested-comment | KNOWN#2 wrap-collision | UNKNOWN:<err> | NOREPRO(rc=N)
cd "$(dirname "$0")" || exit 1
log=$(mktemp)
DAS_FUZZ_DIAG=1 timeout 120 ./build_plain/das_fuzz < "$1" > "$log" 2>&1
rc=$?
if [ "$rc" -eq 139 ]; then
    echo "SEGFAULT (rc=139) -- daslang crash, check plain run"
elif [ "$rc" -ne 134 ]; then
    echo "NOREPRO(rc=$rc)"
# bug #1: unused global commented out with /* */, colliding with the
# initializer's own /*c-tor*/ marker. Covers das_global AND das_shared.
elif grep -qE '^ *\/\*.*das_(global|shared)<.*\/\*' "$log"; then
    echo "KNOWN#1 nested-comment"
# bug #2: hash-less aotFuncName makes two __wrap_ stubs share a name.
elif grep -q "redefinition of '__wrap_" "$log"; then
    echo "KNOWN#2 wrap-collision"
# bug #3: try/recover body is emitted as a C++ lambda, so break/continue
# inside a try inside a loop lands outside the loop.
elif grep -qE "'(break|continue)' statement not in loop" "$log"; then
    echo "KNOWN#3 break-in-try-lambda"
# bug #4: a class whose method shares the class name makes AOT emit a
# same-named ctor function beside the struct; struct lives in an inner
# anonymous namespace, so unqualified lookup is ambiguous.
elif grep -q "is ambiguous" "$log"; then
    echo "KNOWN#4 class-ctor-name-ambiguity"
else
    echo "UNKNOWN: $(grep -m1 -oE 'error: .*' "$log")"
fi
rm -f "$log"
