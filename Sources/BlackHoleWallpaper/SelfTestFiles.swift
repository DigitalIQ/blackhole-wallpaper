import CryptoKit
import Foundation

extension SelfTest {
    /// settings.json protection: backups, a broken file set aside, --help and unknown switches write nothing.
    static func fileChecks(_ check: (Bool, String) -> Void) -> Int {
        var failed = 0
        func c(_ ok: Bool, _ what: String) { check(ok, what); if !ok { failed += 1 } }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("bh-settings-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        func files(_ prefix: String) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(prefix) }.sorted()
        }
        func read(_ name: String) -> Data? { try? Data(contentsOf: dir.appendingPathComponent(name)) }

        // 1. Not JSON: set aside, not overwritten; the next save writes a fresh file.
        let junk = Data("{ kaputt".utf8)
        try? junk.write(to: url)
        let s1 = Store(persist: true, file: url)
        let broken = files("settings.broken-")
        c(!fm.fileExists(atPath: url.path) && broken.count == 1 && read(broken[0]) == junk,
          "Datei: kaputte settings.json liegt unverändert als \(broken.first ?? "nichts") daneben")
        s1.settings.fpsPower = 60
        s1.save()
        c(fm.fileExists(atPath: url.path) && Store(persist: false, file: url).settings.fpsPower == 60,
          "Datei: danach wird eine neue settings.json geschrieben")
        c(files("settings.backup-").isEmpty, "Datei: keine Sicherung von einer Datei, die beiseitegelegt wurde")

        // 2. A preset that cannot be read also counts as not clean; the readable rest is kept.
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let good = Store(persist: false, read: false)
        good.settings.screens = ["A": ScreenConfig(presetID: "eisblau"), "B": ScreenConfig(presetID: "gargantua")]
        if var raw = good.encoded().flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }),
           var list = raw["presets"] as? [[String: Any]] {
            list[0]["look"] = nil
            raw["presets"] = list
            try? JSONSerialization.data(withJSONObject: raw).write(to: url)
        }
        let s2 = Store(persist: true, file: url)
        c(files("settings.broken-").count == 1 && s2.settings.screens.count == 2,
          "Datei: Voreinstellung ohne Werte, Datei beiseitegelegt, beide Schirme geladen")

        // 3. Backups: the first write of a run keeps the old file, later writes in the same run wait.
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? good.encoded()?.write(to: url)
        let first = read("settings.json")
        let run1 = Store(persist: true, file: url)
        run1.save()
        c(files("settings.backup-").isEmpty, "Sicherung: unveränderte Einstellungen werden nicht neu geschrieben")
        run1.settings.fpsPower = 120
        run1.save()
        c(read("settings.backup-1.json") == first, "Sicherung: vor dem ersten Überschreiben liegt der alte Stand in backup-1")
        let second = read("settings.json")
        run1.settings.fpsPower = 60
        run1.save()
        c(files("settings.backup-") == ["settings.backup-1.json"], "Sicherung: weitere Änderungen im selben Lauf schieben die Sicherung nicht weiter")
        let third = read("settings.json")
        for fps in [15, 60, 15] {
            let run = Store(persist: true, file: url)
            run.settings.fpsBattery = fps
            run.save()
        }
        c(files("settings.backup-") == ["settings.backup-1.json", "settings.backup-2.json", "settings.backup-3.json"],
          "Sicherung: höchstens drei Stände \(files("settings.backup-"))")
        c(read("settings.backup-3.json") != first && read("settings.backup-3.json") != second && read("settings.backup-3.json") == third,
          "Sicherung: die ältesten Stände fallen heraus")

        // 4. --help and unknown switches end the app before the store reads or writes.
        let before = read("settings.json")
        let before1 = read("settings.backup-1.json")
        for (arg, code) in [("--help", Int32(0)), ("--hlep", Int32(2))] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            p.arguments = [arg]
            var env = ProcessInfo.processInfo.environment
            env["BH_SETTINGS"] = url.path
            p.environment = env
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { c(false, "Schalter \(arg): App startet nicht"); continue }
            let deadline = Date().addingTimeInterval(10)
            while p.isRunning && Date() < deadline { usleep(50_000) }
            if p.isRunning { p.terminate() }
            c(!p.isRunning && p.terminationStatus == code && read("settings.json") == before && read("settings.backup-1.json") == before1,
              "Schalter \(arg): Hilfe, Exit-Code \(code), settings.json unverändert")
        }

        // 5. Wallpaper cache: of each still only the newest bitmap stays, foreign files stay.
        try? fm.removeItem(at: dir)
        let stills = dir.appendingPathComponent("Application Support/Stills", isDirectory: true)
        let cache = dir.appendingPathComponent("cache", isDirectory: true)
        try? fm.createDirectory(at: stills, withIntermediateDirectories: true)
        try? fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let still = stills.appendingPathComponent("KEY-a.png")
        try? Data("png".utf8).write(to: still)
        let prefix = SHA256.hash(data: Data(still.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let names = ["\(prefix)-3840-0-old.bmp", "\(prefix)-3840-0-mid.bmp", "\(prefix)-3840-0-new.bmp", "ffff-3840-0-fremd.bmp"]
        for (i, n) in names.enumerated() {
            let u = cache.appendingPathComponent(n)
            try? Data("bmp".utf8).write(to: u)
            try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: Double(i - 10) * 60)], ofItemAtPath: u.path)
        }
        let removed = Stills.pruneAgentCache(stills: stills, cache: cache)
        let left = ((try? fm.contentsOfDirectory(atPath: cache.path)) ?? []).sorted()
        c(removed == 2 && left == [names[2], names[3]].sorted(),
          "Wallpaper-Cache: zwei alte Bilder weg, neuestes und fremdes bleiben (\(left.count) übrig)")
        return failed
    }
}
