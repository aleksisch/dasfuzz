#!/usr/bin/env bash
#
# One-shot setup for the grammar fuzzer. Idempotent: every step is skipped if
# its output already exists, so re-running it after a pull only redoes what
# actually changed. Pass --force to rebuild everything from scratch.
#
#   ./setup.sh                 # set up whatever is missing
#   ./setup.sh --force         # rebuild grammar, mutator, das_fuzz and seeds
#   AFL_DIR=/path ./setup.sh   # point at an AFL++ checkout other than the default
#
set -euo pipefail
cd "$(dirname "$0")"
SRC=$PWD

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

AFL_DIR=${AFL_DIR:-$HOME/work/AFLplusplus}
YPP=${YPP:-$SRC/modules/daScript/src/parser/ds2_parser.ypp}
GRAMMAR=$SRC/type_inference_simple.json
MUT=$SRC/modules/Grammar-Mutator
GEN=$MUT/src/grammar_generator-type
ANTLR_JAR=$SRC/antlr-4.8-complete.jar
SEEDS=${SEEDS:-/dev/shm/das_seeds}
TREES=${TREES:-/dev/shm/das_trees}

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
skip() { printf '    (already done: %s)\n' "$*"; }
die()  { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- prereqs ---
say "Checking prerequisites"
missing=()
for t in git cmake ninja python3 java make clang clang++; do
    command -v "$t" >/dev/null || missing+=("$t")
done
[[ ${#missing[@]} -eq 0 ]] || die "missing tools: ${missing[*]}
  Ubuntu: sudo apt install git cmake ninja-build python3 default-jre make clang libclang-dev llvm-dev"

[[ -f "$YPP" ]] || die "daScript submodule not checked out.
  Run: git submodule update --init --recursive"

[[ -x "$AFL_DIR/afl-fuzz" && -x "$AFL_DIR/afl-clang-fast++" ]] || die "AFL++ not found at $AFL_DIR
  git clone https://github.com/AFLplusplus/AFLplusplus \"$AFL_DIR\" && make -C \"$AFL_DIR\" -j\$(nproc)
  or set AFL_DIR=/path/to/AFLplusplus"

if [[ ! -f "$ANTLR_JAR" ]]; then
    say "Fetching antlr jar (needed by Grammar-Mutator)"
    wget -q https://www.antlr.org/download/antlr-4.8-complete.jar -O "$ANTLR_JAR" \
        || die "could not download antlr-4.8-complete.jar"
fi
printf '    ok\n'

# ---------------------------------------------------------------- grammar ---
# The JSON is generated, not checked in. convert.py is TWO steps: the .ypp pass
# does not apply START_PROLOGUE, so without --apply the grammar has no
# `require UnitTest` prologue and generates far weaker programs.
if [[ $FORCE -eq 1 || ! -f $GRAMMAR ]]; then
    say "Generating grammar from $(basename "$YPP")"
    python3 "$SRC/convert.py" "$YPP" > "$GRAMMAR"
    python3 "$SRC/convert.py" --apply "$GRAMMAR"

    python3 - "$GRAMMAR" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
nts = set(d)
refs = {t for alts in d.values() for a in alts for t in a
        if t.startswith('<') and t.endswith('>')}
undef = sorted(refs - nts)
prod, changed = set(), True
while changed:
    changed = False
    for k, alts in d.items():
        if k in prod:
            continue
        for a in alts:
            if all(not (t.startswith('<') and t.endswith('>')) or t in prod for t in a):
                prod.add(k); changed = True; break
unprod = sorted(nts - prod)
if undef or unprod:
    print(f"  undefined refs: {undef[:5]}\n  unproductive:   {unprod[:5]}", file=sys.stderr)
    sys.exit("grammar failed validation")
print(f"    {len(d)} rules, no undefined refs, no unproductive symbols")
PY
else
    skip "$GRAMMAR"
fi

# ---------------------------------------------------------------- mutator ---
# The Makefile depends on .grammar (a path file), NOT on the JSON contents, so
# editing the grammar does not trigger a rebuild. Delete the generated sources
# to force it.
if [[ $FORCE -eq 1 || ! -x $GEN ]]; then
    say "Building Grammar-Mutator"
    rm -f "$MUT/src/f1_c_fuzz.c" "$MUT/include/f1_c_fuzz.h"
    make -C "$MUT" GRAMMAR_FILE="$GRAMMAR" -j"$(nproc)"
else
    skip "$GEN"
fi

# --------------------------------------------------------------- das_fuzz ---
if [[ $FORCE -eq 1 || ! -x $SRC/build_afl/das_fuzz ]]; then
    say "Building das_fuzz (AFL instrumented)"
    # daScript writes its static libs into the source tree, so an AFL build and
    # a plain build clobber each other. Clear them before each.
    rm -f "$SRC/modules/daScript/lib"/*.a
    AFL_DIR="$AFL_DIR" "$SRC/build_das_fuzz.sh"
else
    skip "$SRC/build_afl/das_fuzz"
fi

# ------------------------------------------------------------------ seeds ---
# Program size dominates the compile rate far more than any grammar tweak
# (58% at max_size 80 vs 17% at 200), so seed from a mix rather than one size.
if [[ $FORCE -eq 1 || ! -d $SEEDS || -z "$(ls -A "$SEEDS" 2>/dev/null)" ]]; then
    say "Generating seeds into $SEEDS"
    rm -rf "$SEEDS" "$TREES"
    mkdir -p "$SEEDS" "$TREES"
    for cfg in "500 120 11" "400 200 22" "200 350 33"; do
        set -- $cfg
        tmp_s=$(mktemp -d) ; tmp_t=$(mktemp -d)
        LD_LIBRARY_PATH="$MUT/src" "$GEN" "$1" "$2" "$tmp_s" "$tmp_t" "$3" >/dev/null
        # keep seed and tree names paired -- the mutator looks the tree up by name
        for f in "$tmp_s"/*; do
            b=$(basename "$f")
            cp "$f" "$SEEDS/s$2_$b"
            [[ -e "$tmp_t/$b" ]] && cp "$tmp_t/$b" "$TREES/s$2_$b"
        done
        rm -rf "$tmp_s" "$tmp_t"
    done
    printf '    %s seeds, %s trees\n' "$(ls "$SEEDS" | wc -l)" "$(ls "$TREES" | wc -l)"
else
    skip "$SEEDS ($(ls "$SEEDS" | wc -l) seeds)"
fi

# ------------------------------------------------------------------- done ---
say "Ready"
cat <<EOF
    grammar   $GRAMMAR
    generator $GEN
    target    $SRC/build_afl/das_fuzz
    seeds     $SEEDS ($(ls "$SEEDS" | wc -l) files)

Start fuzzing:
    ./launch20_supervised.sh              # 20 supervised instances in tmux
    tmux attach -t fuzz                   # watch them
    $AFL_DIR/afl-whatsup out_clean        # aggregate status

Single instance:
    LD_LIBRARY_PATH=$MUT/src TREES_PATH=$TREES \\
      AFL_CUSTOM_MUTATOR_LIBRARY=$MUT/src/libgrammarmutator-type.so \\
      AFL_CUSTOM_MUTATOR_ONLY=1 $AFL_DIR/afl-fuzz -t 3000 -i $SEEDS -o out -- ./build_afl/das_fuzz

If afl-fuzz refuses to start over core_pattern:
    echo core | sudo tee /proc/sys/kernel/core_pattern
EOF
