import AppKit
import Combine
import Foundation

/// All user settings, persisted as JSON in Application Support.
final class Store: ObservableObject {
    static let shared = Store()

    @Published var presets: [Preset] = Preset.factory
    @Published var settings = AppSettings() {
        didSet { if settings.language != oldValue.language { Loc.choice = settings.language } }
    }
    /// Preset shown in the settings window.
    @Published var editingID: String = "strudel"
    /// Screen the settings window edits; nil means all connected screens.
    @Published var editScreen: String?
    /// Whether macOS let the app tidy its wallpaper cache; nil until the app tried.
    @Published var cacheAccess: Bool?
    /// Keys of the connected screens. The self-test swaps in made-up ones.
    var connectedKeys: () -> [String] = { NSScreen.screens.map(Store.key(for:)) }
    /// Short screen name for preset copies, e.g. "Ultrawide".
    var shortName: (String) -> String = { Store.shortName(forKey: $0) }
    private let persist: Bool
    private let fileOverride: URL?
    /// False when settings.json exists but could not be read: then this run never writes it.
    private var writable = true
    private var backedUpThisRun = false
    /// A new backup at most this often within one run, so dragging a slider does not push out the old ones.
    static let backupSpacing: TimeInterval = 30 * 60

    /// True when no settings.json existed at the start of this run: a first launch.
    private(set) var freshInstall = false

    private var saveWork: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []

    var fileURL: URL {
        if let fileOverride { return fileOverride }
        // BH_SETTINGS=/path/file.json: run on a copy, e.g. for live measurements.
        if let path = ProcessInfo.processInfo.environment["BH_SETTINGS"], !path.isEmpty { return URL(fileURLWithPath: path) }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlackHoleWallpaper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    private struct File: Codable {
        var presets: [Preset]
        var settings: AppSettings
    }

    /// persist = false: nothing is written. read = false: start from defaults (self-test).
    /// file: another settings file, for the self-test.
    init(persist: Bool = true, read: Bool = true, file: URL? = nil) {
        self.persist = persist
        fileOverride = file
        if read { load() }
        Loc.choice = settings.language
        guard persist else { return }
        objectWillChange
            .sink { [weak self] _ in self?.scheduleSave() }
            .store(in: &cancellables)
    }

    // MARK: Persistence

    private func load() {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { freshInstall = true; return }
        guard let data = try? Data(contentsOf: url) else {
            writable = false
            NSLog("BlackHole: %@ exists but cannot be read; it will not be written in this run.", url.path)
            return
        }
        if !load(from: data) { setAside(url) }
    }

    /// Reads a settings file. Public for the self-test, which feeds it a copy. Returns false when the
    /// file did not load cleanly: not JSON, a part missing, or a preset that could not be read.
    @discardableResult
    func load(from data: Data) -> Bool {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        var clean = true
        if let s = raw["settings"], let d = try? JSONSerialization.data(withJSONObject: s),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: d) {
            settings = decoded
        } else {
            clean = false
        }
        if let list = raw["presets"] as? [[String: Any]] {
            var loaded: [Preset] = []
            for p in list {
                guard let id = p["id"] as? String, let name = p["name"] as? String,
                      let lookObj = p["look"], let ld = try? JSONSerialization.data(withJSONObject: lookObj),
                      let look = Look.decodeLenient(ld) else { clean = false; continue }
                loaded.append(Preset(id: id, name: name, look: look, builtIn: p["builtIn"] as? Bool ?? false,
                                     basedOn: p["basedOn"] as? String))
            }
            // Built-ins that are new in this version get added.
            for f in Preset.factory where !loaded.contains(where: { $0.id == f.id }) { loaded.append(f) }
            if !loaded.isEmpty { presets = loaded }
        } else {
            clean = false
        }
        return clean
    }

    /// A file that did not load cleanly is kept as settings.broken-<date>.json; a new one is written later.
    private func setAside(_ url: URL) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        let base = url.deletingPathExtension().lastPathComponent
        let target = url.deletingLastPathComponent().appendingPathComponent("\(base).broken-\(f.string(from: Date())).json")
        do {
            try FileManager.default.moveItem(at: url, to: target)
            NSLog("BlackHole: %@ did not load cleanly, kept as %@", url.path, target.lastPathComponent)
        } catch {
            writable = false
            NSLog("BlackHole: %@ did not load cleanly and could not be moved aside; it will not be written.", url.path)
        }
    }

    /// settings.backup-1.json is the newest of three.
    func backupURL(_ n: Int) -> URL {
        let url = fileURL
        return url.deletingLastPathComponent()
            .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent).backup-\(n).json")
    }

    /// Keeps the file about to be overwritten: the first time in each run, later at most every
    /// backupSpacing, never twice the same content.
    private func backUp(_ old: Data) {
        let fm = FileManager.default
        if let last = try? Data(contentsOf: backupURL(1)), last == old { backedUpThisRun = true; return }
        if backedUpThisRun, let date = (try? fm.attributesOfItem(atPath: backupURL(1).path))?[.modificationDate] as? Date,
           Date().timeIntervalSince(date) < Store.backupSpacing { return }
        try? fm.removeItem(at: backupURL(3))
        try? fm.moveItem(at: backupURL(2), to: backupURL(3))
        try? fm.moveItem(at: backupURL(1), to: backupURL(2))
        try? old.write(to: backupURL(1), options: .atomic)
        backedUpThisRun = true
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func save() {
        guard persist, writable, let data = encoded() else { return }
        let url = fileURL
        if let old = try? Data(contentsOf: url) {
            if old == data { return }
            backUp(old)
        }
        try? data.write(to: url, options: .atomic)
    }

    /// The settings file as it would be written.
    func encoded() -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(File(presets: presets, settings: settings))
    }

    // MARK: Presets

    func preset(_ id: String) -> Preset { presets.first { $0.id == id } ?? presets[0] }

    var editingIndex: Int { presets.firstIndex { $0.id == editingID } ?? 0 }

    @discardableResult
    func duplicate(_ id: String, name: String) -> String {
        var p = preset(id)
        p.basedOn = p.builtIn ? p.id : p.basedOn
        p.id = UUID().uuidString
        p.name = name
        p.builtIn = false
        presets.append(p)
        editingID = p.id
        return p.id
    }

    func rename(_ id: String, to name: String) {
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[i].name = name
    }

    func delete(_ id: String) {
        guard let i = presets.firstIndex(where: { $0.id == id }), !presets[i].builtIn else { return }
        presets.remove(at: i)
        for (k, c) in settings.screens where c.presetID == id { settings.screens[k]?.presetID = "strudel" }
        editingID = "strudel"
        syncEditing()
    }

    /// Values the reset buttons go back to: the built-in the preset is, or was copied from.
    func defaultLook(for id: String) -> Look {
        let p = preset(id)
        let base = p.builtIn ? p.id : (p.basedOn ?? "strudel")
        return Preset.factory.first { $0.id == base }?.look ?? Look()
    }

    /// Puts every value of one preset back to its defaults.
    func resetPreset(_ id: String) {
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[i].look = defaultLook(for: id)
        if let f = Preset.factory.first(where: { $0.id == id }) { presets[i].name = f.name }
    }

    /// Factory state: the five built-ins as shipped, own presets gone, every setting back
    /// to default. Keeps only the original wallpapers so they can still be restored.
    func resetAllToFactory() {
        let originals = settings.originalWallpapers
        let hidden = (settings.hideMenuIcon, settings.hideMenuIconConfirmed)
        let welcomed = settings.welcomeShown
        presets = Preset.factory
        settings = AppSettings()
        settings.originalWallpapers = originals
        settings.welcomeShown = welcomed
        // The way back in must not vanish with a reset; the icon keeps its state.
        (settings.hideMenuIcon, settings.hideMenuIconConfirmed) = hidden
        editingID = "strudel"
        syncEditing()
    }

    // MARK: Screens

    static func key(for screen: NSScreen) -> String {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(num.uint32Value)?.takeRetainedValue(),
              let s = CFUUIDCreateString(nil, uuid) as String? else { return screen.localizedName }
        return s
    }

    func config(for screen: NSScreen) -> ScreenConfig {
        if let c = settings.screens[Store.key(for: screen)] { return c }
        let portrait = screen.frame.height > screen.frame.width
        return ScreenConfig(presetID: "strudel", holeX: 0.5, holeY: portrait ? 0.3 : 0.5)
    }

    func setConfig(_ c: ScreenConfig, for screen: NSScreen) {
        settings.screens[Store.key(for: screen)] = c
        syncEditing()
    }

    func assignToAllScreens(_ id: String) {
        for s in NSScreen.screens {
            var c = config(for: s)
            c.presetID = id
            settings.screens[Store.key(for: s)] = c
        }
        syncEditing()
    }

    /// Every connected screen gets a stored entry, so the copy rule below sees all of them.
    func ensureEntries(for screens: [NSScreen]) {
        for s in screens where settings.screens[Store.key(for: s)] == nil {
            settings.screens[Store.key(for: s)] = config(for: s)
        }
    }

    static func screen(forKey k: String) -> NSScreen? { NSScreen.screens.first { key(for: $0) == k } }

    // MARK: Editing per screen

    func presetID(forKey k: String) -> String { settings.screens[k]?.presetID ?? "strudel" }

    private func setPreset(_ id: String, forKey k: String) {
        var c = settings.screens[k] ?? ScreenConfig()
        c.presetID = id
        settings.screens[k] = c
    }

    /// All screens chosen, but the connected ones show different presets: nothing to edit.
    var lookLocked: Bool { editScreen == nil && Set(connectedKeys().map(presetID(forKey:))).count > 1 }

    /// Points editingID at what the window edits: the chosen screen's preset or the common one.
    func syncEditing() {
        let id: String?
        if let k = editScreen {
            id = presetID(forKey: k)
        } else {
            let ids = Set(connectedKeys().map(presetID(forKey:)))
            id = ids.count == 1 ? ids.first : nil
        }
        if let id, id != editingID { editingID = id }
    }

    func selectScreen(_ key: String?) {
        editScreen = key
        syncEditing()
    }

    /// The preset picker at the top: sets it for the chosen screen, or for every connected one.
    func choosePreset(_ id: String) {
        if let k = editScreen { setPreset(id, forKey: k) } else { connectedKeys().forEach { setPreset(id, forKey: $0) } }
        editingID = id
    }

    /// Runs before any look value changes in the window. If the chosen screen shares its preset
    /// with another screen, connected or not, it first gets its own copy, which is then changed.
    func willEditLook() {
        guard let k = editScreen else { return }
        let id = presetID(forKey: k)
        let shared = settings.screens.contains { $0.key != k && $0.value.presetID == id }
            || connectedKeys().contains { $0 != k && presetID(forKey: $0) == id }
        guard shared else { return }
        var base = preset(id).displayName
        // A copy of a copy: "Dein Strudel (Ultrawide)" becomes "Dein Strudel (Hochkant)".
        for other in connectedKeys() where base.hasSuffix(" (\(shortName(other)))") {
            base = String(base.dropLast(shortName(other).count + 3))
        }
        let label = shortName(k)
        var name = "\(base) (\(label))"
        var n = 2
        while presets.contains(where: { $0.name == name }) { name = "\(base) (\(label) \(n))"; n += 1 }
        let copy = duplicate(id, name: name)
        setPreset(copy, forKey: k)
        editingID = copy
    }

    // MARK: Screen names

    /// "Ultrawide", "Hochkant", "MacBook" or the display's own name; plus where it sits if
    /// another connected screen would get the same name.
    static func shortName(forKey k: String) -> String {
        guard let s = screen(forKey: k) else { return L("Schirm") }
        let all = NSScreen.screens
        let same = all.filter { baseShortName($0) == baseShortName(s) }
        return same.count > 1 ? baseShortName(s) + " " + position(of: s, among: same) : baseShortName(s)
    }

    private static func baseShortName(_ s: NSScreen) -> String {
        let f = s.frame
        if f.height > f.width { return L("Hochkant") }
        if f.width / f.height >= 2.1 { return "Ultrawide" }
        if let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
           CGDisplayIsBuiltin(n.uint32Value) != 0 { return "MacBook" }
        return s.localizedName
    }

    /// Picker entry: name and size, plus the position when two screens share a name.
    static func label(for s: NSScreen) -> String {
        let same = NSScreen.screens.filter { $0.localizedName == s.localizedName }
        let pos = same.count > 1 ? ", " + position(of: s, among: same) : ""
        return "\(s.localizedName) (\(Int(s.frame.width)) x \(Int(s.frame.height))\(pos))"
    }

    /// links, Mitte, rechts; or oben, unten when the screens are stacked.
    static func position(of s: NSScreen, among group: [NSScreen]) -> String {
        let xs = group.map(\.frame.midX), ys = group.map(\.frame.midY)
        let wide = (xs.max()! - xs.min()!) >= (ys.max()! - ys.min()!)
        if wide {
            if s.frame.midX == xs.min() { return L("links") }
            if s.frame.midX == xs.max() { return L("rechts") }
            return L("Mitte")
        }
        if s.frame.midY == ys.max() { return L("oben") }
        if s.frame.midY == ys.min() { return L("unten") }
        return L("Mitte")
    }
}
