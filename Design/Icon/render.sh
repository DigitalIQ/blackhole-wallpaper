#!/bin/zsh
# Rendert das Rohbild für das App-Symbol mit der gebauten App (Gargantua, Draufsicht schräg, ohne Ränder).
set -e
cd "${0:A:h}"
APP=../../.build/release/BlackHoleWallpaper
[[ -x $APP ]] || (cd ../.. && swift build -c release)
mkdir -p work/renders
$APP --snapshot work/renders/gargantua.png --size 3000x3000 --preset gargantua --hole 0.5,0.5 --top 0 --bottom 0 --time 20 --nobox
