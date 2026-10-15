import Foundation

extension SelfTest {
    /// A trimmed answer of `GET /repos/DigitalIQ/blackhole-wallpaper/releases/latest`, shaped like the real API.
    static let releaseFixture = #"""
    {
      "url": "https://api.github.com/repos/DigitalIQ/blackhole-wallpaper/releases/1",
      "html_url": "https://github.com/DigitalIQ/blackhole-wallpaper/releases/tag/v1.0.1",
      "id": 1,
      "tag_name": "v1.0.1",
      "target_commitish": "main",
      "name": "Black Hole Wallpaper 1.0.1",
      "draft": false,
      "prerelease": false,
      "created_at": "2026-10-20T10:00:00Z",
      "published_at": "2026-10-20T10:05:00Z",
      "assets": [
        {"name": "BlackHoleWallpaper-1.0.0.dmg", "size": 9000000, "content_type": "application/x-apple-diskimage",
         "browser_download_url": "https://github.com/DigitalIQ/blackhole-wallpaper/releases/download/v1.0.1/BlackHoleWallpaper-1.0.0.dmg"},
        {"name": "BlackHoleWallpaper-1.0.1.zip", "size": 8000000, "content_type": "application/zip",
         "browser_download_url": "https://github.com/DigitalIQ/blackhole-wallpaper/releases/download/v1.0.1/BlackHoleWallpaper-1.0.1.zip"},
        {"name": "BlackHoleWallpaper-1.0.1.dmg.sha256", "size": 65, "content_type": "text/plain",
         "browser_download_url": "https://github.com/DigitalIQ/blackhole-wallpaper/releases/download/v1.0.1/BlackHoleWallpaper-1.0.1.dmg.sha256"},
        {"name": "BlackHoleWallpaper-1.0.1.dmg", "size": 9100000, "content_type": "application/x-apple-diskimage",
         "browser_download_url": "https://github.com/DigitalIQ/blackhole-wallpaper/releases/download/v1.0.1/BlackHoleWallpaper-1.0.1.dmg"}
      ],
      "tarball_url": "https://api.github.com/repos/DigitalIQ/blackhole-wallpaper/tarball/v1.0.1",
      "zipball_url": "https://api.github.com/repos/DigitalIQ/blackhole-wallpaper/zipball/v1.0.1",
      "body": "## What is new\r\n\r\n- **Quality:** High is now the default on the power adapter.\r\n- The app checks for updates once a day. You can switch it off.\r\n\r\n### Install\r\nDownload the DMG below."
    }
    """#

    /// Updater: versions, the GitHub answer, asset choice, checksum, Homebrew, schedule and settings.
    static func updateChecks(_ check: (Bool, String) -> Void) -> Int {
        var failed = 0
        func c(_ ok: Bool, _ what: String) { check(ok, what); if !ok { failed += 1 } }
        func v(_ s: String) -> SemVer { SemVer(s)! }

        // Versions.
        c(v("1.0.1") > v("1.0.0") && v("v1.0.0") == v("1.0") && v("1.10.0") > v("1.9.9") && v("2.0.0") > v("1.99.99"),
          "Update: Versionen vergleichen (1.0.1 > 1.0.0, v1.0.0 = 1.0, 1.10.0 > 1.9.9)")
        c(v("2.0.0-beta.1") < v("2.0.0") && v("1.0.0-alpha") < v("1.0.0-alpha.1") && v("1.0.0-alpha.1") < v("1.0.0-beta")
            && v("1.0.0-beta.2") < v("1.0.0-beta.11") && v("1.0.0+build.5") == v("1.0.0"),
          "Update: Vorabversionen liegen vor der Version, Build-Angabe zählt nicht")
        c(["", "abc", "1.x", "1..2", "1.2.3.4", "-1.0", "1.0-"].allSatisfy { SemVer($0) == nil }, "Update: unsinnige Versionen werden abgelehnt")

        // The GitHub answer.
        guard let r = Release.parse(Data(releaseFixture.utf8)) else { c(false, "Update: Antwort von GitHub lesbar"); return failed }
        c(r.tag == "v1.0.1" && r.versionString == "1.0.1" && !r.draft && !r.prerelease && r.assets.count == 4
            && r.page?.absoluteString == "https://github.com/DigitalIQ/blackhole-wallpaper/releases/tag/v1.0.1",
          "Update: Antwort von GitHub gelesen (Tag, Seite, vier Dateien)")
        c(r.excerpt.hasPrefix("Quality: High is now the default") && !r.excerpt.contains("#") && !r.excerpt.contains("**"),
          "Update: Auszug der Release Notes ohne Überschriften und Markdown: \(r.excerpt.prefix(60))")
        c(Release.excerpt(String(repeating: "word ", count: 200)).count <= 242, "Update: Auszug ist kurz")
        c(Release.parse(Data(#"{"message": "Not Found"}"#.utf8)) == nil && Release.parse(Data("kaputt".utf8)) == nil,
          "Update: Fehlerantwort und kaputtes JSON ergeben kein Release")

        // Asset choice.
        let files = r.installFiles
        c(files?.dmg.name == "BlackHoleWallpaper-1.0.1.dmg" && files?.sha.name == "BlackHoleWallpaper-1.0.1.dmg.sha256",
          "Update: richtige DMG und Prüfsumme gewählt, nicht die alte DMG oder das ZIP")
        let noSha = Release(tag: r.tag, version: r.version, notes: "", page: nil,
                            assets: r.assets.filter { !$0.name.hasSuffix(".sha256") }, draft: false, prerelease: false)
        c(noSha.installFiles == nil, "Update: ohne Prüfsummen-Datei wird nichts installiert")
        c(UpdateCore.trusted(files!.dmg.url, overridden: false)
            && !UpdateCore.trusted(URL(string: "http://github.com/x.dmg")!, overridden: false)
            && !UpdateCore.trusted(URL(string: "https://example.com/x.dmg")!, overridden: false)
            && !UpdateCore.trusted(URL(fileURLWithPath: "/x.dmg"), overridden: false)
            && UpdateCore.trusted(URL(fileURLWithPath: "/x.dmg"), overridden: true),
          "Update: ohne Test-Feed nur https von github.com")

        // Decision.
        let cur = v("1.0.0")
        c(UpdateCore.decide(r, current: cur, skipped: "", manual: false) == .newer, "Update: 1.0.1 gegen 1.0.0 ist neuer")
        c(UpdateCore.decide(r, current: v("1.0.1"), skipped: "", manual: true) == .upToDate
            && UpdateCore.decide(r, current: v("1.2.0"), skipped: "", manual: true) == .upToDate, "Update: gleiche oder ältere Version wird nicht angeboten")
        c(UpdateCore.decide(r, current: cur, skipped: "1.0.1", manual: false) == .skipped
            && UpdateCore.decide(r, current: cur, skipped: "1.0.1", manual: true) == .newer,
          "Update: übersprungene Version nur bei der automatischen Suche still")
        let draft = Release(tag: "v9.0.0", version: v("9.0.0"), notes: "", page: nil, assets: [], draft: true, prerelease: false)
        let pre = Release(tag: "v9.0.0", version: v("9.0.0"), notes: "", page: nil, assets: [], draft: false, prerelease: true)
        let rc = Release(tag: "v9.0.0-rc.1", version: v("9.0.0-rc.1"), notes: "", page: nil, assets: [], draft: false, prerelease: false)
        c([draft, pre, rc].allSatisfy { UpdateCore.decide($0, current: cur, skipped: "", manual: true) == .ignored },
          "Update: Entwürfe und Vorabversionen werden ignoriert")

        // Checksum.
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("bh-update-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let file = dir.appendingPathComponent("x.dmg"), sha = dir.appendingPathComponent("x.dmg.sha256")
        try? Data("hello".utf8).write(to: file)
        let helloHash = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        c((try? UpdateCore.sha256(of: file)) == helloHash, "Update: SHA-256 einer Datei stimmt")
        func verifies(_ shaText: String) -> Bool {
            try? Data(shaText.utf8).write(to: sha)
            return (try? UpdateCore.verify(file: file, shaFile: sha)) != nil
        }
        c(verifies(helloHash + "\n") && verifies(helloHash.uppercased() + "  x.dmg\n"), "Update: passende Prüfsumme wird angenommen, auch mit Dateiname")
        let wrong = String(helloHash.dropLast()) + "5"
        c(!verifies(wrong) && !verifies("") && !verifies("abc") && !verifies("<html>Not Found</html>"),
          "Update: falsche oder kaputte Prüfsumme bricht ab")
        do { try Data(wrong.utf8).write(to: sha); try UpdateCore.verify(file: file, shaFile: sha); c(false, "Update: Fehler bei falscher Prüfsumme") }
        catch { c(error as? UpdateError == .checksum, "Update: falsche Prüfsumme meldet „\(UpdateError.checksum.message)“") }

        // Homebrew and install mode.
        let cask = dir.appendingPathComponent("Caskroom/blackhole-wallpaper", isDirectory: true)
        let none = dir.appendingPathComponent("Caskroom/fehlt").path
        try? fm.createDirectory(at: cask, withIntermediateDirectories: true)
        let home = "/Users/test"
        func brew(_ path: String, _ rooms: [String]) -> Bool {
            UpdateCore.homebrewManages(app: URL(fileURLWithPath: path), caskrooms: rooms, home: home)
        }
        c(brew("/opt/homebrew/Caskroom/blackhole-wallpaper/1.0.0/BlackHoleWallpaper.app", [none]),
          "Homebrew: App im Caskroom erkannt")
        c(brew("/Applications/BlackHoleWallpaper.app", [cask.path]) && brew(home + "/Applications/BlackHoleWallpaper.app", [cask.path]),
          "Homebrew: Cask installiert, App in Programme erkannt")
        c(!brew("/Applications/BlackHoleWallpaper.app", [none]), "Homebrew: ohne Cask installiert sich die App selbst")
        c(!brew(dir.appendingPathComponent("e2e/BlackHoleWallpaper.app").path, [cask.path]),
          "Homebrew: Kopie außerhalb von Programme gilt nicht als Cask")
        c(UpdateCore.caskrooms == ["/opt/homebrew/Caskroom/blackhole-wallpaper", "/usr/local/Caskroom/blackhole-wallpaper"],
          "Homebrew: prüft /opt/homebrew und /usr/local")
        c(UpdateCore.installMode(app: URL(fileURLWithPath: "/opt/homebrew/Caskroom/blackhole-wallpaper/1.0.0/BlackHoleWallpaper.app"), caskrooms: [none]) == .homebrew,
          "Homebrew: Installationsart Homebrew")
        let writable = dir.appendingPathComponent("rw", isDirectory: true), locked = dir.appendingPathComponent("ro", isDirectory: true)
        try? fm.createDirectory(at: writable, withIntermediateDirectories: true)
        try? fm.createDirectory(at: locked, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        c(UpdateCore.installMode(app: writable.appendingPathComponent("BlackHoleWallpaper.app"), caskrooms: [none]) == .selfInstall,
          "Update: beschreibbarer Ordner ersetzt sich selbst")
        c(UpdateCore.installMode(app: locked.appendingPathComponent("BlackHoleWallpaper.app"), caskrooms: [none]) == .notWritable,
          "Update: Ordner ohne Schreibrecht öffnet die Download-Seite")
        c(UpdateCore.installMode(app: writable.appendingPathComponent("BlackHoleWallpaper"), caskrooms: [none]) == .notBundled,
          "Update: Programm ohne App-Paket ersetzt sich nicht")
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)

        // Schedule.
        let now = 1_800_000_000.0
        func due(_ on: Bool, _ low: Bool, _ last: Double) -> Bool { UpdateCore.autoCheckDue(enabled: on, lowPower: low, lastCheck: last, now: now) }
        c(due(true, false, 0) && due(true, false, now - 25 * 3600) && !due(true, false, now - 3600),
          "Update: automatisch höchstens einmal in 24 Stunden")
        c(!due(false, false, 0) && !due(true, true, 0), "Update: nicht, wenn abgeschaltet oder im Energiesparmodus")

        // Settings.
        func load(_ json: String) -> UpdateSettings? { (try? JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)))?.updates }
        c(AppSettings().updates.auto && load("{}") == UpdateSettings(), "Update: alte Datei ohne Eintrag lädt, Suche ist an")
        let part = load(#"{"updates": {"skipped": "1.0.1", "auto": "ja"}}"#)
        c(part?.skipped == "1.0.1" && part?.auto == true && part?.lastCheck == 0, "Update: Teil-Eintrag lädt mit Standardwerten")
        var u = AppSettings()
        u.updates.auto = false; u.updates.lastCheck = now; u.updates.skipped = "2.0.0"
        let back = (try? JSONEncoder().encode(u)).flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) }
        c(back?.updates == u.updates, "Update: Speichern und Laden ergibt dieselben Werte")

        // Feed override.
        let old = ProcessInfo.processInfo.environment["BH_UPDATE_FEED"]
        setenv("BH_UPDATE_FEED", dir.appendingPathComponent("feed.json").path, 1)
        let fileFeed = UpdateCore.feedURL
        setenv("BH_UPDATE_FEED", "http://127.0.0.1:8000/latest.json", 1)
        let httpFeed = UpdateCore.feedURL
        if let old { setenv("BH_UPDATE_FEED", old, 1) } else { unsetenv("BH_UPDATE_FEED") }
        c(fileFeed.isFileURL && httpFeed.scheme == "http" && (old != nil || UpdateCore.feedURL == UpdateCore.defaultFeed),
          "Update: BH_UPDATE_FEED nimmt Pfad oder URL, sonst die GitHub-API")
        c(UpdateCore.defaultFeed.absoluteString == "https://api.github.com/repos/DigitalIQ/blackhole-wallpaper/releases/latest",
          "Update: Standard ist die GitHub-API des Projekts")
        return failed
    }
}
