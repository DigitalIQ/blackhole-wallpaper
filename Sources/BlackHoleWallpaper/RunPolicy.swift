import AppKit
import Combine

/// How hot the Mac is, from ProcessInfo.thermalState. A separate type so the self-test can feed any value.
enum Heat: Int, Comparable {
    case nominal, fair, serious, critical

    init(_ s: ProcessInfo.ThermalState) {
        switch s {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .fair
        }
    }

    static var current: Heat { Heat(ProcessInfo.processInfo.thermalState) }
    static func < (a: Heat, b: Heat) -> Bool { a.rawValue < b.rawValue }
}

/// Why nothing should be drawn. Any one of them is enough to stop; all must be gone to start again.
enum PauseReason: String, CaseIterable {
    case screenLocked, screensaver, displaysAsleep, systemAsleep, sessionInactive
}

/// Everything the run state depends on, in one value.
struct RunInputs {
    var animation = AnimationMode.all
    var lowPowerMode = false
    var freezeInLowPower = true
    var onBattery = false
    var fpsPower = 30
    var fpsBattery = 30
    /// The hidden `fpsOverride` default, 0 = none.
    var fpsOverride = 0
    var throttleWhenHot = true
    var heat = Heat.nominal
    var respectReduceMotion = true
    var reduceMotion = false
    var pauseReasons: Set<PauseReason> = []

    init() {}

    init(settings s: AppSettings, lowPowerMode: Bool, onBattery: Bool, fpsOverride: Int, heat: Heat,
         reduceMotion: Bool, pauseReasons: Set<PauseReason>) {
        animation = s.animation
        self.lowPowerMode = lowPowerMode
        freezeInLowPower = s.freezeInLowPower
        self.onBattery = onBattery
        fpsPower = s.fpsPower
        fpsBattery = s.fpsBattery
        self.fpsOverride = fpsOverride
        throttleWhenHot = s.throttleWhenHot
        self.heat = heat
        respectReduceMotion = s.respectReduceMotion
        self.reduceMotion = reduceMotion
        self.pauseReasons = pauseReasons
    }
}

/// What the app does right now.
enum RunKind: Equatable {
    case running, edgesOnly
    case frozenByUser, frozenReduceMotion, frozenLowPower, frozenHot
    /// Locked, asleep, screen saver or another session in front: no frames at all.
    case pausedBySystem
}

struct RunPlan: Equatable {
    var kind: RunKind
    var fps: Int
    /// Quality levels to drop below the chosen ones (heat from serious on), never below Akku sparen.
    var qualityStep = 0
    /// True when heat halved the frame rate.
    var throttled = false

    var animates: Bool { kind == .running || kind == .edgesOnly }
}

enum RunPolicy {
    /// The animation level that counts: Reduce Motion in macOS turns it off, unless the user opted out.
    static func effectiveAnimation(_ mode: AnimationMode, respectReduceMotion: Bool, reduceMotion: Bool) -> AnimationMode {
        respectReduceMotion && reduceMotion ? .off : mode
    }

    /// Heat at .serious: half the frame rate, but not below this.
    static let hotMinimumFps = 5

    /// The quality step that goes with a heat level: one lower from .serious on, also when critical (the
    /// still frame keeps the lowered levels, so heating up further redoes nothing) and also while paused.
    static func qualityStep(heat: Heat, throttleWhenHot: Bool) -> Int { throttleWhenHot && heat >= .serious ? 1 : 0 }

    static func plan(_ i: RunInputs) -> RunPlan {
        let step = qualityStep(heat: i.heat, throttleWhenHot: i.throttleWhenHot)
        func fixed(_ kind: RunKind) -> RunPlan { RunPlan(kind: kind, fps: 1, qualityStep: step) }
        if !i.pauseReasons.isEmpty { return fixed(.pausedBySystem) }
        if i.animation == .off { return fixed(.frozenByUser) }
        let anim = effectiveAnimation(i.animation, respectReduceMotion: i.respectReduceMotion, reduceMotion: i.reduceMotion)
        if anim == .off { return fixed(.frozenReduceMotion) }
        if i.lowPowerMode && i.freezeInLowPower { return fixed(.frozenLowPower) }
        let heat = i.throttleWhenHot ? i.heat : .nominal
        if heat >= .critical { return fixed(.frozenHot) }
        var fps = i.fpsOverride > 0 ? i.fpsOverride : (i.onBattery ? i.fpsBattery : i.fpsPower)
        var plan = RunPlan(kind: anim == .edgesOnly ? .edgesOnly : .running, fps: fps, qualityStep: step)
        if heat == .serious {
            fps = max(fps / 2, hotMinimumFps)
            plan.fps = fps
            plan.throttled = true
        }
        return plan
    }
}

extension RenderQuality {
    /// The same levels, `steps` lower, none below Akku sparen.
    func lowered(by steps: Int) -> RenderQuality {
        guard steps > 0 else { return self }
        var q = self
        for (a, l) in levels { q.levels[a] = QualityLevel(rawValue: max(l.rawValue - steps, 0)) ?? .saver }
        return q
    }
}

/// The Reduce Motion switch of macOS, observable by the settings window.
final class SystemAccess: ObservableObject {
    static let shared = SystemAccess()
    @Published private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var token: NSObjectProtocol?

    private init() {
        // Test runs only (BH_SETTINGS): BH_FAKE_REDUCE_MOTION=1 shows the hint in a screenshot.
        let env = ProcessInfo.processInfo.environment
        if env["BH_SETTINGS"] != nil, env["BH_FAKE_REDUCE_MOTION"] == "1" { reduceMotion = true }
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let now = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if now != self.reduceMotion { self.reduceMotion = now }
        }
    }
}

/// Collects the reasons to stop drawing from the system and tells the app when the set changes.
/// Going to sleep or locking reports at once. Coming back waits a moment, so a wake that is followed
/// right away by the lock screen never draws a frame in between.
final class SystemWatch {
    private(set) var reasons: Set<PauseReason> = []
    private var resumePending = false
    private var resumeWork: DispatchWorkItem?
    var onChange: (() -> Void)?
    let resumeDelay: TimeInterval

    /// What the app should treat as paused: a reason is active, or the last one just went.
    var effective: Set<PauseReason> { resumePending && reasons.isEmpty ? [.systemAsleep] : reasons }
    var isPaused: Bool { !effective.isEmpty }

    init(resumeDelay: TimeInterval = 0.35, observe: Bool = true) {
        self.resumeDelay = resumeDelay
        guard observe else { return }
        let ws = NSWorkspace.shared.notificationCenter
        let dist = DistributedNotificationCenter.default()
        func on(_ c: NotificationCenter, _ name: Notification.Name, _ reason: PauseReason, _ active: Bool) {
            c.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.set(reason, active) }
        }
        on(ws, NSWorkspace.screensDidSleepNotification, .displaysAsleep, true)
        on(ws, NSWorkspace.screensDidWakeNotification, .displaysAsleep, false)
        on(ws, NSWorkspace.willSleepNotification, .systemAsleep, true)
        on(ws, NSWorkspace.didWakeNotification, .systemAsleep, false)
        on(ws, NSWorkspace.sessionDidResignActiveNotification, .sessionInactive, true)
        on(ws, NSWorkspace.sessionDidBecomeActiveNotification, .sessionInactive, false)
        on(dist, Notification.Name("com.apple.screenIsLocked"), .screenLocked, true)
        on(dist, Notification.Name("com.apple.screenIsUnlocked"), .screenLocked, false)
        on(dist, Notification.Name("com.apple.screensaver.didstart"), .screensaver, true)
        on(dist, Notification.Name("com.apple.screensaver.didstop"), .screensaver, false)
        // The app can start while the screen is locked or another user is in front.
        if let d = CGSessionCopyCurrentDictionary() as? [String: Any] {
            if (d["CGSSessionScreenIsLocked"] as? Bool) == true { reasons.insert(.screenLocked) }
            if (d["kCGSSessionOnConsoleKey"] as? Bool) == false { reasons.insert(.sessionInactive) }
        }
    }

    func set(_ reason: PauseReason, _ active: Bool) {
        if active {
            let wasPaused = !reasons.isEmpty || resumePending
            reasons.insert(reason)
            resumeWork?.cancel()
            resumePending = false
            if !wasPaused { onChange?() }
            return
        }
        guard reasons.remove(reason) != nil, reasons.isEmpty else { return }
        resumePending = true
        resumeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.resumePending else { return }
            self.resumePending = false
            self.onChange?()
        }
        resumeWork = work
        if resumeDelay <= 0 { work.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + resumeDelay, execute: work) }
    }
}
