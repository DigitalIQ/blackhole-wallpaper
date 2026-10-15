# frozen_string_literal: true

cask "blackhole-wallpaper" do
  version "1.0.0"
  sha256 "7d6faab019c677a1af005618ecd6fc72050cf8ed19072c68cc11e527f17570ed"

  url "https://github.com/DigitalIQ/blackhole-wallpaper/releases/download/v#{version}/BlackHoleWallpaper-#{version}.dmg"
  name "Black Hole Wallpaper"
  desc "Live black hole desktop wallpaper and screen saver with real light bending"
  homepage "https://digitaliq.github.io/blackhole-wallpaper/"

  # Installed with Homebrew, the app does not replace itself. It points to brew upgrade instead,
  # so auto_updates stays off and a plain `brew upgrade` picks up new versions.
  depends_on arch: :arm64
  depends_on macos: ">= :sequoia"

  app "BlackHoleWallpaper.app"
  screen_saver "Schwarzes Loch.saver"

  zap trash: [
    "~/Library/Application Support/BlackHoleWallpaper",
    "~/Library/Preferences/io.github.digitaliq.blackholewallpaper.plist",
  ]

  caveats <<~EOS
    Black Hole Wallpaper is ad-hoc signed and not notarized by Apple,
    so macOS blocks the first start. Run:
      xattr -dr com.apple.quarantine "#{appdir}/BlackHoleWallpaper.app"
      xattr -dr com.apple.quarantine ~/Library/"Screen Savers/Schwarzes Loch.saver"
    Or open it once, then click Open Anyway in
    System Settings > Privacy & Security.
    Update with: brew upgrade --cask blackhole-wallpaper
  EOS
end
