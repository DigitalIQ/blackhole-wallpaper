#!/bin/zsh
# Builds the app and the screen saver (release, ad-hoc signed) and packs both into
# build/BlackHoleWallpaper-<version>.dmg, plus build/BlackHoleWallpaper-<version>.dmg.sha256 with the
# hex checksum that the in-app updater checks. Installs nothing. BH_VERSION overrides the file VERSION.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${BH_VERSION:-$(cat VERSION)}
export BH_VERSION=$VERSION
DMG="build/BlackHoleWallpaper-${VERSION}.dmg"
STAGE="build/dmg"

./scripts/build-app.sh
./scripts/build-saver.sh

rm -rf "$STAGE" "$DMG" "$DMG.sha256"
mkdir -p "$STAGE"
cp -R build/BlackHoleWallpaper.app "$STAGE/"
cp -R "build/Schwarzes Loch.saver" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Install.txt" <<TXT
Black Hole Wallpaper ${VERSION}

English
1. Drag BlackHoleWallpaper.app onto the Applications folder.
2. The app is not notarized, so macOS blocks the first start. Run in Terminal:
   xattr -dr com.apple.quarantine /Applications/BlackHoleWallpaper.app
   Or open the app once, then click Open Anyway in System Settings >
   Privacy & Security and confirm.
3. Screen saver (optional): double-click "Schwarzes Loch.saver" and confirm.
   It then shows up in System Settings > Screen Saver. If macOS blocks it, run:
   xattr -dr com.apple.quarantine ~/Library/"Screen Savers/Schwarzes Loch.saver"
The app lives in the menu bar. Start it a second time to open its settings.
It checks GitHub for updates once a day. Switch this off on the General page.

Deutsch
1. BlackHoleWallpaper.app auf den Ordner Programme ziehen.
2. Die App ist nicht notarisiert, deshalb blockiert macOS den ersten Start.
   Im Terminal ausführen:
   xattr -dr com.apple.quarantine /Applications/BlackHoleWallpaper.app
   Oder die App einmal öffnen, dann in Systemeinstellungen > Datenschutz &
   Sicherheit auf "Trotzdem öffnen" klicken und bestätigen.
3. Bildschirmschoner (optional): "Schwarzes Loch.saver" doppelklicken und
   bestätigen. Er steht dann in den Systemeinstellungen unter Bildschirmschoner.
   Blockiert macOS ihn, im Terminal:
   xattr -dr com.apple.quarantine ~/Library/"Screen Savers/Schwarzes Loch.saver"
Die App sitzt in der Menüleiste. Ein zweiter Start öffnet die Einstellungen.
Sie sucht einmal am Tag bei GitHub nach Updates. Abschalten unter Allgemein.
TXT

hdiutil create -volname "Black Hole Wallpaper ${VERSION}" -srcfolder "$STAGE" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
rm -rf "$STAGE"
# Only the hex digits; the release uploads this file next to the DMG.
shasum -a 256 "$DMG" | awk '{print $1}' > "$DMG.sha256"
shasum -a 256 "$DMG"
echo "$DMG.sha256"
