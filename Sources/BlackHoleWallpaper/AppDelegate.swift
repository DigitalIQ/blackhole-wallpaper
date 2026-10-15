import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = Store.shared
    private var wallpapers: [Wallpaper] = []
    private var statusItem: NSStatusItem!
    private var statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var presetMenu = NSMenu()
    private var rebuildWork: DispatchWorkItem?
    private var layoutTimer: Timer?
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var applyPending = false
    private lazy var stills = Stills(store: store)
    private var driftTimer: Timer?
    private var lastLooks: [String: Look] = [:]
    private var lastStillSettings: (Bool, Double) = (false, 0)
    private var lastQuality = QualitySettings()
    private var updateLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let watch = SystemWatch()
    private var welcome: WelcomeController?
    /// What the screens looked like when the wallpapers were built; the same again needs no rebuild.
    private var screenSignature: [String] = []
    /// Test runs only (BH_SETTINGS): pretend values for heat and Reduce Motion.
    private var testHeat: Heat?
    private var testReduceMotion: Bool?
    private var debugTimer: Timer?
    private var lastPlan: RunPlan?

    static let testNote = Notification.Name("io.github.digitaliq.blackholewallpaper.test")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second launch (Spotlight, Finder, `open`) asks the running copy for its
        // settings window. The app has no Dock icon, so this is the natural way back in.
        let openSettingsNote = Notification.Name("io.github.digitaliq.blackholewallpaper.openSettings")
        // A run on a settings copy (BH_SETTINGS) is a test and may run beside the installed app.
        if ProcessInfo.processInfo.environment["BH_SETTINGS"] == nil, let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            DistributedNotificationCenter.default().postNotificationName(openSettingsNote, object: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        DistributedNotificationCenter.default().addObserver(forName: openSettingsNote, object: nil, queue: .main) { [weak self] _ in
            self?.openSettings()
        }
        setUpMenu()
        rebuild()

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleRebuild()
        }
        nc.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.updateRunState()
        }
        nc.addObserver(forName: .powerSourceChanged, object: nil, queue: .main) { [weak self] _ in
            // Frame rate and quality levels differ between adapter and battery.
            self?.scheduleApply()
        }
        Power.startWatching()
        // Pause while locked, asleep, in the screen saver or switched out; come back after a short wait.
        watch.onChange = { [weak self] in self?.updateRunState() }
        // The Mac gets hot or cools down; Reduce Motion is switched.
        nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleApply()
        }
        SystemAccess.shared.objectWillChange
            .sink { [weak self] _ in self?.scheduleApply() }
            .store(in: &cancellables)
        setUpTestHooks()
        // The Dock can move between screens without a screen-parameter notification.
        layoutTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            for w in self.wallpapers { w.refreshLayout(config: self.store.config(for: w.screen)) }
        }
        store.objectWillChange
            .sink { [weak self] _ in self?.scheduleApply() }
            .store(in: &cancellables)
        nc.addObserver(forName: .restoreWallpapers, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.stills.restore(self.wallpapers)
        }
        nc.addObserver(forName: .refreshStills, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.stills.refresh(self.wallpapers)
        }
        // Day drift moves slowly; a new look every five minutes is plenty.
        driftTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self, self.store.settings.dayDrift else { return }
            self.scheduleApply()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            NSLog("BlackHole GPU allocated: %.1f MB", Double(GPU.shared.device.currentAllocatedSize) / 1e6)
        }
        stills.settingsChanged(wallpapers: wallpapers, soon: true)
        lastStillSettings = (store.settings.stillWallpaper, store.settings.stillInterval)
        exportSaverConfig()
        MainActor.assumeIsolated { Updater.shared.start() }
        showWelcomeIfNeeded()
    }

    /// The look a screen shows right now: its preset, plus the drift over the day if on.
    private func effectiveLook(_ c: ScreenConfig) -> Look {
        let l = store.preset(c.presetID).look
        return store.settings.dayDrift ? DayDrift.apply(l, strength: store.settings.dayDriftStrength) : l
    }

    // MARK: Screens

    /// Frame and scale of every screen. A wake from sleep or a plain Dock change posts the screen
    /// notification without changing any of this, and a rebuild would trace every ray map again.
    private static func signature() -> [String] {
        NSScreen.screens.map { "\(Store.key(for: $0)) \(NSStringFromRect($0.frame)) \($0.backingScaleFactor)" }
    }

    private func scheduleRebuild() {
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if AppDelegate.signature() == self.screenSignature && !self.wallpapers.isEmpty {
                for w in self.wallpapers { w.refreshLayout(config: self.store.config(for: w.screen)) }
                return
            }
            self.rebuild()
        }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func rebuild() {
        screenSignature = AppDelegate.signature()
        store.ensureEntries(for: NSScreen.screens)
        // The screen chosen in the window was unplugged: fall back to all screens.
        if let k = store.editScreen, Store.screen(forKey: k) == nil { store.selectScreen(nil) } else { store.syncEditing() }
        wallpapers.forEach { $0.close() }
        wallpapers = NSScreen.screens.map { screen in
            let c = store.config(for: screen)
            let w = Wallpaper(screen: screen, look: effectiveLook(c), config: c)
            w.update(look: effectiveLook(c), config: c, settings: store.settings, qualityStep: runPlan.qualityStep)
            w.onVisibilityChange = { [weak self] in self?.updateRunState() }
            return w
        }
        updateRunState()
    }

    /// objectWillChange fires before the value changes; apply on the next turn of the run loop.
    private func scheduleApply() {
        guard !applyPending else { return }
        applyPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyPending = false
            var looksChanged = false
            for w in self.wallpapers {
                let c = self.store.config(for: w.screen)
                let look = self.effectiveLook(c)
                let key = Store.key(for: w.screen)
                if self.lastLooks[key] != look { looksChanged = true; self.lastLooks[key] = look }
                w.update(look: look, config: c, settings: self.store.settings, qualityStep: self.runPlan.qualityStep)
            }
            self.updateRunState()
            self.statusItem.isVisible = !self.store.settings.hideMenuIcon
            self.settingsWindow?.title = L("Schwarzes Loch")
            let st = (self.store.settings.stillWallpaper, self.store.settings.stillInterval)
            let q = self.store.settings.quality
            if q != self.lastQuality { looksChanged = true; self.lastQuality = q }
            if looksChanged || st != self.lastStillSettings {
                self.stills.settingsChanged(wallpapers: self.wallpapers, soon: true)
                self.lastStillSettings = st
                self.exportSaverConfig()
            }
        }
    }

    // MARK: Power and run state

    private var heat: Heat { testHeat ?? .current }
    private var reduceMotion: Bool { testReduceMotion ?? SystemAccess.shared.reduceMotion }

    private var runPlan: RunPlan {
        RunPolicy.plan(RunInputs(settings: store.settings, lowPowerMode: Power.lowPowerMode, onBattery: Power.onBattery,
                                 fpsOverride: UserDefaults.standard.integer(forKey: "fpsOverride"), heat: heat,
                                 reduceMotion: reduceMotion, pauseReasons: watch.effective))
    }

    private func updateRunState() {
        let plan = runPlan
        for w in wallpapers {
            if plan.kind == .pausedBySystem { w.setSuspended(true); continue }
            switch plan.kind {
            case .running: w.apply(running: w.visible, edgesOnly: false, fps: plan.fps)
            case .edgesOnly: w.apply(running: w.visible, edgesOnly: true, fps: plan.fps)
            default: w.apply(running: false, edgesOnly: false, fps: 1)
            }
            w.setSuspended(false)
        }
        stills.setPaused(plan.kind == .pausedBySystem || plan.kind == .frozenHot, wallpapers: wallpapers)
        statusLine.title = switch plan.kind {
        case .running where plan.throttled, .edgesOnly where plan.throttled: L("Gedrosselt wegen Hitze, %d Bilder pro Sekunde", plan.fps)
        case .running: L("Läuft mit %d Bildern pro Sekunde", plan.fps)
        case .edgesOnly: L("Nur Ränder, %d Bilder pro Sekunde", plan.fps)
        case .frozenByUser: L("Angehalten")
        case .frozenReduceMotion: L("Angehalten: Bewegung reduzieren ist an")
        case .frozenLowPower: L("Angehalten: Energiesparmodus")
        case .frozenHot: L("Angehalten: Mac ist zu heiß")
        case .pausedBySystem: L("Angehalten: Mac gesperrt oder im Ruhezustand")
        }
        if Renderer.debugLog, plan != lastPlan {
            NSLog("Run state: %@, %d fps, quality step %d%@", String(describing: plan.kind), plan.fps, plan.qualityStep,
                  plan.kind == .pausedBySystem ? " (" + watch.reasons.map(\.rawValue).sorted().joined(separator: ",") + ")" : "")
        }
        lastPlan = plan
    }

    /// BH_DEBUG: how many frames were started in the last five seconds. Zero while paused.
    private func startDebugCounter() {
        guard Renderer.debugLog, debugTimer == nil else { return }
        var last = Renderer.framesDrawn
        debugTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            NSLog("Frames started in the last 5 s: %d", Renderer.framesDrawn - last)
            last = Renderer.framesDrawn
        }
    }

    /// A run on a settings copy (BH_SETTINGS) may fake lock, heat and Reduce Motion through a distributed
    /// notification, so the paused state can be measured without locking the real screen.
    /// The object is one of: lock, unlock, heat:nominal|fair|serious|critical, heat:off, motion:on|off|auto.
    private func setUpTestHooks() {
        startDebugCounter()
        guard ProcessInfo.processInfo.environment["BH_SETTINGS"] != nil else { return }
        DistributedNotificationCenter.default().addObserver(forName: AppDelegate.testNote, object: nil, queue: .main) { [weak self] n in
            guard let self, let cmd = n.object as? String else { return }
            switch cmd {
            case "lock": self.watch.set(.screenLocked, true)
            case "unlock": self.watch.set(.screenLocked, false)
            case "heat:off": self.testHeat = nil
            case "motion:auto": self.testReduceMotion = nil
            case "motion:on", "motion:off": self.testReduceMotion = cmd == "motion:on"
            default:
                if cmd.hasPrefix("heat:"), let h = ["nominal": Heat.nominal, "fair": .fair, "serious": .serious, "critical": .critical][String(cmd.dropFirst(5))] {
                    self.testHeat = h
                }
            }
            self.scheduleApply()
            self.updateRunState()
        }
    }

    // MARK: Welcome

    /// First launch only: no settings.json before this run. BH_FORCE_WELCOME=1 shows it for testing.
    private func showWelcomeIfNeeded() {
        let forced = ProcessInfo.processInfo.environment["BH_FORCE_WELCOME"] == "1"
        guard forced || Welcome.shouldShow(freshInstall: store.freshInstall, shown: store.settings.welcomeShown) else { return }
        if !forced { store.settings.welcomeShown = true }
        let w = WelcomeController(store: store)
        w.onOpenSettings = { [weak self] in self?.openSettings() }
        welcome = w
        w.show()
    }

    // MARK: Menu

    /// Template image from the bundle (18 pt); falls back to an SF Symbol when the file is missing.
    private static func menuBarImage() -> NSImage? {
        if let image = Bundle.main.image(forResource: "MenuBarTemplate") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            image.accessibilityDescription = L("Schwarzes Loch")
            return image
        }
        return NSImage(systemSymbolName: "circle.circle", accessibilityDescription: L("Schwarzes Loch"))
    }

    private func setUpMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarImage()
        let menu = NSMenu()
        menu.delegate = self
        fillMenu(menu)
        statusItem.menu = menu
        statusItem.isVisible = !store.settings.hideMenuIcon
    }

    /// Builds the items in the current language; runs again before the menu opens.
    private func fillMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        // Shown only when the automatic check found a new version; no window pops up by itself.
        updateLine = item("", #selector(showUpdate))
        updateLine.isHidden = true
        menu.addItem(updateLine)
        menu.addItem(.separator())
        let heading = NSMenuItem(title: L("Animation"), action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        for mode in AnimationMode.allCases {
            let i = item(mode.title, #selector(pickAnimation(_:)))
            i.representedObject = mode.rawValue
            i.indentationLevel = 1
            menu.addItem(i)
        }
        menu.addItem(.separator())
        menu.addItem(item(L("Im Energiesparmodus anhalten"), #selector(toggleLowPower)))
        menu.addItem(item(L("Maus-Modus"), #selector(toggleMouse)))
        menu.addItem(.separator())
        let presets = NSMenuItem(title: L("Voreinstellung für alle Schirme"), action: nil, keyEquivalent: "")
        presets.submenu = presetMenu
        menu.addItem(presets)
        menu.addItem(item(L("Einstellungen …"), #selector(openSettings), key: ","))
        menu.addItem(item(L("Nach Updates suchen …"), #selector(checkForUpdates)))
        menu.addItem(.separator())
        menu.addItem(item(L("Beim Anmelden starten"), #selector(toggleLogin)))
        menu.addItem(.separator())
        menu.addItem(item(L("Beenden"), #selector(quit), key: "q"))
        menuLang = Loc.lang
    }

    private var menuLang = Loc.lang

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu == statusItem.menu && menuLang != Loc.lang { fillMenu(menu) }
        updateRunState()
        if menu == statusItem.menu {
            let found = MainActor.assumeIsolated { Updater.shared.foundAutomatically ? Updater.shared.available : nil }
            updateLine.isHidden = found == nil
            if let r = found {
                updateLine.title = L("Version %@ ist da …", r.versionString)
                updateLine.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            }
        }
        for i in menu.items {
            switch i.action {
            case #selector(pickAnimation(_:)):
                i.state = i.representedObject as? String == store.settings.animation.rawValue ? .on : .off
            case #selector(toggleLowPower): i.state = store.settings.freezeInLowPower ? .on : .off
            case #selector(toggleMouse): i.state = store.settings.mouseMode ? .on : .off
            case #selector(toggleLogin): i.state = SMAppService.mainApp.status == .enabled ? .on : .off
            default: break
            }
        }
        presetMenu.removeAllItems()
        let used = Set(NSScreen.screens.map { store.config(for: $0).presetID })
        for p in store.presets {
            let i = item(p.displayName, #selector(pickPreset(_:)))
            i.representedObject = p.id
            i.state = used == [p.id] ? .on : (used.contains(p.id) ? .mixed : .off)
            presetMenu.addItem(i)
        }
    }

    @objc private func pickPreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        store.assignToAllScreens(id)
    }

    @objc private func pickAnimation(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = AnimationMode(rawValue: raw) else { return }
        store.settings.animation = mode
    }
    @objc private func toggleLowPower() { store.settings.freezeInLowPower.toggle() }
    @objc private func toggleMouse() { store.settings.mouseMode.toggle() }

    /// The screen saver runs sandboxed inside legacyScreenSaver and cannot read our
    /// settings, so the look of the main screen is copied into its container.
    private func exportSaverConfig() {
        // A run on a settings copy must not change the real screen saver.
        if ProcessInfo.processInfo.environment["BH_SETTINGS"] != nil { return }
        guard let main = NSScreen.main ?? NSScreen.screens.first else { return }
        let c = store.config(for: main)
        let container = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support")
        guard FileManager.default.fileExists(atPath: container.path) else { return }
        let dir = container.appendingPathComponent("BlackHoleWallpaper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cfg = SaverConfig(look: effectiveLook(c), holeX: c.holeX, holeY: c.holeY, quality: store.settings.quality)
        if let data = try? JSONEncoder().encode(cfg) { try? data.write(to: dir.appendingPathComponent("saver.json")) }
        // Own 3D models of the scene go along, the saver cannot read our folder.
        ModelStore.exportForSaver(names: cfg.look.objects.items.filter { $0.kind == "model" }.map(\.model), to: dir)
    }

    @objc private func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = L("Autostart ließ sich nicht ändern")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc func openSettings() {
        let wasVisible = settingsWindow?.isVisible ?? false
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = L("Schwarzes Loch")
            w.contentViewController = NSHostingController(rootView: SettingsView().environmentObject(store))
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("SettingsWindow")
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        // Opening starts on the screen the window sits on.
        if !wasVisible {
            store.ensureEntries(for: NSScreen.screens)
            store.selectScreen((settingsWindow?.screen ?? NSScreen.main).map(Store.key(for:)))
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showUpdate() { showSettingsPage(0) }

    @objc private func checkForUpdates() {
        MainActor.assumeIsolated { Updater.shared.checkNow() }
        showSettingsPage(0)
    }

    /// Opens the settings window on one page (0 = Allgemein, where the updates are).
    func showSettingsPage(_ page: Int) {
        openSettings()
        NotificationCenter.default.post(name: .showSettingsPage, object: page)
    }
}
