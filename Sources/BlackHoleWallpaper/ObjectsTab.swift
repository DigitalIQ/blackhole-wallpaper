import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Local state of the objects page. A class instead of @State, see TabModel.
final class ObjectsTabModel: ObservableObject {
    @Published var selected: String?
    @Published var confirmDelete = false
    @Published var confirmClear = false
}

extension ObjectCatalog {
    static func icon(_ kind: String) -> String {
        switch ObjectKind(rawValue: kind) {
        case .galaxy: "hurricane"
        case .star: "sun.max.fill"
        case .jet: "arrow.up.and.down.circle"
        case .planet: "globe.americas.fill"
        case .moon: "moon.fill"
        case .asteroid: "circle.hexagongrid.fill"
        case .belt: "circle.dotted"
        case .comet: "sparkle"
        case .meteor: "line.diagonal"
        case .ship: "airplane"
        case .station: "building.2"
        case .model: "cube"
        case .blackHole: "circle.circle.fill"
        case .wormhole: "tornado"
        default: "questionmark.circle"
        }
    }
}

struct ObjectsTab: View {
    @EnvironmentObject var store: Store
    @StateObject private var m = ObjectsTabModel()

    private var scene: Binding<ObjectScene> { store.binding(\.objects) }

    private func item(_ id: String) -> Binding<SpaceObject> {
        let scene = self.scene
        return Binding(get: { scene.wrappedValue.items.first { $0.id == id } ?? SpaceObject() },
                       set: { new in
                           var s = scene.wrappedValue
                           guard let i = s.items.firstIndex(where: { $0.id == id }) else { return }
                           s.items[i] = new
                           scene.wrappedValue = s
                       })
    }

    private func param(_ o: Binding<SpaceObject>, _ key: String) -> Binding<Float> {
        Binding(get: { o.wrappedValue.param(key) }, set: { o.wrappedValue.params[key] = $0 })
    }

    /// The selected object, or the first one when nothing is selected yet.
    private func selectedID(_ items: [SpaceObject]) -> String? {
        if let s = m.selected, items.contains(where: { $0.id == s }) { return s }
        return items.first?.id
    }

    private static func ms(_ v: Float) -> String {
        let s = String(format: "%.2f", v)
        return Loc.lang == .de ? s.replacingOccurrences(of: ".", with: ",") : s
    }

    private var loadText: String {
        let active = scene.wrappedValue.active
        let specs = active.compactMap(ObjectCatalog.spec(for:))
        // Measured with --bench-ab (3440 x 1440): bodies and particles add passes that cost about 0.1 ms together.
        let passes: Float = active.contains { $0.objectKind != nil && ![.galaxy, .jet].contains($0.objectKind!) && !($0.objectKind == .star && $0.motion.mode == .sky) } ? 0.1 : 0
        let total = specs.reduce(passes) { $0 + $1.ms }
        let worst = specs.map(\.cost).max() ?? .leicht
        let level = total > 0.5 ? Cost.schwer : (total > 0.12 ? Cost.mittel : worst == .schwer ? .schwer : .leicht)
        if active.isEmpty { return L("keine") }
        return L("%@, etwa %@ ms pro Bild", level.title, ObjectsTab.ms(total))
    }

    var body: some View {
        let items = scene.wrappedValue.items
        let sel = selectedID(items)
        Page {
            Section(L("Objekte")) {
                Toggle(L("Objekte zeigen"), isOn: scene.on)
                SliderRow(title: L("Zeitraffer"), value: scene.speed, range: 0...10, format: "%.1f×",
                          help: L("1 heißt: alles läuft im Takt der Scheibe. Ein Körper doppelt so weit draußen braucht 2,8-mal so lang für eine Runde, wie bei Kepler. Höher rafft die Zeit für alle gleich, die Verhältnisse bleiben echt."), defaultValue: 1)
                HStack {
                    Text(L("Geschätzte Last"))
                    Spacer()
                    Text(loadText).foregroundStyle(.secondary)
                }
                Toggle(L("Relativistische Effekte"), isOn: scene.relativistic)
                    .help(L("Körper auf engen Bahnen leuchten heller und bläulicher, wenn sie auf dich zukommen (Doppler)."))
                Text(L("Bei „Nur Ränder“ und „Aus“ stehen die Objekte still, nur Objekte am Rand fahren bei „Nur Ränder“ weiter. Ein Jet wird beim Ändern seiner Form oder seines Tempos neu durchgerechnet wie Spin und Blickwinkel."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section(L("Liste")) {
                if items.isEmpty {
                    Text(L("Noch keine Objekte. Füge unten welche hinzu oder würfle eine Szene."))
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { o in row(o, selected: o.id == sel) }
                HStack {
                    addMenu
                    Button(L("Duplizieren")) { duplicate(sel) }.disabled(sel == nil)
                    Button(L("Würfeln")) { roll(sel) }.disabled(sel == nil)
                        .help(L("Neuer Seed und neue Werte für das gewählte Objekt"))
                    Button(L("Entfernen")) { m.confirmDelete = true }.disabled(sel == nil)
                    Spacer()
                    moreMenu
                }
            }
            if let id = sel, items.contains(where: { $0.id == id }) {
                ObjectDetail(o: item(id), param: { param(item(id), $0) },
                             planets: items.filter { $0.objectKind == .planet }.map { ($0.id, ObjectCatalog.displayName($0.name)) })
            }
        }
        .alert(L("Objekt entfernen?"), isPresented: $m.confirmDelete) {
            Button(L("Entfernen"), role: .destructive) { remove(sel) }
            Button(L("Abbrechen"), role: .cancel) {}
        } message: {
            Text(L("„%@“ verschwindet aus dieser Voreinstellung.", ObjectCatalog.displayName(items.first { $0.id == sel }?.name ?? "")))
        }
        .alert(L("Alle Objekte entfernen?"), isPresented: $m.confirmClear) {
            Button(L("Alle entfernen"), role: .destructive) { scene.wrappedValue.items = [] }
            Button(L("Abbrechen"), role: .cancel) {}
        } message: {
            Text(L("Die Szene dieser Voreinstellung wird leer."))
        }
    }

    private func row(_ o: SpaceObject, selected: Bool) -> some View {
        let b = item(o.id)
        let spec = ObjectCatalog.spec(for: o)
        return HStack(spacing: 8) {
            Toggle("", isOn: b.on).labelsHidden().toggleStyle(.checkbox)
            Image(systemName: ObjectCatalog.icon(o.kind)).frame(width: 22)
            Text(o.name.isEmpty ? (spec.map { L($0.title) } ?? o.kind) : ObjectCatalog.displayName(o.name))
                .foregroundStyle(o.objectKind == nil ? .secondary : .primary)
            if o.objectKind == nil { Text(L("unbekannte Art, wird nicht gezeichnet")).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Text(spec?.cost.title ?? "").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.22) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { m.selected = o.id }
    }

    private var addMenu: some View {
        let shown = ObjectCatalog.all.filter { $0.stage <= ObjectCatalog.builtStage && $0.kind != .model }
        // First level of the menu path; ships and stations get a second level per universe.
        var groups: [String] = []
        for v in shown where !groups.contains(v.menu[0]) { groups.append(v.menu[0]) }
        let hasJet = scene.wrappedValue.items.contains { $0.kind == "jet" && ($0.attach.isEmpty || $0.attach == "main") }
        let near = ObjectCatalog.variants(of: .star).filter { ObjectCatalog.nearStarIDs.contains($0.id) }
        func subs(_ g: String) -> [String] {
            var out: [String] = []
            for v in shown where v.menu[0] == g && v.menu.count > 1 && !out.contains(v.menu[1]) { out.append(v.menu[1]) }
            return out
        }
        return Menu(L("Hinzufügen")) {
            ForEach(groups, id: \.self) { g in
                Menu(L(g)) {
                    if subs(g).isEmpty {
                        ForEach(shown.filter { $0.menu[0] == g }, id: \.id) { v in
                            Button(L(v.title)) { add(v) }.disabled(v.kind == .jet && hasJet)
                        }
                    } else {
                        ForEach(subs(g), id: \.self) { u in
                            Menu(L(u)) {
                                ForEach(shown.filter { $0.menu[0] == g && $0.menu.count > 1 && $0.menu[1] == u }, id: \.id) { v in
                                    Button(L(v.title)) { add(v) }
                                }
                            }
                        }
                    }
                }
                if g == "Sterne" {
                    Menu(L("Sterne nah")) {
                        ForEach(near, id: \.id) { v in Button(L(v.title)) { addNear(v) } }
                    }
                }
            }
            Divider()
            Button(L("Eigenes Modell …")) { addModel() }
        }
        .fixedSize()
    }

    /// Picks a 3D file, copies it into the models folder and adds it as an object.
    private func addModel() {
        guard let url = ObjectsTab.pickModel(), let v = ObjectCatalog.models.first else { return }
        do {
            let name = try ModelStore.importFile(url)
            var o = v.make(UInt32.random(in: 1...999_999))
            o.model = name
            o.name = url.deletingPathExtension().lastPathComponent
            scene.wrappedValue.items.append(o)
            m.selected = o.id
        } catch {
            NSSound.beep()
        }
    }

    static func pickModel() -> URL? {
        let p = NSOpenPanel()
        p.allowedContentTypes = ModelImport.fileTypes.compactMap { UTType(filenameExtension: $0) }
        p.allowsMultipleSelection = false
        p.message = UIText.pickModel
        return p.runModal() == .OK ? p.url : nil
    }

    private var moreMenu: some View {
        Menu(L("Mehr")) {
            Button(L("Szene würfeln")) {
                let new = ObjectCatalog.randomScene(UInt32.random(in: 1...999_999))
                scene.wrappedValue.items = new
                m.selected = new.first?.id
            }
            Divider()
            Button(L("Szene kopieren")) {
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let d = try? enc.encode(scene.wrappedValue), let s = String(data: d, encoding: .utf8) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(s, forType: .string)
                }
            }
            Button(L("Szene einfügen")) {
                guard let s = NSPasteboard.general.string(forType: .string),
                      let new = try? JSONDecoder().decode(ObjectScene.self, from: Data(s.utf8)) else { NSSound.beep(); return }
                scene.wrappedValue = new
                m.selected = new.items.first?.id
            }
            Divider()
            Button(L("Alle entfernen …")) { m.confirmClear = true }.disabled(scene.wrappedValue.items.isEmpty)
        }
        .fixedSize()
    }

    // MARK: Actions

    private func add(_ v: VariantSpec) {
        var o = v.make(UInt32.random(in: 1...999_999))
        // A moon goes around the selected planet, or the first one in the scene.
        if v.kind == .moon {
            let items = scene.wrappedValue.items
            let sel = items.first { $0.id == m.selected && $0.objectKind == .planet }
            o.attach = (sel ?? items.first { $0.objectKind == .planet })?.id ?? ""
        }
        scene.wrappedValue.items.append(o)
        m.selected = o.id
    }

    private func addNear(_ v: VariantSpec) {
        let o = ObjectCatalog.makeNear(v, seed: UInt32.random(in: 1...999_999))
        scene.wrappedValue.items.append(o)
        m.selected = o.id
    }

    private func duplicate(_ id: String?) {
        guard let id, var o = scene.wrappedValue.items.first(where: { $0.id == id }) else { return }
        guard o.objectKind != .jet else { NSSound.beep(); return }
        o.id = UUID().uuidString
        o.name = L("%@ Kopie", ObjectCatalog.displayName(o.name))
        o.motion.azimuth += 4
        o.motion.phase = (o.motion.phase + 0.3).truncatingRemainder(dividingBy: 1)
        o.motion.x = min(o.motion.x + 0.05, 0.95)
        scene.wrappedValue.items.append(o)
        m.selected = o.id
    }

    private func roll(_ id: String?) {
        guard let id else { return }
        let b = item(id)
        b.wrappedValue = ObjectCatalog.rolled(b.wrappedValue, seed: UInt32.random(in: 1...999_999))
    }

    private func remove(_ id: String?) {
        guard let id else { return }
        scene.wrappedValue.items.removeAll { $0.id == id }
        m.selected = nil
    }
}

/// Sections for the selected object: general values, motion, then the catalog's groups.
struct ObjectDetail: View {
    @Binding var o: SpaceObject
    let param: (String) -> Binding<Float>
    var planets: [(String, String)] = []

    private var spec: VariantSpec? { ObjectCatalog.spec(for: o) }

    var body: some View {
        let spec = self.spec
        let def = spec?.make(o.seed)
        Section(L("Allgemein")) {
            TextField(L("Name"), text: Binding(get: { ObjectCatalog.displayName(o.name) }, set: { o.name = $0 }))
            if let kind = o.objectKind, ObjectCatalog.variants(of: kind).count > 1 {
                Picker(L("Untertyp"), selection: Binding(get: { o.variant }, set: { changeVariant($0) })) {
                    ForEach(ObjectCatalog.variants(of: kind), id: \.id) { Text(L($0.title)).tag($0.id) }
                }
            }
            HStack {
                Text(L("Seed"))
                Spacer()
                Text(String(o.seed)).monospacedDigit().foregroundStyle(.secondary)
                Button { o.seed = UInt32.random(in: 1...999_999) } label: { Image(systemName: "dice") }
                    .buttonStyle(.borderless)
                    .help(L("Neuer Seed: anderes Aussehen, gleiche Werte"))
            }
            if o.objectKind != .jet && o.objectKind != .belt && o.objectKind != .meteor {
                SliderRow(title: sizeTitle, value: $o.size, range: sizeRange, format: sizeFormat, help: sizeHelp,
                          defaultValue: o.motion.mode == def?.motion.mode ? def?.size : nil)
            }
            SliderRow(title: L("Helligkeit"), value: $o.brightness, range: 0...4, defaultValue: def?.brightness ?? 1)
            HStack {
                ColorPicker(L("Tönung"), selection: Binding(get: { Color(nsColor: Palette.color(o.tint)) },
                                                         set: { o.tint = Palette.hex(NSColor($0)) }), supportsOpacity: false)
            }
            SliderRow(title: L("Stärke der Tönung"), value: $o.tintAmount, range: 0...1, defaultValue: 0)
        }
        Section(L("Bewegung")) {
            let modes = spec?.modes ?? [o.motion.mode]
            if o.objectKind == .meteor {
                Text(L("Meteore leuchten kurz an zufälligen Stellen auf, vor allem anderen. Bei „Nur Ränder“, „Aus“ und im Standbild fehlen sie."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if modes.count > 1 {
                Picker(L("Bewegungsart"), selection: Binding(get: { o.motion.mode }, set: { changeMode($0) })) {
                    ForEach(modes, id: \.self) { Text(Motion.titles[$0].map(L) ?? $0.rawValue).tag($0) }
                }
            } else {
                HStack { Text(L("Bewegungsart")); Spacer(); Text(Motion.titles[modes[0]].map(L) ?? "").foregroundStyle(.secondary) }
            }
            if o.objectKind != .meteor { motionControls(def?.motion ?? Motion()) }
        }
        if let spec {
            ForEach(groups(spec), id: \.self) { g in
                Section(L(g)) {
                    ForEach(spec.params.filter { $0.group == g }, id: \.key) { p in control(p) }
                }
            }
            if !spec.events.isEmpty { eventSection(spec) }
        }
        if o.objectKind == .model { modelSection }
    }

    /// Events of ships: which ones, how often. On a band the ship arrives and leaves with them.
    @ViewBuilder private func eventSection(_ spec: VariantSpec) -> some View {
        Section(L("Ereignisse")) {
            Toggle(L("Ereignisse zeigen"), isOn: $o.events.on)
            Text(o.motion.mode == .edge ? L("Am Rand kommt das Schiff mit dem Ereignis an und verlässt den Schirm mit ihm.") :
                    L("Ab und zu verschwindet das Schiff mit dem Ereignis und taucht ein paar Sekunden später wieder auf."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if spec.events.count > 1 {
                ForEach(spec.events, id: \.self) { e in
                    Toggle(ShipCatalog.event(e).map { L($0.title) } ?? e, isOn: Binding(
                        get: { o.events.kinds.isEmpty || o.events.kinds.contains(e) },
                        set: { on in
                            var k = o.events.kinds.isEmpty ? spec.events : o.events.kinds
                            if on { if !k.contains(e) { k.append(e) } } else { k.removeAll { $0 == e } }
                            o.events.kinds = k
                        }))
                    .disabled(!o.events.on)
                }
            }
            if o.motion.mode != .edge {
                SliderRow(title: L("Mittlerer Abstand"), value: $o.events.interval, range: 20...900, format: "%.0f s", defaultValue: 120)
                    .disabled(!o.events.on)
            }
        }
    }

    /// The model file of an own model.
    @ViewBuilder private var modelSection: some View {
        Section(L("Modell")) {
            HStack {
                Text(L("Datei"))
                Spacer()
                Text(o.model.isEmpty ? "keine" : o.model).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            HStack {
                Spacer()
                Button(L("Datei wählen …")) {
                    guard let url = ObjectsTab.pickModel(), let name = try? ModelStore.importFile(url) else { return }
                    ModelStore.reload(name)
                    o.model = name
                }
            }
            if let m = ModelStore.mesh(named: o.model) {
                let n = m.data.triangles
                HStack { Text(L("Dreiecke")); Spacer(); Text("\(n)").monospacedDigit().foregroundStyle(.secondary) }
                if n > ModelImport.warnTriangles {
                    Text(L("Über %d Dreiecke: das kostet spürbar Grafikleistung, wenn das Modell groß im Bild ist.", ModelImport.warnTriangles))
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            } else if let p = ModelStore.problem(o.model) {
                Text(p).font(.caption).foregroundStyle(.orange)
            }
            Text(L("Das Modell wird mittig gesetzt und auf seine Länge gebracht. Seine y-Achse zeigt nach oben, die längere der beiden anderen Achsen nach vorn. Mit Drehung, Neigung und Rollen richtest du es aus."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // Size means different things per motion: angle on the sky, radius in M near the hole, height in points on the screen.
    private var sizeRange: ClosedRange<Float> {
        if o.objectKind == .blackHole { return 0.05...1 }
        return switch o.motion.mode {
        case .sky: o.objectKind == .galaxy ? 0.3...40 : 0.05...4
        case .fixed, .edge: isShip ? 8...800 : 4...400
        default: o.objectKind == .comet ? 0.2...5 : isShip ? 0.3...24 : 0.1...12
        }
    }
    private var isShip: Bool { o.objectKind.map(ObjectSystem.shipKinds.contains) ?? false }
    private var sizeTitle: String {
        if isShip { return L("Länge") }
        if o.objectKind == .blackHole { return L("Masse") }
        if o.objectKind == .wormhole && o.motion.mode != .fixed { return L("Radius der Kehle") }
        return o.motion.mode == .fixed || o.motion.mode == .edge ? L("Höhe") : o.motion.mode == .sky ? L("Größe") : (o.objectKind == .comet ? L("Größe der Koma") : L("Radius"))
    }
    private var sizeFormat: String {
        if o.objectKind == .blackHole { return "%.2f" }
        return switch o.motion.mode {
        case .sky: "%.2f°"
        case .fixed, .edge: "%.0f pt"
        default: "%.2f M"
        }
    }
    private var sizeHelp: String? {
        if o.objectKind == .blackHole { return L("Im Verhältnis zum Hauptloch. Wie groß es erscheint, hängt zusätzlich vom Abstand ab.") }
        return switch o.motion.mode {
        case .sky: L("Winkeldurchmesser am Himmel. Zum Vergleich: der Schirm ist in der Höhe etwa 40° hoch.")
        case .fixed, .edge: isShip ? L("Längste Seite auf dem Schirm in Punkten.") : L("Höhe auf dem Schirm in Punkten.")
        default: L("In M, der Masse des Lochs. Der Schatten hat einen Radius von gut 5 M.")
        }
    }

    /// Another motion mode: keep the apparent size roughly (about 23 points per M at the hole, 0.64° per M).
    private func changeMode(_ mode: MotionMode) {
        let old = o.motion.mode
        guard mode != old else { return }
        // A second hole's size is its mass in every mode.
        if o.objectKind == .blackHole { o.motion.mode = mode; return }
        // Ships: size is a length, not a radius, so half the points per M.
        let k: Float = isShip ? 23.5 : 47
        func toM(_ v: Float) -> Float {
            switch old {
            case .sky: v / 1.27
            case .fixed, .edge: v / k
            default: v
            }
        }
        let r = toM(o.size)
        switch mode {
        case .sky: o.size = min(max(r * 1.27, 0.05), 4)
        case .fixed, .edge: o.size = min(max(r * k, 8), isShip ? 800 : 400)
        default: o.size = min(max(r, 0.1), isShip ? 24 : 12)
        }
        if mode == .orbit && o.motion.radius < 6 && o.objectKind != .moon { o.motion.radius = 58 }
        o.motion.mode = mode
    }

    @ViewBuilder private func motionControls(_ d: Motion) -> some View {
        switch o.motion.mode {
        case .sky:
            SliderRow(title: L("Azimut"), value: $o.motion.azimuth, range: -90...90, format: "%.1f°",
                      help: L("0° liegt genau hinter dem Loch. Nahe 0 biegt das Loch das Objekt zu Bögen oder einem Einstein-Ring."),
                      defaultValue: d.azimuth)
            SliderRow(title: L("Höhe"), value: $o.motion.elevation, range: -60...60, format: "%.1f°", defaultValue: d.elevation)
            SliderRow(title: L("Drift"), value: $o.motion.drift, range: 0...10, format: "%.1f° pro Minute",
                      help: L("Langsames Wandern über den Himmel, etwa einmal quer hinter dem Loch durch."), defaultValue: 0)
            SliderRow(title: L("Drift-Richtung"), value: $o.motion.driftAngle, range: 0...360, format: "%.0f°", defaultValue: 0)
        case .attached:
            Text(L("Sitzt auf der Drehachse des Hauptlochs und folgt dessen Blickwinkel."))
                .font(.caption).foregroundStyle(.secondary)
        case .orbit:
            if o.objectKind == .moon {
                Picker(L("Planet"), selection: $o.attach) {
                    Text(L("Erster Planet")).tag("")
                    ForEach(planets, id: \.0) { Text($0.1.isEmpty ? L("Planet") : $0.1).tag($0.0) }
                }
                SliderRow(title: L("Bahnradius"), value: $o.motion.radius, range: 1.3...12, format: "%.1f",
                          help: L("In Radien des Planeten."), defaultValue: d.radius)
            } else if o.objectKind != .belt {
                SliderRow(title: L("Bahnradius"), value: $o.motion.radius, range: 8...80, format: "%.0f M",
                          help: L("Große Halbachse. Die Kamera steht in 90 M Abstand, die Scheibe reicht je nach Voreinstellung bis 14 bis 55 M."),
                          defaultValue: d.radius)
                SliderRow(title: L("Exzentrizität"), value: $o.motion.eccentricity, range: 0...0.95, defaultValue: d.eccentricity)
            }
            SliderRow(title: L("Neigung"), value: $o.motion.inclination, range: -90...90, format: "%.0f°",
                      help: L("Gegen die Ebene der Scheibe."), defaultValue: d.inclination)
            SliderRow(title: L("Knoten"), value: $o.motion.node, range: 0...360, format: "%.0f°", help: L("Wohin die Bahn gekippt ist."), defaultValue: d.node)
            if o.objectKind != .belt {
                SliderRow(title: L("Periapsis"), value: $o.motion.periapsis, range: 0...360, format: "%.0f°", help: L("Lage des lochnächsten Punkts."), defaultValue: d.periapsis)
                SliderRow(title: L("Startpunkt"), value: $o.motion.phase, range: 0...1, defaultValue: d.phase)
            }
            SliderRow(title: L("Eigener Zeitraffer"), value: $o.motion.tempo, range: 0...200, format: "%.1f×",
                      help: L("1 folgt dem Zeitraffer der Szene und ist echtes Kepler-Tempo: innen schnell, außen langsam. Ein anderer Wert beschleunigt nur diesen Körper."), defaultValue: d.tempo)
            if o.objectKind != .moon && o.objectKind != .belt {
                Toggle(L("Periheldrehung"), isOn: $o.motion.precession)
                    .help(L("Die Bahn dreht sich bei jedem Umlauf ein Stück weiter, wie es die Allgemeine Relativitätstheorie sagt. Nahe am Loch entsteht eine Rosette."))
            }
        case .flyby:
            SliderRow(title: L("Kleinster Abstand von"), value: $o.motion.passMin, range: 2...80, format: "%.0f M",
                      help: L("Unter 4 M stürzt der Körper ins Loch."), defaultValue: d.passMin)
            SliderRow(title: L("Kleinster Abstand bis"), value: $o.motion.passMax, range: 2...80, format: "%.0f M", defaultValue: d.passMax)
            SliderRow(title: L("Mittlere Wartezeit"), value: $o.motion.interval, range: 10...900, format: "%.0f s", defaultValue: d.interval)
            SliderRow(title: L("Tempo weit draußen"), value: $o.motion.flySpeed, range: 0.1...5, format: "%.1f×",
                      help: L("1 sind 0,1 c fern vom Loch. Nahe am Loch wird jeder Körper schneller, und das Loch lenkt seine Bahn ab."), defaultValue: d.flySpeed)
            SliderRow(title: L("Eigener Zeitraffer"), value: $o.motion.tempo, range: 0...200, format: "%.1f×",
                      help: L("1 folgt dem Zeitraffer der Szene und ist echtes Kepler-Tempo: innen schnell, außen langsam. Ein anderer Wert beschleunigt nur diesen Körper."), defaultValue: d.tempo)
            Picker(L("Seite"), selection: $o.motion.side) {
                Text(L("Vor dem Loch")).tag("front")
                Text(L("Hinter dem Loch")).tag("behind")
                Text(L("Beide")).tag("both")
            }
        case .edge:
            Picker(L("Rand"), selection: $o.motion.edge) {
                Text(L("Unten (Dock)")).tag("bottom")
                Text(L("Oben (Menüleiste)")).tag("top")
                Text(L("Abwechselnd")).tag("both")
            }
            Picker(L("Richtung"), selection: $o.motion.direction) {
                Text(L("Nach rechts")).tag("right")
                Text(L("Nach links")).tag("left")
                Text(L("Abwechselnd")).tag("alternate")
                Text(L("Zufällig")).tag("random")
            }
            SliderRow(title: L("Abstand vom Rand"), value: $o.motion.offset, range: -40...200, format: "%.0f pt",
                      help: L("Positiv ins Bild, negativ unter die Leiste."), defaultValue: d.offset)
            SliderRow(title: L("Tempo"), value: $o.motion.edgeSpeed, range: 5...400, format: "%.0f pt/s", defaultValue: d.edgeSpeed)
            SliderRow(title: L("Pause"), value: $o.motion.edgeGap, range: 0...300, format: "%.0f s", defaultValue: d.edgeGap)
            SliderRow(title: L("Wackeln"), value: $o.motion.wobble, range: 0...1, defaultValue: d.wobble)
        case .fixed:
            SliderRow(title: L("Waagrecht"), value: $o.motion.x, range: 0...1, defaultValue: d.x)
            SliderRow(title: L("Senkrecht"), value: $o.motion.y, range: 0...1, defaultValue: d.y)
            Picker(L("Tiefe"), selection: $o.motion.depth) {
                Text(L("Vor dem Loch")).tag("front")
                Text(L("Hinter dem Loch")).tag("behind")
            }
            .help(L("Hinter dem Loch wird das Objekt vom Loch gebogen."))
        }
    }

    private func groups(_ spec: VariantSpec) -> [String] {
        var out: [String] = []
        for p in spec.params where !out.contains(p.group) { out.append(p.group) }
        return out
    }

    @ViewBuilder private func control(_ p: ParamSpec) -> some View {
        let b = param(p.key)
        if p.toggle {
            HStack {
                Toggle(L(p.title), isOn: Binding(get: { b.wrappedValue > 0.5 }, set: { b.wrappedValue = $0 ? 1 : 0 }))
                Spacer()
                ResetButton(active: abs(b.wrappedValue - p.def) > 1e-4) { b.wrappedValue = p.def }
            }
        } else if let opts = p.options {
            HStack {
                Picker(L(p.title), selection: Binding(get: { Int(b.wrappedValue.rounded()) }, set: { b.wrappedValue = Float($0) })) {
                    ForEach(opts.indices, id: \.self) { Text(L(opts[$0])).tag($0) }
                }
                ResetButton(active: abs(b.wrappedValue - p.def) > 1e-4) { b.wrappedValue = p.def }
            }
        } else {
            SliderRow(title: L(p.title), value: b, range: p.range, format: p.format, help: p.help.map(L), defaultValue: p.def)
        }
    }

    /// Another subtype of the same kind: keeps place, seed and name, takes the new defaults.
    private func changeVariant(_ id: String) {
        guard let v = ObjectCatalog.variant(o.kind, id) else { return }
        let old = ObjectCatalog.spec(for: o)
        var n = v.make(o.seed)
        n.id = o.id
        n.on = o.on
        n.motion = o.motion
        n.tint = o.tint
        n.tintAmount = o.tintAmount
        if let old, o.name != old.title { n.name = o.name }
        // Values the user moved away from the old default stay where the new variant has them too.
        for (k, val) in o.params where v.param(k) != nil && old?.param(k)?.def != val { n.params[k] = val }
        o = n
    }
}
