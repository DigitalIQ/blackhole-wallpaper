#!/bin/zsh
# Renders Saver/thumbnail.png (180x116) and thumbnail@2x.png (360x232) from the built app.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=.build/release/BlackHoleWallpaper
[[ -x $APP ]] || swift build -c release
mkdir -p .tmp
$APP --snapshot .tmp/thumb-big.png --size 1440x928 --top 0 --bottom 0 --preset strudel --time 20
sips -z 232 360 .tmp/thumb-big.png --out Saver/thumbnail@2x.png >/dev/null
sips -z 116 180 .tmp/thumb-big.png --out Saver/thumbnail.png >/dev/null
rm .tmp/thumb-big.png
