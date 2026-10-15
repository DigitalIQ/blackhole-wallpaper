import AppKit
import ServiceManagement
import SwiftUI

/// The welcome window on the first launch.
enum Welcome {
    /// Only for a fresh install: no settings.json existed before this run, and the window was not shown yet.
    /// A file from an older version never counts, even when it has no `welcomeShown` key.
    static func shouldShow(freshInstall: Bool, shown: Bool) -> Bool { freshInstall && !shown }

    /// The built-in presets in the order of the preset list.
    static var presets: [Preset] { Preset.factory }

    static func appIcon() -> NSImage {
        if let img = Bundle.main.image(forResource: "AppIcon") { return img }
        if let img = NSImage(contentsOfFile: "Design/Icon/AppIcon.icns") { return img }
        return NSApp.applicationIconImage
    }

    static func menuBarIcon() -> NSImage {
        let img = Bundle.main.image(forResource: "MenuBarTemplate") ?? NSImage(contentsOfFile: "Design/Icon/MenuBarTemplate.png")
            ?? NSImage(systemSymbolName: "circle.circle", accessibilityDescription: nil) ?? NSImage()
        img.isTemplate = true
        return img
    }

    /// Small picture of one preset: the same renderer as the wallpaper, lowest quality, 16:10.
    static func thumbnail(_ preset: Preset, width: Int = 240, height: Int = 150) -> NSImage? {
        let r = Renderer(look: preset.look, layout: ScreenLayout(holeX: 0.5, holeY: 0.5, topBar: 2, bottomBar: 2))
        r.quality = RenderQuality(.saver)
        r.stillMode = true
        guard let cg = Snapshot.render(r, width: width, height: height) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: width / 2, height: height / 2))
    }
}

final class WelcomeModel: ObservableObject {
    @Published var thumbs: [String: NSImage] = [:]
    /// Pre-checked. Registered when the window closes, if still checked.
    @Published var openAtLogin = true
    private var started = false

    /// One picture per turn of the run loop, so the window stays responsive. The renderer is not
    /// thread safe against the live wallpaper (shared texture cache), so this stays on the main thread.
    func loadThumbnails() {
        guard !started else { return }
        started = true
        func next(_ rest: ArraySlice<Preset>) {
            guard let p = rest.first else { return }
            DispatchQueue.main.async { [weak self] in
                if let img = Welcome.thumbnail(p) { self?.thumbs[p.id] = img }
                next(rest.dropFirst())
            }
        }
        next(Welcome.presets[...])
    }

    /// The same pictures at once, for the screenshot tool.
    func loadThumbnailsNow() {
        started = true
        for p in Welcome.presets { if let img = Welcome.thumbnail(p) { thumbs[p.id] = img } }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var store: Store
    @ObservedObject var model: WelcomeModel
    var openSettings: () -> Void = {}
    var close: () -> Void = {}

    private let columns = Array(repeating: GridItem(.fixed(112), spacing: 12), count: 4)

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Image(nsImage: Welcome.appIcon())
                    .resizable()
                    .frame(width: 80, height: 80)
                Text(L("Schwarzes Loch"))
                    .font(.system(size: 26, weight: .semibold))
                Text(L("Ein lebendiger Schreibtisch-Hintergrund: ein drehendes Schwarzes Loch, das das Licht von Sternen und Nebeln wirklich biegt."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Wähle einen Look")).font(.headline)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(Welcome.presets) { p in
                        Button { choose(p.id) } label: { tile(p) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                Toggle(L("Beim Anmelden starten"), isOn: $model.openAtLogin)
                HStack(alignment: .center, spacing: 10) {
                    Image(nsImage: Welcome.menuBarIcon())
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.1)))
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(.secondary)
                    Text(L("Die Einstellungen findest du jederzeit über das Symbol in der Menüleiste."))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(L("Die App sucht einmal am Tag bei GitHub nach Updates. Das schaltest du unter Allgemein ab."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button(L("Einstellungen öffnen")) { openSettings() }
                    .buttonStyle(.bordered)
                Button(L("Los geht's")) { close() }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 540)
    }

    private var chosen: String? {
        let ids = Set(NSScreen.screens.map { store.config(for: $0).presetID })
        return ids.count == 1 ? ids.first : nil
    }

    private func choose(_ id: String) {
        store.ensureEntries(for: NSScreen.screens)
        store.assignToAllScreens(id)
    }

    private func tile(_ p: Preset) -> some View {
        let on = chosen == p.id
        return VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.black)
                if let img = model.thumbs[p.id] {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 112, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: on ? 3 : 1))
            Text(p.displayName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 112)
                .foregroundStyle(on ? Color.primary : Color.secondary)
        }
        .contentShape(Rectangle())
    }
}

/// Owns the window. Closing it, by any way, registers the login item if the box is still checked.
final class WelcomeController: NSObject, NSWindowDelegate {
    private let store: Store
    private let model = WelcomeModel()
    private var window: NSWindow?
    var onOpenSettings: () -> Void = {}

    init(store: Store) { self.store = store }

    func show() {
        let root = WelcomeView(model: model, openSettings: { [weak self] in
            self?.onOpenSettings()
            self?.window?.close()
        }, close: { [weak self] in self?.window?.close() })
        let host = NSHostingController(rootView: root.environmentObject(store))
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable]
        w.title = L("Willkommen")
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        model.loadThumbnails()
    }

    func windowWillClose(_ notification: Notification) {
        // A test run (settings copy) must not register a login item for a build from the project folder.
        guard model.openAtLogin, ProcessInfo.processInfo.environment["BH_SETTINGS"] == nil else { return }
        let svc = SMAppService.mainApp
        guard svc.status != .enabled else { return }
        do { try svc.register() } catch { NSLog("BlackHole: login item not registered: %@", error.localizedDescription) }
    }
}
