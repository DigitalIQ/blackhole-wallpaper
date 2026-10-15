import AppKit
import MetalKit
import ScreenSaver

/// Screen saver with the live black hole. Built from the app's renderer sources by
/// scripts/build-saver.sh. Runs sandboxed inside legacyScreenSaver, so the app copies
/// the look into this process's container as saver.json.
@objc(BlackHoleSaverView)
final class BlackHoleSaverView: ScreenSaverView {
    private var mtk: MTKView?
    private var renderer: Renderer?
    private var stopObserver: NSObjectProtocol?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private static func loadConfig() -> SaverConfig {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("BlackHoleWallpaper/saver.json")
        if let data = try? Data(contentsOf: url), let c = SaverConfig.decode(data) {
            return c
        }
        return SaverConfig(look: Look(), holeX: 0.5, holeY: 0.5)
    }

    private func setUp() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        var cfg = BlackHoleSaverView.loadConfig()
        // No menu bar or Dock over a screen saver.
        cfg.look.edgeTop.on = false
        cfg.look.edgeBottom.on = false
        let r = Renderer(look: cfg.look, layout: ScreenLayout(holeX: cfg.holeX, holeY: cfg.holeY, topBar: 0, bottomBar: 0))
        r.quality = cfg.quality.resolved(battery: false)
        let v = MTKView(frame: bounds, device: device)
        v.autoresizingMask = [.width, .height]
        v.colorPixelFormat = GPU.outFormat
        v.framebufferOnly = true
        v.autoResizeDrawable = false
        v.drawableSize = bounds.size
        v.preferredFramesPerSecond = isPreview ? 15 : 30
        (v.layer as? CAMetalLayer)?.maximumDrawableCount = 2
        v.delegate = r
        v.isPaused = true
        addSubview(v)
        mtk = v
        renderer = r
        animationTimeInterval = 1.0 / 30.0
        // legacyScreenSaver keeps instances alive after the saver ends; stop drawing then.
        stopObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screensaver.willstop"), object: nil, queue: .main
        ) { [weak self] _ in self?.mtk?.isPaused = true }
    }

    deinit {
        if let stopObserver { DistributedNotificationCenter.default().removeObserver(stopObserver) }
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        mtk?.drawableSize = bounds.size
    }

    override func startAnimation() {
        super.startAnimation()
        mtk?.drawableSize = bounds.size
        mtk?.isPaused = false
    }

    override func stopAnimation() {
        super.stopAnimation()
        mtk?.isPaused = true
    }

    override func animateOneFrame() {}

    override var hasConfigureSheet: Bool { false }
}
