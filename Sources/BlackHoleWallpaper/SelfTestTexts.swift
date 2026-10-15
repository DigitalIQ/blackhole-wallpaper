import Foundation

extension SelfTest {
    /// Every German source text the catalogs and fixed lists show, for the coverage check.
    static func catalogTexts() -> Set<String> {
        var t = Set<String>()
        for v in ObjectCatalog.all {
            t.insert(v.title)
            v.menu.forEach { t.insert($0) }
            for p in v.params {
                t.insert(p.title)
                t.insert(p.group)
                if let h = p.help { t.insert(h) }
                p.options?.forEach { t.insert($0) }
            }
            for e in v.events { if let s = ShipCatalog.event(e) { t.insert(s.title) } }
            let o = v.make(1)
            if !o.name.isEmpty { t.insert(o.name) }
        }
        let scenes = ObjectCatalog.starSystemScene().items + ObjectCatalog.sciFiScene().items + ObjectCatalog.demoScene()
        scenes.map(\.name).filter { !$0.isEmpty }.forEach { t.insert($0) }
        Motion.titles.values.forEach { t.insert($0) }
        Palette.builtIn.forEach { t.insert($0.name) }
        Palette.slotNames.forEach { t.insert($0) }
        EdgeStyle.flowModes.forEach { t.insert($0) }
        SettingsView.pages.forEach { t.insert($0.0) }
        Preset.factory.forEach { t.insert($0.name) }
        ["leicht", "mittel", "schwer", " (nah)"].forEach { t.insert($0) }
        QualityLevel.allCases.forEach { t.insert($0.key) }
        QualityArea.allCases.forEach { t.insert($0.key); t.insert($0.help) }
        // The ships' universes are names; a few have a German name ("Echte Raumfahrt", "Weitere").
        return t
    }

    /// L("…") keys written in the sources. Only runs from the project folder.
    static func sourceKeys() -> Set<String>? {
        let fm = FileManager.default
        let roots = ["Sources/BlackHoleWallpaper", "Saver"]
        guard fm.fileExists(atPath: roots[0]) else { return nil }
        let pattern = try! NSRegularExpression(pattern: #"(?<![A-Za-z_.])L\("(?!"")((?:[^"\\]|\\.)*)""#)
        var keys = Set<String>()
        for root in roots {
            for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where name.hasSuffix(".swift") {
                guard let src = try? String(contentsOfFile: root + "/" + name, encoding: .utf8) else { continue }
                // Comment lines do not count.
                let code = src.split(separator: "\n", omittingEmptySubsequences: false)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
                for m in pattern.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                    guard let r = Range(m.range(at: 1), in: code) else { continue }
                    keys.insert(String(code[r]).replacingOccurrences(of: #"\""#, with: "\"").replacingOccurrences(of: #"\\"#, with: "\\"))
                }
            }
        }
        return keys
    }

    /// Format specifiers like %@, %d, %.1f in order.
    private static func specifiers(_ s: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"%[0-9.]*[@dfs]"#)
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s).map { String(s[$0]) } }
    }

    /// Both languages for every key, nothing empty, no dashes or emoji, same placeholders; every text shown is in the table.
    static func textChecks(_ check: (Bool, String) -> Void) -> Int {
        var failed = 0
        func c(_ ok: Bool, _ what: String) { check(ok, what); if !ok { failed += 1 } }
        let table = Loc.en
        var empty: [String] = [], dashes: [String] = [], emoji: [String] = [], formats: [String] = [], german: [String] = []
        for (de, en) in table {
            if de.trimmingCharacters(in: .whitespaces).isEmpty || en.trimmingCharacters(in: .whitespaces).isEmpty { empty.append(de) }
            if (de + en).contains("–") || (de + en).contains("—") { dashes.append(de) }
            if (de + en).unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) { emoji.append(de) }
            if specifiers(de) != specifiers(en) { formats.append(de) }
            if en.range(of: "[äöüÄÖÜß„]", options: .regularExpression) != nil { german.append(de) }
        }
        c(empty.isEmpty, "Texte: \(table.count) Schlüssel, jeder hat Deutsch und Englisch, keiner leer \(empty.prefix(5))")
        c(dashes.isEmpty, "Texte: keine Gedankenstriche \(dashes.prefix(5))")
        c(emoji.isEmpty, "Texte: keine Emojis \(emoji.prefix(5))")
        c(formats.isEmpty, "Texte: gleiche Platzhalter in beiden Sprachen \(formats.prefix(5))")
        c(german.isEmpty, "Texte: keine Umlaute oder deutschen Anführungszeichen im Englischen \(german.prefix(5))")

        let catalog = catalogTexts()
        // BH_MISSING_TEXTS=file.json: writes every key without a translation, sorted, as a start for the table.
        if let path = ProcessInfo.processInfo.environment["BH_MISSING_TEXTS"] {
            let all = catalog.union(sourceKeys() ?? []).filter { table[$0] == nil }.sorted()
            try? JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: path))
        }
        let missingCatalog = catalog.filter { table[$0] == nil }.sorted()
        c(missingCatalog.isEmpty, "Texte: Katalog, Paletten und Seiten vollständig übersetzt (\(catalog.count)) \(missingCatalog.prefix(8))")
        if let source = sourceKeys() {
            let missing = source.filter { table[$0] == nil }.sorted()
            c(missing.isEmpty, "Texte: jedes L(…) im Code steht in der Tabelle (\(source.count)) \(missing.prefix(8))")
            let unused = table.keys.filter { !source.contains($0) && !catalog.contains($0) && !dynamicKeys.contains($0) }.sorted()
            c(unused.isEmpty, "Texte: keine verwaisten Einträge \(unused.prefix(8))")
        } else {
            print("…     Quellen nicht gefunden, Abgleich mit dem Code übersprungen (aus dem Projektordner starten)")
        }

        // Built-in names: shown per language, stored unchanged.
        let s = Store(persist: false, read: false)
        let before = s.encoded()
        s.settings.language = "en"
        let names = Dictionary(uniqueKeysWithValues: s.presets.map { ($0.id, $0.displayName) })
        c(names["strudel"] == "Swirl" && names["gargantua"] == "Gargantua" && names["m87"] == "M87* as photographed"
            && names["draufsicht"] == "Top View" && names["eisblau"] == "Ice Blue" && names["sternsystem"] == "Star System"
            && names["scifi"] == "Sci-Fi Harbor", "Texte: eingebaute Voreinstellungen auf Englisch \(names.values.sorted())")
        s.settings.language = "de"
        c(s.preset("strudel").displayName == "Dein Strudel", "Texte: auf Deutsch heißt Dein Strudel wie bisher")
        s.settings.language = "system"
        c(before == s.encoded(), "Texte: Sprachwechsel ändert keine gespeicherten Namen")
        s.rename("gargantua", to: "Mein Loch")
        s.settings.language = "en"
        c(s.preset("gargantua").displayName == "Mein Loch", "Texte: umbenannte und eigene Voreinstellungen werden nicht übersetzt")
        c(ObjectCatalog.displayName("Roter Riese (nah)") == "Red Giant (near)", "Texte: Name eines nahen Sterns auf Englisch")
        c(L("%@ Kopie", "Swirl") == "Swirl copy", "Texte: Platzhalter werden gefüllt")
        s.settings.language = "system"
        return failed
    }

    /// Keys only built at run time (format strings of sliders).
    static let dynamicKeys: Set<String> = ["%.1f° pro s", "%.1f° pro Minute"]
}
