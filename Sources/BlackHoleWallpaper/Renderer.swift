import Metal
import MetalKit
import QuartzCore
import simd

/// Shared Metal objects. The shader source is compiled once per process.
final class GPU {
    static let shared = GPU()
    let device: MTLDevice
    let queue: MTLCommandQueue
    /// The fast-math library, for pipelines made elsewhere (BodyGPU).
    let fastLib: MTLLibrary
    let geoPipeline: MTLRenderPipelineState
    /// geoFrag plus a fourth target with the jet emission collected along each ray.
    let geoJetPipeline: MTLRenderPipelineState
    let bakeGalaxyPipeline: MTLRenderPipelineState
    /// Which sky objects can show in each 8 x 8 cell, one bit per object.
    let skyMaskPipeline: MTLRenderPipelineState
    static let maskCell = 8
    /// 1 x 1 zero texture for slots nothing is bound to (no jet, no galaxies).
    let blank: MTLTexture
    let blankUint: MTLTexture
    let dispPipeline: MTLRenderPipelineState
    /// dispFrag also writing linear colour into a memoryless second attachment, for path F in the same pass.
    let dispLinearPipeline: MTLRenderPipelineState
    let edgeLinearPipeline: MTLRenderPipelineState
    /// dispFrag writing linear colour, the still base under the edge strips.
    let basePipeline: MTLRenderPipelineState
    let edgePipeline: MTLRenderPipelineState
    let bakeDiskPipeline: MTLRenderPipelineState
    let bakeNebulaPipeline: MTLRenderPipelineState
    let nebFramePipeline: MTLRenderPipelineState
    /// Periodic noise for the bar edges; the same for every screen.
    let edgeNoise: MTLTexture
    /// Map 0 holds direction, winding and the capture metric in 16-bit fixed point;
    /// maps 1 and 2 hold the disk crossings in half floats. 24 bytes per texel in total.
    /// Maps 3 and 4 (only with a jet): jet emission in front of and behind the disk in half floats,
    /// and where along the jet it comes from in 16 bit (8 bit made the knots step). 8 bytes per texel more.
    static func mapFormat(_ i: Int) -> MTLPixelFormat {
        switch i {
        case 0: .rgba16Unorm
        case 3: .rg16Float
        case 4: .rg16Unorm
        default: .rgba16Float
        }
    }
    static let mapCount = 3
    static let outFormat: MTLPixelFormat = .bgra8Unorm

    /// The same passes with object lenses (stage 4), made when first needed.
    /// The per-frame passes draw these as quads over rectangles (vRects): the lens variant where a lens can bend,
    /// the plain one (rects: true, lenses: false) around it.
    lazy var dispLens = lensPipeline("dispFrag", [GPU.outFormat], linear: false, rects: true)
    lazy var dispLinearLens = lensPipeline("dispFrag", [GPU.outFormat, .rgba16Float], linear: true, rects: true)
    lazy var baseLens = lensPipeline("dispFrag", [.rgba16Float], linear: false)
    lazy var dispBehind = lensPipeline("dispFrag", [GPU.outFormat], linear: false, behind: true, rects: true)
    lazy var dispLinearBehind = lensPipeline("dispFrag", [GPU.outFormat, .rgba16Float], linear: true, behind: true, rects: true)
    lazy var baseBehind = lensPipeline("dispFrag", [.rgba16Float], linear: false, behind: true)
    lazy var nebFrameLens = lensPipeline("nebFrag", [.rgba16Float], linear: nil, rects: true)
    lazy var dispFar = lensPipeline("dispFrag", [GPU.outFormat], linear: false, far: true, rects: true)
    lazy var dispLinearFar = lensPipeline("dispFrag", [GPU.outFormat, .rgba16Float], linear: true, far: true, rects: true)
    lazy var nebFrameFar = lensPipeline("nebFrag", [.rgba16Float], linear: nil, far: true, rects: true)
    lazy var dispRects = lensPipeline("dispFrag", [GPU.outFormat], linear: false, lenses: false, rects: true)
    lazy var dispLinearRects = lensPipeline("dispFrag", [GPU.outFormat, .rgba16Float], linear: true, lenses: false, rects: true)
    lazy var nebFrameRects = lensPipeline("nebFrag", [.rgba16Float], linear: nil, lenses: false, rects: true)
    lazy var skyMaskLens = lensPipeline("skyMaskFrag", [.r32Uint], linear: nil)
    /// Light of the lenses in front of the hole plane, over the picture (with its linear copy) or a linear still.
    lazy var lensFront = overlayPipeline("lensFrontFrag", [GPU.outFormat, .rgba16Float])
    lazy var lensLin = overlayPipeline("lensLinFrag", [.rgba16Float])

    private func overlayPipeline(_ frag: String, _ formats: [MTLPixelFormat]) -> MTLRenderPipelineState {
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = fastLib.makeFunction(name: "lensVert")
        d.fragmentFunction = fastLib.makeFunction(name: frag)
        for (i, f) in formats.enumerated() { d.colorAttachments[i].pixelFormat = f }
        do { return try device.makeRenderPipelineState(descriptor: d) } catch {
            fatalError("Pipeline \(frag) failed: \(error)")
        }
    }

    private func lensPipeline(_ frag: String, _ formats: [MTLPixelFormat], linear: Bool?, behind: Bool = false,
                              lenses: Bool = true, far: Bool = false, rects: Bool = false) -> MTLRenderPipelineState {
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = fastLib.makeFunction(name: rects ? "vRects" : "vFull")
        let cv = MTLFunctionConstantValues()
        var lin = linear ?? false, on = lenses
        if linear != nil { cv.setConstantValue(&lin, type: .bool, index: 0) }
        cv.setConstantValue(&on, type: .bool, index: 1)
        var bh = behind
        cv.setConstantValue(&bh, type: .bool, index: 2)
        var fr = far
        cv.setConstantValue(&fr, type: .bool, index: 3)
        d.fragmentFunction = try? fastLib.makeFunction(name: frag, constantValues: cv)
        d.label = frag + (!lenses ? "" : far ? " far" : behind ? " behind" : " lens")
        for (i, f) in formats.enumerated() { d.colorAttachments[i].pixelFormat = f }
        do { return try device.makeRenderPipelineState(descriptor: d) } catch {
            fatalError("Pipeline \(frag) with lenses failed: \(error)")
        }
    }

    /// Ray maps of second holes (Lenses.swift), by spec.
    var holeMapCache: [String: [MTLTexture]] = [:]
    var holeMapOrder: [String] = []

    /// A memoryless render target: lives in tile memory during one pass only, costs no memory.
    private var memoryless: [String: MTLTexture] = [:]
    func linearScratch(_ w: Int, _ h: Int) -> MTLTexture {
        let key = "\(w)x\(h)"
        if let t = memoryless[key] { return t }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget]
        d.storageMode = .memoryless
        let t = device.makeTexture(descriptor: d)!
        if memoryless.count > 8 { memoryless = [:] }
        memoryless[key] = t
        return t
    }

    private init() {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("No Metal device") }
        self.device = device
        queue = device.makeCommandQueue()!
        // The geodesic pass needs IEEE semantics (NaN checks near the horizon); the
        // per-frame pass runs every frame and gets fast math.
        func compile(_ mode: MTLMathMode) -> MTLLibrary {
            let opts = MTLCompileOptions()
            opts.mathMode = mode
            do { return try device.makeLibrary(source: shaderSource, options: opts) } catch {
                fatalError("Shader compile failed: \(error)")
            }
        }
        let safeLib = compile(.safe)
        let lib = compile(.fast)
        fastLib = lib
        func pipeline(_ l: MTLLibrary, _ frag: String, _ formats: [MTLPixelFormat], linear: Bool? = nil) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = l.makeFunction(name: "vFull")
            if let linear {
                // dispFrag and edgeFrag: with or without the second, linear output.
                let cv = MTLFunctionConstantValues()
                var on = linear
                cv.setConstantValue(&on, type: .bool, index: 0)
                d.fragmentFunction = try? l.makeFunction(name: frag, constantValues: cv)
            } else {
                // Specialised with no constants set: passes that can have lenses get the plain variant.
                d.fragmentFunction = (try? l.makeFunction(name: frag, constantValues: MTLFunctionConstantValues())) ?? l.makeFunction(name: frag)
            }
            d.label = frag
            for (i, f) in formats.enumerated() { d.colorAttachments[i].pixelFormat = f }
            do { return try device.makeRenderPipelineState(descriptor: d) } catch {
                fatalError("Pipeline \(frag) failed: \(error)")
            }
        }
        geoPipeline = pipeline(safeLib, "geoFrag", (0..<GPU.mapCount).map(GPU.mapFormat))
        geoJetPipeline = pipeline(safeLib, "geoFragJet", (0..<GPU.mapCount + 2).map(GPU.mapFormat))
        bakeGalaxyPipeline = pipeline(lib, "bakeGalaxy", [.rgba8Unorm])
        skyMaskPipeline = pipeline(lib, "skyMaskFrag", [.r32Uint])
        let bd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false)
        bd.usage = [.shaderRead]
        bd.storageMode = .shared
        blank = device.makeTexture(descriptor: bd)!
        var zero = [UInt16](repeating: 0, count: 4)
        blank.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &zero, bytesPerRow: 8)
        let ud = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Uint, width: 1, height: 1, mipmapped: false)
        ud.usage = [.shaderRead]
        ud.storageMode = .shared
        blankUint = device.makeTexture(descriptor: ud)!
        var zu: UInt32 = 0
        blankUint.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &zu, bytesPerRow: 4)
        dispPipeline = pipeline(lib, "dispFrag", [GPU.outFormat], linear: false)
        dispLinearPipeline = pipeline(lib, "dispFrag", [GPU.outFormat, .rgba16Float], linear: true)
        basePipeline = pipeline(lib, "dispFrag", [.rgba16Float], linear: false)
        edgePipeline = pipeline(lib, "edgeFrag", [GPU.outFormat], linear: false)
        edgeLinearPipeline = pipeline(lib, "edgeFrag", [GPU.outFormat, .rgba16Float], linear: true)
        bakeDiskPipeline = pipeline(lib, "bakeDisk", [.rgba8Unorm])
        bakeNebulaPipeline = pipeline(lib, "bakeNebula", [.rgba8Unorm])
        nebFramePipeline = pipeline(lib, "nebFrag", [.rgba16Float])
        let edgePipe = pipeline(lib, "bakeEdgeNoise", [.rgba8Unorm])
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 4096, height: 2, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        edgeNoise = device.makeTexture(descriptor: d)!
        let cmd = queue.makeCommandBuffer()!
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = edgeNoise
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        let enc = cmd.makeRenderCommandEncoder(descriptor: rp)!
        enc.setRenderPipelineState(edgePipe)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.commit()
    }

    static func makeMaps(_ w: Int, _ h: Int, jet: Bool = false) -> [MTLTexture] {
        (0..<(jet ? mapCount + 2 : mapCount)).map { i in
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: mapFormat(i), width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            return shared.device.makeTexture(descriptor: d)!
        }
    }

    /// Baked textures depend on two or three numbers only; screens with the same look share them.
    private var baked: [String: MTLTexture] = [:]
    private var bakedOrder: [String] = []

    func bakedTexture(_ key: String, _ w: Int, _ h: Int, make: (MTLTexture) -> Void) -> MTLTexture {
        if let t = baked[key] {
            bakedOrder.removeAll { $0 == key }
            bakedOrder.append(key)
            return t
        }
        let t = GPU.makeTarget(w, h)
        make(t)
        baked[key] = t
        bakedOrder.append(key)
        // Keep a few: one per screen plus the one a slider just left behind.
        while bakedOrder.count > 6 { baked[bakedOrder.removeFirst()] = nil }
        return t
    }

    /// Galaxy atlases, keyed by everything that shapes them; screens with the same galaxies share one.
    private var atlases: [String: MTLTexture] = [:]
    private var atlasOrder: [String] = []

    func galaxyAtlas(_ key: String, _ w: Int, _ h: Int, make: (MTLTexture) -> Void) -> MTLTexture {
        if let t = atlases[key] {
            atlasOrder.removeAll { $0 == key }
            atlasOrder.append(key)
            return t
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: true)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let t = device.makeTexture(descriptor: d)!
        make(t)
        atlases[key] = t
        atlasOrder.append(key)
        while atlasOrder.count > 3 { atlases[atlasOrder.removeFirst()] = nil }
        return t
    }

    static func makeTarget(_ w: Int, _ h: Int) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        return shared.device.makeTexture(descriptor: d)!
    }
}

/// Renders one screen. Keeps the geodesic maps and rebuilds them only when the view changes.
final class Renderer: NSObject, MTKViewDelegate {
    var look: Look {
        didSet {
            if look != oldValue { lastNebFrame = -1; lastLight = -1 }
            if look.geometryKey != oldValue.geometryKey { mapDirty = true }
            if look.diskOuter != oldValue.diskOuter { diskDirty = true }
            if look.nebulaScale != oldValue.nebulaScale || look.nebulaSeed != oldValue.nebulaSeed { nebulaDirty = true }
        }
    }
    var layout: ScreenLayout {
        didSet {
            if layout.holeX != oldValue.holeX || layout.holeY != oldValue.holeY { mapDirty = true; lastNebFrame = -1 }
            if layout != oldValue { lastLight = -1 }
        }
    }
    /// Fixed ray map scale (--map); nil: from the quality levels.
    var mapScale: Float? { didSet { if mapScale != oldValue { mapDirty = true } } }
    var detailBox = true { didSet { if detailBox != oldValue { mapDirty = true } } }
    /// Quality levels per area. Only what a change needs is redone: the ray maps when their scale or the
    /// box changes, the light buffer and nebula on their next refresh, atlases when their tiles change.
    var quality = RenderQuality() {
        didSet {
            guard quality != oldValue else { return }
            objects.quality = quality
            if quality.boxRadius != oldValue.boxRadius { mapDirty = true }
            lastNebFrame = -1; lastLight = -1; maskDirty = true
            atlasCache.drawn = [:]; edgeCache.drawn = [:]
        }
    }

    private func effectiveMapScale(_ width: Int, _ height: Int) -> Float {
        mapScale ?? quality.mapScale(width: width, height: height, jet: look.objects.mainJet != nil)
    }
    /// Drawable pixels per point.
    var pixelScale: Float = 1
    var debug: Float = 0
    /// Mouse lens: x, y in drawable pixels, Einstein radius in pixels (0 = off), shadow 0/1.
    var mouse = SIMD4<Float>(0, 0, 0, 0)
    /// Called right before each live frame, e.g. to read the pointer position.
    var beforeDraw: (() -> Void)?

    private(set) var time: Float = 20
    /// The edge bands run ahead of `time` by this much, so they can move while the rest stands still.
    private var edgeLead: Float = 0
    private var lastEdgeTick: CFTimeInterval = 0
    /// Bumped on every full picture; edge strips rebuild their base when it changes.
    private(set) var pictureVersion = 0
    /// Separate clocks, so changing a speed never makes the pattern jump.
    private var diskClock: Float = 0
    private var nebulaClock: Float = 0
    /// Clocks and packing for the objects; objFrame is what the last picture used.
    private let objects = ObjectSystem()
    private var objFrame = ObjectFrame()
    /// Bodies, particles and front instances of the last full picture.
    private var bodyFrame = BodyFrame()
    /// Second holes, wormholes and gates of the last full picture, their ray maps, and where the sky mask saw them.
    private var lensFrame = LensFrame()
    private var lensMaps: [[MTLTexture]] = [[], []]
    private var lensMaskKey: [SIMD4<Float>] = []
    /// Indices in FrameParams: region and the light buffer's rectangle.
    static let regionIndex = 25, lightUIndex = 36
    /// Body sprites of this screen, and of the band objects in the strips; tiles are kept between frames.
    private var atlas: MTLTexture?
    private let atlasCache = TileCache()
    private var edgeAtlas: MTLTexture?
    private let edgeCache = TileCache()

    private func atlasFor(_ f: BodyFrame, edge: Bool) -> MTLTexture {
        if edge {
            if edgeAtlas?.width != f.atlasSize { edgeAtlas = BodyGPU.makeAtlas(f.atlasSize); edgeCache.drawn = [:] }
            return edgeAtlas!
        }
        if atlas?.width != f.atlasSize { atlas = BodyGPU.makeAtlas(f.atlasSize); atlasCache.drawn = [:] }
        return atlas!
    }
    /// Edges-only mode: objects on a band are drawn by the strips, not the still picture.
    var edgeObjectsInStrips = false
    /// Desktop still: nothing fleeting (meteors).
    var stillMode = false
    private(set) var galaxyTex: MTLTexture?
    private var skyMask: MTLTexture?
    /// Sky positions and reaches the mask was made for; it is redone only when one moved
    /// by more than half its margin, or the rays changed.
    private var maskFor: [SIMD4<Float>] = []
    private var maskDirty = true
    static let maskMargin: Float = 0.006   // rad, about 0.35 degrees
    var animating = true
    private var lastTick: CFTimeInterval = 0
    private var maps: [MTLTexture] = []
    private var mapSize = (0, 0)
    private var box: [MTLTexture] = []
    private var boxRect = SIMD4<Float>(-1, -1, -1, -1)   // screen uv, x0 < 0 = none
    private var mapDirty = true
    private var diskDirty = true
    private var nebulaDirty = true
    private var diskTex: MTLTexture?
    private var nebulaTex: MTLTexture?
    /// The lensed, coloured nebula at the sky quality's scale (half by default); refreshed about 20 times a second.
    private var nebFrame: MTLTexture?
    private var lastNebFrame: Float = -1
    /// Rebuilding the rays is expensive; while sliders move, do it at most this often.
    private var lastGeo: CFTimeInterval = 0
    var geoInterval: CFTimeInterval = 0

    static var liveCount = 0
    static let debugLog = ProcessInfo.processInfo.environment["BH_DEBUG"] != nil
    private var statFrames = 0, statGeo = 0
    private var statGPU = 0.0
    private var statStart = CACurrentMediaTime()

    static let profiles: [PassProfiler] = ProcessInfo.processInfo.environment["BH_PROFILE"] == nil ? []
        : (0..<4).compactMap { _ in PassProfiler(device: GPU.shared.device) }
    private var statPasses: [String: Double] = [:]

    private func logFrame(_ gpu: Double, passes: [String: Double] = [:]) {
        statFrames += 1
        statGPU += gpu
        for (k, v) in passes { statPasses[k, default: 0] += v }
        let now = CACurrentMediaTime()
        if now - statStart >= 5 {
            NSLog("Renderer map %dx%d: %.1f fps, %.2f ms GPU/frame, %d ray passes",
                  mapSize.0, mapSize.1, Double(statFrames) / (now - statStart),
                  statGPU / Double(max(statFrames, 1)) * 1000, statGeo)
            if !statPasses.isEmpty {
                NSLog("Passes (ms per frame): %@", statPasses.sorted { $0.key < $1.key }
                    .map { String(format: "%@ %.3f", $0.key, $0.value / Double(max(statFrames, 1))) }.joined(separator: ", "))
            }
            statFrames = 0; statGPU = 0; statGeo = 0; statStart = now; statPasses = [:]
        }
    }

    init(look: Look, layout: ScreenLayout) {
        self.look = look
        self.layout = layout
        super.init()
        setTime(20)
        Renderer.liveCount += 1
        if ProcessInfo.processInfo.environment["BH_DEBUG"] != nil { NSLog("Renderer init, live: %d", Renderer.liveCount) }
    }

    deinit {
        Renderer.liveCount -= 1
        if ProcessInfo.processInfo.environment["BH_DEBUG"] != nil { NSLog("Renderer deinit, live: %d", Renderer.liveCount) }
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { mapDirty = true }

    /// After a stop: the next frame does not count the stretch in between as elapsed time.
    func resumeClock() { lastTick = 0; lastEdgeTick = 0 }

    /// Frames the main views started, for the BH_DEBUG log: zero while paused.
    static var framesDrawn = 0

    func draw(in view: MTKView) {
        Renderer.framesDrawn += 1
        let now = CACurrentMediaTime()
        if animating && lastTick > 0 { advance(Float(min(now - lastTick, 0.1))) }
        lastTick = animating ? now : 0
        beforeDraw?()
        guard let drawable = view.currentDrawable else { return }
        let w = Int(view.drawableSize.width), h = Int(view.drawableSize.height)
        guard let cmd = GPU.shared.queue.makeCommandBuffer() else { return }
        // BH_PROFILE=1 with BH_DEBUG=1: GPU time per pass in the log too, from a ring of profilers (frames overlap).
        let prof = Renderer.profiles.isEmpty ? nil : Renderer.profiles[statFrames % Renderer.profiles.count]
        prof?.begin()
        PassProfiler.shared = prof
        encode(cmd, target: drawable.texture, width: w, height: h)
        PassProfiler.shared = nil
        if Renderer.debugLog {
            cmd.addCompletedHandler { [weak self] c in
                let passes = prof?.collect() ?? [:]
                DispatchQueue.main.async { self?.logFrame(c.gpuEndTime - c.gpuStartTime, passes: passes) }
            }
        }
        cmd.present(drawable)
        cmd.commit()
    }

    /// True while a throttled geometry update is still waiting.
    var needsRedraw: Bool { mapDirty || diskDirty || nebulaDirty }

    private func advance(_ dt: Float) {
        time += dt
        diskClock += dt * 2 * .pi / max(look.diskPeriod, 0.5) / look.iscoOmega
        nebulaClock += dt * 2 * .pi / max(look.nebulaPeriod, 1)
        objects.advance(dt, look: look)
    }

    func setTime(_ t: Float) {
        time = 0; diskClock = 0; nebulaClock = 0
        advance(t)
        objects.reset(t, look: look)
    }

    // MARK: Encoding (shared by the live view, snapshots and stills)

    func encode(_ cmd: MTLCommandBuffer, target: MTLTexture, width: Int, height: Int) {
        let ms = effectiveMapScale(width, height)
        let want = (max(Int(Float(width) * ms), 16), max(Int(Float(height) * ms), 16))
        if mapSize != want { mapDirty = true }
        let now = CACurrentMediaTime()
        if mapDirty && now - lastGeo >= geoInterval {
            encodeRays(cmd, width: width, height: height)
            lastNebFrame = -1
            statGeo += 1
            lastGeo = now
        } else if maps.isEmpty {
            encodeRays(cmd, width: width, height: height)
        }
        if diskDirty || diskTex == nil {
            let b = SIMD4<Float>(look.diskOuter, 0, 0, 0)
            diskTex = GPU.shared.bakedTexture("disk \(b.x)", 2048, 512) { encodeBake(cmd, GPU.shared.bakeDiskPipeline, $0, b) }
            diskDirty = false
        }
        if nebulaDirty || nebulaTex == nil {
            let b = SIMD4<Float>(look.nebulaScale, look.nebulaSeed, 0, 0)
            nebulaTex = GPU.shared.bakedTexture("nebula \(b.x) \(b.y)", 2048, 1024) { encodeBake(cmd, GPU.shared.bakeNebulaPipeline, $0, b) }
            nebulaDirty = false
        }
        objFrame = objects.frame(look: look, width: width, height: height)
        lensFrame = objects.lenses(look: look, layout: layout, width: width, height: height, pxScale: pixelScale)
        bodyFrame = objects.bodies(look: look, layout: layout, width: width, height: height, pxScale: pixelScale,
                                   edgeTime: time + edgeLead, sky: objFrame, filter: edgeObjectsInStrips ? .without : .all,
                                   transient: animating && !stillMode)
        ObjectSystem.addGates(&lensFrame, gates: bodyFrame.gates, time: time)
        for i in 0..<ObjectSystem.maxHoles {
            lensMaps[i] = lensFrame.maps[i].map { GPU.shared.holeMaps($0, cmd) } ?? []
        }
        updateGalaxies(cmd)
        if !bodyFrame.tiles.isEmpty { BodyGPU.shared.renderTiles(bodyFrame, cmd, atlas: atlasFor(bodyFrame, edge: false), cache: atlasCache) }
        var params = frameParams(width: width, height: height)
        if objFrame.skyCount > 0 {
            let mw = (width + GPU.maskCell - 1) / GPU.maskCell, mh = (height + GPU.maskCell - 1) / GPU.maskCell
            if skyMask?.width != mw || skyMask?.height != mh {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Uint, width: mw, height: mh, mipmapped: false)
                d.usage = [.renderTarget, .shaderRead]
                d.storageMode = .private
                skyMask = GPU.shared.device.makeTexture(descriptor: d)
                maskDirty = true
            }
            let pos = (0..<objFrame.skyCount).map { objFrame.sky[$0 * 5] }
            let moved = pos.count != maskFor.count || zip(pos, maskFor).contains { a, b in
                a.w != b.w || simd_dot(SIMD3(a.x, a.y, a.z), SIMD3(b.x, b.y, b.z)) < cosf(Renderer.maskMargin * 0.5)
            }
            // Lenses move what is seen where: redo the mask when one moved.
            var lk: [SIMD4<Float>] = []
            for i in 0..<lensFrame.count { lk += lensFrame.data[(i * LensFrame.stride)..<(i * LensFrame.stride + 3)] }
            if maskDirty || moved || lk != lensMaskKey {
                encodePass(cmd, lensFrame.bendCount > 0 ? GPU.shared.skyMaskLens : GPU.shared.skyMaskPipeline, target: skyMask!, params: params, inputs: .masks)
                maskFor = pos
                lensMaskKey = lk
                maskDirty = false
                lastNebFrame = -1   // its alpha carries the mask
            }
        }
        frameInstances = prepareInstances(cmd, bodyFrame, params: params)
        // Soft light (belt haze, tails, smoke, shells) moves slowly: refreshed like the nebula, about 20 times a second.
        if bodyFrame.hasLight && (lastLight < 0 || abs(time - lastLight) >= quality.lightInterval || !animating || lightSize != (width, height)) {
            encodeLight(cmd, frame: bodyFrame, params: params, inst: frameInstances!, width: width, height: height)
            lastLight = time
            lightSize = (width, height)
        }
        if !bodyFrame.hasLight { lastLight = -1 }
        if bodyFrame.hasLight {
            bodyFrame.params[6] = lightUsed
            params[Renderer.lightUIndex] = lightUsed
        }
        let zones = lensFrame.bendCount > 0 ? lensZones(width: width, height: height) : nil
        let ns = quality.nebulaScale
        let nw = max(Int(Float(width) * ns), 1), nh = max(Int(Float(height) * ns), 1)
        if nebFrame?.width != nw || nebFrame?.height != nh {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: nw, height: nh, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            nebFrame = GPU.shared.device.makeTexture(descriptor: d)
            lastNebFrame = -1
        }
        if lastNebFrame < 0 || abs(time - lastNebFrame) >= quality.nebulaInterval || mouse.z > 0 || !animating {
            encodePass(cmd, GPU.shared.nebFramePipeline, target: nebFrame!, params: params, inputs: .nebula,
                       lens: lensFrame.bendCount > 0 ? LensSplit(lens: GPU.shared.nebFrameLens, far: GPU.shared.nebFrameFar,
                                                                 plain: GPU.shared.nebFrameRects, zones: zones,
                                                                 scale: Float(nebFrame!.width) / Float(width)) : nil)
            lastNebFrame = time
        }
        if bodyFrame.hasFront || lensFrame.frontCount > 0, let inst = frameInstances {
            // Path F inside the same pass: no load and store of the whole picture.
            let rp = MTLRenderPassDescriptor()
            rp.colorAttachments[0].texture = target
            rp.colorAttachments[0].loadAction = .dontCare
            rp.colorAttachments[0].storeAction = .store
            rp.colorAttachments[1].texture = GPU.shared.linearScratch(target.width, target.height)
            rp.colorAttachments[1].loadAction = .dontCare
            rp.colorAttachments[1].storeAction = .dontCare
            if let enc = cmd.renderEncoder(rp, "disp+front") {
                bindPassInputs(enc, params: params, inputs: .full)
                drawSplit(enc, GPU.shared.dispLinearPipeline,
                          lens: lensFrame.bendCount > 0 ? LensSplit(lens: lensFrame.behindCount > 0 ? GPU.shared.dispLinearBehind : GPU.shared.dispLinearLens,
                                                                    far: GPU.shared.dispLinearFar, plain: GPU.shared.dispLinearRects,
                                                                    zones: zones, scale: 1) : nil,
                          width: target.width, height: target.height)
                drawLenses(enc, params: params, linear: false)
                if bodyFrame.hasFront { drawFront(enc, frame: bodyFrame, params: params, inst: inst, linear: false, edge: false) }
                enc.endEncoding()
            }
        } else {
            encodePass(cmd, GPU.shared.dispPipeline, target: target, params: params,
                       lens: lensFrame.bendCount > 0 ? LensSplit(lens: lensFrame.behindCount > 0 ? GPU.shared.dispBehind : GPU.shared.dispLens,
                                                                 far: GPU.shared.dispFar, plain: GPU.shared.dispRects, zones: zones, scale: 1) : nil)
        }
        pictureVersion += 1
    }

    /// Front instances of the frame being drawn, and where the glows of far stars found their images.
    private var frameInstances: Instances?
    /// Screen rectangle the light buffer covers this frame (px).
    private var lightUsed = SIMD4<Float>(0, 0, 2, 2)
    /// Light instances first, then the front ones; one refined texel per instance.
    private struct Instances { var buffer: MTLBuffer?; var refined: MTLTexture?; var light: Int; var count: Int }
    private var lightTex: MTLTexture?
    private var lastLight: Float = -1
    private var lightSize = (0, 0)
    private var refineTex: MTLTexture?
    private var refineKey: [Float] = []
    private var rayVersion = 0
    /// True while encoding a strip: its instances are not the picture's, do not touch the cache.
    private var isStrip = false

    private func prepareInstances(_ cmd: MTLCommandBuffer, _ f: BodyFrame, params p: [SIMD4<Float>]) -> Instances {
        var out = Instances(buffer: nil, refined: nil, light: f.lightCount, count: f.frontCount)
        let all = f.light + f.front
        guard !all.isEmpty else { return out }
        out.buffer = all.withUnsafeBytes { GPU.shared.device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        guard f.needsRefine else { return out }
        let g = BodyGPU.shared
        let n = f.lightCount + f.frontCount
        if (refineTex?.width ?? 0) < n { refineTex = BodyGPU.makeRefineTarget(n); refineKey = [] }
        let rt = refineTex!
        out.refined = rt
        // The images only move when the rays or the stars do: reuse the last search otherwise.
        var key: [Float] = [Float(rayVersion), Float(n)]
        // What glowRefine reads: the start estimate, the direction and the fallback magnification (not the quad).
        for i in 0..<n where all[i * 6 + 1].x.rounded() <= 2 {
            let b = all[i * 6 + 2], d = all[i * 6 + (all[i * 6 + 1].x.rounded() == 1 ? 4 : 5)], e = all[i * 6 + 5]
            key += [Float(i), b.x, b.y, d.x, d.y, d.z, d.w, e.y]
        }
        if key == refineKey && !isStrip { return out }
        if !isStrip { refineKey = key }
        let detail = boxRect.x >= 0 && box.count == maps.count ? box : maps
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = rt
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        if let enc = cmd.renderEncoder(rp, "refine") {
            enc.setRenderPipelineState(g.refine)
            enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(n), height: 1, znear: 0, zfar: 1))
            enc.setFragmentBytes(p, length: p.count * 16, index: 0)
            enc.setFragmentBuffer(out.buffer, offset: 0, index: 4)
            enc.setFragmentTexture(maps[0], index: 0)
            enc.setFragmentTexture(detail[0], index: 5)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }
        return out
    }

    /// Particles and front instances into an open pass: with the linear attachment (display) or over a linear target.
    private func drawFront(_ enc: MTLRenderCommandEncoder, frame f: BodyFrame, params p: [SIMD4<Float>], inst: Instances, linear: Bool, edge: Bool) {
        let g = BodyGPU.shared
        let detail = boxRect.x >= 0 && box.count == maps.count ? box : maps
        enc.setFragmentTexture(maps[0], index: 0)
        enc.setFragmentTexture(maps[1], index: 1)
        enc.setFragmentTexture(detail[0], index: 5)
        enc.setFragmentTexture(detail[1], index: 6)
        enc.setFragmentTexture(GPU.shared.edgeNoise, index: 9)
        enc.setFragmentTexture(f.tiles.isEmpty ? GPU.shared.blank : atlasFor(f, edge: edge), index: 18)
        enc.setVertexBytes(p, length: p.count * 16, index: 0)
        enc.setFragmentBytes(p, length: p.count * 16, index: 0)
        let refs = f.refs.isEmpty ? [SIMD4<Float>](repeating: .zero, count: 5) : f.refs
        enc.setVertexBytes(refs, length: refs.count * 16, index: 2)
        enc.setVertexTexture(inst.refined ?? GPU.shared.blank, index: 0)
        for job in f.parts where job.count > 0 {
            var prm = job.params
            // With a light buffer the dust went there; rocks only here.
            prm[9].w = f.allFront || job.edge ? 0 : 1
            enc.setRenderPipelineState(linear ? g.partLinear : g.part)
            enc.setVertexBytes(prm, length: prm.count * 16, index: 3)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: job.count * 2)
        }
        if inst.count > 0, let b = inst.buffer {
            var base = SIMD2<UInt32>(UInt32(inst.light), inst.refined != nil ? 1 : 0)
            let off = inst.light * 6 * 16
            enc.setRenderPipelineState(linear ? g.frontLinear : g.front)
            enc.setVertexBuffer(b, offset: off, index: 4)
            enc.setFragmentBuffer(b, offset: off, index: 4)
            enc.setVertexBytes(&base, length: 8, index: 5)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: inst.count)
        }
    }

    /// Soft light into the light buffer (half resolution), before dispFrag reads it.
    private func encodeLight(_ cmd: MTLCommandBuffer, frame f: BodyFrame, params p: [SIMD4<Float>], inst: Instances, width: Int, height: Int) {
        guard f.hasLight else { return }
        // Only the rectangle that has light, at half resolution; the pass draws with it as its region.
        let r = f.params[6], k = f.lightScale
        let w = max(Int(((r.z - r.x) / k).rounded(.up)), 1), h = max(Int(((r.w - r.y) / k).rounded(.up)), 1)
        let rw = (w + 63) / 64 * 64, rh = (h + 63) / 64 * 64
        if (lightTex?.width ?? 0) < w || (lightTex?.height ?? 0) < h || (lightTex?.width ?? 0) > rw * 2 || (lightTex?.height ?? 0) > rh * 2 {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: BodyGPU.lightFormat, width: rw, height: rh, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            lightTex = GPU.shared.device.makeTexture(descriptor: d)
        }
        // The buffer may be larger than needed: draw into its corner and tell dispFrag the matching rectangle.
        var p = p
        let tw = Float(lightTex!.width), th = Float(lightTex!.height)
        let used = SIMD4(r.x, r.y, r.x + tw * k, r.y + th * k)
        p[Renderer.lightUIndex] = used
        p[Renderer.regionIndex] = SIMD4(used.x / Float(width), used.y / Float(height), used.z / Float(width), used.w / Float(height))
        lightUsed = used
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = lightTex
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cmd.renderEncoder(rp, "light") else { return }
        let g = BodyGPU.shared
        let detail = boxRect.x >= 0 && box.count == maps.count ? box : maps
        enc.setFragmentTexture(maps[0], index: 0)
        enc.setFragmentTexture(maps[1], index: 1)
        enc.setFragmentTexture(detail[0], index: 5)
        enc.setFragmentTexture(detail[1], index: 6)
        enc.setVertexBytes(p, length: p.count * 16, index: 0)
        enc.setFragmentBytes(p, length: p.count * 16, index: 0)
        let refs = f.refs.isEmpty ? [SIMD4<Float>](repeating: .zero, count: 5) : f.refs
        enc.setVertexBytes(refs, length: refs.count * 16, index: 2)
        enc.setVertexTexture(inst.refined ?? GPU.shared.blank, index: 0)
        for job in f.parts where job.count > 0 && !job.edge {
            var prm = job.params
            prm[9].w = 2   // haze only
            prm[9].z = f.hazeScale
            enc.setRenderPipelineState(g.partLight)
            enc.setVertexBytes(prm, length: prm.count * 16, index: 3)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: job.count * 2)
        }
        if inst.light > 0, let b = inst.buffer {
            var base = SIMD2<UInt32>(0, inst.refined != nil ? 1 : 0)
            enc.setRenderPipelineState(g.light)
            enc.setVertexBuffer(b, offset: 0, index: 4)
            enc.setFragmentBuffer(b, offset: 0, index: 4)
            enc.setVertexBytes(&base, length: 8, index: 5)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: inst.light)
        }
        enc.endEncoding()
    }

    /// Light of the lenses in front of the hole plane, one quad each, into an open pass whose inputs are bound.
    private func drawLenses(_ enc: MTLRenderCommandEncoder, params p: [SIMD4<Float>], linear: Bool) {
        guard lensFrame.frontCount > 0 else { return }
        enc.setRenderPipelineState(linear ? GPU.shared.lensLin : GPU.shared.lensFront)
        enc.setVertexBytes(p, length: p.count * 16, index: 0)
        enc.setVertexBytes(lensFrame.data, length: lensFrame.data.count * 16, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: lensFrame.count)
    }

    /// Path F over a finished linear picture in its own pass (the still under the strips).
    private func encodeFrontLinear(_ cmd: MTLCommandBuffer, target: MTLTexture, frame f: BodyFrame, params: [SIMD4<Float>]) {
        guard f.hasFront else { return }
        let inst = prepareInstances(cmd, f, params: params)
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = target
        rp.colorAttachments[0].loadAction = .load
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cmd.renderEncoder(rp, "front linear") else { return }
        drawFront(enc, frame: f, params: params, inst: inst, linear: true, edge: false)
        enc.endEncoding()
    }

    /// Traces the rays for the whole screen and the detail box. Public for --bench-geo.
    func encodeRays(_ cmd: MTLCommandBuffer, width: Int, height: Int) {
        let jet = look.objects.mainJet != nil
        let ms = effectiveMapScale(width, height)
        let mw = max(Int(Float(width) * ms), 16)
        let mh = max(Int(Float(height) * ms), 16)
        if maps.isEmpty || mapSize != (mw, mh) || (maps.count > GPU.mapCount) != jet {
            maps = GPU.makeMaps(mw, mh, jet: jet)
            mapSize = (mw, mh)
        }
        encodeGeo(cmd, targets: maps, screenW: width, screenH: height, region: SIMD4(0, 0, 1, 1))
        updateBox(cmd, width: width, height: height)
        rayVersion += 1
        mapDirty = false
        maskDirty = true
    }

    /// Jet emission of the whole-screen map (front + back per texel), for --jet-stats.
    func jetMapValues() -> [Float]? {
        guard maps.count > GPU.mapCount else { return nil }
        let t = maps[GPU.mapCount]
        let gpu = GPU.shared
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg16Float, width: t.width, height: t.height, mipmapped: false)
        d.storageMode = .shared
        guard let copy = gpu.device.makeTexture(descriptor: d), let cmd = gpu.queue.makeCommandBuffer(),
              let blit = cmd.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: t, to: copy)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        var half = [Float16](repeating: 0, count: t.width * t.height * 2)
        copy.getBytes(&half, bytesPerRow: t.width * 4, from: MTLRegionMake2D(0, 0, t.width, t.height), mipmapLevel: 0)
        return stride(from: 0, to: half.count, by: 2).map { Float(half[$0]) + Float(half[$0 + 1]) }
    }

    /// Bakes the galaxy atlas when the galaxies changed; screens with the same ones share it.
    private func updateGalaxies(_ cmd: MTLCommandBuffer) {
        guard !objFrame.galaxies.isEmpty else { galaxyTex = nil; return }
        let (cols, rows) = objFrame.atlasTiles
        let ts = objFrame.tileSize
        let bakes = objFrame.galaxies
        galaxyTex = GPU.shared.galaxyAtlas(objFrame.atlasKey, cols * ts, rows * ts) { tex in
            let rp = MTLRenderPassDescriptor()
            rp.colorAttachments[0].texture = tex
            rp.colorAttachments[0].loadAction = .clear
            rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            rp.colorAttachments[0].storeAction = .store
            guard let enc = cmd.renderEncoder(rp, "bakeGalaxy") else { return }
            enc.setRenderPipelineState(GPU.shared.bakeGalaxyPipeline)
            for g in bakes {
                let x = Double((g.tile % cols) * ts), y = Double((g.tile / cols) * ts)
                enc.setViewport(MTLViewport(originX: x, originY: y, width: Double(ts), height: Double(ts), znear: 0, zfar: 1))
                enc.setFragmentBytes(g.params, length: g.params.count * MemoryLayout<SIMD4<Float>>.stride, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
            enc.endEncoding()
            if let blit = cmd.blitEncoder("galaxy mips") {
                blit.generateMipmaps(for: tex)
                blit.endEncoding()
            }
        }
    }

    // MARK: Edges only

    /// Advances the band clock alone. Several strips may call this per frame; the clamp
    /// keeps a pause from turning into a jump.
    func tickEdges(_ now: CFTimeInterval) {
        if lastEdgeTick > 0 { edgeLead += Float(min(now - lastEdgeTick, 0.1)) }
        lastEdgeTick = now
    }

    func stopEdgeClock() { lastEdgeTick = 0 }

    /// For snapshots of the edges-only mode: how far the bands ran ahead of the still picture.
    func setEdgeLead(_ t: Float) { edgeLead = t }

    /// Rows of the screen (pixels from the top, y0 < y1) where the bands can light anything.
    /// Outside them the still picture is final. nil when that band is off.
    func stripRows(height: Int) -> (top: (Int, Int)?, bottom: (Int, Int)?) {
        let s = pixelScale, H = Float(height)
        func span(_ e: EdgeStyle, bar: Float) -> (Float, Float)? {
            guard e.on, e.intensity > 0 else { return nil }
            // Matches the cutoff in edgeLight, plus a few pixels of margin.
            let w = max(e.lineWidth, 0.2) * s
            let inPic = max(e.reachPicture * s * 4 + 6 * s, w * 4) + 3
            let inBar = max(e.reachBar * s * 4 + 6 * s, w * 4) + 3
            return (max(0, bar - inBar), min(H, bar + inPic))
        }
        let t = span(look.edgeTop, bar: layout.topBar * s).map { (Int($0.0.rounded(.down)), Int($0.1.rounded(.up))) }
        let b = span(look.edgeBottom, bar: layout.bottomBar * s).map {
            (Int((H - $0.1).rounded(.down)), Int((H - $0.0).rounded(.up)))
        }
        // Objects running along a band need their rows too.
        let o = ObjectSystem.edgeRows(look: look, layout: layout, height: height, pxScale: s)
        func union(_ a: (Int, Int)?, _ b: (Int, Int)?) -> (Int, Int)? {
            guard let a else { return b }
            guard let b else { return a }
            return (min(a.0, b.0), max(a.1, b.1))
        }
        let tt = union(t, o.top), bb = union(b, o.bottom)
        return (tt.flatMap { $0.1 > $0.0 ? $0 : nil }, bb.flatMap { $0.1 > $0.0 ? $0 : nil })
    }

    /// One strip in edges-only mode. The still part under it is cached in `strip.base` and
    /// rebuilt only after the full picture changed; per frame only the light is drawn.
    /// Returns false while there is no full picture yet to build on.
    @discardableResult
    func encodeStrip(_ cmd: MTLCommandBuffer, strip: EdgeStrip, target: MTLTexture, screenW: Int, screenH: Int, rows: (Int, Int)) -> Bool {
        guard !maps.isEmpty, diskTex != nil, nebulaTex != nil, nebFrame != nil else { return false }
        let w = target.width, h = target.height
        let region = SIMD4<Float>(0, Float(rows.0) / Float(screenH), 1, Float(rows.1) / Float(screenH))
        if strip.base?.width != w || strip.base?.height != h {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            strip.base = GPU.shared.device.makeTexture(descriptor: d)
            strip.version = -1
        }
        if strip.version != pictureVersion || strip.region != region {
            // The still under the strip without the band objects (they move on top). The atlas is
            // shared between screens: render the tiles again right before reading them.
            if edgeObjectsInStrips {
                bodyFrame = objects.bodies(look: look, layout: layout, width: screenW, height: screenH, pxScale: pixelScale,
                                           edgeTime: time + edgeLead, sky: objFrame, filter: .without, transient: false)
                if bodyFrame.hasLight { bodyFrame.params[6] = lightUsed }
            }
            if !bodyFrame.tiles.isEmpty { BodyGPU.shared.renderTiles(bodyFrame, cmd, atlas: atlasFor(bodyFrame, edge: false), cache: atlasCache) }
            let bp = frameParams(width: screenW, height: screenH, region: region, stage: 1)
            encodePass(cmd, lensFrame.bendCount == 0 ? GPU.shared.basePipeline
                                : lensFrame.behindCount > 0 ? GPU.shared.baseBehind : GPU.shared.baseLens, target: strip.base!, params: bp)
            if lensFrame.frontCount > 0 {
                let rp = MTLRenderPassDescriptor()
                rp.colorAttachments[0].texture = strip.base
                rp.colorAttachments[0].loadAction = .load
                rp.colorAttachments[0].storeAction = .store
                if let enc = cmd.renderEncoder(rp, "strip lenses") {
                    bindPassInputs(enc, params: bp, inputs: .full)
                    drawLenses(enc, params: bp, linear: true)
                    enc.endEncoding()
                }
            }
            encodeFrontLinear(cmd, target: strip.base!, frame: bodyFrame, params: bp)
            strip.version = pictureVersion
            strip.region = region
        }
        // Objects on the band move with the band clock, drawn over the light of the strip in the same pass.
        var ef: BodyFrame?
        if edgeObjectsInStrips {
            let e = objects.bodies(look: look, layout: layout, width: screenW, height: screenH, pxScale: pixelScale,
                                   edgeTime: time + edgeLead, sky: objFrame, filter: .only, transient: false)
            if e.hasContent { ef = e }
        }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = target
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        if ef != nil {
            rp.colorAttachments[1].texture = GPU.shared.linearScratch(w, h)
            rp.colorAttachments[1].loadAction = .dontCare
            rp.colorAttachments[1].storeAction = .dontCare
        }
        var inst: Instances?
        if let e = ef {
            if !e.tiles.isEmpty { BodyGPU.shared.renderTiles(e, cmd, atlas: atlasFor(e, edge: true), cache: edgeCache) }
            isStrip = true
            inst = prepareInstances(cmd, e, params: frameParams(width: screenW, height: screenH, region: region, stage: 0, bodies: e))
            isStrip = false
        }
        guard let enc = cmd.renderEncoder(rp, "strip") else { return false }
        let p = frameParams(width: screenW, height: screenH, region: region, stage: 0)
        enc.setRenderPipelineState(ef != nil ? GPU.shared.edgeLinearPipeline : GPU.shared.edgePipeline)
        enc.setFragmentBytes(p, length: p.count * MemoryLayout<SIMD4<Float>>.stride, index: 0)
        enc.setFragmentTexture(GPU.shared.edgeNoise, index: 9)
        enc.setFragmentTexture(strip.base, index: 10)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        if let e = ef, let inst {
            drawFront(enc, frame: e, params: frameParams(width: screenW, height: screenH, region: region, stage: 0, bodies: e),
                      inst: inst, linear: false, edge: true)
        }
        enc.endEncoding()
        return true
    }

    /// Forces the nebula layer to be redrawn, e.g. after a look change while paused.
    func invalidateNebulaFrame() { lastNebFrame = -1; lastLight = -1 }

    /// Maps at twice the screen resolution for a square around the hole, where the sharp
    /// edges are. Sampling it bilinearly at pixel centres averages 2 x 2 rays per pixel:
    /// four-fold supersampling of the photon ring and the lensed disk images.
    private func updateBox(_ cmd: MTLCommandBuffer, width: Int, height: Int) {
        guard detailBox else { box = []; boxRect = SIMD4(-1, -1, -1, -1); return }
        let W = Float(width), H = Float(height)
        let shadowPx = look.holeSize * min(W, H)
        // The photon ring and the lensed disk edges lie within about 1.3 shadow radii.
        let half = shadowPx * quality.boxRadius + 12
        let cx = layout.holeX * W, cy = layout.holeY * H
        let x0 = max(0, (cx - half).rounded(.down)), x1 = min(W, (cx + half).rounded(.up))
        let y0 = max(0, (cy - half).rounded(.down)), y1 = min(H, (cy + half).rounded(.up))
        let bw = Int(x1 - x0) * 2, bh = Int(y1 - y0) * 2
        guard bw > 8, bh > 8 else { box = []; boxRect = SIMD4(-1, -1, -1, -1); return }
        if box.first?.width != bw || box.first?.height != bh || box.count != maps.count {
            box = GPU.makeMaps(bw, bh, jet: maps.count > GPU.mapCount)
        }
        boxRect = SIMD4(x0 / W, y0 / H, x1 / W, y1 / H)
        encodeGeo(cmd, targets: box, screenW: width, screenH: height, region: boxRect)
    }

    private func encodeGeo(_ cmd: MTLCommandBuffer, targets: [MTLTexture], screenW: Int, screenH: Int, region: SIMD4<Float>) {
        let rp = MTLRenderPassDescriptor()
        let jet = targets.count > GPU.mapCount
        for i in 0..<targets.count {
            rp.colorAttachments[i].texture = targets[i]
            rp.colorAttachments[i].loadAction = .dontCare
            rp.colorAttachments[i].storeAction = .store
        }
        guard let enc = cmd.renderEncoder(rp, "geo") else { return }
        let shadowRadius: Float = 5.2   // M, close enough for the size slider
        let p: [SIMD4<Float>] = [
            SIMD4(Float(screenW), Float(screenH), layout.holeX, layout.holeY),
            SIMD4(look.spin, look.inclinationDeg * .pi / 180, look.cameraDistance, shadowRadius / look.holeSize),
            SIMD4(look.diskOuter, look.horizon, 0, 0),
            region,
        ] + ObjectSystem.jetGeo(look)
        enc.setRenderPipelineState(jet ? GPU.shared.geoJetPipeline : GPU.shared.geoPipeline)
        enc.setFragmentBytes(p, length: p.count * MemoryLayout<SIMD4<Float>>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private func encodeBake(_ cmd: MTLCommandBuffer, _ pipe: MTLRenderPipelineState, _ tex: MTLTexture, _ b: SIMD4<Float>) {
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = tex
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cmd.renderEncoder(rp, "bake") else { return }
        var b = b
        enc.setRenderPipelineState(pipe)
        enc.setFragmentBytes(&b, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private func edgeParams(_ e: EdgeStyle, barPx: Float) -> [SIMD4<Float>] {
        let c = Palette.linear(e.colour)
        return [
            SIMD4(e.on ? e.intensity : 0, e.lineWidth, e.reachPicture, e.reachBar),
            SIMD4(e.darkenPicture, e.darkenBar, e.flowSpeed, Float(e.flowMode)),
            SIMD4(e.focus, e.customColour ? 1 : 0, barPx, 0),
            SIMD4(c, 0),
        ]
    }

    private func frameParams(width: Int, height: Int, region: SIMD4<Float> = SIMD4(0, 0, 1, 1), stage: Float = 0,
                             bodies: BodyFrame? = nil) -> [SIMD4<Float>] {
        let s = pixelScale
        let top = layout.topBar * s, bottom = layout.bottomBar * s
        var p: [SIMD4<Float>] = [
            SIMD4(Float(width), Float(height), time, layout.holeX),
            SIMD4(top, bottom, s, layout.holeY),
            SIMD4(look.isco, look.diskOuter, look.spin, look.diskBrightness),
            SIMD4(look.exposure, look.stars, look.nebula, look.ringGlow),
            SIMD4(diskClock * look.iscoOmega, look.diskShear, nebulaClock, debug),
            boxRect,
            SIMD4(look.twinkle, look.starDensity, look.starColour, 0),
            SIMD4(look.nebulaSwirl, time + edgeLead, look.diskHueVariety, stage),
            mouse,
        ]
        p += edgeParams(look.edgeTop, barPx: top)
        p += edgeParams(look.edgeBottom, barPx: bottom)
        p += look.linearPalette.map { SIMD4($0, 1) }
        p.append(region)
        p += objFrame.params
        p += (bodies ?? bodyFrame).params
        p.append(lensFrame.params)
        p.append(SIMD4(quality.jetCubic ? 1 : 0, 0, 0, 0))
        return p
    }

    /// What a pass reads besides the ray maps. Binding only that keeps passes independent: a texture
    /// bound to a pass makes it wait for the pass that wrote it, even when the shader never reads it.
    private enum PassInputs { case masks, nebula, full }

    /// lens: the pipelines for the split (the variant with object lenses and the plain one, both drawn as
    /// rectangles), the circles (screen px) outside of which no lens bends anything (nil: everywhere), and the
    /// target's scale against the screen.
    private func encodePass(_ cmd: MTLCommandBuffer, _ pipe: MTLRenderPipelineState, target: MTLTexture, params p: [SIMD4<Float>],
                            inputs: PassInputs = .full, lens: LensSplit? = nil) {
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = target
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cmd.renderEncoder(rp, (lens?.lens ?? pipe).label ?? "pass") else { return }
        bindPassInputs(enc, params: p, inputs: inputs)
        drawSplit(enc, pipe, lens: lens, width: target.width, height: target.height)
        enc.endEncoding()
    }

    struct LensSplit {
        var lens: MTLRenderPipelineState     // all of the lens code
        var far: MTLRenderPipelineState      // weak far fields only
        var plain: MTLRenderPipelineState
        var zones: LensZones?                // nil: the full variant everywhere
        var scale: Float                     // target px per screen px
    }

    /// One full-screen pass in tiles: the plain variant where no lens bends, the far-field variant where the lenses
    /// are seen only in their weak far field, the full one near them. The big lens shader would slow down every
    /// pixel it runs on; all three give the same colour where their cases overlap.
    private func drawSplit(_ enc: MTLRenderCommandEncoder, _ plain: MTLRenderPipelineState, lens: LensSplit?, width: Int, height: Int) {
        guard let lens else {
            enc.setRenderPipelineState(plain)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            return
        }
        var lists = lens.zones.map { Renderer.lensTiles($0, scale: lens.scale, width: width, height: height) }
            ?? [[], [], [SIMD4<Float>(0, 0, 1, 1)]]
        // At most 256 rectangles each (setVertexBytes takes 4 KB): beyond that, the full variant everywhere.
        if lists.contains(where: { $0.count > 256 }) { lists = [[], [], [SIMD4(0, 0, 1, 1)]] }
        for (pipe, rects) in zip([lens.plain, lens.far, lens.lens], lists) where !rects.isEmpty {
            enc.setRenderPipelineState(pipe)
            enc.setVertexBytes(rects, length: rects.count * 16, index: 7)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: rects.count)
        }
    }

    /// Classifies tiles of 32 screen px (whole 2 x 2 quads and sky mask cells) and merges equal neighbours into
    /// rectangles (target uv): plain, far field, full lens variant.
    static func lensTiles(_ z: LensZones, scale k: Float, width: Int, height: Int) -> [[SIMD4<Float>]] {
        let T = max(Int(32 * k), 8)
        var out: [[SIMD4<Float>]] = [[], [], []]
        let W = Float(width), H = Float(height)
        var band: (y0: Int, y1: Int, runs: [(Int, Int, Int)])?   // class, x0, x1
        func flush() {
            guard let b = band else { return }
            for (c, a, e) in b.runs {
                out[c].append(SIMD4(Float(a) / W, Float(b.y0) / H, Float(e) / W, Float(b.y1) / H))
            }
        }
        var y0 = 0
        while y0 < height {
            let y1 = min(y0 + T, height)
            var runs: [(Int, Int, Int)] = []
            var x0 = 0
            while x0 < width {
                let x1 = min(x0 + T, width)
                let c = z.classify(Float(x0) / k, Float(y0) / k, Float(x1) / k, Float(y1) / k)
                if let l = runs.last, l.0 == c { runs[runs.count - 1].2 = x1 } else { runs.append((c, x0, x1)) }
                x0 = x1
            }
            if let b = band, b.runs.elementsEqual(runs, by: { $0 == $1 }) {
                band!.y1 = y1
            } else {
                flush()
                band = (y0, y1, runs)
            }
            y0 = y1
        }
        flush()
        return out
    }

    /// Where the object lenses bend what, for splitting the passes into tiles; nil when that is not known
    /// (the mouse lens moves what is looked up).
    private func lensZones(width: Int, height: Int) -> LensZones? {
        guard mouse.z <= 0 else { return nil }
        let cam = bodyFrame.params
        let r0 = cam[0].x, shadowPx = cam[2].w
        let k = shadowPx / 5.2
        var z = LensZones(lenses: [], hole: SIMD2(layout.holeX * Float(width), layout.holeY * Float(height)),
                          chaos: shadowPx * 2.5 + abs(cam[0].z) * k + 4, near: shadowPx * 4.5, k: k, pxPerRad: k * r0)
        let s = LensFrame.stride
        for i in 0..<min(lensFrame.count, ObjectSystem.maxLenses) {
            let a = lensFrame.data[i * s], b = lensFrame.data[i * s + 1], c = lensFrame.data[i * s + 2]
            let reach = lensFrame.data[i * s + 12]
            guard reach.x > 0 else { continue }   // gates do not bend
            let hole = a.x < 1.5
            // Inside: the ray map, the throat, the layer's rectangle (its corners reach 1.42 map radii).
            let inner = hole ? reach.z * 1.5 + 4 : b.x * 1.8 + 4
            let maxShift = hole ? reach.y : b.y * b.y / max(b.x, 1)
            z.lenses.append(.init(c: SIMD2(a.y, a.z), reach: reach.x, inner: inner, behind: a.w > 0.5, w: c.z, maxShift: maxShift))
        }
        return z
    }

    private func bindPassInputs(_ enc: MTLRenderCommandEncoder, params p: [SIMD4<Float>], inputs: PassInputs) {
        enc.setFragmentBytes(p, length: p.count * MemoryLayout<SIMD4<Float>>.stride, index: 0)
        let blank = GPU.shared.blank
        let detail = boxRect.x >= 0 && box.count == maps.count ? box : maps
        enc.setFragmentTexture(maps[0], index: 0)
        enc.setFragmentTexture(detail[0], index: 5)
        let sky = objFrame.skyCount > 0 ? objFrame.sky : Array(repeating: SIMD4<Float>.zero, count: 5)
        enc.setFragmentBytes(sky, length: sky.count * MemoryLayout<SIMD4<Float>>.stride, index: 1)
        let refs = bodyFrame.lCount > 0 ? bodyFrame.refs : Array(repeating: SIMD4<Float>.zero, count: 5)
        enc.setFragmentBytes(refs, length: refs.count * 16, index: 2)
        let lens = lensFrame.count > 0 ? lensFrame.data : Array(repeating: SIMD4<Float>.zero, count: LensFrame.stride)
        enc.setFragmentBytes(lens, length: lens.count * 16, index: 3)
        for slot in 0..<ObjectSystem.maxHoles {
            let m = lensMaps[slot]
            for k in 0..<5 {
                let t = k < m.count ? m[k] : (k == 0 ? blank : blank)
                if inputs == .full || k == 0 { enc.setFragmentTexture(t, index: 20 + slot * 5 + k) }
            }
        }
        if inputs != .masks {
            enc.setFragmentTexture(nebulaTex, index: 4)
            let jet = maps.count > GPU.mapCount, jetBox = detail.count > GPU.mapCount
            enc.setFragmentTexture(jet ? maps[GPU.mapCount] : blank, index: 11)
            enc.setFragmentTexture(jetBox ? detail[GPU.mapCount] : blank, index: 12)
            enc.setFragmentTexture(objFrame.skyCount > 0 ? skyMask : GPU.shared.blankUint, index: 14)
            enc.setFragmentTexture(galaxyTex ?? blank, index: 13)
        }
        if inputs == .full {
            for i in 1..<GPU.mapCount { enc.setFragmentTexture(maps[i], index: i) }
            for i in 1..<GPU.mapCount { enc.setFragmentTexture(detail[i], index: 5 + i) }
            enc.setFragmentTexture(diskTex, index: 3)
            enc.setFragmentTexture(nebFrame, index: 8)
            enc.setFragmentTexture(GPU.shared.edgeNoise, index: 9)
            let jet = maps.count > GPU.mapCount, jetBox = detail.count > GPU.mapCount
            enc.setFragmentTexture(jet ? maps[GPU.mapCount + 1] : blank, index: 15)
            enc.setFragmentTexture(jetBox ? detail[GPU.mapCount + 1] : blank, index: 16)
            enc.setFragmentTexture(galaxyTex ?? blank, index: 13)
            enc.setFragmentTexture(bodyFrame.lCount > 0 ? atlasFor(bodyFrame, edge: false) : blank, index: 18)
            enc.setFragmentTexture(bodyFrame.hasLight ? lightTex ?? blank : blank, index: 19)
        }
    }

}

/// Cache of one edge strip: the still picture under it, and which picture that was.
final class EdgeStrip {
    var base: MTLTexture?
    var version = -1
    var region = SIMD4<Float>(-1, -1, -1, -1)
}

/// The object lenses of a frame as the tile classifier sees them (screen px).
struct LensZones {
    struct Lens {
        var c: SIMD2<Float>
        var reach: Float      // beyond it the lens bends nothing
        var inner: Float      // inside it the far-field formulas do not hold
        var behind: Bool      // behind the hole plane: it bends after the hole did
        var w: Float          // lens weight (behind)
        var maxShift: Float   // largest shift its far field gives (px)
    }
    var lenses: [Lens]
    var hole: SIMD2<Float>    // main hole centre
    var chaos: Float          // around the main hole rays may leave in any direction
    var near: Float           // lensNear's circle around the main hole for lenses behind the plane
    var k: Float              // px per M of the main hole
    var pxPerRad: Float       // shift on the screen per radian of bend

    /// 0 plain, 1 far field only, 2 everything, for the tile x0 y0 x1 y1 (screen px).
    func classify(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float) -> Int {
        func nearest(_ p: SIMD2<Float>) -> Float {
            let dx = max(x0 - p.x, 0, p.x - x1), dy = max(y0 - p.y, 0, p.y - y1)
            return (dx * dx + dy * dy).squareRoot()
        }
        let dh = nearest(hole)
        let behind = lenses.contains { $0.behind }
        // lensNear is false on every pixel of the tile: the plain variant gives the same.
        guard lenses.contains(where: { nearest($0.c) < $0.reach }) || (behind && dh < near) else { return 0 }
        var cls = 0
        var frontShift: Float = 0
        for L in lenses where !L.behind {
            let d = nearest(L.c)
            if d >= L.reach { continue }
            cls = max(cls, d >= L.inner ? 1 : 2)
            frontShift += L.maxShift
        }
        for L in lenses where L.behind {
            if dh < chaos { return 2 }
            // Where the ray meets the lens's plane: off the pixel by at most its weight times the hole's bend
            // (weak field to third order, with a margin), plus what lenses in front shifted.
            let b = dh / k
            let alpha = 4 / b + 15 * .pi / (4 * b * b) + 128 / (3 * b * b * b)
            let d = nearest(L.c) - L.w * alpha * 1.3 * pxPerRad - frontShift - 4
            if d >= L.reach { continue }
            cls = max(cls, d >= L.inner ? 1 : 2)
        }
        return cls
    }
}
