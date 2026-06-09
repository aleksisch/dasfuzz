#!/usr/bin/env bash
# Verify minimized aot_cxx_error repros still fail clang -fsyntax-only.
set -u
R="$HOME/daScript2/daScript"
DB="$R/bin/daslang_static"
DIR="${1:-minimized/aot_cxx_error}"
cd "$(dirname "$0")"
for f in "$DIR"/*.das; do
    [[ -e "$f" ]] || { echo "no files in $DIR"; break; }
    "$DB" -aot "$f" /tmp/v.cpp -dasroot "$R" >/dev/null 2>&1
    if clang++ -std=c++17 -fsyntax-only -I "$R/include" -I "$R/3rdparty/fmt/include" \
         -I "$R/modules/dasUnitTest" /tmp/v.cpp >/dev/null 2>&1; then
        echo "DRIFT  $(basename "$f")  ($(stat -c%s "$f")B) compiles clean"
    else
        echo "OK     $(basename "$f")  ($(stat -c%s "$f")B) reproduces"
    fi
done
