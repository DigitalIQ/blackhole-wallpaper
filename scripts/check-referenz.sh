#!/bin/zsh
# Renders the five built-in presets without objects and compares them pixel by pixel with the
# reference pictures (both sizes). The references were made at Ausgewogen. The default at the power
# adapter is Hoch now, so the snapshots set --quality 1 (Ausgewogen) explicitly.
# Call: ./scripts/check-referenz.sh [reference folder]   (default shots/objekte/referenz)
set -uo pipefail
cd "$(dirname "$0")/.."
REF=${1:-shots/objekte/referenz}
BIN=.build/release/BlackHoleWallpaper
OUT=.tmp/referenz
mkdir -p "$OUT"
fail=0
for p in strudel gargantua m87 draufsicht eisblau; do
  for f in wide hoch; do
    if [[ $f == wide ]]; then size=(--size 3440x1440); else size=(--size 1440x2560 --hole 0.5,0.3); fi
    "$BIN" --snapshot "$OUT/$p-$f.png" --preset $p $size --top 24 --bottom 70 --time 20 --quality 1 >/dev/null 2>&1
    line=$("$BIN" --diff "$OUT/$p-$f.png" "$REF/$p-$f.png" 2>&1 | tail -1)
    echo "$p $f: $line"
    [[ $line == *"differing pixels: 0 of"* ]] || fail=1
  done
done
[[ $fail == 0 ]] && echo "PASS: all presets match the references" || echo "FAIL: differences, see above"
exit $fail
