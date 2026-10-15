#!/bin/zsh
# Builds build/BlackHoleWallpaper.app (release, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/BlackHoleWallpaper.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/BlackHoleWallpaper "$APP/Contents/MacOS/"
cp Design/Icon/AppIcon.icns Design/Icon/MenuBarTemplate.png "Design/Icon/MenuBarTemplate@2x.png" "$APP/Contents/Resources/"
# Localized app name (Finder, Spotlight, login items); the texts inside the app come from Strings.swift.
for l in en:"Black Hole Wallpaper" de:"Schwarzes Loch"; do
  mkdir -p "$APP/Contents/Resources/${l%%:*}.lproj"
  printf 'CFBundleName = "%s";\nCFBundleDisplayName = "%s";\n' "${l#*:}" "${l#*:}" > "$APP/Contents/Resources/${l%%:*}.lproj/InfoPlist.strings"
done
# BH_VERSION overrides the file VERSION, e.g. for a test build of a higher version.
VERSION=${BH_VERSION:-$(cat VERSION)}
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.digitaliq.blackholewallpaper</string>
  <key>CFBundleName</key><string>Black Hole Wallpaper</string>
  <key>CFBundleDisplayName</key><string>Black Hole Wallpaper</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>de</string></array>
  <key>LSHasLocalizedDisplayName</key><true/>
  <key>CFBundleExecutable</key><string>BlackHoleWallpaper</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "$APP"
