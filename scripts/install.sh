#!/bin/zsh
# Builds the app, copies it to ~/Applications and (re)starts it.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
./scripts/build-saver.sh
mkdir -p ~/Library/"Screen Savers"
rm -rf ~/Library/"Screen Savers/Schwarzes Loch.saver"
cp -R "build/Schwarzes Loch.saver" ~/Library/"Screen Savers/"
pkill -x BlackHoleWallpaper 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/BlackHoleWallpaper.app
cp -R build/BlackHoleWallpaper.app ~/Applications/
open ~/Applications/BlackHoleWallpaper.app
echo "installiert: ~/Applications/BlackHoleWallpaper.app und ~/Library/Screen Savers/Schwarzes Loch.saver"
