import AppKit
import MetalKit

/// One borderless window per screen, at desktop level, behind icons and every app window.
final class Wallpaper {
    let screen: NSScreen
    let window: NSWindow
    let view: MTKView
    let renderer: Renderer
    private(set) var visible = true
    private var running = false
    var onVisibilityChange: (() -> Void)?
    private var observer: NSObjectProtocol?
    private var mouseOn = false
    private var mouseSize: Float = 70
    private var mouseShadow = true
    /// Edges-only mode: the main view holds a still, these two redraw the bands (top, bottom).
    private let strips: [BandStrip]
    private var edgesOnly = false
    private var fps = 30
    private var applied: (Bool, Bool, Int)?
    private var mouseTimer: Timer?
    /// Locked, asleep or another session in front: no frames at all, whatever the settings say.
    /// The picture in the layer stays as it is, so waking up shows it at once.
    private(set) var suspended = false
    /// A change arrived while suspended and the held picture does not show it yet.
    private var missedRedraw = false

    init(screen: NSScreen, look: Look, config: ScreenConfig) {
        self.screen = screen
        renderer = Renderer(look: look, layout: Wallpaper.layout(for: screen, config: config))
        renderer.geoInterval = 0.12

        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false

        view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size), device: GPU.shared.device)
        view.colorPixelFormat = GPU.outFormat
        view.framebufferOnly = true
        view.autoResizeDrawable = false
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        // Two drawables instead of three: one full-screen buffer less per screen.
        (view.layer as? CAMetalLayer)?.maximumDrawableCount = 2
        view.delegate = renderer
        view.autoresizingMask = [.width, .height]
        let root = NSView(frame: view.frame)
        root.wantsLayer = true
        root.addSubview(view)
        strips = [BandStrip(renderer: renderer), BandStrip(renderer: renderer)]
        for s in strips { root.addSubview(s.view) }
        window.contentView = root
        // Render at point resolution: Retina pixels cost power and the scene is soft anyway.
        view.drawableSize = screen.frame.size
        renderer.pixelScale = 1
        renderer.beforeDraw = { [weak self] in self?.updateMouse() }

        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let v = self.window.occlusionState.contains(.visible)
            if v != self.visible { self.visible = v; self.onVisibilityChange?() }
        }
        window.orderFront(nil)
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func close() {
        mouseTimer?.invalidate()
        for s in strips { s.view.isPaused = true }
        view.isPaused = true
        window.orderOut(nil)
        window.close()
    }

    /// Applies look and screen config; redraws a paused view so changes show at once.
    /// qualityStep: levels to drop because the Mac is hot.
    func update(look: Look, config: ScreenConfig, settings: AppSettings, qualityStep: Int = 0) {
        renderer.look = look
        renderer.layout = Wallpaper.layout(for: screen, config: config)
        renderer.quality = settings.quality.resolved(battery: Power.onBattery).lowered(by: qualityStep)
        mouseOn = settings.mouseMode
        mouseSize = settings.mouseSize
        mouseShadow = settings.mouseShadow
        layoutStrips()
        updateMouseTimer()
        redrawIfPaused()
    }

    /// Pointer position for the mouse lens; off while the pointer is on another screen.
    private func updateMouse() { renderer.mouse = mouseLens() }

    private func mouseLens() -> SIMD4<Float> {
        let p = NSEvent.mouseLocation
        let f = screen.frame
        guard mouseOn, f.contains(p) else { return .zero }
        let s = renderer.pixelScale
        return SIMD4(Float(p.x - f.minX) * s, Float(f.maxY - p.y) * s, mouseSize * s, mouseShadow ? 1 : 0)
    }

    /// Edges-only mode keeps the lens: the still is redrawn only when the pointer moved.
    private func updateMouseTimer() {
        let want = edgesOnly && mouseOn && !suspended
        if !want { mouseTimer?.invalidate(); mouseTimer = nil; return }
        if mouseTimer != nil { return }
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 1 / Double(max(fps, 1)), repeats: true) { [weak self] _ in
            guard let self, self.mouseLens() != self.renderer.mouse else { return }
            self.view.setNeedsDisplay(self.view.bounds)
        }
    }

    /// The current picture as an image, for the desktop picture behind the lock screen.
    func renderStill() -> CGImage? {
        let saved = renderer.mouse, savedStrips = renderer.edgeObjectsInStrips
        renderer.mouse = .zero
        renderer.stillMode = true
        renderer.edgeObjectsInStrips = false
        defer { renderer.mouse = saved; renderer.stillMode = false; renderer.edgeObjectsInStrips = savedStrips }
        return Snapshot.render(renderer, width: Int(view.drawableSize.width), height: Int(view.drawableSize.height))
    }

    func refreshLayout(config: ScreenConfig) {
        let l = Wallpaper.layout(for: screen, config: config)
        if l != renderer.layout {
            renderer.layout = l
            layoutStrips()
            redrawIfPaused()
        }
    }

    private func redrawIfPaused() {
        guard !running else { return }
        if suspended { missedRedraw = true; return }
        view.setNeedsDisplay(view.bounds)
        // A throttled ray rebuild may still be pending; draw again once it is allowed.
        DispatchQueue.main.asyncAfter(deadline: .now() + renderer.geoInterval + 0.02) { [weak self] in
            guard let self, !self.running, !self.suspended, self.renderer.needsRedraw else { return }
            self.view.setNeedsDisplay(self.view.bounds)
        }
    }

    /// Stops every view without touching the picture or any renderer state, and starts the same
    /// views again later. Nothing is redone on the way back: the ray maps stay, the first frame
    /// is an ordinary one, and the clock does not jump (the renderer drops the time of a paused stretch).
    func setSuspended(_ on: Bool) {
        guard on != suspended else { return }
        suspended = on
        if on {
            view.isPaused = true
            for s in strips { s.view.isPaused = true }
            mouseTimer?.invalidate()
            mouseTimer = nil
            return
        }
        renderer.resumeClock()
        if running { view.isPaused = false }
        if edgesOnly { for s in strips where !s.view.isHidden { s.view.isPaused = false } }
        updateMouseTimer()
        if missedRedraw && !running {
            missedRedraw = false
            view.setNeedsDisplay(view.bounds)
        }
    }

    /// running = animate at fps; otherwise draw once and hold the frame. With edgesOnly the
    /// picture holds and only the band strips animate.
    func apply(running: Bool, edgesOnly: Bool, fps: Int) {
        let state = (running, edgesOnly, fps)
        if let a = applied, a == state { return }
        applied = state
        let full = running && !edgesOnly
        self.running = full
        self.edgesOnly = running && edgesOnly
        self.fps = fps
        renderer.animating = full
        // Edges only: objects on a band move in the strips, the still picture leaves them out.
        renderer.edgeObjectsInStrips = self.edgesOnly
        view.preferredFramesPerSecond = fps
        if full {
            view.enableSetNeedsDisplay = false
            view.isPaused = suspended
        } else {
            view.isPaused = true
            view.enableSetNeedsDisplay = true
            if suspended { missedRedraw = true } else { view.setNeedsDisplay(view.bounds) }
        }
        if !self.edgesOnly { renderer.stopEdgeClock() }
        mouseTimer?.invalidate()
        mouseTimer = nil
        updateMouseTimer()
        layoutStrips()
    }

    /// Places the strips over the rows the bands can reach; hides them outside edges-only mode.
    private func layoutStrips() {
        let W = Int(view.drawableSize.width), H = Int(view.drawableSize.height)
        let rows = renderer.stripRows(height: H)
        let s = CGFloat(renderer.pixelScale)
        for (strip, r) in zip(strips, [rows.top, rows.bottom]) {
            guard edgesOnly, let r else {
                strip.view.isPaused = true
                strip.view.isHidden = true
                continue
            }
            strip.screenSize = (W, H)
            strip.rows = r
            let frame = NSRect(x: 0, y: CGFloat(H - r.1) / s, width: CGFloat(W) / s, height: CGFloat(r.1 - r.0) / s)
            if strip.view.frame != frame { strip.view.frame = frame }
            let size = CGSize(width: W, height: r.1 - r.0)
            if strip.view.drawableSize != size { strip.view.drawableSize = size }
            strip.view.preferredFramesPerSecond = fps
            strip.view.isHidden = false
            strip.view.isPaused = suspended
        }
    }

    static func layout(for screen: NSScreen, config: ScreenConfig) -> ScreenLayout {
        let f = screen.frame, v = screen.visibleFrame
        let top = Float(f.maxY - v.maxY)
        let bottom = Float(v.minY - f.minY)
        return ScreenLayout(holeX: config.holeX, holeY: config.holeY,
                            topBar: top > 1 ? top : 2,
                            bottomBar: bottom > 1 ? bottom : 2)
    }
}

/// A small Metal view over one bar in edges-only mode. It draws only its strip of rows;
/// the still picture around it stays in the main view untouched.
final class BandStrip: NSObject, MTKViewDelegate {
    let view: MTKView
    private let cache = EdgeStrip()
    private weak var renderer: Renderer?
    var rows = (0, 0)
    var screenSize = (0, 0)
    private var statFrames = 0
    private var statGPU = 0.0
    private var statStart = CACurrentMediaTime()

    init(renderer: Renderer) {
        self.renderer = renderer
        view = MTKView(frame: .zero, device: GPU.shared.device)
        super.init()
        view.colorPixelFormat = GPU.outFormat
        view.framebufferOnly = true
        view.autoResizeDrawable = false
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        (view.layer as? CAMetalLayer)?.maximumDrawableCount = 2
        view.layer?.isOpaque = true
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.isHidden = true
        view.delegate = self
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        Renderer.framesDrawn += 1
        guard let r = renderer, rows.1 > rows.0, let drawable = view.currentDrawable,
              let cmd = GPU.shared.queue.makeCommandBuffer() else { return }
        r.tickEdges(CACurrentMediaTime())
        // Without a picture to build on, present nothing: the main view shows through.
        guard r.encodeStrip(cmd, strip: cache, target: drawable.texture,
                            screenW: screenSize.0, screenH: screenSize.1, rows: rows) else { return }
        if Renderer.debugLog {
            cmd.addCompletedHandler { [weak self] c in
                DispatchQueue.main.async { self?.log(c.gpuEndTime - c.gpuStartTime) }
            }
        }
        cmd.present(drawable)
        cmd.commit()
    }

    private func log(_ gpu: Double) {
        statFrames += 1
        statGPU += gpu
        let now = CACurrentMediaTime()
        if now - statStart >= 5 {
            NSLog("Band strip %dx%d: %.1f fps, %.3f ms GPU/frame", screenSize.0, rows.1 - rows.0,
                  Double(statFrames) / (now - statStart), statGPU / Double(max(statFrames, 1)) * 1000)
            statFrames = 0; statGPU = 0; statStart = now
        }
    }
}
