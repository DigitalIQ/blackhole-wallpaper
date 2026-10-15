cask "blackhole-wallpaper" do
  version "1.0.0"
  sha256 "7d6faab019c677a1af005618ecd6fc72050cf8ed19072c68cc11e527f17570ed"

  url "https://github.com/DigitalIQ/blackhole-wallpaper/releases/download/v#{version}/BlackHoleWallpaper-#{version}.dmg"
  name "Black Hole Wallpaper"
  desc "Live black hole desktop wallpaper and screen saver with real light bending"
  homepage "https://digitaliq.github.io/blackhole-wallpaper/"

  # The app checks GitHub for updates. Installed with Homebrew it does not replace itself,
  # it tells the user to run: brew upgrade --cask blackhole-wallpaper
  auto_updates true

  depends_on macos: ">= :sequoia"
  depends_on arch: :arm64

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
