#!/bin/bash
# Two-stage hunt over generated Zig programs.
#   stage 1  zig ast-check            ~7ms   parser + AstGen
#   stage 2  zig build-obj            ~0.8s  adds Sema, run only on stage-1 passers
# A normal rejection is rc=1 and a valid program is rc=0; anything else, or the
# word "panic" on stderr, is the compiler falling over and is what we keep.
set -u
IN=$1; OUT=$2; ZIG=$3; P=${P:-8}
mkdir -p "$OUT/crashes" "$OUT/valid"
: > "$OUT/hits.tsv"

stage () {                    # $1=dir of inputs  $2=label  $3... = zig argv
  local dir=$1 label=$2; shift 2
  # Stage 2 runs build-obj, which writes a compilation cache. Point it inside
  # $OUT so a hunt never grows ~/.cache (the root fs sits at 98% full) and is
  # thrown away with the run. Shared rather than per-process: zig locks the
  # cache, and sharing lets the stage-2 workers reuse each other's entries.
  mkdir -p "$OUT/zigcache"
  ls "$dir"/* 2>/dev/null | xargs -P "$P" -I{} env OUT="$OUT" ZIG="$ZIG" LABEL="$label" \
    ZIG_LOCAL_CACHE_DIR="$OUT/zigcache" ZIG_GLOBAL_CACHE_DIR="$OUT/zigcache" \
    bash -c '
      f=$1; shift
      log=$(timeout 60 "$ZIG" "$@" "$f" 2>&1); rc=$?   # "$@" is the zig subcommand only
      if [ "$rc" -ge 128 ] || printf "%s" "$log" | grep -qiE "panic|unreachable code was executed|Aborted|Segmentation fault"; then
        b=$(basename "$f")
        cp "$f" "$OUT/crashes/${LABEL}_${b}"
        sig=$(printf "%s" "$log" | grep -oiE "panic: .*|error: unable .*" | head -1)
        printf "%s\t%s\t%s\t%s\n" "$LABEL" "$b" "$rc" "${sig:-rc$rc}" >> "$OUT/hits.tsv"
      elif [ "$rc" -eq 0 ] && [ "$LABEL" = ast ]; then
        cp "$f" "$OUT/valid/$(basename $f)"
      fi' _ {} "$@"
}

stage "$IN" ast ast-check
echo "stage1 done: $(ls $IN | wc -l) in, $(ls $OUT/valid | wc -l) parse-clean, $(wc -l < $OUT/hits.tsv) hits"
if [ -n "$(ls -A "$OUT/valid" 2>/dev/null)" ]; then
  stage "$OUT/valid" sema build-obj -fno-emit-bin
fi
echo "DONE hits=$(wc -l < $OUT/hits.tsv)"
touch "$OUT/.done"
