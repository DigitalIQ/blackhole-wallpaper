#!/bin/zsh
# Builds build/Schwarzes Loch.saver from the app's renderer sources plus Saver/.
set -euo pipefail
cd "$(dirname "$0")/.."
SAVER="build/Schwarzes Loch.saver"
# BH_VERSION overrides the file VERSION, e.g. for a test build of a higher version.
VERSION=${BH_VERSION:-$(cat VERSION)}
rm -rf "$SAVER"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources"
cp Saver/thumbnail.png "Saver/thumbnail@2x.png" "$SAVER/Contents/Resources/"
swiftc -O -swift-version 5 -target arm64-apple-macos15 \
  -emit-library -module-name BlackHoleSaver \
  -framework ScreenSaver -framework MetalKit -framework Metal -framework AppKit -framework ModelIO \
  Sources/BlackHoleWallpaper/Shaders.swift \
  Sources/BlackHoleWallpaper/Renderer.swift \
  Sources/BlackHoleWallpaper/Settings.swift \
  Sources/BlackHoleWallpaper/Quality.swift \
  Sources/BlackHoleWallpaper/Objects.swift \
  Sources/BlackHoleWallpaper/ObjectCatalog.swift \
  Sources/BlackHoleWallpaper/ObjectSystem.swift \
  Sources/BlackHoleWallpaper/ObjectShaders.swift \
  Sources/BlackHoleWallpaper/BodyShaders.swift \
  Sources/BlackHoleWallpaper/BodyRenderer.swift \
  Sources/BlackHoleWallpaper/Orbits.swift \
  Sources/BlackHoleWallpaper/ShipShaders.swift \
  Sources/BlackHoleWallpaper/ShipCatalog.swift \
  Sources/BlackHoleWallpaper/ShipSystem.swift \
  Sources/BlackHoleWallpaper/MeshBuilder.swift \
  Sources/BlackHoleWallpaper/BorgCube.swift \
  Sources/BlackHoleWallpaper/ModelStore.swift \
  Sources/BlackHoleWallpaper/ModelImage.swift \
  Sources/BlackHoleWallpaper/GLTFLoader.swift \
  Sources/BlackHoleWallpaper/UIText.swift \
  Sources/BlackHoleWallpaper/Localization.swift \
  Sources/BlackHoleWallpaper/Strings.swift \
  Sources/BlackHoleWallpaper/Lenses.swift \
  Sources/BlackHoleWallpaper/LensShaders.swift \
  Sources/BlackHoleWallpaper/Profiler.swift \
  Saver/BlackHoleSaverView.swift \
  -o "$SAVER/Contents/MacOS/BlackHoleSaver"
for l in en:"Black Hole Wallpaper" de:"Schwarzes Loch"; do
  mkdir -p "$SAVER/Contents/Resources/${l%%:*}.lproj"
  printf 'CFBundleName = "%s";\nCFBundleDisplayName = "%s";\n' "${l#*:}" "${l#*:}" > "$SAVER/Contents/Resources/${l%%:*}.lproj/InfoPlist.strings"
done
cat > "$SAVER/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.digitaliq.blackholewallpaper.saver</string>
  <key>CFBundleName</key><string>Schwarzes Loch</string>
  <key>CFBundleDisplayName</key><string>Schwarzes Loch</string>
  <key>CFBundleDevelopmentRegion</key><string>de</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>de</string></array>
  <key>CFBundleExecutable</key><string>BlackHoleSaver</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>NSPrincipalClass</key><string>BlackHoleSaverView</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$SAVER"
echo "$SAVER"
