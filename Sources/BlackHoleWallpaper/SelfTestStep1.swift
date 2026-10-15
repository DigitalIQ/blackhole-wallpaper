import AppKit
import Foundation

extension SelfTest {
    /// Pause when locked or asleep, heat, Reduce Motion, the welcome window, and old settings files.
    static func step1Checks(_ check: (Bool, String) -> Void) -> Int {
        var failed = 0
        func c(_ ok: Bool, _ what: String) { check(ok, what); if !ok { failed += 1 } }

        // Heat: the thermal state decides frame rate and quality.
        func plan(_ edit: (inout RunInputs) -> Void) -> RunPlan { var i = RunInputs(); edit(&i); return RunPolicy.plan(i) }
        let nominal = plan { $0.heat = .nominal }, fair = plan { $0.heat = .fair }
        c(nominal.kind == .running && nominal.fps == 30 && nominal.qualityStep == 0 && !nominal.throttled,
          "Hitze: normal läuft mit 30 Bildern und voller Qualität")
        c(fair == nominal, "Hitze: leicht erhöht ändert nichts")
        let serious = plan { $0.heat = .serious }
        c(serious.kind == .running && serious.fps == 15 && serious.qualityStep == 1 && serious.throttled,
          "Hitze: hoch halbiert die Bildrate und senkt die Qualität um eine Stufe")
        c(plan { $0.heat = .serious; $0.fpsPower = 60 }.fps == 30 && plan { $0.heat = .serious; $0.fpsPower = 120 }.fps == 60,
          "Hitze: 60 wird 30, 120 wird 60")
        c(plan { $0.heat = .serious; $0.onBattery = true; $0.fpsBattery = 15 }.fps == 7
            && plan { $0.heat = .serious; $0.onBattery = true; $0.fpsBattery = 15 }.fps >= RunPolicy.hotMinimumFps,
          "Hitze: am Akku mit 15 Bildern bleiben mindestens \(RunPolicy.hotMinimumFps)")
        c(plan { $0.heat = .serious; $0.animation = .edgesOnly }.kind == .edgesOnly
            && plan { $0.heat = .serious; $0.animation = .edgesOnly }.fps == 15, "Hitze: Nur Ränder wird ebenfalls gedrosselt")
        let critical = plan { $0.heat = .critical }
        c(critical.kind == .frozenHot && !critical.animates && critical.qualityStep == 1, "Hitze: kritisch hält das Standbild an")
        c(plan { $0.heat = .critical; $0.throttleWhenHot = false }.kind == .running
            && plan { $0.heat = .serious; $0.throttleWhenHot = false } == nominal,
          "Hitze: mit ausgeschalteter Option bleibt alles wie eingestellt")
        c(plan { $0.heat = .nominal; $0.fpsOverride = 60 }.fps == 60, "Hitze: abgekühlt gilt wieder die eingestellte Bildrate")
        c(Heat(.nominal) == .nominal && Heat(.fair) == .fair && Heat(.serious) == .serious && Heat(.critical) == .critical
            && Heat.critical > Heat.serious, "Hitze: ProcessInfo.thermalState wird richtig übersetzt")
        let high = RenderQuality(.high).lowered(by: 1)
        c(QualityArea.allCases.allSatisfy { high.level($0) == QualityLevel.balanced.rawValue }, "Hitze: Hoch wird Ausgewogen")
        c(QualityArea.allCases.allSatisfy { RenderQuality(.saver).lowered(by: 1).level($0) == 0 }, "Hitze: unter Akku sparen geht es nicht")
        var mixed = RenderQuality(.ultra)
        mixed.levels[.jet] = .saver
        let lowMixed = mixed.lowered(by: 1)
        c(lowMixed.level(.hole) == 2 && lowMixed.level(.jet) == 0, "Hitze: jeder Bereich sinkt für sich um eine Stufe")
        c(RenderQuality(.high).lowered(by: 0) == RenderQuality(.high), "Hitze: Stufe 0 ändert nichts")
        c(PlanStability.holds, "Hitze: derselbe Zustand gibt denselben Plan, abgekühlt hebt die Qualität wieder an")

        // Reduce Motion.
        c(RunPolicy.effectiveAnimation(.all, respectReduceMotion: true, reduceMotion: true) == .off
            && RunPolicy.effectiveAnimation(.edgesOnly, respectReduceMotion: true, reduceMotion: true) == .off,
          "Bewegung reduzieren: wirksame Animation ist Aus")
        c(RunPolicy.effectiveAnimation(.all, respectReduceMotion: true, reduceMotion: false) == .all
            && RunPolicy.effectiveAnimation(.edgesOnly, respectReduceMotion: false, reduceMotion: true) == .edgesOnly,
          "Bewegung reduzieren: ohne den Schalter in macOS oder mit ausgeschalteter Option bleibt die Wahl")
        c(plan { $0.reduceMotion = true }.kind == .frozenReduceMotion && !plan { $0.reduceMotion = true }.animates,
          "Bewegung reduzieren: der Lauf wird zum Standbild")
        c(plan { $0.reduceMotion = true; $0.respectReduceMotion = false }.kind == .running, "Bewegung reduzieren: Option aus, Animation läuft")
        c(plan { $0.reduceMotion = true; $0.animation = .off }.kind == .frozenByUser, "Bewegung reduzieren: bei Aus bleibt es Aus durch den Nutzer")
        c(plan { $0.reduceMotion = false }.kind == .running, "Bewegung reduzieren: Schalter in macOS wieder aus, Animation läuft wieder")
        c(plan { $0.lowPowerMode = true }.kind == .frozenLowPower && plan { $0.lowPowerMode = true; $0.freezeInLowPower = false }.kind == .running,
          "Energiesparmodus: wie bisher")
        let defaults = AppSettings()
        c(defaults.throttleWhenHot && defaults.respectReduceMotion && !defaults.welcomeShown,
          "Neue Einstellungen: Bei Hitze drosseln und Bewegung reduzieren beachten sind standardmäßig an")

        // Pause: every reason alone stops, all must go to start again.
        for r in PauseReason.allCases {
            c(plan { $0.pauseReasons = [r] }.kind == .pausedBySystem && !plan { $0.pauseReasons = [r] }.animates, "Pause: \(r.rawValue) hält an")
        }
        c(plan { $0.pauseReasons = [.screenLocked]; $0.animation = .off }.kind == .pausedBySystem, "Pause: gesperrt zählt auch bei Aus")
        let w = SystemWatch(resumeDelay: 0, observe: false)
        var changes = 0
        w.onChange = { changes += 1 }
        w.set(.screenLocked, true)
        w.set(.displaysAsleep, true)
        c(w.isPaused && changes == 1, "Pause: gesperrt und Display aus meldet einmal")
        w.set(.screenLocked, false)
        c(w.isPaused && changes == 1, "Pause: entsperrt, aber das Display schläft noch: bleibt angehalten")
        w.set(.displaysAsleep, false)
        c(!w.isPaused && changes == 2, "Pause: Display wach, nichts mehr offen: läuft wieder")
        w.set(.systemAsleep, true); w.set(.systemAsleep, true)
        c(changes == 3, "Pause: dieselbe Meldung zweimal ändert nichts")
        w.set(.systemAsleep, false)
        let slow = SystemWatch(resumeDelay: 0.15, observe: false)
        var slowChanges = 0
        slow.onChange = { slowChanges += 1 }
        slow.set(.systemAsleep, true)
        slow.set(.systemAsleep, false)
        c(slow.isPaused && slowChanges == 1, "Pause: nach dem Aufwachen wartet der Start einen Moment")
        slow.set(.screenLocked, true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        c(slow.isPaused && slowChanges == 1, "Pause: Aufwachen und sofort Sperrbildschirm: kein Bild dazwischen")
        slow.set(.screenLocked, false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        c(!slow.isPaused && slowChanges == 2, "Pause: nach dem Warten läuft es wieder")

        // Welcome window: only for a fresh install.
        c(Welcome.shouldShow(freshInstall: true, shown: false) && !Welcome.shouldShow(freshInstall: true, shown: true)
            && !Welcome.shouldShow(freshInstall: false, shown: false) && !Welcome.shouldShow(freshInstall: false, shown: true),
          "Willkommen: nur bei frischer Installation und nur einmal")
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("bh-welcome-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        let fresh = Store(persist: true, file: url)
        c(fresh.freshInstall && Welcome.shouldShow(freshInstall: fresh.freshInstall, shown: fresh.settings.welcomeShown),
          "Willkommen: ohne settings.json zeigt sich das Fenster")
        fresh.settings.welcomeShown = true
        fresh.save()
        let again = Store(persist: false, file: url)
        c(fm.fileExists(atPath: url.path) && !again.freshInstall && again.settings.welcomeShown
            && !Welcome.shouldShow(freshInstall: again.freshInstall, shown: again.settings.welcomeShown),
          "Willkommen: beim nächsten Start gibt es die Datei, kein Fenster")
        // A file from an older version has no welcomeShown at all: still no window.
        let old = Store(persist: false, read: false)
        if var raw = old.encoded().flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }),
           var st = raw["settings"] as? [String: Any] {
            for k in ["welcomeShown", "throttleWhenHot", "respectReduceMotion"] { st[k] = nil }
            raw["settings"] = st
            try? JSONSerialization.data(withJSONObject: raw).write(to: url)
        }
        let existing = Store(persist: false, file: url)
        c(!existing.freshInstall && !existing.settings.welcomeShown
            && !Welcome.shouldShow(freshInstall: existing.freshInstall, shown: existing.settings.welcomeShown),
          "Willkommen: bestehende Datei ohne den Schalter, kein Fenster für bisherige Nutzer")
        c(existing.settings.throttleWhenHot && existing.settings.respectReduceMotion,
          "Alte Datei: die neuen Schalter bekommen ihre Standardwerte")
        // Broken file: set aside, but not a first launch either.
        try? Data("{ kaputt".utf8).write(to: url)
        let broken = Store(persist: false, file: url)
        c(!broken.freshInstall, "Willkommen: eine kaputte Datei ist keine frische Installation")
        c(Welcome.presets.count == 7, "Willkommen: sieben eingebaute Voreinstellungen im Auswahlfeld")
        let thumbs = Welcome.presets.compactMap { Welcome.thumbnail($0, width: 120, height: 75) }
        c(thumbs.count == 7, "Willkommen: alle sieben Vorschaubilder lassen sich zeichnen")
        let applied = Store(persist: false, read: false)
        applied.assignToAllScreens("eisblau")
        c(NSScreen.screens.allSatisfy { applied.config(for: $0).presetID == "eisblau" }, "Willkommen: Auswahl wirkt gleich auf alle Schirme")

        // Old settings files get the new keys with defaults and keep everything else.
        func load(_ json: String) -> AppSettings? { try? JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)) }
        let o = load(#"{"animation": "edgesOnly", "fpsPower": 60, "freezeInLowPower": false, "language": "en"}"#)
        c(o?.animation == .edgesOnly && o?.fpsPower == 60 && o?.freezeInLowPower == false && o?.language == "en",
          "Alte Datei: bisherige Werte bleiben")
        c(o?.throttleWhenHot == true && o?.respectReduceMotion == true && o?.welcomeShown == false, "Alte Datei: neue Werte bekommen Standard")
        c(load("{}") == AppSettings(), "Alte Datei: leere Einstellungen ergeben die Standardwerte")
        c(load(#"{"throttleWhenHot": false, "respectReduceMotion": false, "welcomeShown": true}"#).map { !$0.throttleWhenHot && !$0.respectReduceMotion && $0.welcomeShown } == true,
          "Neue Datei: gespeicherte Werte bleiben")
        let full = Store(persist: false, read: false)
        full.settings.throttleWhenHot = false
        full.settings.welcomeShown = true
        let reloaded = Store(persist: false, read: false)
        c(full.encoded().map { reloaded.load(from: $0) } == true && !reloaded.settings.throttleWhenHot && reloaded.settings.welcomeShown,
          "Speichern und Laden: die neuen Werte kommen zurück")
        full.resetAllToFactory()
        c(full.settings.welcomeShown && full.settings.throttleWhenHot, "Werkseinstellung: das Willkommensfenster kommt nicht wieder")
        return failed
    }
}

/// Plans must compare equal when nothing changed; the app skips the rebuild then.
enum PlanStability {
    static var holds: Bool {
        var i = RunInputs()
        i.heat = .serious
        let hot = RunPolicy.plan(i)
        i.heat = .fair
        let cool = RunPolicy.plan(i)
        i.heat = .serious
        return hot == RunPolicy.plan(i) && cool != hot && cool.qualityStep == 0
    }
}
