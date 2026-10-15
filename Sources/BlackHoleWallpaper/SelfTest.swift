import Foundation
import simd

/// `--selftest`: plays the per-screen copy rules through with made-up screen keys, without
/// screens and without touching settings.json. Exit code 0 when every check holds.
enum SelfTest {
    static func run() -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print((ok ? "ok    " : "FEHLER ") + what)
            if !ok { failures += 1 }
        }
        let check: (Bool, String) -> Void = check

        let s = Store(persist: false, read: false)
        // The copy names below are the German ones.
        s.settings.language = "de"
        let wide = "WIDE-KEY", tall = "TALL-KEY", away = "AWAY-KEY"
        s.connectedKeys = { [wide, tall] }
        s.shortName = { $0 == wide ? "Ultrawide" : "Hochkant" }
        s.settings.screens = [wide: ScreenConfig(presetID: "strudel"), tall: ScreenConfig(presetID: "strudel", holeY: 0.3)]
        let original = s.preset("strudel").look
        let count0 = s.presets.count

        // 1. Shared preset: the chosen screen gets a copy, the other one keeps the original.
        s.selectScreen(wide)
        check(s.editingID == "strudel", "Ultrawide gewählt: Auswahl zeigt sein Preset")
        s.binding(\.spin).wrappedValue = 0.5
        let copy = s.presetID(forKey: wide)
        check(copy != "strudel", "Wert geändert: Ultrawide hat eine eigene Kopie")
        check(s.preset(copy).name == "Dein Strudel (Ultrawide)", "Kopie heißt \"\(s.preset(copy).name)\"")
        check(s.preset(copy).look.spin == 0.5, "Kopie hat den neuen Wert")
        check(s.presetID(forKey: tall) == "strudel" && s.preset("strudel").look == original, "Hochkant und Original unverändert")
        check(s.editingID == copy, "Fenster bearbeitet jetzt die Kopie")

        // 2. Only this screen uses it now: change in place, no second copy.
        s.binding(\.diskBrightness).wrappedValue = 2
        check(s.presets.count == count0 + 1 && s.presetID(forKey: wide) == copy, "Zweite Änderung: keine weitere Kopie")
        check(s.preset(copy).look.diskBrightness == 2, "Zweite Änderung landet in der Kopie")

        // 3. A screen that is not connected still counts as a user.
        s.settings.screens[away] = ScreenConfig(presetID: "strudel")
        s.selectScreen(tall)
        s.binding(\.exposure).wrappedValue = 2
        let tallCopy = s.presetID(forKey: tall)
        check(tallCopy != "strudel" && s.preset(tallCopy).name == "Dein Strudel (Hochkant)",
              "Nicht angeschlossener Schirm teilt das Preset: Hochkant bekommt eine Kopie")
        check(s.presetID(forKey: away) == "strudel" && s.preset("strudel").look == original, "Eintrag des fehlenden Schirms bleibt")

        // 4. Sole user: changed directly.
        s.settings.screens[away] = nil
        s.selectScreen(tall)
        let before = s.presets.count
        s.binding(\.stars).wrappedValue = 0.2
        check(s.presets.count == before && s.preset(tallCopy).look.stars == 0.2, "Einziger Nutzer: direkt geändert")

        // 5. All screens with different presets: locked.
        s.selectScreen(nil)
        check(s.lookLocked, "Alle Schirme, verschiedene Presets: Regler gesperrt")

        // 6. All screens, one preset chosen: set everywhere, edits change it directly.
        s.settings.screens[away] = ScreenConfig(presetID: "eisblau")
        s.choosePreset("gargantua")
        check(!s.lookLocked && s.presetID(forKey: wide) == "gargantua" && s.presetID(forKey: tall) == "gargantua",
              "Alle Schirme: Preset für beide gesetzt")
        check(s.presetID(forKey: away) == "eisblau", "Nicht angeschlossener Schirm behält sein Preset")
        let n6 = s.presets.count
        s.binding(\.ringGlow).wrappedValue = 2.5
        check(s.presets.count == n6 && s.preset("gargantua").look.ringGlow == 2.5, "Alle Schirme: gemeinsames Preset direkt geändert")

        // 7. One screen, preset picker only touches that screen.
        s.selectScreen(wide)
        s.choosePreset("eisblau")
        check(s.presetID(forKey: wide) == "eisblau" && s.presetID(forKey: tall) == "gargantua", "Preset-Wechsel nur für Ultrawide")
        s.selectScreen(nil)
        check(s.lookLocked, "Danach wieder gesperrt bei Alle Schirme")

        // 8. Copy of a copy keeps a clean name; a taken name gets a number.
        s.selectScreen(wide)
        s.choosePreset(copy)
        s.selectScreen(tall)
        s.choosePreset(copy)
        s.binding(\.spin).wrappedValue = 0.7
        check(s.preset(s.presetID(forKey: tall)).name == "Dein Strudel (Hochkant 2)",
              "Kopie einer Kopie heißt \"\(s.preset(s.presetID(forKey: tall)).name)\"")

        // 9. Old settings files.
        func mode(_ json: String) -> AnimationMode? {
            (try? JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)))?.animation
        }
        check(mode(#"{"animationOn": true}"#) == .all, "Alte Datei animationOn true wird Alles")
        check(mode(#"{"animationOn": false}"#) == .off, "Alte Datei animationOn false wird Aus")
        check(mode(#"{"animation": false}"#) == .off, "Alte Datei animation false wird Aus")
        check(mode(#"{"animation": true}"#) == .all, "Alte Datei animation true wird Alles")
        check(mode(#"{"animation": "edgesOnly"}"#) == .edgesOnly, "Neue Datei Nur Ränder")
        check(mode("{}") == .all, "Ohne Eintrag: Alles")
        var round = AppSettings()
        round.animation = .edgesOnly
        round.hideMenuIcon = true
        let back = (try? JSONEncoder().encode(round)).flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) }
        check(back == round, "Speichern und Laden ergibt dieselben Einstellungen")

        // 10. Objects in the look.
        failures += objectChecks(check)
        failures += motionChecks(check)
        failures += gltfChecks(check)
        failures += fileChecks(check)
        failures += textChecks(check)
        failures += qualityChecks(check)
        failures += updateChecks(check)
        failures += step1Checks(check)
        if let i = CommandLine.arguments.firstIndex(of: "--settings-file"), i + 1 < CommandLine.arguments.count {
            failures += settingsFileCheck(CommandLine.arguments[i + 1], check)
        }

        print(failures == 0 ? "Alle Prüfungen bestanden." : "\(failures) Prüfung(en) fehlgeschlagen.")
        return failures == 0 ? 0 : 1
    }

    /// Returns the number of failed checks (they are already printed by check).
    /// Quality levels: defaults, old files with mapScale and detailBox, unknown entries, the saver's copy.
    private static func qualityChecks(_ check: (Bool, String) -> Void) -> Int {
        var failed = 0
        func c(_ ok: Bool, _ what: String) { check(ok, what); if !ok { failed += 1 } }
        func load(_ json: String) -> AppSettings? { try? JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)) }
        let d = AppSettings()
        c(d.quality.power == .high && d.quality.battery == .balanced && d.quality.areas.isEmpty,
          "Qualität: Standard ist Hoch am Netzteil und Ausgewogen am Akku")
        c(d.quality.resolved(battery: false).level(.hole) == 2 && d.quality.resolved(battery: true).level(.hole) == 1,
          "Qualität: ohne eigene Wahl rechnet das Netzteil mit Hoch, der Akku mit Ausgewogen")
        c(load("{}")?.quality == d.quality, "Qualität: alte Datei ohne Stufen lädt mit Standard")
        c(load(#"{"quality": {"power": 1, "battery": 1}}"#)?.quality.power == .balanced,
          "Qualität: gespeichertes Ausgewogen am Netzteil bleibt")
        let partial = load(#"{"quality": {"battery": 0}}"#)?.quality
        c(partial?.power == .high && partial?.battery == .saver, "Qualität: Eintrag ohne Stufe am Netzteil bekommt Hoch")
        c(load(#"{"mapScale": 0.6}"#)?.quality.power == .high, "Qualität: alte Datei mit mapScale bekommt am Netzteil Hoch")
        c(load(#"{"mapScale": 0.5, "detailBox": true}"#)?.quality.areas.isEmpty == true, "Qualität: mapScale 0,5 bleibt bei der Gesamtstufe")
        c(load(#"{"mapScale": 0.75}"#)?.quality.areas["hole"] == .ultra, "Qualität: mapScale 0,75 wird Loch und Scheibe Ultra")
        c(load(#"{"mapScale": 0.6}"#)?.quality.areas["hole"] == .high, "Qualität: mapScale 0,6 wird Loch und Scheibe Hoch")
        c(load(#"{"mapScale": 0.3}"#)?.quality.areas["hole"] == .saver, "Qualität: mapScale 0,3 wird Loch und Scheibe Akku sparen")
        c(load(#"{"detailBox": false}"#)?.quality.areas["hole"] == .saver, "Qualität: ohne scharfe Zone wird Loch und Scheibe Akku sparen")
        let odd = load(#"{"quality": {"power": 3, "battery": 9, "areas": {"jet": 2, "warp": 1, "sky": 7}}}"#)
        c(odd?.quality.power == .ultra && odd?.quality.battery == .balanced && odd?.quality.areas == ["jet": .high],
          "Qualität: unbekannte Bereiche und Stufen werden verworfen")
        var q = QualitySettings()
        q.power = .high; q.areas["bodies"] = .saver
        let back = (try? JSONEncoder().encode(q)).flatMap { try? JSONDecoder().decode(QualitySettings.self, from: $0) }
        c(back == q, "Qualität: Speichern und Laden ergibt dieselben Stufen")
        let r = q.resolved(battery: false), rb = q.resolved(battery: true)
        c(r.level(.jet) == 2 && r.level(.bodies) == 0 && rb.level(.jet) == 1 && rb.level(.bodies) == 0,
          "Qualität: eigene Stufe eines Bereichs gilt am Netzteil und am Akku")
        c(RenderQuality().mapScale(width: 3440, height: 1440, jet: true) == 0.5, "Qualität: Ausgewogen rechnet die Strahlenkarte in halber Auflösung")
        let ultra = RenderQuality(.ultra)
        let ms = ultra.mapScale(width: 3440, height: 1440, jet: true)
        c(Float(3440 * 1440) * ms * ms <= RenderQuality.mapTexelCap * 1.001, "Qualität: Ultra bleibt auf 3440 x 1440 unter 2,8 Millionen Kartenpunkten")
        c(ultra.mapScale(width: 5120, height: 2880, jet: false) < 0.75, "Qualität: Ultra wächst auf einem 5K-Schirm nicht über 2,8 Millionen Kartenpunkte")
        let saver = SaverConfig.decode(Data(#"{"look": {}, "holeX": 0.4, "holeY": 0.5}"#.utf8))
        c(saver?.quality == QualitySettings() && saver?.quality.power == .high,
          "Qualität: alte saver.json ohne Stufen lädt, der Bildschirmschoner rechnet mit Hoch")
        var cfg = SaverConfig(look: Look(), holeX: 0.5, holeY: 0.5)
        cfg.quality.power = .ultra
        let cb = (try? JSONEncoder().encode(cfg)).flatMap(SaverConfig.decode)
        c(cb?.quality.power == .ultra, "Qualität: Bildschirmschoner bekommt die Stufe am Netzteil")
        return failed
    }

    private static func objectChecks(_ check: (Bool, String) -> Void) -> Int {
        var failed = 0
        func c(_ ok: Bool, _ what: String) { check(ok, what); if !ok { failed += 1 } }
        func look(_ json: String) -> Look? { Look.decodeLenient(Data(json.utf8)) }

        let old = look(#"{"spin": 0.5, "exposure": 1.3}"#)
        c(old?.objects == ObjectScene() && old?.spin == 0.5 && old?.exposure == 1.3, "Alte Voreinstellung ohne objects: Szene leer, Werte bleiben")
        c(old?.geometryKey == Look(spin: 0.5).geometryKey, "Ohne Jet bleibt der Geometrie-Schlüssel wie vorher")

        let mixed = look(#"{"objects": {"items": [{"id": "a", "kind": "dragon", "variant": "red", "size": 3},"#
                         + #" {"id": "b", "kind": "galaxy"}, 42, {"kind": "star"}, {"id": "c", "kind": "star", "size": "groß"}]}}"#)
        let items = mixed?.objects.items ?? []
        c(items.map(\.id) == ["a", "b", "c"], "Kaputte Elemente übersprungen, Rest bleibt (\(items.map(\.id)))")
        c(items.first?.kind == "dragon" && mixed?.objects.active.map(\.id) == ["b", "c"], "Unbekannte Art bleibt erhalten, wird aber nicht gezeichnet")
        c(items.dropFirst().first?.size == 1 && items.dropFirst().first?.motion == Motion() && mixed?.objects.speed == 1,
          "Fehlende Schlüssel mit Standard gefüllt")
        c(items.last?.size == 1, "Falscher Typ bei einem Wert: Standard statt Fehler")
        if let m = mixed, let d = try? JSONEncoder().encode(m), let back = Look.decodeLenient(d) {
            c(back.objects.items.first?.kind == "dragon", "Unbekannte Art übersteht Speichern und Laden")
        } else { c(false, "Unbekannte Art übersteht Speichern und Laden") }

        var demo = Look()
        demo.objects.items = ObjectCatalog.demoScene()
        let back = (try? JSONEncoder().encode(demo)).flatMap(Look.decodeLenient)
        c(back == demo, "Szene mit allen Arten: Speichern und Laden ergibt dieselbe Szene")
        c(demo.geometryKey.count > Look().geometryKey.count, "Jet hängt seine Werte an den Geometrie-Schlüssel")
        var noJet = demo
        noJet.objects.items.removeAll { $0.kind == "jet" }
        c(noJet.geometryKey == Look().geometryKey, "Galaxien und Sterne ändern den Geometrie-Schlüssel nicht")

        let saverOld = #"{"look": {"spin": 0.7}, "holeX": 0.4, "holeY": 0.6}"#
        let sc = SaverConfig.decode(Data(saverOld.utf8))
        c(sc?.look.spin == 0.7 && sc?.holeX == 0.4 && sc?.look.objects == ObjectScene(), "Alte saver.json lädt, Szene leer")
        let saverNew = (try? JSONEncoder().encode(SaverConfig(look: demo, holeX: 0.5, holeY: 0.5))).flatMap(SaverConfig.decode)
        c(saverNew?.look.objects == demo.objects, "Schoner bekommt die Szene mit")

        // Ships, stations, models (stage 3).
        var fleet = Look()
        fleet.objects.items = ObjectCatalog.shipDemoScene()
        var model = ObjectCatalog.models[0].make(5)
        model.model = "nicht da.obj"
        model.events = ObjectEvents(on: true, kinds: ["warp", "cloak"], interval: 60)
        fleet.objects.items.append(model)
        let fleetBack = (try? JSONEncoder().encode(fleet)).flatMap(Look.decodeLenient)
        c(fleetBack == fleet, "Schiffe, Stationen, Ereignisse und Modell: Speichern und Laden ergibt dieselbe Szene")
        c(fleet.geometryKey == Look().geometryKey, "Schiffe ändern den Geometrie-Schlüssel nicht")
        let ships = ObjectCatalog.ships
        c(ships.allSatisfy { ShipCatalog.mesh(for: $0.make(1)).map { $0.data.triangles > 0 && $0.radius > 0.4 && $0.radius < 0.9 } ?? false },
          "Jedes Schiff und jede Station hat ein Netz (\(ships.count) Varianten)")
        let borgA = ShipCatalog.build("borg"), borgB = ShipCatalog.build("borg")
        let borgTris = borgA?.triangles ?? 0
        c(borgA != nil && borgA?.v == borgB?.v && borgA?.idx == borgB?.idx && (8000...40000).contains(borgTris),
          "Borg-Würfel: Netz deterministisch, \(borgTris) Dreiecke (8000 bis 40000)")
        c(ships.allSatisfy { $0.events.allSatisfy { ShipCatalog.event($0) != nil } }, "Alle Ereignisse der Schiffe sind bekannt")
        var universes: [String: Int] = [:]
        for v in ships where v.kind == .ship { universes[v.menu[1], default: 0] += 1 }
        c(universes.values.allSatisfy { $0 >= 2 }, "Mindestens zwei Schiffe je Universum (\(universes.count) Universen)")
        c(ModelStore.mesh(named: "nicht da.obj") == nil && ModelStore.problem("nicht da.obj") != nil, "Fehlendes Modell: nichts gezeichnet, Hinweis statt Absturz")
        let oldEvents = look(#"{"objects": {"items": [{"id": "s", "kind": "ship", "variant": "falcon", "events": {"on": true}}]}}"#)
        c(oldEvents?.objects.items.first?.events.interval == 120 && oldEvents?.objects.items.first?.events.kinds == [], "Ereignisse mit fehlenden Schlüsseln: Standard")

        // Stage 4: second holes, wormholes and gates.
        var exo = Look()
        exo.objects.items = ObjectCatalog.exotics.map { $0.make(3) }
        exo.objects.items.append(ObjectCatalog.variant("station", "stargate")!.make(4))
        let exoBack = (try? JSONEncoder().encode(exo)).flatMap(Look.decodeLenient)
        c(exoBack == exo, "Zweites Loch, Wurmloch und Tor: Speichern und Laden ergibt dieselbe Szene")
        c(exo.geometryKey == Look().geometryKey, "Linsen ändern den Geometrie-Schlüssel des Hauptlochs nicht")
        let sys = ObjectSystem()
        let lf = sys.lenses(look: exo, layout: ScreenLayout(holeX: 0.5, holeY: 0.5, topBar: 0, bottomBar: 0), width: 1720, height: 720, pxScale: 1)
        c(lf.count <= ObjectSystem.maxLenses && lf.data.count == lf.count * LensFrame.stride && lf.maps.compactMap { $0 }.count <= ObjectSystem.maxHoles,
          "Linsenliste: höchstens \(ObjectSystem.maxLenses) Linsen, \(ObjectSystem.maxHoles) kleine Strahlenkarten")
        let maps = lf.maps.compactMap { $0 }
        c(maps.allSatisfy { $0.res * $0.res * (24 + ($0.jet ? 8 : 0)) <= 8 << 20 }, "Kleine Strahlenkarte höchstens 8 MB")
        // Galaxy pair: an old file without the member types bakes as two spirals, exactly as before.
        let oldPair = look(#"{"objects": {"items": [{"id": "p", "kind": "galaxy", "variant": "pair", "seed": 3, "size": 30, "motion": {"mode": "sky"}}]}}"#)
        let pairBake = oldPair.map { sys.frame(look: $0, width: 1720, height: 720).galaxies.first?.params ?? [] } ?? []
        let pairSpec = ObjectCatalog.variant("galaxy", "pair")
        c(pairBake.count == 4 && pairBake[0].x == 7 && pairBake[3].y == 0 && pairBake[3].z == 0
          && pairSpec?.param("typeA")?.def == 0 && pairSpec?.param("typeB")?.def == 0 && ObjectCatalog.pairTypeCodes[0] == 0,
          "Galaxienpaar ohne Arten in der Datei: zwei Spiralen wie bisher")
        let port = Preset.factory.first { $0.id == "scifi" }
        c(port != nil && port!.look.objects.items.contains { $0.objectKind == .wormhole }, "Eingebaute Voreinstellung SciFi-Hafen mit Wurmloch")
        c(ShipCatalog.event("wormhole") != nil && ShipCatalog.design("endurance")?.events == ["wormhole"], "Endurance fliegt durchs Wurmloch")

        // Monitor copy carries the objects; the original keeps its own.
        let s = Store(persist: false, read: false)
        s.connectedKeys = { ["W", "T"] }
        s.shortName = { $0 == "W" ? "Ultrawide" : "Hochkant" }
        s.settings.screens = ["W": ScreenConfig(presetID: "strudel"), "T": ScreenConfig(presetID: "strudel")]
        s.presets[0].look.objects.items = [ObjectCatalog.variant("galaxy", "spiral")!.make(1)]
        s.selectScreen("W")
        var sceneW = s.binding(\.objects).wrappedValue
        sceneW.items.append(ObjectCatalog.variant("star", "G")!.make(2))
        s.binding(\.objects).wrappedValue = sceneW
        let copy = s.preset(s.presetID(forKey: "W"))
        c(copy.id != "strudel" && copy.look.objects.items.count == 2, "Monitor-Kopie übernimmt die Objekte und bekommt den neuen dazu")
        c(s.preset("strudel").look.objects.items.count == 1, "Original behält seine Szene")
        return failed
    }

    /// Loads a copy of a real settings.json and checks that nothing is lost on the way through.
    private static func settingsFileCheck(_ path: String, _ check: (Bool, String) -> Void) -> Int {
        var failed = 0
        func c(_ ok: Bool, _ what: String) { check(ok, what); if !ok { failed += 1 } }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let orig = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            c(false, "Datei \(path) lesbar"); return failed
        }
        let s = Store(persist: false, read: false)
        s.load(from: data)
        guard let out = s.encoded(), let new = try? JSONSerialization.jsonObject(with: out) as? [String: Any] else {
            c(false, "Einstellungen wieder kodierbar"); return failed
        }
        var lost: [String] = []
        func same(_ a: Any, _ b: Any, _ path: String) {
            if let x = a as? [String: Any] {
                guard let y = b as? [String: Any] else { lost.append(path); return }
                for (k, v) in x { if let w = y[k] { same(v, w, path + "." + k) } else { lost.append(path + "." + k) } }
            } else if let x = a as? [Any] {
                guard let y = b as? [Any], x.count == y.count else { lost.append(path); return }
                for (i, v) in x.enumerated() { same(v, y[i], path + "[\(i)]") }
            } else if let x = a as? NSNumber, let y = b as? NSNumber {
                if abs(x.doubleValue - y.doubleValue) > 1e-6 * max(1, abs(x.doubleValue)) { lost.append(path) }
            } else if let x = a as? String, let y = b as? String {
                if x != y { lost.append(path) }
            } else if "\(a)" != "\(b)" { lost.append(path) }
        }
        let origPresets = (orig["presets"] as? [[String: Any]]) ?? []
        let newPresets = (new["presets"] as? [[String: Any]]) ?? []
        for p in origPresets {
            guard let id = p["id"] as? String, let q = newPresets.first(where: { $0["id"] as? String == id }) else {
                lost.append("preset \(p["id"] ?? "?")"); continue
            }
            same(p, q, "preset \(p["name"] ?? id)")
        }
        if var st = orig["settings"] as? [String: Any] {
            // mapScale and detailBox went into the quality levels (checked in qualityChecks).
            let migrated = ["mapScale", "detailBox"].filter { st[$0] != nil }
            migrated.forEach { st[$0] = nil }
            same(st, new["settings"] ?? [:], "settings")
            if !migrated.isEmpty, let data = try? JSONSerialization.data(withJSONObject: orig["settings"]!),
               let back = try? JSONDecoder().decode(AppSettings.self, from: data) {
                var want = QualitySettings()
                let o = orig["settings"] as! [String: Any]
                want.migrate(mapScale: (o["mapScale"] as? NSNumber)?.floatValue, detailBox: (o["detailBox"] as? NSNumber)?.boolValue)
                c(back.quality == want, "settings.json: mapScale und detailBox gehen in die Qualitätsstufen über")
            }
        }
        c(lost.isEmpty, "settings.json (\(origPresets.count) Voreinstellungen) lädt ohne Verlust" + (lost.isEmpty ? "" : ": " + lost.prefix(8).joined(separator: ", ")))
        // Presets that had no objects in the file must come back with an empty scene.
        func hadItems(_ p: [String: Any]) -> Bool {
            (((p["look"] as? [String: Any])?["objects"] as? [String: Any])?["items"] as? [Any])?.isEmpty == false
        }
        let empty = Set(origPresets.filter { !hadItems($0) }.compactMap { $0["id"] as? String })
        c(s.presets.filter { empty.contains($0.id) }.allSatisfy { $0.look.objects.items.isEmpty }, "Voreinstellungen ohne Szene in der Datei bleiben leer")
        c(s.presets.contains { $0.id == "sternsystem" && !$0.look.objects.items.isEmpty }, "Neue eingebaute Voreinstellung Sternsystem kommt dazu")
        c(s.presets.contains { $0.id == "scifi" && !$0.look.objects.items.isEmpty }, "Neue eingebaute Voreinstellung SciFi-Hafen kommt dazu")
        return failed
    }

    /// The glTF reader on a tiny model made here: a triangle under two nodes (translation, scale), without
    /// normals, as .gltf with a data URI and as .glb; plus a required extension it cannot read and a broken accessor.
    private static func gltfChecks(_ check: (Bool, String) -> Void) -> Int {
        var failed = 0
        func c(_ ok: Bool, _ what: String) { check(ok, what); if !ok { failed += 1 } }
        var bin = Data()
        for f: Float in [0, 0, 0, 1, 0, 0, 0, 2, 0] { withUnsafeBytes(of: f.bitPattern.littleEndian) { bin.append(contentsOf: $0) } }
        for i: UInt16 in [0, 1, 2, 0] { withUnsafeBytes(of: i.littleEndian) { bin.append(contentsOf: $0) } }
        func doc(_ buffer: String, count: Int = 3, extra: String = "") -> String {
            #"{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"#
            + #""nodes":[{"translation":[10,0,0],"children":[1]},{"scale":[2,2,2],"mesh":0}],"#
            + #""meshes":[{"primitives":[{"attributes":{"POSITION":0},"indices":1,"material":0}]}],"#
            + #""materials":[{"pbrMetallicRoughness":{"baseColorFactor":[0.2,0.4,0.6,1],"metallicFactor":0.25,"roughnessFactor":0.75}}],"#
            + #""buffers":[{"byteLength":44\#(buffer)}],"#
            + #""bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":36},{"buffer":0,"byteOffset":36,"byteLength":6}],"#
            + #""accessors":[{"bufferView":0,"componentType":5126,"count":\#(count),"type":"VEC3"},{"bufferView":1,"componentType":5123,"count":3,"type":"SCALAR"}]"#
            + extra + "}"
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bh-gltf-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func write(_ name: String, _ d: Data) -> URL { let u = dir.appendingPathComponent(name); try? d.write(to: u); return u }

        let gltf = write("t.gltf", Data(doc(#","uri":"data:application/octet-stream;base64,\#(bin.base64EncodedString())""#).utf8))
        if case .success(let m) = GLTFLoader.load(gltf) {
            let (lo, hi) = m.bounds
            c(m.triangles == 1 && simd_distance(lo, SIMD3(10, 0, 0)) < 1e-4 && simd_distance(hi, SIMD3(12, 4, 0)) < 1e-4,
              "glTF: Dreieck unter zwei Knoten, Verschiebung und Skalierung angewandt")
            c(abs(abs(m.normal(0).z) - 1) < 1e-4, "glTF: fehlende Normalen werden berechnet")
            let mat = m.materials.first
            c(m.parts.count == 1 && mat?.base == SIMD4(0.2, 0.4, 0.6, 1) && mat?.metal == 0.25 && mat?.rough == 0.75,
              "glTF: Material mit Grundfarbe, Metall und Rauheit übernommen")
        } else { c(false, "glTF mit eingebettetem Puffer lädt") }
        if case .success(let m) = ModelImport.load(gltf) {
            let (lo, hi) = m.bounds
            c(abs(simd_reduce_max(hi - lo) - 1) < 1e-4, "glTF: wie die anderen Formate auf Länge 1 gebracht")
        } else { c(false, "glTF über ModelImport") }

        // The same as .glb: JSON chunk and binary chunk, each padded to four bytes.
        var json = Data(doc("").utf8)
        while json.count % 4 != 0 { json.append(0x20) }
        var body = bin
        while body.count % 4 != 0 { body.append(0) }
        var glb = Data("glTF".utf8)
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { glb.append(contentsOf: $0) } }
        u32(2); u32(12 + 8 + json.count + 8 + body.count)
        u32(json.count); u32(0x4E4F_534A); glb.append(json)
        u32(body.count); u32(0x004E_4942); glb.append(body)
        if case .success(let m) = GLTFLoader.load(write("t.glb", glb)) { c(m.triangles == 1, "GLB mit Binärteil lädt") } else { c(false, "GLB mit Binärteil lädt") }

        let draco = write("d.gltf", Data(doc("", extra: #","extensionsRequired":["KHR_draco_mesh_compression"]"#).utf8))
        if case .failure(let e) = GLTFLoader.load(draco) { c(e.description.contains("KHR_draco_mesh_compression"), "glTF: Pflicht-Erweiterung Draco gibt eine klare Meldung") }
        else { c(false, "glTF: Pflicht-Erweiterung Draco gibt eine klare Meldung") }
        // Import into the models folder: a .gltf with an external .bin goes into its own folder, also for the saver.
        let src = dir.appendingPathComponent("src", isDirectory: true)
        try? FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try? bin.write(to: src.appendingPathComponent("schiff daten.bin"))
        try? Data(doc(#","uri":"schiff%20daten.bin""#).utf8).write(to: src.appendingPathComponent("schiff.gltf"))
        let oldModels = ProcessInfo.processInfo.environment["BH_MODELS"]
        setenv("BH_MODELS", dir.appendingPathComponent("models").path, 1)
        let name = try? ModelStore.importFile(src.appendingPathComponent("schiff.gltf"))
        let copied = FileManager.default.fileExists(atPath: dir.appendingPathComponent("models/schiff/schiff daten.bin").path)
        c(name == "schiff/schiff.gltf" && copied && name.flatMap { ModelStore.mesh(named: $0) }?.data.triangles == 1,
          "glTF-Import: Datei mit externem Puffer in eigenen Ordner kopiert und geladen")
        ModelStore.exportForSaver(names: [name ?? ""], to: dir.appendingPathComponent("saver"))
        c(FileManager.default.fileExists(atPath: dir.appendingPathComponent("saver/Models/schiff/schiff daten.bin").path),
          "glTF-Import: Puffer geht mit zum Bildschirmschoner")
        if let o = oldModels { setenv("BH_MODELS", o, 1) } else { unsetenv("BH_MODELS") }

        let broken = write("b.gltf", Data(doc(#","uri":"data:application/octet-stream;base64,\#(bin.base64EncodedString())""#, count: 99).utf8))
        if case .failure(let e) = GLTFLoader.load(broken) { c(e.description == UIText.gltfBrokenData, "glTF: Accessor außerhalb des Puffers gibt eine Meldung statt eines Absturzes") }
        else { c(false, "glTF: kaputter Accessor") }
        return failed
    }
}
