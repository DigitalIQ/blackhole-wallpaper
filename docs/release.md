# Release 1.0.0

The steps below are prepared but not run. Run them in this order. Each block assumes the previous one worked.

The repository `DigitalIQ/blackhole-wallpaper` is private until step 4. The local `origin` remote also pushes to a second, private server. Every push below therefore goes to an explicit GitHub URL, not to `origin`.

## 0. Merge the release branch

```bash
cd blackhole-wallpaper
git checkout main
git merge --no-ff release -m "Release 1.0.0"
```

## 1. Build the DMG and note the checksum

```bash
./scripts/make-dmg.sh
# prints: <sha256>  build/BlackHoleWallpaper-1.0.0.dmg
#         build/BlackHoleWallpaper-1.0.0.dmg.sha256
```

The script also writes `build/BlackHoleWallpaper-1.0.0.dmg.sha256` with only the hex checksum. The in-app updater needs both files in the release: it installs only a DMG whose `.sha256` matches.

If the checksum differs from the one in `packaging/homebrew/blackhole-wallpaper.rb`, put the new one there and commit. Every rebuild changes the checksum, so upload exactly this file and its `.sha256` in step 6.

## 2. Rewrite author and committer in the history

All commits carry a private name and e-mail address. Rewrite them to the GitHub noreply address. Work on a fresh mirror clone, not on the working copy.

With git filter-repo (`brew install git-filter-repo`):

```bash
cd ..
git clone --mirror https://github.com/DigitalIQ/blackhole-wallpaper.git bh-rewrite.git
cd bh-rewrite.git

cat > ../bh-mailmap.txt <<'EOF'
DigitalIQ <30226996+DigitalIQ@users.noreply.github.com> <OLD_EMAIL>
EOF
# Replace OLD_EMAIL with the address shown by:
git log --all --format='%ae%n%ce' | sort -u

git filter-repo --mailmap ../bh-mailmap.txt --force
git log --all --format='%an <%ae> | %cn <%ce>' | sort | uniq -c   # must show only DigitalIQ
```

Optional: the old file contents in the history still contain the private first name (14 commits, mostly `docs/objekte-plan.md`) and the old bundle identifier with the surname (15 commits). To scrub them as well, fill in the three placeholders and run:

```bash
# OLD_BUNDLE_ID: the old CFBundleIdentifier of the app, shown by
git log -p --all -S blackholewallpaper | grep -o '[a-z]*\.[a-z]*\.blackholewallpaper' | sort -u

cat > ../bh-replace.txt <<'EOF'
OLD_BUNDLE_ID==>io.github.digitaliq.blackholewallpaper
regex:\bOLD_FIRST_NAMEs\b==>des Nutzers
regex:\bOLD_FIRST_NAME\b==>der Nutzer
EOF
git filter-repo --replace-text ../bh-replace.txt --force
git log -p --all | grep -c -E 'OLD_FIRST_NAME|OLD_BUNDLE_ID'   # with the real values, should print 0
```

The replacement for the first name is grammatically rough in a few old sentences. That only affects old commits; the current files already read correctly.

Fallback without filter-repo (git filter-branch, slower, author and committer only):

```bash
git filter-branch --env-filter '
  export GIT_AUTHOR_NAME="DigitalIQ"
  export GIT_AUTHOR_EMAIL="30226996+DigitalIQ@users.noreply.github.com"
  export GIT_COMMITTER_NAME="DigitalIQ"
  export GIT_COMMITTER_EMAIL="30226996+DigitalIQ@users.noreply.github.com"
' --tag-name-filter cat -- --all
```

## 3. Force-push the rewritten history

```bash
git push --force --mirror https://github.com/DigitalIQ/blackhole-wallpaper.git
```

Afterwards, in the normal working copy, take over the new history (local commits that are not pushed are lost, so push or stash them first):

```bash
cd ../blackhole-wallpaper
git fetch https://github.com/DigitalIQ/blackhole-wallpaper.git main
git reset --hard FETCH_HEAD
```

The private second server still has the old history. Force-push there as well if both should match. Old forks and clones keep the old history.

Set the local identity for future commits:

```bash
git config user.name "DigitalIQ"
git config user.email "30226996+DigitalIQ@users.noreply.github.com"
```

## 4. Make the repository public

```bash
gh repo edit DigitalIQ/blackhole-wallpaper --visibility public --accept-visibility-change-consequences
gh repo edit DigitalIQ/blackhole-wallpaper \
  --description "Live black hole desktop wallpaper and screen saver for macOS, with real gravitational lensing in Metal" \
  --homepage "https://digitaliq.github.io/blackhole-wallpaper/"
```

## 5. Topics

```bash
gh repo edit DigitalIQ/blackhole-wallpaper \
  --add-topic macos \
  --add-topic macos-app \
  --add-topic wallpaper \
  --add-topic live-wallpaper \
  --add-topic screensaver \
  --add-topic black-hole \
  --add-topic gravitational-lensing \
  --add-topic general-relativity \
  --add-topic kerr-metric \
  --add-topic ray-tracing \
  --add-topic astrophysics \
  --add-topic metal \
  --add-topic swift \
  --add-topic swiftui \
  --add-topic shaders
```

## 6. Create the release

```bash
git tag -a v1.0.0 -m "Black Hole Wallpaper 1.0.0"
git push https://github.com/DigitalIQ/blackhole-wallpaper.git v1.0.0

gh release create v1.0.0 build/BlackHoleWallpaper-1.0.0.dmg build/BlackHoleWallpaper-1.0.0.dmg.sha256 \
  --repo DigitalIQ/blackhole-wallpaper \
  --title "Black Hole Wallpaper 1.0.0" \
  --notes-file docs/release-notes-1.0.0.md
```

Write the release notes below into `docs/release-notes-1.0.0.md` first, or paste them with `--notes`.

Check the checksum of the uploaded file:

```bash
curl -sL https://github.com/DigitalIQ/blackhole-wallpaper/releases/download/v1.0.0/BlackHoleWallpaper-1.0.0.dmg | shasum -a 256
curl -sL https://github.com/DigitalIQ/blackhole-wallpaper/releases/download/v1.0.0/BlackHoleWallpaper-1.0.0.dmg.sha256
# both must show the same hex
```

Check what the updater sees (no install):

```bash
build/BlackHoleWallpaper.app/Contents/MacOS/BlackHoleWallpaper --update-check
# decision: upToDate for the same version; an older build shows decision: newer
```

Do not mark a release as prerelease or draft if the app should offer it: the updater ignores both. Each later release needs the same two files with the new version in the name, for example `BlackHoleWallpaper-1.0.1.dmg` and `BlackHoleWallpaper-1.0.1.dmg.sha256`, and the tag `v1.0.1`.

## 7. Turn on GitHub Pages with the source "GitHub Actions"

```bash
gh api -X POST repos/DigitalIQ/blackhole-wallpaper/pages -f build_type=workflow
# if Pages already exists:
gh api -X PUT repos/DigitalIQ/blackhole-wallpaper/pages -f build_type=workflow

gh workflow run pages.yml --repo DigitalIQ/blackhole-wallpaper
gh run watch --repo DigitalIQ/blackhole-wallpaper
```

The site then lives at https://digitaliq.github.io/blackhole-wallpaper/.

## 8. Homebrew tap

```bash
gh repo create DigitalIQ/homebrew-tap --public \
  --description "Homebrew casks by DigitalIQ"
git clone https://github.com/DigitalIQ/homebrew-tap.git
cd homebrew-tap
mkdir -p Casks
cp ../blackhole-wallpaper/packaging/homebrew/blackhole-wallpaper.rb Casks/
git add Casks/blackhole-wallpaper.rb
git commit -m "Add blackhole-wallpaper 1.0.0"
git push origin main
```

Test it:

```bash
brew tap digitaliq/tap
brew trust --tap digitaliq/tap
brew audit --cask --strict digitaliq/tap/blackhole-wallpaper
brew install --cask blackhole-wallpaper
```

## Release notes v1.0.0

```markdown
First public release.

Black Hole Wallpaper is a live desktop wallpaper for macOS. It shows a spinning black hole whose light bending is computed from the Kerr metric, plus nebulae and a glowing band along the menu bar and the Dock. The same renderer runs as a screen saver.

### Features

- 7 presets: Swirl, Gargantua, M87* as photographed, Top View, Ice Blue, Star System and Sci-Fi Harbor
- A separate preset for each display
- Animation levels All, Edges Only and Off. Edges Only keeps the hole still and costs about 0.13 ms GPU time per frame on a MacBook Air M4 at 3440 x 1440
- Objects: galaxies, stars, planets, moons, asteroids, comets, meteors, ships and stations from many sci-fi worlds, a second black hole, a wormhole and a relativistic jet
- Kepler orbits, hyperbolic fly-bys and tidal stretching near the hole
- Quality levels Battery Saver, Balanced, High and Ultra, separately for power adapter and battery
- Import of OBJ, USD, USDZ, PLY, STL, glTF and GLB models
- English and German interface
- Screen saver
- Update check once a day. The app only contacts api.github.com and GitHub's download servers to check for and fetch updates, and you can switch it off. No analytics.

### Install

Requires macOS 15 or later on Apple Silicon.

1. Download `BlackHoleWallpaper-1.0.0.dmg` below.
2. Drag the app onto Applications. Double-click `Schwarzes Loch.saver` for the screen saver.
3. The app is not notarized, so macOS blocks the first start. Run
   `xattr -dr com.apple.quarantine /Applications/BlackHoleWallpaper.app`,
   or open it once and click Open Anyway in System Settings > Privacy & Security.
   Right-click > Open no longer works since macOS 15.

Homebrew:

    brew tap digitaliq/tap
    brew trust --tap digitaliq/tap
    brew install --cask blackhole-wallpaper

Homebrew quarantines the download too, so the first start needs the same step.

SHA-256 of the DMG: see `packaging/homebrew/blackhole-wallpaper.rb`.
```
