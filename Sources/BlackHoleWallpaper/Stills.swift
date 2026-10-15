import AppKit

/// Puts a still of the live picture on the real desktop picture, so the lock screen and
/// Mission Control match. Remembers what was there before so it can be put back.
final class Stills {
    private let store: Store
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var flip = false
    /// The app is paused (locked, asleep, critical heat): the timer does not render, it only notes that a still is due.
    private var paused = false
    private var due = false

    init(store: Store) { self.store = store }

    private var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlackHoleWallpaper/Stills", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Re-arms the timer after a settings change; refreshes soon when the look changed.
    func settingsChanged(wallpapers: [Wallpaper], soon: Bool) {
        timer?.invalidate()
        guard store.settings.stillWallpaper else { due = false; return }
        let minutes = max(store.settings.stillInterval, 5)
        timer = Timer.scheduledTimer(withTimeInterval: minutes * 60, repeats: true) { [weak self] _ in
            self?.refreshOrDefer(wallpapers)
        }
        if soon {
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.refreshOrDefer(wallpapers) }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
        }
    }

    private func refreshOrDefer(_ wallpapers: [Wallpaper]) {
        if paused { due = true } else { refresh(wallpapers) }
    }

    /// Pauses with the rest of the app. On the way back one refresh runs only if a timer fired meanwhile.
    func setPaused(_ on: Bool, wallpapers: [Wallpaper]) {
        guard on != paused else { return }
        paused = on
        if !on, due {
            due = false
            refresh(wallpapers)
        }
    }

    func refresh(_ wallpapers: [Wallpaper]) {
        guard store.settings.stillWallpaper else { return }
        let ws = NSWorkspace.shared
        // macOS caches by URL, so alternate between two file names.
        flip.toggle()
        for w in wallpapers {
            let key = Store.key(for: w.screen)
            if store.settings.originalWallpapers[key] == nil, let cur = ws.desktopImageURL(for: w.screen),
               !cur.path.hasPrefix(dir.path) {
                store.settings.originalWallpapers[key] = cur.path
            }
            guard let img = w.renderStill() else { continue }
            let url = dir.appendingPathComponent("\(key)-\(flip ? "a" : "b").png")
            guard Snapshot.writePNG(img, to: url) else { continue }
            try? ws.setDesktopImageURL(url, for: w.screen, options: [:])
        }
    }

    func restore(_ wallpapers: [Wallpaper]) {
        timer?.invalidate()
        let ws = NSWorkspace.shared
        for w in wallpapers {
            let key = Store.key(for: w.screen)
            if let path = store.settings.originalWallpapers[key] {
                try? ws.setDesktopImageURL(URL(fileURLWithPath: path), for: w.screen, options: [:])
            }
        }
        store.settings.stillWallpaper = false
        store.settings.originalWallpapers = [:]
    }
}

/// Slow change over the day on top of the chosen preset.
enum DayDrift {
    static func apply(_ look: Look, strength: Float, date: Date = Date()) -> Look {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: date)
        let hours = Float(c.hour ?? 12) + Float(c.minute ?? 0) / 60
        let day = hours / 24 * 2 * .pi
        var l = look
        // Viewing angle swings a few degrees once a day, the nebula winds along.
        l.inclinationDeg = min(max(look.inclinationDeg + 6 * strength * sin(day), 3), 89)
        l.nebulaSwirl = look.nebulaSwirl + 1.2 * strength * sin(day * 3)
        // Evening and night: a little darker. Dark from 21 to 6, light from 9 to 18.
        let evening = hours >= 18 ? min((hours - 18) / 3, 1) : (hours < 9 ? max(1 - (hours - 6) / 3, 0) : 0)
        l.exposure = look.exposure * (1 - 0.22 * strength * min(max(evening, 0), 1))
        return l
    }
}
