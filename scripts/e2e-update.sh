#!/bin/zsh
# End-to-end test of the in-app updater, entirely inside .tmp/e2e. Touches neither the installed app,
# nor ~/Library/Screen Savers, nor the real settings.json.
#  1. Builds the current version as the "old" app plus screen saver and copies both to .tmp/e2e.
#  2. Builds a DMG with a higher version (default 1.0.1, via BH_VERSION; the file VERSION stays as it is).
#  3. Writes a feed in the shape of the GitHub API that points to that DMG and its .sha256.
#  4. Runs --update-check and --update-install on the copy, waits for the relaunch and checks the version.
#  5. Quits the relaunched copy.
# Call: ./scripts/e2e-update.sh [new version]
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
OLD=$(cat VERSION)
NEW=${1:-1.0.1}
E2E=$ROOT/.tmp/e2e
APP=$E2E/BlackHoleWallpaper.app
SAVERS="$E2E/Screen Savers"
BIN=$APP/Contents/MacOS/BlackHoleWallpaper

rm -rf "$E2E"
mkdir -p "$E2E/release" "$SAVERS"

echo "== 1. old version $OLD"
./scripts/build-app.sh >/dev/null
./scripts/build-saver.sh >/dev/null
ditto build/BlackHoleWallpaper.app "$APP"
ditto "build/Schwarzes Loch.saver" "$SAVERS/Schwarzes Loch.saver"

echo "== 2. DMG with version $NEW"
BH_VERSION=$NEW ./scripts/make-dmg.sh >/dev/null
cp "build/BlackHoleWallpaper-$NEW.dmg" "build/BlackHoleWallpaper-$NEW.dmg.sha256" "$E2E/release/"
echo "sha256 file: $(cat "$E2E/release/BlackHoleWallpaper-$NEW.dmg.sha256")"

echo "== 3. feed and settings copy"
cat > "$E2E/feed.json" <<JSON
{
  "tag_name": "v$NEW",
  "name": "Black Hole Wallpaper $NEW",
  "draft": false,
  "prerelease": false,
  "html_url": "https://github.com/DigitalIQ/blackhole-wallpaper/releases/tag/v$NEW",
  "body": "## Test\n\n- End-to-end test of the updater.",
  "assets": [
    {"name": "BlackHoleWallpaper-$NEW.dmg", "size": $(stat -f %z "$E2E/release/BlackHoleWallpaper-$NEW.dmg"),
     "browser_download_url": "file://$E2E/release/BlackHoleWallpaper-$NEW.dmg"},
    {"name": "BlackHoleWallpaper-$NEW.dmg.sha256", "size": 65,
     "browser_download_url": "file://$E2E/release/BlackHoleWallpaper-$NEW.dmg.sha256"}
  ]
}
JSON
# A fresh settings file: no still image (it would change the real desktop picture), no automatic check.
cat > "$E2E/settings.json" <<JSON
{"presets": [], "settings": {"stillWallpaper": false, "updates": {"auto": false}}}
JSON
export BH_SETTINGS="$E2E/settings.json" BH_UPDATE_FEED="$E2E/feed.json" BH_SAVER_DIR="$SAVERS"

echo "== 4. before: app $(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString), saver $(defaults read "$SAVERS/Schwarzes Loch.saver/Contents/Info.plist" CFBundleShortVersionString)"
"$BIN" --update-check
echo "-- install"
"$BIN" --update-install
for i in {1..100}; do
  PID=$(pgrep -f "^$BIN" || true)
  [[ -n $PID ]] && break
  sleep 0.2
done
[[ -n ${PID:-} ]] || { echo "FAIL: the copy did not relaunch"; exit 1; }
sleep 2
echo "== 5. after"
echo "running: $(ps -o pid=,lstart=,command= -p $PID)"
APPV=$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)
SAVV=$(defaults read "$SAVERS/Schwarzes Loch.saver/Contents/Info.plist" CFBundleShortVersionString)
echo "app on disk: $APPV, saver on disk: $SAVV"
echo "leftovers: $(/bin/ls -A "$E2E" | tr '\n' ' ')"
"$BIN" --update-check | /usr/bin/grep -e "installed version" -e "decision"
kill $PID
sleep 1
pgrep -f "^$BIN" >/dev/null && { echo "FAIL: copy still running"; exit 1; }
[[ $APPV == "$NEW" && $SAVV == "$NEW" ]] || { echo "FAIL: version on disk"; exit 1; }
echo "PASS: copy replaced with $NEW, relaunched as pid $PID, quit again"
