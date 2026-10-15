import AppKit
import ServiceManagement
import SwiftUI

extension Notification.Name {
    static let restoreWallpapers = Notification.Name("BlackHoleRestoreWallpapers")
    static let refreshStills = Notification.Name("BlackHoleRefreshStills")
}

extension Store {
    /// The look of the preset open in the settings window.
    /// Writes go through willEditLook, so a screen that shares its preset gets a copy first.
    func binding<T>(_ kp: WritableKeyPath<Look, T>) -> Binding<T> {
        Binding(get: { self.presets[self.editingIndex].look[keyPath: kp] },
                set: { self.willEditLook(); self.presets[self.editingIndex].look[keyPath: kp] = $0 })
    }

    func defaultValue<T>(_ kp: KeyPath<Look, T>) -> T { defaultLook(for: editingID)[keyPath: kp] }
}

/// Local UI state. Classes instead of @State: the SwiftUI macro plugin is missing from
/// the Command Line Tools, so @State does not compile here.
final class TabModel: ObservableObject {
    @Published var tab: Int
    init(_ tab: Int) { self.tab = tab }
}

/// Fixed-width icon column so the titles line up, even for wide symbols like display.2.
struct SidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.frame(width: 26, alignment: .center)
            configuration.title
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @StateObject private var tabs: TabModel

    init(tab: Int = 0) { _tabs = StateObject(wrappedValue: TabModel(tab)) }

    /// German titles, shown through L().
    static let pages: [(String, String)] = [
        ("Allgemein", "gearshape"), ("Loch", "circle.fill"), ("Scheibe", "circle.dashed"), ("Farben", "paintpalette"),
        ("Nebel", "cloud"), ("Sterne", "sparkles"), ("Ränder", "rectangle.topthird.inset.filled"),
        ("Objekte", "globe.europe.africa"), ("Bewegung", "wind"), ("Schirme", "display.2"), ("Energie", "bolt"),
        ("Qualität", "slider.horizontal.3"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            PresetBar()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()
            HStack(spacing: 0) {
                List(selection: $tabs.tab) {
                    ForEach(Array(SettingsView.pages.enumerated()), id: \.offset) { i, page in
                        Label(L(page.0), systemImage: page.1)
                            .labelStyle(SidebarLabelStyle())
                            .tag(i)
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 170)
                Divider()
                Group {
                    let locked = store.lookLocked
                    switch tabs.tab {
                    case 1: HoleTab().lockable(locked)
                    case 2: DiskTab().lockable(locked)
                    case 3: ColorsTab().lockable(locked)
                    case 4: NebulaTab().lockable(locked)
                    case 5: StarsTab().lockable(locked)
                    case 6: EdgesTab().lockable(locked)
                    case 7: ObjectsTab().lockable(locked)
                    case 8: MotionTab()
                    case 9: ScreensTab()
                    case 10: EnergyTab()
                    case 11: QualityTab()
                    default: GeneralTab()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: .showSettingsPage)) { n in
            if let page = n.object as? Int { tabs.tab = page }
        }
    }
}

// MARK: - Building blocks

struct ResetButton: View {
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "arrow.uturn.backward") }
            .buttonStyle(.borderless)
            .help(L("Auf den Standardwert zurücksetzen"))
            .disabled(!active)
            .opacity(active ? 1 : 0.25)
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    var format = "%.2f"
    var help: String?
    var defaultValue: Float?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: Loc.text(format), value)).monospacedDigit().foregroundStyle(.secondary)
                if let d = defaultValue { ResetButton(active: abs(value - d) > 1e-4) { value = d } }
            }
            Slider(value: $value, in: range)
            if let help {
                Text(help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

struct LookSlider: View {
    @EnvironmentObject var store: Store
    let title: String
    let kp: WritableKeyPath<Look, Float>
    let range: ClosedRange<Float>
    var format = "%.2f"
    var help: String?

    var body: some View {
        SliderRow(title: title, value: store.binding(kp), range: range, format: format, help: help,
                  defaultValue: store.defaultValue(kp))
    }
}

struct LookToggle: View {
    @EnvironmentObject var store: Store
    let title: String
    let kp: WritableKeyPath<Look, Bool>

    var body: some View {
        let d = store.defaultValue(kp)
        let b = store.binding(kp)
        HStack {
            Toggle(title, isOn: b)
            Spacer()
            ResetButton(active: b.wrappedValue != d) { b.wrappedValue = d }
        }
    }
}

struct LookPicker: View {
    @EnvironmentObject var store: Store
    let title: String
    let kp: WritableKeyPath<Look, Int>
    let options: [String]

    var body: some View {
        let d = store.defaultValue(kp)
        let b = store.binding(kp)
        HStack {
            Picker(title, selection: b) {
                ForEach(options.indices, id: \.self) { Text(L(options[$0])).tag($0) }
            }
            ResetButton(active: b.wrappedValue != d) { b.wrappedValue = d }
        }
    }
}

struct LookColour: View {
    @EnvironmentObject var store: Store
    let title: String
    let kp: WritableKeyPath<Look, String>

    var body: some View {
        let d = store.defaultValue(kp)
        let b = store.binding(kp)
        HStack {
            ColorPicker(title, selection: Binding(get: { Color(nsColor: Palette.color(b.wrappedValue)) },
                                                  set: { b.wrappedValue = Palette.hex(NSColor($0)) }),
                        supportsOpacity: false)
            ResetButton(active: b.wrappedValue != d) { b.wrappedValue = d }
        }
    }
}

extension View {
    /// Look controls while all screens show different presets: greyed out and inert.
    func lockable(_ locked: Bool) -> some View { disabled(locked).opacity(locked ? 0.45 : 1) }
}

struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Form { content }.formStyle(.grouped)
    }
}

// MARK: - Preset bar

enum NameAction { case duplicate, rename }

final class PresetBarModel: ObservableObject {
    @Published var naming: NameAction?
    @Published var nameText = ""
    @Published var confirmFactory = false
}

struct PresetBar: View {
    @EnvironmentObject var store: Store
    @StateObject private var m = PresetBarModel()

    private var current: Preset { store.presets[store.editingIndex] }
    private static let allTag = "*"

    /// Screen picker: "*" stands for all screens.
    private var screenBinding: Binding<String> {
        Binding(get: { store.editScreen ?? PresetBar.allTag },
                set: { tag in
                    let key = tag == PresetBar.allTag ? nil : tag
                    store.selectScreen(key)
                    if let key, let screen = Store.screen(forKey: key) { ScreenFlash.show(screen.localizedName, on: screen) }
                })
    }

    private var presetBinding: Binding<String> {
        Binding(get: { store.lookLocked ? "" : store.editingID },
                set: { if !$0.isEmpty { store.choosePreset($0) } })
    }

    private var note: (String, Bool) {
        if store.lookLocked {
            return (L("Die Schirme zeigen verschiedene Voreinstellungen. Wähle oben einen Schirm oder eine gemeinsame Voreinstellung, dann kannst du die Werte ändern."), true)
        }
        guard let k = store.editScreen else {
            return (L("Änderungen wirken sofort auf alle Schirme und werden gespeichert."), false)
        }
        let others = NSScreen.screens.filter { Store.key(for: $0) != k && store.config(for: $0).presetID == current.id }
        let offline = store.settings.screens.filter { e in
            e.key != k && e.value.presetID == current.id && Store.screen(forKey: e.key) == nil
        }.count
        var users = others.map { Store.shortName(forKey: Store.key(for: $0)) }
        if offline > 0 { users.append(offline == 1 ? L("ein nicht angeschlossener Schirm") : L("%d nicht angeschlossene Schirme", offline)) }
        if users.isEmpty { return (L("Änderungen wirken sofort nur auf diesen Schirm und werden gespeichert."), false) }
        return (L("Diese Voreinstellung nutzt auch: %@. Änderst du einen Wert, bekommt dieser Schirm vorher eine eigene Kopie.",
                  users.joined(separator: ", ")), false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Schirm")).frame(width: 100, alignment: .leading)
                Picker(L("Schirm"), selection: screenBinding) {
                    ForEach(NSScreen.screens, id: \.self) { sc in Text(Store.label(for: sc)).tag(Store.key(for: sc)) }
                    Divider()
                    Text(L("Alle Schirme")).tag(PresetBar.allTag)
                }
                .labelsHidden()
                .frame(maxWidth: 360)
                Spacer()
            }
            HStack {
                Text(L("Voreinstellung")).frame(width: 100, alignment: .leading)
                Picker(L("Voreinstellung"), selection: presetBinding) {
                    if store.lookLocked { Text(L("Verschiedene")).tag("").selectionDisabled() }
                    ForEach(store.presets) { p in Text(p.displayName).tag(p.id) }
                }
                .labelsHidden()
                .frame(maxWidth: 360)
                Spacer()
                if store.editScreen != nil {
                    Button(L("Auf allen Schirmen")) { store.assignToAllScreens(current.id) }
                }
                Menu(L("Mehr")) {
                    Group {
                        Button(L("Duplizieren …")) { m.nameText = L("%@ Kopie", current.displayName); m.naming = .duplicate }
                        Button(L("Umbenennen …")) { m.nameText = current.displayName; m.naming = .rename }
                        Divider()
                        Button(L("Diese Voreinstellung zurücksetzen")) { store.willEditLook(); store.resetPreset(store.editingID) }
                        Button(L("Löschen"), role: .destructive) { store.delete(current.id) }
                            .disabled(current.builtIn)
                    }
                    .disabled(store.lookLocked)
                    Divider()
                    Button(L("Alles auf Werkseinstellung …")) { m.confirmFactory = true }
                }
                .fixedSize()
            }
            let n = note
            Label(n.0, systemImage: n.1 ? "exclamationmark.triangle" : "info.circle")
                .font(.caption)
                .foregroundStyle(n.1 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .alert(m.naming == .duplicate ? L("Neue Voreinstellung") : L("Umbenennen"),
               isPresented: Binding(get: { m.naming != nil }, set: { if !$0 { m.naming = nil } })) {
            TextField(L("Name"), text: $m.nameText)
            Button(L("OK")) {
                let n = m.nameText.trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty else { return }
                if m.naming == .duplicate { store.choosePreset(store.duplicate(current.id, name: n)) } else { store.rename(current.id, to: n) }
            }
            Button(L("Abbrechen"), role: .cancel) {}
        }
        .alert(L("Alles auf Werkseinstellung?"), isPresented: $m.confirmFactory) {
            Button(L("Zurücksetzen"), role: .destructive) { store.resetAllToFactory() }
            Button(L("Abbrechen"), role: .cancel) {}
        } message: {
            Text(L("Alle eingebauten Voreinstellungen bekommen wieder ihre Originalwerte. Eigene Voreinstellungen werden gelöscht. Schirme, Energie und Maus-Modus gehen auf Standard."))
        }
    }
}

// MARK: - Tabs

struct HoleTab: View {
    var body: some View {
        Page {
            Section(L("Physik")) {
                LookSlider(title: L("Drehung (Spin)"), kp: \.spin, range: 0...0.998,
                           help: L("0 heißt keine Drehung. Nahe 1 zieht das Loch den Raum fast mit Lichtgeschwindigkeit mit. Der Schatten wird dann schief und die Scheibe reicht näher heran."))
                LookSlider(title: L("Blickwinkel"), kp: \.inclinationDeg, range: 3...89, format: "%.0f°",
                           help: L("0° schaut von oben auf den Pol, 90° von der Seite wie in Interstellar."))
                LookSlider(title: L("Kamera-Abstand"), kp: \.cameraDistance, range: 30...300, format: "%.0f M",
                           help: L("M ist die Masse des Lochs als Länge. Nah heißt starke Verzerrung der Sterne über den ganzen Schirm."))
            }
            Section(L("Bild")) {
                LookSlider(title: L("Größe des Schattens"), kp: \.holeSize, range: 0.03...0.2, format: "%.3f")
                LookSlider(title: L("Leuchten am Photonenring"), kp: \.ringGlow, range: 0...3)
                LookSlider(title: L("Belichtung"), kp: \.exposure, range: 0.3...3)
            }
        }
    }
}

struct DiskTab: View {
    var body: some View {
        Page {
            Section(L("Akkretionsscheibe")) {
                LookSlider(title: L("Außenradius"), kp: \.diskOuter, range: 8...80, format: "%.0f M",
                           help: L("Innen beginnt die Scheibe immer an der innersten stabilen Bahn. Die hängt vom Spin ab."))
                LookSlider(title: L("Helligkeit"), kp: \.diskBrightness, range: 0...3)
                LookSlider(title: L("Farbvielfalt"), kp: \.diskHueVariety, range: 0...1.5,
                           help: L("0 färbt nur nach Temperatur, wie in der Physik. Höher mischt Farbwolken hinein."))
            }
        }
    }
}

struct ColorsTab: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Page {
            Section(L("Palette")) {
                HStack {
                    Text(L("Vorlage übernehmen"))
                    Spacer()
                    Menu(L("Wählen")) {
                        ForEach(Palette.builtIn) { p in
                            Button(L(p.name)) { store.binding(\.palette).wrappedValue = p.colors }
                        }
                    }
                    .fixedSize()
                    ResetButton(active: store.binding(\.palette).wrappedValue != store.defaultValue(\.palette)) {
                        store.binding(\.palette).wrappedValue = store.defaultValue(\.palette)
                    }
                }
                ForEach(0..<Palette.slotNames.count, id: \.self) { i in
                    LookColour(title: L(Palette.slotNames[i]), kp: \.palette[i])
                }
            }
            Section {
                Text(L("Tiefe bis Kern bilden den Verlauf von kalt nach heiß in der Scheibe. Die Akzente färben die kühlen Nebel und die Ränder."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct NebulaTab: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Page {
            Section(L("Nebel")) {
                LookSlider(title: L("Helligkeit"), kp: \.nebula, range: 0...3)
                LookSlider(title: L("Wirbel"), kp: \.nebulaSwirl, range: -8...8, format: "%.1f",
                           help: L("Wie stark sich die Nebel um den Punkt hinter dem Loch winden. Das Loch biegt den Wirbel zu Ringen."))
                LookSlider(title: L("Körnung"), kp: \.nebulaScale, range: 2...20, format: "%.1f",
                           help: L("Klein heißt große Wolken, groß heißt feine Fetzen."))
                HStack {
                    LookSlider(title: L("Muster"), kp: \.nebulaSeed, range: 0...50, format: "%.0f")
                    Button(L("Zufall")) { store.binding(\.nebulaSeed).wrappedValue = Float(Int.random(in: 0...50)) }
                }
            }
        }
    }
}

struct StarsTab: View {
    var body: some View {
        Page {
            Section(L("Sterne")) {
                LookSlider(title: L("Helligkeit"), kp: \.stars, range: 0...3)
                LookSlider(title: L("Dichte"), kp: \.starDensity, range: 0...3)
                LookSlider(title: L("Farbe nach Temperatur"), kp: \.starColour, range: 0...2,
                           help: L("Kühle Sterne leuchten orange, heiße blauweiß. 0 ist alles weiß, 1 ist echt, 2 ist übertrieben."))
                LookSlider(title: L("Funkeln"), kp: \.twinkle, range: 0...1)
            }
        }
    }
}

final class EdgeSideModel: ObservableObject {
    @Published var bottom = false
}

struct EdgesTab: View {
    @EnvironmentObject var store: Store
    @StateObject private var side = EdgeSideModel()

    var body: some View {
        let base: WritableKeyPath<Look, EdgeStyle> = side.bottom ? \.edgeBottom : \.edgeTop
        Page {
            Section {
                Picker(L("Rand"), selection: $side.bottom) {
                    Text(L("Oben (Menüleiste)")).tag(false)
                    Text(L("Unten (Dock)")).tag(true)
                }
                .pickerStyle(.segmented)
                HStack {
                    Spacer()
                    Button(side.bottom ? L("Auf oben übertragen") : L("Auf unten übertragen")) {
                        let l = store.binding(\.self)
                        if side.bottom { l.wrappedValue.edgeTop = l.wrappedValue.edgeBottom }
                        else { l.wrappedValue.edgeBottom = l.wrappedValue.edgeTop }
                    }
                }
            }
            Section(L("Linie")) {
                LookToggle(title: L("An"), kp: base.appending(path: \.on))
                LookSlider(title: L("Stärke"), kp: base.appending(path: \.intensity), range: 0...3)
                LookSlider(title: L("Linienbreite"), kp: base.appending(path: \.lineWidth), range: 0.3...4, format: "%.1f pt")
                LookSlider(title: L("Bündelung zum Loch"), kp: base.appending(path: \.focus), range: 0...2,
                           help: L("0 leuchtet gleichmäßig über die ganze Breite. Höher sammelt das Licht dort, wo das Loch steht."))
            }
            Section(L("Glühen")) {
                LookSlider(title: L("Reichweite ins Bild"), kp: base.appending(path: \.reachPicture), range: 0...60, format: "%.0f pt")
                LookSlider(title: side.bottom ? L("Reichweite ins Dock") : L("Reichweite in die Menüleiste"), kp: base.appending(path: \.reachBar), range: 0...60, format: "%.0f pt")
                LookSlider(title: L("Abdunkeln im Bild"), kp: base.appending(path: \.darkenPicture), range: 0...1)
                LookSlider(title: side.bottom ? L("Abdunkeln im Dock") : L("Abdunkeln in der Menüleiste"), kp: base.appending(path: \.darkenBar), range: 0...1,
                           help: L("Abdunkeln hält Menüleiste und Dock lesbar."))
            }
            Section(L("Bewegung")) {
                LookPicker(title: L("Richtung"), kp: base.appending(path: \.flowMode), options: EdgeStyle.flowModes)
                LookSlider(title: L("Tempo"), kp: base.appending(path: \.flowSpeed), range: 0...4)
            }
            Section(L("Farbe")) {
                LookToggle(title: L("Eigene Farbe statt Palette"), kp: base.appending(path: \.customColour))
                LookColour(title: L("Farbe"), kp: base.appending(path: \.colour))
            }
        }
    }
}

struct MotionTab: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Page {
            Section(L("Scheibe")) {
                LookSlider(title: L("Umlaufzeit am Innenrand"), kp: \.diskPeriod, range: 3...120, format: "%.0f s",
                           help: L("So lange braucht das Gas ganz innen für eine Runde."))
                LookSlider(title: L("Scherung"), kp: \.diskShear, range: 0...1,
                           help: L("1 ist echte Physik nach Kepler: Außen ist das Gas viel langsamer, bei 20 M etwa 25-mal. 0 dreht die ganze Scheibe wie eine Schallplatte."))
            }
            .lockable(store.lookLocked)
            Section(L("Nebel")) {
                LookSlider(title: L("Umlaufzeit des Wirbels"), kp: \.nebulaPeriod, range: 20...1200, format: "%.0f s",
                           help: L("Der Nebel dreht sich um den Punkt hinter dem Loch, innen schneller als außen. Das Loch biegt die Drehung mit."))
            }
            .lockable(store.lookLocked)
            Section(L("Maus-Modus")) {
                Toggle(L("Kleine Linse folgt dem Mauszeiger"), isOn: $store.settings.mouseMode)
                SliderRow(title: L("Größe"), value: $store.settings.mouseSize, range: 20...200, format: "%.0f pt",
                          help: L("Radius des Einstein-Rings. Innerhalb davon steht das Bild auf dem Kopf."), defaultValue: 70)
                Toggle(L("Mit schwarzem Schatten in der Mitte"), isOn: $store.settings.mouseShadow)
            }
            Section(L("Langsame Veränderung")) {
                Toggle(L("Bild verändert sich über den Tag"), isOn: $store.settings.dayDrift)
                SliderRow(title: L("Stärke"), value: $store.settings.dayDriftStrength, range: 0...2,
                          help: L("Der Blickwinkel pendelt über den Tag um einige Grad, der Nebel windet sich mit. Abends wird es dunkler."),
                          defaultValue: 1)
            }
        }
    }
}

struct ScreensTab: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Page {
            ForEach(shown, id: \.self) { screen in
                Section(Store.label(for: screen)) {
                    Picker(L("Voreinstellung"), selection: binding(screen, \.presetID)) {
                        ForEach(store.presets) { p in Text(p.displayName).tag(p.id) }
                    }
                    SliderRow(title: L("Loch waagrecht"), value: binding(screen, \.holeX), range: 0...1, defaultValue: 0.5)
                    SliderRow(title: L("Loch senkrecht"), value: binding(screen, \.holeY), range: 0...1,
                              help: L("0 ist oben, 1 ist unten."),
                              defaultValue: screen.frame.height > screen.frame.width ? 0.3 : 0.5)
                }
            }
            if store.editScreen == nil {
                Section {
                    Text(L("Wählst du oben einen Schirm, siehst du hier nur ihn."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The chosen screen, or all of them.
    private var shown: [NSScreen] {
        guard let k = store.editScreen, let s = Store.screen(forKey: k) else { return NSScreen.screens }
        return [s]
    }

    private func binding<T>(_ screen: NSScreen, _ kp: WritableKeyPath<ScreenConfig, T>) -> Binding<T> {
        Binding(get: { store.config(for: screen)[keyPath: kp] },
                set: { var c = store.config(for: screen); c[keyPath: kp] = $0; store.setConfig(c, for: screen) })
    }
}

final class LoginModel: ObservableObject {
    @Published var on = SMAppService.mainApp.status == .enabled {
        didSet {
            guard on != oldValue else { return }
            do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { on = SMAppService.mainApp.status == .enabled }
        }
    }
}

final class GeneralModel: ObservableObject {
    @Published var confirmHide = false
}

struct GeneralTab: View {
    @EnvironmentObject var store: Store
    @StateObject private var login = LoginModel()
    @StateObject private var m = GeneralModel()
    @ObservedObject private var access = SystemAccess.shared

    static var wayBack: String { L("Zurück kommst du, indem du die App noch einmal startest, etwa über Spotlight. Dann öffnet sich dieses Fenster.") }

    private var modeHelp: String {
        switch store.settings.animation {
        case .all: L("Scheibe, Nebel, Sterne und die Bänder an Menüleiste und Dock bewegen sich.")
        case .edgesOnly: L("Loch, Scheibe, Nebel und Sterne stehen still. Nur die Bänder an Menüleiste und Dock fließen weiter. Das braucht einen Bruchteil der Grafikleistung.")
        case .off: L("Ein stehendes Bild. Die Grafikkarte hat nichts zu tun.")
        }
    }

    /// The first time the icon goes, ask once and say how to get back.
    private var hideBinding: Binding<Bool> {
        Binding(get: { store.settings.hideMenuIcon },
                set: { on in
                    if on && !store.settings.hideMenuIconConfirmed { m.confirmHide = true } else { store.settings.hideMenuIcon = on }
                })
    }

    var body: some View {
        Page {
            Section(L("Animation")) {
                // Not $store.settings.animation: that would be Binding.animation().
                Picker(L("Animation"), selection: Binding(get: { store.settings.animation }, set: { store.settings.animation = $0 })) {
                    ForEach(AnimationMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(modeHelp).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle(L("Im Energiesparmodus anhalten"), isOn: $store.settings.freezeInLowPower)
                Toggle(L("Bewegung reduzieren beachten"), isOn: $store.settings.respectReduceMotion)
                Text(L("Ist in den Systemeinstellungen unter Bedienungshilfen „Bewegung reduzieren“ an, zeigt die App ein stehendes Bild."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if store.settings.respectReduceMotion && access.reduceMotion {
                    Label(L("„Bewegung reduzieren“ ist in macOS an. Die App zeigt deshalb ein stehendes Bild, was du oben auch wählst."),
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section(L("Maus-Modus")) {
                Toggle(L("Kleine Linse folgt dem Mauszeiger"), isOn: $store.settings.mouseMode)
                Text(L("Größe und Schatten stellst du unter Bewegung ein. Bei „Nur Ränder“ zeichnet die App das Bild nur neu, wenn sich der Zeiger bewegt."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section(L("Menüleiste")) {
                Toggle(L("Menüleisten-Symbol ausblenden"), isOn: hideBinding)
                Text(GeneralTab.wayBack)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section(L("Start")) {
                Toggle(L("Beim Anmelden starten"), isOn: $login.on)
            }
            Section(L("Sprache")) {
                // Language names stay in their own language, like in macOS.
                Picker(L("Sprache"), selection: $store.settings.language) {
                    Text(L("System")).tag("system")
                    Text("English").tag("en")
                    Text("Deutsch").tag("de")
                }
                Text(L("System folgt der Sprache von macOS: Deutsch, wenn Deutsch vor Englisch steht, sonst Englisch."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            UpdatesSection()
            Section {
                HStack {
                    Text(L("Beendet die App. Der Schreibtisch zeigt dann wieder das Hintergrundbild von macOS."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(L("Beenden")) { NSApp.terminate(nil) }
                }
            }
        }
        .alert(L("Menüleisten-Symbol ausblenden?"), isPresented: $m.confirmHide) {
            Button(L("Ausblenden")) {
                store.settings.hideMenuIconConfirmed = true
                store.settings.hideMenuIcon = true
            }
            Button(L("Abbrechen"), role: .cancel) {}
        } message: {
            Text(GeneralTab.wayBack)
        }
    }
}

/// Updates on the General page: version, automatic check, Check Now, and an offer when there is a new version.
struct UpdatesSection: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var updater = Updater.shared

    private static func caption(_ s: String) -> some View {
        Text(s).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private var lastCheck: String {
        let t = store.settings.updates.lastCheck
        guard t > 0 else { return L("Noch nicht gesucht.") }
        let f = DateFormatter()
        f.locale = Locale(identifier: Loc.lang.rawValue)
        f.dateStyle = .medium
        f.timeStyle = .short
        return L("Zuletzt gesucht: %@", f.string(from: Date(timeIntervalSince1970: t)))
    }

    var body: some View {
        Section(L("Updates")) {
            LabeledContent(L("Installierte Version"), value: UpdateCore.currentVersionString ?? "-")
            Toggle(L("Automatisch nach Updates suchen"), isOn: $store.settings.updates.auto)
            switch updater.state {
            case .available(let r): offer(r)
            default: status
            }
            UpdatesSection.caption(L("Die App spricht nur mit api.github.com und den Download-Servern von GitHub, um nach Updates zu suchen und sie zu laden. Automatisch höchstens einmal am Tag und nie im Energiesparmodus."))
        }
    }

    @ViewBuilder private var status: some View {
        HStack {
            Button(L("Jetzt suchen")) { updater.checkNow() }.disabled(updater.busy)
            if updater.busy { ProgressView().controlSize(.small) }
            switch updater.state {
            case .checking: UpdatesSection.caption(L("Sucht nach Updates …"))
            case .upToDate: UpdatesSection.caption(L("Du hast die neueste Version."))
            case .working(let step): UpdatesSection.caption(step)
            case .failed: EmptyView()
            default: UpdatesSection.caption(lastCheck)
            }
        }
        if case .failed(let msg, let page) = updater.state {
            Text(msg).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            if page != nil { Button(L("Download-Seite öffnen")) { updater.openPage(page) } }
        }
    }

    @ViewBuilder private func offer(_ r: Release) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Version %@ ist da", r.versionString)).font(.headline)
            if !r.excerpt.isEmpty { UpdatesSection.caption(r.excerpt) }
            switch updater.mode {
            case .homebrew:
                Text(L("Mit Homebrew aktualisieren: brew upgrade --cask blackhole-wallpaper"))
                    .font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            case .notWritable:
                UpdatesSection.caption(L("Der Ordner der App ist nicht beschreibbar. Lade die neue Version von der Download-Seite."))
            case .notBundled:
                UpdatesSection.caption(L("Diese Kopie läuft nicht als App und kann sich nicht selbst ersetzen."))
            case .selfInstall:
                EmptyView()
            }
            HStack {
                switch updater.mode {
                case .selfInstall: Button(L("Installieren")) { updater.install() }.keyboardShortcut(.defaultAction)
                case .notWritable, .notBundled: Button(L("Download-Seite öffnen")) { updater.openPage(r.page) }
                case .homebrew: EmptyView()
                }
                Button(L("Später")) { updater.later() }
                Button(L("Diese Version überspringen")) { updater.skip() }
            }
        }
    }
}

struct EnergyTab: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Page {
            Section(L("Bildrate")) {
                Picker(L("Bilder pro Sekunde am Netzteil"), selection: $store.settings.fpsPower) {
                    ForEach([30, 60, 120], id: \.self) { Text("\($0)").tag($0) }
                }
                Picker(L("Bilder pro Sekunde am Akku"), selection: $store.settings.fpsBattery) {
                    ForEach([15, 30, 60], id: \.self) { Text("\($0)").tag($0) }
                }
            }
            Section(L("Hitze")) {
                Toggle(L("Bei Hitze drosseln"), isOn: $store.settings.throttleWhenHot)
                Text(L("Wird der Mac sehr heiß, läuft die Animation mit halber Bildrate und einer Qualitätsstufe weniger. Wird er kritisch heiß, bleibt ein Standbild stehen. Kühlt er ab, gelten wieder deine Einstellungen."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section(L("Sperrbildschirm und Mission Control")) {
                Toggle(L("Standbild als echten Hintergrund setzen"), isOn: $store.settings.stillWallpaper)
                Picker(L("Standbild erneuern alle"), selection: $store.settings.stillInterval) {
                    ForEach([10.0, 30.0, 60.0, 180.0], id: \.self) { Text(L("%d Minuten", Int($0))).tag($0) }
                }
                HStack {
                    Button(L("Jetzt erneuern")) { NotificationCenter.default.post(name: .refreshStills, object: nil) }
                        .disabled(!store.settings.stillWallpaper)
                    Button(L("Altes Hintergrundbild zurückholen")) {
                        NotificationCenter.default.post(name: .restoreWallpapers, object: nil)
                    }
                    .disabled(store.settings.originalWallpapers.isEmpty)
                }
                Text(L("macOS zeigt auf dem Sperrbildschirm und in Mission Control das echte Hintergrundbild. Die App setzt dort ein Standbild vom Loch, damit nichts springt."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Bildschirmschoner")) {
                Text(L("Der Bildschirmschoner „Schwarzes Loch“ zeigt das Loch live. Wähle ihn in den Systemeinstellungen unter Bildschirmschoner aus."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L("Bildschirmschoner-Einstellungen öffnen")) {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension") {
                        NSWorkspace.shared.open(u)
                    }
                }
            }
        }
    }
}

/// Renders the settings window offscreen to PNG, for reviews without screen recording rights.
enum SettingsShot {
    /// allScreens: show "Alle Schirme" instead of the main screen. store: e.g. the self-test's.
    /// Reads settings.json but never writes it. lockedDemo adds a made-up second screen with
    /// another preset, to show the locked state under "Alle Schirme".
    /// lang: "en" or "de" instead of the stored language.
    /// objectsDemo: puts a fixed scene into the shown preset (only in memory), for the objects page.
    static func run(path: String, tab: Int, allScreens: Bool = false, lockedDemo: Bool = false,
                    objectsDemo: Bool = false, shipsDemo: Bool = false, exoticsDemo: Bool = false, height: CGFloat = 700,
                    lang: String? = nil, welcome: Bool = false) -> Int32 {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let store = Store(persist: false)
        if let lang { store.settings.language = lang }
        store.ensureEntries(for: NSScreen.screens)
        if lockedDemo {
            let real = NSScreen.screens.map(Store.key(for:))
            store.connectedKeys = { real + ["DEMO"] }
            store.settings.screens["DEMO"] = ScreenConfig(presetID: store.presetID(forKey: real[0]) == "gargantua" ? "eisblau" : "gargantua")
        }
        store.selectScreen(allScreens ? nil : (NSScreen.main ?? NSScreen.screens.first).map(Store.key(for:)))
        if objectsDemo { store.presets[store.editingIndex].look.objects.items = ObjectCatalog.demoScene() }
        if shipsDemo { store.presets[store.editingIndex].look.objects.items = ObjectCatalog.shipDemoScene() }
        if exoticsDemo {
            store.presets[store.editingIndex].look.objects.items = [ObjectCatalog.variant("blackHole", "diskJet")!.make(5)] + ObjectCatalog.sciFiScene().items
        }
        let window: NSWindow
        if welcome {
            // The first-launch window as it opens: the thumbnails are drawn before the picture is taken.
            let model = WelcomeModel()
            model.loadThumbnailsNow()
            let host = NSHostingController(rootView: WelcomeView(model: model).environmentObject(store))
            window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable]
            window.title = L("Willkommen")
        } else {
            let view = NSHostingView(rootView: SettingsView(tab: tab).environmentObject(store))
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: height),
                              styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
        }
        // Controls only draw fully in a window that is on screen; park it off to the side.
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return 1 }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return 1 }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil ? 0 : 1
    }
}

/// Shows a screen's name large in its middle for a moment, like "Detect Displays" in macOS.
enum ScreenFlash {
    private static var windows: [ObjectIdentifier: NSWindow] = [:]

    static func show(_ text: String, on screen: NSScreen) {
        let id = ObjectIdentifier(screen)
        windows[id]?.orderOut(nil)
        let label = Text(text)
            .font(.system(size: 56, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .padding(.horizontal, 48)
            .padding(.vertical, 28)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color.black.opacity(0.72)))
        let host = NSHostingView(rootView: label)
        let size = host.fittingSize
        let w = min(size.width, screen.frame.width * 0.8)
        let frame = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.midY - size.height / 2, width: w, height: size.height)
        let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.level = .statusBar
        win.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        win.isReleasedWhenClosed = false
        win.contentView = host
        win.setFrame(frame, display: false)
        win.orderFrontRegardless()
        windows[id] = win
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard windows[id] === win else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                win.animator().alphaValue = 0
            }, completionHandler: {
                win.orderOut(nil)
                if windows[id] === win { windows[id] = nil }
            })
        }
    }
}

/// Quality levels: one overall level for adapter and battery, below it one level per area.
struct QualityTab: View {
    @EnvironmentObject var store: Store

    private static func num(_ v: Float, _ f: String) -> String {
        let s = String(format: f, v)
        return Loc.lang == .de ? s.replacingOccurrences(of: ".", with: ",") : s
    }

    /// "Hoch, etwa 3,4 ms pro Bild, 230 MB"
    static func levelLabel(_ l: QualityLevel) -> String {
        let c = QualityCost.overall[l.rawValue]
        return L("%@, etwa %@ ms pro Bild, %d MB", L(l.key), num(c.ms, "%.1f"), c.mb)
    }

    /// Extra load of an area at a level against Ausgewogen, e.g. "Bei Hoch: +0,02 ms pro Bild, +34 MB".
    static func areaLoad(_ a: QualityArea, _ l: QualityLevel) -> String {
        guard l != .balanced, let c = QualityCost.area[a]?[l.rawValue] else { return L("Bei %@: Grundlast", L(l.key)) }
        let sign = c.ms >= 0 ? "+" : "-"
        let mbSign = c.mb >= 0 ? "+" : "-"
        return L("Bei %@: %@%@ ms pro Bild, %@%d MB", L(l.key), sign, num(abs(c.ms), "%.2f"), mbSign, abs(c.mb))
    }

    private func areaBinding(_ a: QualityArea) -> Binding<Int> {
        Binding(get: { store.settings.quality.areas[a.rawValue]?.rawValue ?? -1 },
                set: { store.settings.quality.areas[a.rawValue] = QualityLevel(rawValue: $0) })
    }

    var body: some View {
        let q = store.settings.quality
        Page {
            Section(L("Gesamtstufe")) {
                Picker(L("Am Netzteil"), selection: $store.settings.quality.power) {
                    ForEach(QualityLevel.allCases, id: \.self) { Text(QualityTab.levelLabel($0)).tag($0) }
                }
                Picker(L("Am Akku"), selection: $store.settings.quality.battery) {
                    ForEach(QualityLevel.allCases, id: \.self) { Text(QualityTab.levelLabel($0)).tag($0) }
                }
                Text(L("Wie in Spielen: Akku sparen rechnet gröber, Hoch und Ultra feiner und brauchen mehr Grafikspeicher. Standard ist Hoch am Netzteil und Ausgewogen am Akku. Ein Wechsel wirkt sofort. Der Bildschirmschoner nutzt die Stufe am Netzteil. Gemessen auf dem MacBook Air M4 bei 3440 x 1440 mit der Voreinstellung Sternsystem."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section(L("Erweitert")) {
                ForEach(QualityArea.allCases, id: \.self) { a in
                    let own = q.areas[a.rawValue]
                    let shown = own ?? (Power.onBattery ? q.battery : q.power)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Picker(L(a.key), selection: areaBinding(a)) {
                                Text(L("Wie Gesamtstufe")).tag(-1)
                                ForEach(QualityLevel.allCases, id: \.self) { Text(L($0.key)).tag($0.rawValue) }
                            }
                            ResetButton(active: own != nil) { store.settings.quality.areas[a.rawValue] = nil }
                        }
                        Text(L(a.help) + " " + QualityTab.areaLoad(a, shown))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(L("Eine eigene Stufe gilt am Netzteil und am Akku. Die Mehrlast ist gegen Ausgewogen gemessen."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
