import Foundation
import Metal
import simd

/// One sprite to render into the body atlas.
struct BodyTile {
    var params: [SIMD4<Float>]          // BodyP
    var rect: (x: Int, y: Int, w: Int, h: Int) = (0, 0, 0, 0)
    var side: Int                        // wanted size in atlas px (square)
    var planet: PlanetSurface?
    var edge: Bool
    var key = ""                         // object id: a tile is only redrawn when it changed
    var radiusPx: Float = 1              // body radius on the screen, sets how much change is visible
    var mesh: ShipMesh? = nil            // ships: rasterised instead of the body kernel, params are ShipP
}

/// What a renderer's atlas holds: per tile its place and the parameters it was drawn with.
final class TileCache {
    var drawn: [String: (rect: [Int], params: [SIMD4<Float>])] = [:]

    /// True when the change would be visible: spin or clouds moved by about half a pixel at the
    /// body's size, slow surface time by a quarter second, anything else by more than 0.2 %.
    static func changed(_ a: [SIMD4<Float>], _ b: [SIMD4<Float>], radiusPx: Float) -> Bool {
        guard a.count == b.count else { return true }
        let ang = 0.4 / max(radiusPx, 1)
        if a.count == BodyGPU.shipParamCount {
            // ShipP: a turn by less than half a pixel at the tips, animated lights four times a second. The
            // reflected sky and disk change slowly with the place; a percent is not visible.
            for i in 0..<a.count {
                for c in 0..<4 {
                    let x = a[i][c], y = b[i][c]
                    let tol: Float = i < 3 && c < 3 ? ang : (i == 10 && c == 1) ? 0.25 : i >= 11 && i < 18 ? 0.01 * max(1, abs(x)) : 0.002 * max(1, abs(x))
                    if abs(x - y) > tol { return true }
                }
            }
            return false
        }
        for i in 0..<a.count {
            for c in 0..<4 {
                let x = a[i][c], y = b[i][c]
                let tol: Float
                switch (i, c) {
                case (1, 3), (2, 3), (13, 3): tol = ang
                case (3, 3): tol = 0.25
                default: tol = 0.002 * max(1, abs(x))
                }
                if abs(x - y) > tol { return true }
            }
        }
        return false
    }
}

/// Baked surface of one planet or moon.
struct PlanetSurface {
    var key: String
    var bake: [SIMD4<Float>]            // PlanetBake
    var width: Int
}

/// One particle system for partVert.
struct PartJob {
    var params: [SIMD4<Float>]          // PartSys
    var count: Int
    var edge: Bool
    var rect: SIMD4<Float>? = nil       // screen rectangle the haze can reach; nil: anywhere
}

/// What the body passes need for one frame.
struct BodyFrame {
    /// camA, camP, camR, camU, camF, bodyU, lightU: appended to FrameParams.
    var params: [SIMD4<Float>] = Array(repeating: .zero, count: 7)
    /// Path L: BodyRef (five float4) per body, far to near.
    var refs: [SIMD4<Float>] = []
    var lCount = 0
    var tiles: [BodyTile] = []
    /// Path F: FrontInst (six float4) per instance, drawn over the finished picture.
    var front: [SIMD4<Float>] = []
    var frontCount = 0
    /// Soft additive light (glows, tails, smoke) for the light buffer, drawn before dispFrag.
    var light: [SIMD4<Float>] = []
    var lightCount = 0
    /// Rectangle (px) the light buffer has anything in.
    var lightRect = SIMD4<Float>(1e9, 1e9, -1e9, -1e9)
    /// Light buffer scale: quarter resolution.
    var lightScale: Float = 4
    /// Point size factor of the haze in the light buffer.
    var hazeScale: Float = 1
    /// Some instance has to find its image in the ray map first (glows and spikes of far stars).
    var needsRefine = false
    var parts: [PartJob] = []
    /// Gate stations whose ring is a wormhole (stage 4), for the lens list.
    var gates: [GateView] = []
    var atlasSize = 1024
    /// The sky the ships mirror (ShipEnvP), when there are ships.
    var shipEnv: (key: String, params: [SIMD4<Float>])?
    /// Band-object frame of the strips: everything goes through the front pass.
    var allFront = false
    var hasContent: Bool { lCount > 0 || frontCount > 0 || lightCount > 0 || !parts.isEmpty }
    var hasLight: Bool { lightCount > 0 || parts.contains { !$0.edge } }
    var hasFront: Bool { frontCount > 0 || !parts.isEmpty }
}

/// Which objects a pass wants: everything, all but the ones on a band, or only those.
enum EdgeFilter { case all, without, only }

/// Pipelines and caches for bodies. Shared by all screens; atlas tiles are rendered right
/// before they are read, inside the same command buffer, so screens can share the atlas.
final class BodyGPU {
    static let shared = BodyGPU()
    let bakePlanet: MTLRenderPipelineState
    let body: MTLComputePipelineState
    let front: MTLRenderPipelineState
    let frontLinear: MTLRenderPipelineState
    let part: MTLRenderPipelineState
    let partLinear: MTLRenderPipelineState
    let refine: MTLRenderPipelineState
    let light: MTLRenderPipelineState
    let partLight: MTLRenderPipelineState
    let ship: MTLRenderPipelineState
    let shipOpaque: MTLRenderPipelineState
    let shipDepth: MTLDepthStencilState
    let shipEnvBake: MTLRenderPipelineState
    static let lightFormat: MTLPixelFormat = .rg11b10Float
    static let shipSamples = 4
    /// Float4 in ShipP; the tile cache tells ship tiles by it.
    static let shipParamCount = 19

    private init() {
        let gpu = GPU.shared
        let lib = gpu.fastLib
        func pipe(_ v: String, _ f: String, _ formats: [MTLPixelFormat]) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: v)
            d.fragmentFunction = lib.makeFunction(name: f)
            for (i, fm) in formats.enumerated() { d.colorAttachments[i].pixelFormat = fm }
            do { return try gpu.device.makeRenderPipelineState(descriptor: d) } catch { fatalError("Pipeline \(f) failed: \(error)") }
        }
        bakePlanet = pipe("vFull", "bakePlanet", [.rgba8Unorm, .rgba8Unorm])
        shipEnvBake = pipe("vFull", "bakeShipEnv", [.rgba16Float])
        do { body = try gpu.device.makeComputePipelineState(function: lib.makeFunction(name: "bodyKernel")!) } catch { fatalError("bodyKernel: \(error)") }
        front = pipe("frontVert", "frontFrag", [GPU.outFormat, .rgba16Float])
        frontLinear = pipe("frontVert", "frontLinFrag", [.rgba16Float])
        part = pipe("partVert", "partFrag", [GPU.outFormat, .rgba16Float])
        partLinear = pipe("partVert", "partLinFrag", [.rgba16Float])
        refine = pipe("vFull", "glowRefine", [.rgba32Float])
        func additive(_ v: String, _ f: String) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: v)
            d.fragmentFunction = lib.makeFunction(name: f)
            let c = d.colorAttachments[0]!
            c.pixelFormat = BodyGPU.lightFormat
            c.isBlendingEnabled = true
            c.rgbBlendOperation = .add
            c.sourceRGBBlendFactor = .one
            c.destinationRGBBlendFactor = .one
            do { return try gpu.device.makeRenderPipelineState(descriptor: d) } catch { fatalError("Pipeline \(f) failed: \(error)") }
        }
        light = additive("frontVert", "lightFrag")
        partLight = additive("partVert", "partLightFrag")
        // Ships: 4x MSAA with depth. Opaque parts without blending, so hidden surfaces cost nothing;
        // premultiplied blending for the few see-through ones, drawn after them.
        func shipPipe(blend: Bool) -> MTLRenderPipelineState {
            let sd = MTLRenderPipelineDescriptor()
            let cv = MTLFunctionConstantValues()
            var b = blend
            cv.setConstantValue(&b, type: .bool, index: 20)
            sd.vertexFunction = lib.makeFunction(name: "shipVert")
            sd.fragmentFunction = try? lib.makeFunction(name: "shipFrag", constantValues: cv)
            sd.rasterSampleCount = BodyGPU.shipSamples
            sd.colorAttachments[0].pixelFormat = .rgba16Float
            if blend {
                sd.colorAttachments[0].isBlendingEnabled = true
                sd.colorAttachments[0].rgbBlendOperation = .add
                sd.colorAttachments[0].alphaBlendOperation = .add
                sd.colorAttachments[0].sourceRGBBlendFactor = .one
                sd.colorAttachments[0].sourceAlphaBlendFactor = .one
                sd.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                sd.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            sd.depthAttachmentPixelFormat = .depth32Float
            do { return try gpu.device.makeRenderPipelineState(descriptor: sd) } catch { fatalError("Pipeline shipFrag failed: \(error)") }
        }
        ship = shipPipe(blend: true)
        shipOpaque = shipPipe(blend: false)
        let dd = MTLDepthStencilDescriptor()
        dd.depthCompareFunction = .less
        dd.isDepthWriteEnabled = true
        shipDepth = gpu.device.makeDepthStencilState(descriptor: dd)!
    }

    /// Vertex and index buffers of the ship meshes in use.
    private var meshBuffers: [String: (MTLBuffer, MTLBuffer, Int)] = [:]
    private func buffers(_ m: ShipMesh) -> (MTLBuffer, MTLBuffer, Int)? {
        if let b = meshBuffers[m.key] { return b }
        let dev = GPU.shared.device
        guard !m.data.idx.isEmpty,
              let vb = m.data.v.withUnsafeBytes({ dev.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }),
              let ib = m.data.idx.withUnsafeBytes({ dev.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) })
        else { return nil }
        if meshBuffers.count > 48 { meshBuffers = [:] }
        meshBuffers[m.key] = (vb, ib, m.data.idx.count)
        return meshBuffers[m.key]
    }

    /// The sky the ships mirror: 256 x 128, equirectangular, with mipmaps for rough surfaces. Baked when the
    /// look's nebula, palette or stars change; screens with the same look share it.
    private var envs: [String: MTLTexture] = [:]
    private var envOrder: [String] = []
    private func shipEnv(_ e: (key: String, params: [SIMD4<Float>])?, _ cmd: MTLCommandBuffer) -> MTLTexture {
        guard let e else { return GPU.shared.blank }
        if let t = envs[e.key] { return t }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 256, height: 128, mipmapped: true)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let t = GPU.shared.device.makeTexture(descriptor: d)!
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = t
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        if let enc = cmd.renderEncoder(rp, "ship sky") {
            enc.setRenderPipelineState(shipEnvBake)
            enc.setFragmentBytes(e.params, length: e.params.count * 16, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }
        if let blit = cmd.blitEncoder("ship sky mips") { blit.generateMipmaps(for: t); blit.endEncoding() }
        envs[e.key] = t
        envOrder.append(e.key)
        while envOrder.count > 4 { envs[envOrder.removeFirst()] = nil }
        return t
    }

    /// Pictures of model files on the GPU, with mipmaps; made once per picture.
    private var modelTextures: [ObjectIdentifier: (ModelTexture, MTLTexture)] = [:]
    private func texture(_ m: ModelTexture?, _ cmd: MTLCommandBuffer) -> MTLTexture? {
        guard let m else { return nil }
        if let t = modelTextures[ObjectIdentifier(m)] { return t.1 }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: m.width, height: m.height, mipmapped: true)
        d.usage = [.shaderRead]
        d.storageMode = .shared
        guard let t = GPU.shared.device.makeTexture(descriptor: d) else { return nil }
        m.rgba.withUnsafeBytes { t.replace(region: MTLRegionMake2D(0, 0, m.width, m.height), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: m.width * 4) }
        if let blit = cmd.blitEncoder("model mips") { blit.generateMipmaps(for: t); blit.endEncoding() }
        if modelTextures.count > 64 { modelTextures = [:] }
        modelTextures[ObjectIdentifier(m)] = (m, t)
        return t
    }

    /// ShipM of a part: the model file's material, or neutral for built-in ships (their finish is in the vertices).
    private static func partParams(_ m: ModelMaterial?) -> [SIMD4<Float>] {
        guard let m else { return [SIMD4(1, 1, 1, 1), .zero, SIMD4(0, 0.5, 1, 1), .zero, .zero] }
        func has(_ t: ModelTexture?) -> Float { t == nil ? 0 : 1 }
        return [m.base, SIMD4(m.emissive, 0), SIMD4(m.metal, m.rough, m.normalScale, m.occlusion),
                SIMD4(has(m.baseTex), has(m.mrTex), has(m.normalTex), has(m.emissiveTex)), SIMD4(has(m.occlusionTex), m.alphaCutoff, 0, 0)]
    }

    /// Scratch for the ships of one frame: memoryless MSAA colour and depth, and the resolved picture whose
    /// tiles are copied into the atlas. Sizes are rounded up, so a few sizes serve all frames.
    private var shipTargets: [String: (MTLTexture, MTLTexture, MTLTexture)] = [:]
    private func targets(_ w: Int, _ h: Int) -> (MTLTexture, MTLTexture, MTLTexture) {
        let key = "\(w)x\(h)"
        if let t = shipTargets[key] { return t }
        let dev = GPU.shared.device
        func tex(_ f: MTLPixelFormat, samples: Int, memoryless: Bool) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: f, width: w, height: h, mipmapped: false)
            if samples > 1 { d.textureType = .type2DMultisample; d.sampleCount = samples }
            d.usage = [.renderTarget]
            d.storageMode = memoryless ? .memoryless : .private
            return dev.makeTexture(descriptor: d)!
        }
        let t = (tex(.rgba16Float, samples: BodyGPU.shipSamples, memoryless: true),
                 tex(.depth32Float, samples: BodyGPU.shipSamples, memoryless: true),
                 tex(.rgba16Float, samples: 1, memoryless: false))
        if shipTargets.count > 12 { shipTargets = [:] }
        shipTargets[key] = t
        return t
    }

    /// Rasterises the ship tiles of a frame in one pass, side by side in a scratch picture, and copies them
    /// into their places in the atlas. One pass for all ships: each pass has a fixed cost, at the low clock
    /// of the live view more than the drawing itself.
    private func renderShips(_ tiles: [(BodyTile, ShipMesh)], _ cmd: MTLCommandBuffer, atlas: MTLTexture,
                             env e: (key: String, params: [SIMD4<Float>])?) {
        let list = tiles.compactMap { t, m in buffers(m).map { (t, $0, m) } }
        guard !list.isEmpty else { return }
        // Shelf packing, tallest first, in a roughly square scratch: its whole area is cleared and resolved.
        let order = list.indices.sorted { list[$0].0.rect.h > list[$1].0.rect.h }
        let area = list.reduce(0) { $0 + $1.0.rect.w * $1.0.rect.h }
        let rowW = max(Int((Double(area) * 1.3).squareRoot()), list.map { $0.0.rect.w }.max() ?? 0)
        var at = [(Int, Int)](repeating: (0, 0), count: list.count)
        var x = 0, y = 0, rowH = 0, width = 0
        for i in order {
            let r = list[i].0.rect
            if x + r.w > rowW { x = 0; y += rowH; rowH = 0 }
            at[i] = (x, y)
            x += r.w
            rowH = max(rowH, r.h)
            width = max(width, x)
        }
        let height = y + rowH
        // A few sizes only, so the scratch is not made anew whenever another set of ships needs drawing.
        func up(_ v: Int) -> Int { [128, 192, 256, 384, 512, 768, 1024, 1536, 2048].first { $0 >= v } ?? (v + 255) / 256 * 256 }
        let (ms, depth, res) = targets(up(width), up(height))
        let env = shipEnv(e, cmd)
        // Textures of model files: made before the pass, their mipmaps need a blit.
        var texs: [[MTLTexture?]] = []
        for (_, _, m) in list { texs.append(m.data.materials.flatMap { mat in mat.textures.map { texture($0, cmd) } }) }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = ms
        rp.colorAttachments[0].resolveTexture = res
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        rp.colorAttachments[0].storeAction = .multisampleResolve
        rp.depthAttachment.texture = depth
        rp.depthAttachment.loadAction = .clear
        rp.depthAttachment.clearDepth = 1
        rp.depthAttachment.storeAction = .dontCare
        guard let enc = cmd.renderEncoder(rp, "ships") else { return }
        enc.setDepthStencilState(shipDepth)
        enc.setCullMode(.none)
        let blank = GPU.shared.blank
        enc.setFragmentTexture(env, index: 5)
        // Opaque parts of all ships first, then the see-through ones over them.
        for blendPass in [false, true] {
        enc.setRenderPipelineState(blendPass ? ship : shipOpaque)
        for (i, (t, (vb, ib, n), m)) in list.enumerated() {
            let (px, py) = at[i]
            enc.setViewport(MTLViewport(originX: Double(px), originY: Double(py), width: Double(t.rect.w), height: Double(t.rect.h),
                                        znear: 0, zfar: 1))
            enc.setScissorRect(MTLScissorRect(x: px, y: py, width: t.rect.w, height: t.rect.h))
            enc.setVertexBuffer(vb, offset: 0, index: 0)
            enc.setVertexBytes(t.params, length: t.params.count * 16, index: 1)
            enc.setFragmentBytes(t.params, length: t.params.count * 16, index: 1)
            let parts = m.data.parts.isEmpty ? [MeshPart(start: 0, count: n, material: -1)] : m.data.parts
            for part in parts where part.blend == blendPass {
                let mat = part.material >= 0 && part.material < m.data.materials.count ? m.data.materials[part.material] : nil
                let pp = BodyGPU.partParams(mat)
                enc.setFragmentBytes(pp, length: pp.count * 16, index: 2)
                for k in 0..<5 {
                    let tx = mat != nil ? texs[i][part.material * 5 + k] : nil
                    enc.setFragmentTexture(tx ?? blank, index: k)
                }
                enc.drawIndexedPrimitives(type: .triangle, indexCount: part.count, indexType: .uint32, indexBuffer: ib,
                                          indexBufferOffset: part.start * 4)
            }
        }
        }
        enc.endEncoding()
        guard let blit = cmd.blitEncoder("ship copy") else { return }
        for (i, (t, _, _)) in list.enumerated() {
            blit.copy(from: res, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: at[i].0, y: at[i].1, z: 0),
                      sourceSize: MTLSize(width: t.rect.w, height: t.rect.h, depth: 1),
                      to: atlas, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: t.rect.x, y: t.rect.y, z: 0))
        }
        blit.endEncoding()
    }

    /// Image positions of far stars found in the ray map, one texel per front instance.
    static func makeRefineTarget(_ n: Int) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: max(n, 64), height: 1, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        return GPU.shared.device.makeTexture(descriptor: d)!
    }

    static func makeAtlas(_ size: Int) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: size, height: size, mipmapped: false)
        d.usage = [.shaderWrite, .shaderRead]
        d.storageMode = .private
        return GPU.shared.device.makeTexture(descriptor: d)!
    }

    private var surfaces: [String: (MTLTexture, MTLTexture)] = [:]
    private var surfaceOrder: [String] = []

    /// Baked planet surfaces, kept for the planets of all screens plus a few a slider left behind.
    func surface(_ s: PlanetSurface, _ cmd: MTLCommandBuffer) -> (MTLTexture, MTLTexture) {
        if let t = surfaces[s.key] {
            surfaceOrder.removeAll { $0 == s.key }
            surfaceOrder.append(s.key)
            return t
        }
        let dev = GPU.shared.device
        func tex() -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: s.width, height: s.width / 2, mipmapped: true)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            return dev.makeTexture(descriptor: d)!
        }
        let a = tex(), b = tex()
        let rp = MTLRenderPassDescriptor()
        for (i, t) in [a, b].enumerated() {
            rp.colorAttachments[i].texture = t
            rp.colorAttachments[i].loadAction = .dontCare
            rp.colorAttachments[i].storeAction = .store
        }
        if let enc = cmd.renderEncoder(rp, "bakePlanet") {
            enc.setRenderPipelineState(bakePlanet)
            enc.setFragmentBytes(s.bake, length: s.bake.count * 16, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }
        if let blit = cmd.blitEncoder("planet mips") {
            blit.generateMipmaps(for: a)
            blit.generateMipmaps(for: b)
            blit.endEncoding()
        }
        surfaces[s.key] = (a, b)
        surfaceOrder.append(s.key)
        while surfaceOrder.count > 16 { surfaces[surfaceOrder.removeFirst()] = nil }
        return (a, b)
    }

    /// Renders the tiles of a frame that changed into the renderer's atlas.
    func renderTiles(_ f: BodyFrame, _ cmd: MTLCommandBuffer, atlas at: MTLTexture, cache: TileCache) {
        var tiles: [BodyTile] = []
        var keep: Set<String> = []
        for t in f.tiles {
            let rect = [t.rect.x, t.rect.y, t.rect.w, t.rect.h]
            keep.insert(t.key)
            if let d = cache.drawn[t.key], d.rect == rect, !TileCache.changed(d.params, t.params, radiusPx: t.radiusPx) { continue }
            tiles.append(t)
            cache.drawn[t.key] = (rect, t.params)
        }
        for k in cache.drawn.keys where !keep.contains(k) { cache.drawn[k] = nil }
        renderShips(tiles.compactMap { t in t.mesh.map { (t, $0) } }, cmd, atlas: at, env: f.shipEnv)
        tiles.removeAll { $0.mesh != nil }
        guard !tiles.isEmpty else { return }
        let surf = tiles.map { $0.planet.map { surface($0, cmd) } }
        guard let enc = cmd.computeEncoder("body tiles") else { return }
        enc.setComputePipelineState(body)
        enc.setTexture(at, index: 2)
        let blank = GPU.shared.blank
        let tg = MTLSize(width: 16, height: 16, depth: 1)
        for (t, s) in zip(tiles, surf) {
            var rect = SIMD4<UInt32>(UInt32(t.rect.x), UInt32(t.rect.y), UInt32(t.rect.w), UInt32(t.rect.h))
            enc.setBytes(t.params, length: t.params.count * 16, index: 0)
            enc.setBytes(&rect, length: 16, index: 1)
            enc.setTexture(s?.0 ?? blank, index: 0)
            enc.setTexture(s?.1 ?? blank, index: 1)
            enc.dispatchThreadgroups(MTLSize(width: (t.rect.w + 15) / 16, height: (t.rect.h + 15) / 16, depth: 1), threadsPerThreadgroup: tg)
        }
        enc.endEncoding()
    }
}

// MARK: - Packing

extension ObjectSystem {
    static let maxL = 8

    /// Bodies, particles and the front instances of one frame.
    ///  - edgeTime: the band clock (objects on a band move with it)
    ///  - transient: meteors and other fleeting things are drawn
    func bodies(look: Look, layout: ScreenLayout, width: Int, height: Int, pxScale: Float, edgeTime: Float,
                sky: ObjectFrame, filter: EdgeFilter, transient: Bool) -> BodyFrame {
        var f = BodyFrame()
        f.allFront = filter == .only
        let scene = look.objects
        let active = scene.active
        let cam = CamFrame(look: look, layout: layout, width: width, height: height)
        f.params = [
            SIMD4(cam.r0, cam.mPerS, cam.shift, cam.holeDepth),
            SIMD4(cam.pos, 0),
            SIMD4(cam.right, cam.shadowPx),
            SIMD4(cam.up, 0),
            SIMD4(cam.fwd, 0),
            SIMD4(1, 1, 0, 0),
            SIMD4(1, 1, 0, 0),
        ]
        guard !active.isEmpty else { return f }
        f.atlasSize = quality.atlasSize
        let maxTile = quality.maxTile
        let tileScale = quality.tileScale
        f.lightScale = quality.lightScale
        let pal = look.linearPalette

        // The disk lights everything around the hole: colour from the warm end of the palette.
        var holeCol = simd_mix(pal[3], pal[4], SIMD3(repeating: 0.75))
        holeCol /= max(simd_dot(holeCol, SIMD3(0.2126, 0.7152, 0.0722)), 1e-3)
        holeCol = simd_mix(holeCol, SIMD3(repeating: 1), SIMD3(repeating: 0.3))
        holeCol *= look.diskBrightness
        let ambient = pal[6] * 0.02 + pal[5] * 0.012

        // Placements first: moons need their planet.
        var placed: [String: (Placement, SpaceObject)] = [:]
        let bodyKinds: Set<ObjectKind> = [.planet, .moon, .asteroid, .comet, .star, .ship, .station, .model]
        func isBody(_ o: SpaceObject) -> Bool {
            guard let k = o.objectKind, bodyKinds.contains(k) else { return false }
            return k != .star || o.motion.mode != .sky
        }
        let firstPlanet = active.first { $0.objectKind == .planet && $0.motion.mode != .edge }
        for pass in 0..<2 {
            for o in active where isBody(o) && ((o.objectKind == .moon) == (pass == 1)) {
                if let p = place(o, look: look, cam: cam, layout: layout, pxScale: pxScale, edgeTime: edgeTime,
                                 parent: o.objectKind == .moon ? (placed[o.attach] ?? firstPlanet.flatMap { placed[$0.id] }) : nil) {
                    placed[o.id] = (p, o)
                }
            }
        }

        // Near stars light the others.
        struct Light { var pos: SIMD3<Float>; var col: SIMD3<Float>; var radius: Float }
        var lights: [Light] = []
        for (_, (p, o)) in placed where o.objectKind == .star {
            let col = ObjectSystem.blackbody(o.param("temperature")) * o.brightness
            lights.append(Light(pos: p.world, col: col, radius: max(o.size, 0.2)))
        }

        var lBodies: [(depth: Float, ref: [SIMD4<Float>], tile: BodyTile)] = []
        var frontTiles: [(BodyTile, [Float])] = []   // F sprites: box and later uv
        let W = Float(width), H = Float(height)

        for (_, (pl, o)) in placed.sorted(by: { $0.key < $1.key }) {
            if filter == .only && !pl.edge { continue }
            if filter == .without && pl.edge { continue }
            let X = pl.world
            let q = cam.cam(X)
            let screenPlaced = pl.screen != nil
            if !screenPlaced && q.z < 5 { continue }
            let depth = max(q.z, 1)
            let w: Float = screenPlaced ? (o.motion.mode == .fixed && o.motion.depth == "behind" ? 0.5 : 0) : cam.lensWeight(depth: depth)
            var centre = pl.screen ?? cam.px(dir: q)
            // A Cepheid near the hole breathes: radius, brightness and temperature follow its light curve.
            var pulseR: Float = 1, pulseB: Float = 1, pulseT: Float = 1
            if o.objectKind == .star && o.variant == "cepheid" {
                let ph = Float(phase("\(o.id).pulse").truncatingRemainder(dividingBy: 1))
                let lc = ph < 0.15 ? ph / 0.15 : 1 - (ph - 0.15) / 0.85
                let sm = lc * lc * (3 - 2 * lc) - 0.5
                let d = o.param("pulseDepth")
                pulseR = 1 + 0.16 * d * sm
                pulseB = 1 + 1.2 * d * sm
                pulseT = 1 + 0.12 * d * sm
            }
            // Ships: size is the length, the sprite unit half of it.
            let isShip = ObjectSystem.shipKinds.contains(o.objectKind!)
            let rp = (screenPlaced ? pl.radiusPx : max(o.size, 0.01) * cam.scale(depth: depth) * (isShip ? 0.5 : 1)) * pulseR
            guard rp > 0.15 else { continue }
            var shipMesh: ShipMesh?
            var ev: ShipEventNow?
            var shipRot = matrix_identity_float3x3
            var gateEvent: ShipEventNow?
            if isShip {
                guard let m = ShipCatalog.mesh(for: o) else { continue }
                shipMesh = m
                let e = shipEvent(o, cam: cam, pxScale: pxScale, edgeTime: edgeTime, sizePx: rp)
                ev = e.0
                // A gate's events play in its ring: the station itself stays.
                if let g = ev, g.spec.fx >= 9 { gateEvent = g; ev = nil }
                if e.hidden && o.objectKind != .station { continue }
            }

            // Sprite frame: z towards the camera, x along the screen's right.
            let ez = simd_normalize(cam.pos - X)
            var ex = simd_cross(cam.up, ez)
            ex = simd_length(ex) < 1e-4 ? cam.right : simd_normalize(ex)
            let ey = simd_cross(ez, ex)
            func sp(_ v: SIMD3<Float>) -> SIMD3<Float> { SIMD3(simd_dot(v, ex), simd_dot(v, ey), simd_dot(v, ez)) }
            if isShip {
                shipRot = shipRotation(o, pl: pl, ex: ex, ey: ey, ez: ez)
                // Through a wormhole: the nearest one on the screen; nose first in and out.
                if let e = ev, let l = Optional(e.look), l.toTarget > 0 || l.turn > 0,
                   let t = wormholeTargets.min(by: { simd_distance($0, centre) < simd_distance($1, centre) }) {
                    (shipRot, centre) = wormholeSteer(o, R: shipRot, look: l, arrival: e.arrival, rest: centre, target: t)
                }
                // Event shift along the flight direction on the screen.
                if let l = ev?.look, l.shift != 0 {
                    let f = shipRot * SIMD3<Float>(1, 0, 0)
                    centre += SIMD2(f.x, -f.y) * l.shift * 2 * rp
                }
            }

            // Lights: the disk, and the strongest near star other than itself.
            let dHole = max(simd_length(X), 1)
            let lHole = -X / dHole
            var irr = 1.5 * powf(60 / dHole, 1.5)
            irr = min(max(irr, 0.1), 3.5) * (0.4 + 0.6 * abs(lHole.z))
            let wrapHole = min(max(atanf(look.diskOuter * 0.12 / dHole), 0.02), 0.25)
            var l0 = (dir: sp(lHole), wrap: wrapHole, col: holeCol * irr)
            var l1 = (dir: SIMD3<Float>(0, 0, 1), wrap: Float(0), col: SIMD3<Float>(repeating: 0))
            var best: Float = 0
            for L in lights where simd_length(L.pos - X) > 0.01 {
                let d = simd_length(L.pos - X)
                let g = min(1.6 * powf(L.radius * 14 / max(d, 0.5), 2), 8)
                if g * simd_reduce_max(L.col) > best {
                    best = g * simd_reduce_max(L.col)
                    l1 = (sp((L.pos - X) / d), min(atanf(L.radius / d), 0.4), L.col * g)
                }
            }
            if o.objectKind == .star { l1.col = .zero }
            // Doppler on close orbits: brighter and bluer where the body comes towards us.
            var dop: Float = 1
            if scene.relativistic && !screenPlaced {
                let b = min(simd_length(pl.vel), 0.9)
                if b > 1e-3 {
                    let ct = simd_dot(simd_normalize(pl.vel), ez)
                    dop = 1 / ((1 / (1 - b * b).squareRoot()) * (1 - b * ct))
                }
                // Gravitational redshift: light climbing out from near the hole to the camera loses energy.
                let g = max(1 - 2 / max(simd_length(X), 2.05), 0.01).squareRoot() / max(1 - 2 / cam.r0, 0.5).squareRoot()
                dop *= g
            }
            // Towards us bluer, away and deep in the well redder: the reflected light's colour follows the shift.
            let dopTint = dop == 1 ? SIMD3<Float>(repeating: 1) : SIMD3(powf(dop, -0.45), 1, powf(dop, 0.45))
            let tint = o.tintAmount > 0 ? simd_mix(SIMD3<Float>(repeating: 1), Palette.linear(o.tint) / max(simd_reduce_max(Palette.linear(o.tint)), 1e-3),
                                                  SIMD3(repeating: min(o.tintAmount, 1))) : SIMD3<Float>(repeating: 1)
            let bright = o.brightness * min(max(powf(dop, 3), 0.05), 4) * pl.fade
            // A star's disc shows its surface brightness, not its luminosity: relative to the variant's default.
            let relBright = o.brightness / max(ObjectCatalog.spec(for: o)?.make(o.seed).brightness ?? 1, 0.05) * min(max(powf(dop, 3), 0.05), 4) * pl.fade
            l0.col *= bright * tint * dopTint
            // Inside the inner disk a body is lit by the gas all around it, not only from the hole's direction:
            // a soft fill, so the side away from the hole is not black. Without it a body in front of the hole
            // showed only its lit limb, a dark disc in a bright ring. Nothing changes beyond half the disk.
            let embed = 1 - simd_smoothstep(look.diskOuter * 0.25, look.diskOuter * 0.5, dHole)
            let diskFill = !screenPlaced && embed > 0 ? holeCol * min(1.5 * powf(60 / dHole, 1.5), 3.5) * 0.1 * embed * bright * tint * dopTint : .zero
            l1.col *= bright * tint * dopTint

            // A ship that is away during its event: only the event's light.
            if isShip, let e = ev, !e.look.visible, let m = shipMesh {
                addShipLights(&f, o, mesh: m, R: shipRot, centre: centre, rp: rp, cam: cam, behind: w > 0, event: e, bright: bright)
                continue
            }
            // Body axes: spin axis tilted off the orbit normal; spin angle from the clock.
            var rng = SeedRNG(o.seed &+ 99)
            let orbitN = o.motion.mode == .orbit ? Orbits.planeNormal(o.motion) : SIMD3<Float>(0, 0, 1)
            let tilt = o.param("axialTilt") * .pi / 180
            let tAz = rng.range(0...(2 * .pi))
            var t1 = simd_cross(orbitN, SIMD3(1, 0, 0))
            if simd_length(t1) < 1e-3 { t1 = SIMD3(0, 1, 0) }
            t1 = simd_normalize(t1)
            let t2 = simd_cross(orbitN, t1)
            let tdir = t1 * cosf(tAz) + t2 * sinf(tAz)
            let locked = o.objectKind == .moon && o.motion.mode == .orbit && o.param("locked") > 0.5
            var bzW = locked ? orbitN : simd_normalize(orbitN * cosf(tilt) + tdir * sinf(tilt))
            if o.objectKind == .asteroid {
                // A small rock tumbles: its spin axis wanders round its angular momentum (non-principal rotation).
                let L = bzW
                var u1 = simd_cross(L, SIMD3(0.48, -0.6, 0.64))
                u1 = simd_length(u1) < 1e-3 ? simd_cross(L, SIMD3(1, 0, 0)) : u1
                u1 = simd_normalize(u1)
                let u2 = simd_cross(L, u1)
                let psi = Float((phase("\(o.id).spin") * 0.618).truncatingRemainder(dividingBy: 1)) * 2 * .pi
                let cone = rng.range(0.35...0.7)
                bzW = simd_normalize(L * cosf(cone) + (u1 * cosf(psi) + u2 * sinf(psi)) * sinf(cone))
            }
            var bxW = simd_cross(bzW, SIMD3(0.3, 0.5, 0.81))
            bxW = simd_normalize(bxW)
            let byW = simd_cross(bzW, bxW)
            var spin = Float(phase("\(o.id).spin").truncatingRemainder(dividingBy: 1)) * 2 * .pi
            if locked, let par = placed[o.attach] ?? firstPlanet.flatMap({ placed[$0.id] }) {
                // Tidally locked: the same face, and a knobbly moon its long axis, always towards the planet.
                let d = par.0.world - X
                let phi = atan2f(simd_dot(d, byW), simd_dot(d, bxW))
                spin = o.variant == "knolle" ? phi : Float(o.seed % 628) * 0.01 - phi
            }
            let time = Float(phase("\(o.id).t").truncatingRemainder(dividingBy: 10000))
            let cloud = Float(phase("\(o.id).cloud").truncatingRemainder(dividingBy: 1)) * 2 * .pi

            var kind: Float = 0, type: Float = 0, ext: Float = 1.05
            var shipParams: [SIMD4<Float>]?
            var q0 = SIMD4<Float>.zero, q1 = SIMD4<Float>.zero, e = SIMD4<Float>.zero, e2 = SIMD4<Float>.zero
            var atm = SIMD4<Float>.zero, ring = SIMD4<Float>.zero, ringC = SIMD4<Float>.zero
            var bx = sp(bxW), by = sp(byW)
            let bzS = sp(bzW)
            var surface: PlanetSurface?
            let hueRad = o.param("hueShift") * .pi / 180
            switch o.objectKind {
            case .planet, .moon:
                let types = ["rocky": 0, "desert": 1, "earth": 2, "ocean": 3, "ice": 4, "lava": 5, "gasGiant": 6, "ringed": 7,
                             "iceGiant": 8, "hotJupiter": 9, "grey": 10, "io": 11, "europa": 12, "titan": 13, "knolle": 14]
                let ty = types[o.variant] ?? 0
                type = Float(ty)
                if ty == 14 {
                    kind = 2
                    q1 = SIMD4(o.param("elongation"), o.param("craters"), 1, 0)
                    ext = 1.32
                    let ca = cosf(spin), sa = sinf(spin)
                    bx = sp(bxW * ca + byW * sa); by = sp(byW * ca - bxW * sa)
                    break
                }
                let a = o.param("atmosphere")
                let hc = ObjectSystem.hueColour(o.param("atmoHue"), sat: 0.6)
                atm = SIMD4(hc * a * 0.9, a)
                // The rim and haze grow with the light. Close to the hole the disk lights a body four or five times
                // as strongly as far out; there they grow only slowly above that of a far body, so the rim stays a
                // thin line instead of a glowing ring. Far bodies (no fill) keep theirs.
                let lightL = simd_length(l0.col + l1.col)
                if !screenPlaced, embed > 0, lightL > 2 {
                    let k = (2 + (lightL - 2) * 0.15) / lightL
                    atm.x *= 1 + (k - 1) * embed; atm.y *= 1 + (k - 1) * embed; atm.z *= 1 + (k - 1) * embed
                }
                q0 = SIMD4(o.param("specular"), o.param("nightLights"), o.param("emissive"), o.param("clouds"))
                let rings = o.param("rings") > 0.5
                if rings {
                    let ri = o.param("ringInner"), ro = max(o.param("ringOuter"), ri + 0.05)
                    ring = SIMD4(ri, ro, o.param("ringDensity"), o.param("ringGap"))
                    var rc = SIMD3<Float>(0.86, 0.74, 0.58)
                    rc = ObjectSystem.rotateHue(rc, o.param("ringHue") * .pi / 180)
                    ringC = SIMD4(rc * rc * 1.2, 1)
                    ext = max(ext, ro * 1.02)
                }
                ext = max(ext, 1 + a * 0.2 + 0.03)
                let res = (ty >= 10 ? 512 : 1024) * quality.planetScale / 2
                let bake: [SIMD4<Float>] = [
                    SIMD4(type, Float(o.seed % 997) * 1.31, o.param("ocean"), o.param("craters")),
                    SIMD4(o.param("bands"), o.param("storms"), o.param("cracks"), 0),
                ]
                surface = PlanetSurface(key: "planet \(res) \(bake)", bake: bake, width: res)
            case .star:
                let T = o.param("temperature") * min(max(dop, 0.7), 1.4) * pulseT
                let sc = ObjectSystem.nearStarColours(T, exposure: look.exposure)
                let rb = relBright * pulseB
                if o.variant == "binary" {
                    kind = 4
                    let sep = max(o.param("separation"), 1.6)
                    let ph = Float(phase("\(o.id).orbit").truncatingRemainder(dividingBy: 1)) * 2 * .pi
                    q1 = SIMD4(sep, 0.2, o.param("stream"), ph)
                    let qa: Float = 0.2 * 0.2 / (1 + 0.2 * 0.2)
                    ext = max(sep * (1 - qa) + 0.2 + sep * 0.3 + 0.3, sep * qa + 1.5)
                    let c2 = ObjectSystem.nearStarColours(o.param("temperature2"), exposure: look.exposure).centre * rb * 1.3
                    e = SIMD4(sc.centre * rb * tint, T)
                    e2 = SIMD4(c2, 0)
                    q0 = SIMD4(sc.limb * rb * tint, o.param("granulation"))
                } else {
                    kind = 1
                    type = o.variant == "brownDwarf" ? 1 : o.variant == "wolfRayet" ? 2 : 0
                    // Hot stars have no spots and a calmer surface; cool ones are spotted.
                    let cool = min(max((8000 - T) / 2500, 0), 1.6)
                    let gran = o.param("granulation") * (T > 8000 ? 0.6 : 1)
                    let bd: Float = o.variant == "brownDwarf" ? 0.15 : 1
                    q0 = SIMD4(gran, o.param("spots") * cool, o.param("prominences") * bd, o.param("corona") * bd)
                    // Convection cells: fine on dwarfs, a few giant cells on supergiants.
                    let cells: [String: Float] = ["redSupergiant": 4, "blueSupergiant": 6, "redGiant": 6, "cepheid": 8, "whiteDwarf": 20]
                    q1 = SIMD4(cells[o.variant] ?? 16, 0, 0, 0)
                    ext = 1 + max(o.param("corona") * 0.4, o.param("prominences") * 0.24) + 0.06
                    e = SIMD4(sc.centre * rb * tint, T)
                    e2 = SIMD4(sc.limb * rb * tint, 0)
                }
            case .asteroid:
                kind = 2
                q1 = SIMD4(o.param("elongation"), o.param("craters"), o.param("rockType").rounded(), 0)
                ext = 1.32
                let ca = cosf(spin), sa = sinf(spin)
                bx = sp(bxW * ca + byW * sa); by = sp(byW * ca - bxW * sa)
            case .comet:
                kind = 3
                ext = 2.4
                let act = cometActivity(X)
                let green = o.variant == "green"
                let dustC = SIMD3<Float>(1.0, 0.93, 0.80) * holeCol * 0.5 + SIMD3(0.5, 0.47, 0.4)
                e = SIMD4(dustC * tint, o.param("coma") * act * bright * 1.4)
                e2 = SIMD4(green ? SIMD3(0.25, 1.0, 0.42) : SIMD3(0.45, 0.68, 1.0), 0.6 + act)
            case .ship, .station, .model:
                kind = 5
                let l = ev?.look ?? ShipLook()
                let R = shipRot
                // A gate in front of the hole plane opens onto the other side; its membrane gets thin.
                var gateClear: Float = 0
                if o.objectKind == .station, ObjectCatalog.gateIDs.contains(o.variant), o.param("portal") > 0.5, w == 0,
                   filter != .only, let m = shipMesh, let ap = m.aperture {
                    gateClear = o.variant == "stargate" ? 0.45 : 0.2
                    func scr(_ v: SIMD3<Float>) -> SIMD2<Float> { let r = R * v; return SIMD2(r.x, -r.y) * 2 * rp }
                    var n = R * SIMD3<Float>(1, 0, 0)
                    if n.z < 0 { n = -n }
                    f.gates.append(GateView(object: o, centre: centre + scr(ap.centre), u: scr(SIMD3(0, ap.radius, 0)),
                                            v: scr(SIMD3(0, 0, ap.radius)), normal: SIMD2(n.x, -n.y) * 2 * rp * ap.radius,
                                            event: gateEvent))
                }
                let r = shipMesh?.radius ?? 0.5
                ext = 2 * (r + max(l.stretch - 1, 0)) * 1.04 + 0.04
                let d = ShipCatalog.design(o.variant)
                let glowC = ObjectSystem.glowColour(o)
                let tq = (Float(phase("\(o.id).t").truncatingRemainder(dividingBy: 1000)) * 10).rounded() / 10
                shipParams = [
                    SIMD4(R[0][0], R[1][0], R[2][0], ext), SIMD4(R[0][1], R[1][1], R[2][1], l.stretch), SIMD4(R[0][2], R[1][2], R[2][2], l.shrink),
                    // Hard light on metal: little wrap, and no more than a bright day's worth of it.
                    SIMD4(l0.dir, min(l0.wrap, 0.06)), SIMD4(shipLightColour(l0.col), gateClear),
                    SIMD4(l1.dir, min(l1.wrap, 0.1)), SIMD4(l1.col * min(1, 1.5 / max(simd_reduce_max(l1.col), 1e-3)), 0),
                    SIMD4(ambient * bright * 1.5, d?.panels ?? 40),
                    SIMD4(SIMD3(repeating: o.param("hullBright")), o.param("windows")),
                    SIMD4(glowC, o.param("glow") * o.brightness),
                    SIMD4(Float(o.seed % 1000) * 0.731, tq, l.fade, l.flash),
                ] + shipMaterialParams(o, d, look: look, cam: cam, X: X, ex: ex, ey: ey, ez: ez, pal: pal, bright: bright,
                                     lightSize: min(l0.wrap, 0.2), f: &f)
            default: continue
            }
            // Tides: close to the hole a body is pulled long along the radius (ships hold together).
            var tide = SIMD4<Float>(1, 0, 1, 0)
            if !screenPlaced && !isShip && kind != 3 {
                let s = Orbits.tide(simd_length(X))
                if s > 1.001 {
                    let rd = sp(-X / max(simd_length(X), 1e-3))
                    let flat = simd_length(SIMD2(rd.x, rd.y))
                    if flat > 0.05 {
                        let se = 1 + (s - 1) * flat
                        tide = SIMD4(rd.x / flat, rd.y / flat, se, 0)
                        ext *= se
                    }
                }
            }
            let half = rp * ext + 1.5
            let box = SIMD4(centre.x - half, centre.y - half, centre.x + half, centre.y + half)
            // Off screen? A lensed body can still show near the hole, within its Einstein radius.
            var margin: Float = 0
            if w > 0 { margin = (4 * (depth - cam.holeDepth) / (cam.holeDepth * depth)).squareRoot() * cam.r0 * cam.pxPerM }
            if box.z < -margin || box.x > W + margin || box.w < -margin || box.y > H + margin {
                if o.objectKind != .comet { continue }
            }
            let side = min(max(Int((2 * half * tileScale).rounded(.up)), 8), maxTile)
            let lights4: [SIMD4<Float>] = [SIMD4(l0.dir, l0.wrap), SIMD4(l0.col, 0), SIMD4(l1.dir, l1.wrap), SIMD4(l1.col, 0)]
            let params: [SIMD4<Float>] = shipParams ?? [
                SIMD4(kind, type, ext, Float(o.seed % 1000) * 0.731),
                // The coma ignores spin and time; leaving them out keeps its tile from redrawing every frame.
                SIMD4(bx, kind == 3 ? 0 : spin), SIMD4(by, cloud), SIMD4(bzS, kind == 3 ? 0 : time),
            ] + lights4 + [
                SIMD4(ambient + diskFill, hueRad), atm, ring, ringC, q0, q1, e, e2, tide,
            ]
            let tile = BodyTile(params: params, side: (side + 15) / 16 * 16, planet: surface, edge: pl.edge, key: o.id, radiusPx: rp, mesh: shipMesh)
            let diskPx = rp * (kind == 3 ? 0.3 : 1)
            // A ship that nothing can cover (no lens, clear of the disk) goes over the picture in path F:
            // it costs only its own pixels instead of a test in every pixel of path L's rectangle.
            var clear = false
            if isShip && w == 0 {
                let rd = look.diskOuter * cam.pxPerM * 1.3
                let rM = rp * ext / max(cam.scale(depth: depth), 1e-3)
                let above = look.inclinationDeg <= 90 ? box.w < cam.c.y : box.y > cam.c.y
                clear = depth + rM < cam.holeDepth - look.diskOuter || above || box.x > cam.c.x + rd || box.z < cam.c.x - rd
            }
            if pl.edge || clear {
                frontTiles.append((tile, [box.x, box.y, box.z, box.w]))
            } else {
                // Where its images can be: the box widened by the Einstein radius, or near the hole.
                let zb = screenPlaced ? (w > 0 ? cam.holeDepth * 2 : cam.holeDepth * 0.55) : depth
                var eR: Float = 0, reach: Float = 0, side: Float = 0
                if w > 0 {
                    let thetaE = (4 * (zb - cam.holeDepth) / (cam.holeDepth * zb)).squareRoot() * cam.r0 * cam.pxPerM * 1.15
                    // A point lens moves the primary image out by at most thetaE^2 / beta and puts the
                    // counter image that close to the hole, shrunk by about the same ratio.
                    let beta = max(simd_length(centre - cam.c) - half, 1)
                    let shift = min(thetaE, thetaE * thetaE / beta)
                    eR = shift + 4
                    reach = max(shift, cam.shadowPx * 1.4) + half * min(max(thetaE / beta, 0.15), 1) + 4
                    // Each point moves out along its own direction from the hole: across the box that turns by about
                    // half / beta, plus the stretch of the image.
                    side = eR * min(half / beta, 1) * 2 + 4
                }
                // The lens moves the main image outwards from the hole only, by up to eR.
                var od = centre - cam.c + 1e-3
                od = od / simd_length(od) * eR
                let cand = SIMD4(box.x + min(od.x, 0) - side, box.y + min(od.y, 0) - side,
                                 box.z + max(od.x, 0) + side, box.w + max(od.y, 0) + side)
                // Radius in M for round bodies on their own path: path L sorts each pixel of the sphere against the
                // disk instead of the whole body at its centre depth. Ships, comae and placed bodies keep one depth.
                let roundM: Float = !screenPlaced && (kind == 0 || kind == 1 || kind == 2) ? rp / max(cam.scale(depth: depth), 1e-3) : 0
                let ref: [SIMD4<Float>] = [box, .zero, SIMD4(w, zb, centre.x, centre.y), SIMD4(diskPx, eR, reach, roundM), cand]
                lBodies.append((ref[2].y, ref, tile))
            }

            // Star glow and spikes, comet tail: path F.
            if o.objectKind == .star {
                let T = o.param("temperature") * min(max(dop, 0.7), 1.4) * pulseT
                // Hot stars are far more luminous: a stronger glow; a brown dwarf hardly glows.
                let hb = relBright * pulseB * simd_reduce_max(tint) * min(max(T / 6000, 0.5), 2.2) * (o.variant == "brownDwarf" ? 0.4 : 1)
                let halo = ObjectSystem.nearStarColours(T, exposure: look.exposure).halo * hb
                let imgs: [(SIMD2<Float>, Float)] = (screenPlaced || w == 0) ? [(centre, Float(1))] : cam.images(X)
                // The binary's donor sits off the sprite's centre; its companion gets a small glow of its own.
                var off = SIMD2<Float>(0, 0), offB = SIMD2<Float>(0, 0)
                if kind == 4 {
                    let axis = bx * cosf(q1.w) + by * sinf(q1.w)
                    let qa: Float = 0.2 * 0.2 / (1 + 0.2 * 0.2)
                    off = SIMD2(-axis.x, axis.y) * q1.x * qa * rp
                    offB = SIMD2(axis.x, -axis.y) * q1.x * (1 - qa) * rp
                }
                for (p, mu) in imgs where mu > 0.01 {
                    addGlow(&f, at: p + off, col: halo, rhoPx: rp * 0.28, glow: o.param("glow"), mu: min(mu, 3), cam: cam,
                            behind: w > 0, spikes: Int(o.param("spikes").rounded()), seed: o.seed, reachPx: rp * 4.5, nearR: rp)
                    if kind == 4 {
                        let hc = ObjectSystem.nearStarColours(o.param("temperature2"), exposure: look.exposure).halo * hb
                        addGlow(&f, at: p + offB, col: hc, rhoPx: rp * 0.06, glow: o.param("glow") * 1.4, mu: min(mu, 3), cam: cam,
                                behind: w > 0, spikes: 0, seed: o.seed, reachPx: rp * 1.2, nearR: rp * 0.2)
                    }
                }
                if o.variant == "wolfRayet" && o.param("shellGlow") > 0 {
                    let Rs = o.param("shell") * rp * 0.45
                    let r = Rs * 1.5
                    if centre.x + r > 0, centre.x - r < W, centre.y + r > 0, centre.y - r < H {
                        push(&f, [SIMD4(centre.x - r, centre.y - r, centre.x + r, centre.y + r), SIMD4(6, 0, w > 0 ? 1 : 0, Float(o.seed % 1000) * 0.37),
                                  SIMD4(centre.x, centre.y, Rs, 0), SIMD4(SIMD3(repeating: o.param("shellGlow") * 0.5 * hb), 0), .zero, .zero])
                    }
                }
            }
            if o.objectKind == .comet {
                addTail(&f, o, pl: pl, cam: cam, rp: rp, act: cometActivity(X) * bright, holeCol: holeCol, behind: w > 0, centre: centre)
            }
            if isShip, let m = shipMesh {
                addShipLights(&f, o, mesh: m, R: shipRot, centre: centre, rp: rp, cam: cam, behind: w > 0, event: ev, bright: bright, pl: pl)
            }
        }

        // Path L: nearest eight, drawn far to near.
        lBodies.sort { $0.depth > $1.depth }
        if lBodies.count > ObjectSystem.maxL {
            lBodies = Array(lBodies.sorted { $0.depth < $1.depth }.prefix(ObjectSystem.maxL)).sorted { $0.depth > $1.depth }
        }
        var all = lBodies.map { $0.tile } + frontTiles.map { $0.0 }
        pack(&all, size: f.atlasSize)
        let inv = 1 / Float(f.atlasSize)
        for (i, b) in lBodies.enumerated() {
            let r = all[i].rect
            var ref = b.ref
            ref[1] = SIMD4((Float(r.x) + 0.5) * inv, (Float(r.y) + 0.5) * inv, (Float(r.x + r.w) - 0.5) * inv, (Float(r.y + r.h) - 0.5) * inv)
            f.refs += ref
        }
        f.lCount = lBodies.count
        f.params[1].w = Float(f.lCount)
        // Union of the regions the bodies can show in, so other pixels skip path L at once.
        var u = SIMD4<Float>(1e9, 1e9, -1e9, -1e9)
        for b in lBodies {
            let cr = b.ref[4], e = b.ref[3].y, reach = b.ref[3].z
            u = SIMD4(min(u.x, cr.x), min(u.y, cr.y), max(u.z, cr.z), max(u.w, cr.w))
            if e > 0 {
                let c = cam.c
                u = SIMD4(min(u.x, c.x - reach), min(u.y, c.y - reach), max(u.z, c.x + reach), max(u.w, c.y + reach))
            }
        }
        if f.lCount > 0 { f.params[5] = u }
        for (j, ft) in frontTiles.enumerated() {
            let r = all[lBodies.count + j].rect
            let b = ft.1
            f.front += [SIMD4(b[0], b[1], b[2], b[3]), SIMD4(0, 0, 0, 0), .zero, SIMD4(1, 1, 1, 1),
                        SIMD4((Float(r.x) + 0.5) * inv, (Float(r.y) + 0.5) * inv, (Float(r.x + r.w) - 0.5) * inv, (Float(r.y + r.h) - 0.5) * inv), .zero]
            f.frontCount += 1
        }
        f.tiles = all

        // Far stars: their camera glow and spikes, at each image under a point lens.
        if filter != .only {
            let pxA = 1 / (cam.pxPerM * cam.r0)
            for s in sky.starGlows {
                for (p, mu) in cam.skyImages(s.dir) where mu > 0.01 {
                    let rho = max(s.rho / pxA, 0.75)
                    addGlow(&f, at: p, col: s.col, rhoPx: rho, glow: s.glow, mu: min(mu, 3), cam: cam, behind: true,
                            spikes: s.spikes, seed: s.seed, reachPx: s.reach / pxA, skyDir: s.dir)
                }
            }
        }

        // Particles.
        for o in active where o.objectKind == .belt {
            let edge = o.motion.mode == .edge
            if filter == .only && !edge { continue }
            if filter == .without && edge { continue }
            if var job = particles(o, look: look, cam: cam, layout: layout, pxScale: pxScale, edgeTime: edgeTime, holeCol: holeCol) {
                if !edge { job.rect = beltRect(o, cam: cam) }
                f.parts.append(job)
            }
        }

        // Meteors.
        if transient && filter != .only {
            for o in active where o.objectKind == .meteor { addMeteors(&f, o, cam: cam) }
        }
        // Little soft light and no dust: draw it in the picture's own pass, a light pass would cost more.
        if !f.parts.contains(where: { !$0.edge }) && f.lightCount > 0 {
            var area: Float = 0
            for i in 0..<f.lightCount {
                let b = f.light[i * 6], hw = f.light[i * 6 + 1].y, kind = f.light[i * 6 + 1].x.rounded()
                // A nebula shell is soft and wide: always the light buffer, at a fraction of the resolution.
                area += kind == 6 ? 1e9 : kind == 1 ? (b.z - b.x) * (b.w - b.y) : simd_length(SIMD2(b.z - b.x, b.w - b.y)) * 2 * hw
            }
            if area < 250_000 {
                f.front = f.light + f.front
                f.frontCount += f.lightCount
                f.light = []
                f.lightCount = 0
            }
        }
        // Haze of a dust ring was drawn at half resolution; now at a quarter, with blobs as big on the screen as before.
        f.hazeScale = (f.parts.contains(where: { !$0.edge && $0.params[0].x == 1 }) ? 0.5 : 1) * 4 / f.lightScale
        if f.hasLight && !f.allFront {
            f.params[3].w = 1
            // Glows and tails in their rectangle, belts and dust rings in theirs (or anywhere if unknown).
            var r = f.lightRect
            for p in f.parts where !p.edge {
                let q = p.rect ?? SIMD4<Float>(0, 0, W, H)
                r = SIMD4(min(r.x, q.x), min(r.y, q.y), max(r.z, q.z), max(r.w, q.w))
            }
            r = SIMD4(max(r.x, 0).rounded(.down), max(r.y, 0).rounded(.down), min(r.z, W).rounded(.up), min(r.w, H).rounded(.up))
            if r.z - r.x < 2 || r.w - r.y < 2 { r = SIMD4(0, 0, 2, 2) }
            f.params[6] = r
        }
        return f
    }

    /// How strongly a comet glows: more the closer it comes to the hole.
    private func cometActivity(_ X: SIMD3<Float>) -> Float {
        min(max(powf(40 / max(simd_length(X), 4), 1.5), 0.25), 3)
    }

    /// Where a body is this frame, or nil when it is not around right now.
    func place(_ o: SpaceObject, look: Look, cam: CamFrame, layout: ScreenLayout, pxScale: Float, edgeTime: Float,
                       parent: (Placement, SpaceObject)?) -> Placement? {
        let m = o.motion
        switch m.mode {
        case .orbit:
            if o.objectKind == .moon, let (pp, po) = parent {
                let (p, v) = Orbits.kepler(m, orbits: phase("\(o.id).kep"), aScale: max(po.size, 0.1))
                var pl = Placement(world: pp.world + p, vel: pp.vel + v * 0.02)
                if let s = pp.screen {
                    // A moon of a planet that is placed on the screen circles it in the screen plane.
                    let k = pp.radiusPx / max(po.size, 0.1)
                    let off = SIMD2(simd_dot(p, cam.right), -simd_dot(p, cam.up)) * k
                    let behind = simd_dot(p, cam.fwd) > 0
                    pl.screen = s + off
                    pl.radiusPx = o.size * k
                    pl.world = cam.world(px: s + off, depth: simd_length(cam.cam(pp.world)) + (behind ? 1 : -1) * o.size)
                    pl.edge = pp.edge
                }
                return pl
            }
            var mm = m
            mm.radius = min(max(m.radius, 6), cam.r0 * 0.92)
            let mass: Float = o.objectKind == .blackHole ? 1 + max(o.size, 0.02) : 1
            let (p, v) = Orbits.kepler(mm, orbits: phase("\(o.id).kep"), centreMass: mass)
            return Placement(world: p, vel: v)
        case .flyby:
            return Orbits.flyby(m, seed: o.seed, t: phase("\(o.id).fly"), cam: cam, look: look)
        case .fixed:
            let p = SIMD2(m.x * cam.W, m.y * cam.H)
            let depth = m.depth == "behind" ? cam.holeDepth * 2 : cam.holeDepth * 0.55
            let rp = max(o.size, 1) * pxScale * 0.5
            return Placement(world: cam.world(px: p, depth: depth), screen: p, radiusPx: rp)
        case .edge:
            let rp = max(o.size, 1) * pxScale * 0.5
            guard var pl = Orbits.edge(m, seed: o.seed, t: Double(edgeTime), cam: cam, layout: layout, pxScale: pxScale, sizePx: rp)?.0
            else { return nil }
            if ObjectSystem.shipKinds.contains(o.objectKind!) {
                let b = edgeBurn(o, cam: cam, pxScale: pxScale, edgeTime: edgeTime, sizePx: rp)
                let dir: Float = pl.screenVel.x < 0 ? -1 : 1
                pl.screen!.x += dir * b.shift
                pl.screenVel.x += dir * b.dv
                pl.burn = b.burn
                pl.world = cam.world(px: pl.screen!, depth: cam.holeDepth)
            }
            return pl
        default:
            return nil
        }
    }

    // MARK: Front instances

    /// Glows, tails and smoke go to the light buffer; sprites, spikes and meteors over the picture.
    private func push(_ f: inout BodyFrame, _ v: [SIMD4<Float>]) {
        let kind = Int(v[1].x.rounded())
        if v[4].w > 0.5 || v[5].w > 0.5, kind == 1 || kind == 2 { f.needsRefine = true }
        if !f.allFront && (kind == 3 || kind == 5 || kind == 6) {
            guard f.lightCount < 512 else { return }
            f.light += v
            f.lightCount += 1
            // Its rectangle: an axis box, or a line with a half width (tails, smoke).
            let b = v[0], r = kind == 1 ? 0 : v[1].y
            let refineSlack: Float = v[4].w > 0.5 ? 80 : 0
            let e = r + refineSlack
            f.lightRect = SIMD4(min(f.lightRect.x, min(b.x, b.z) - e), min(f.lightRect.y, min(b.y, b.w) - e),
                                max(f.lightRect.z, max(b.x, b.z) + e), max(f.lightRect.w, max(b.y, b.w) + e))
        } else {
            guard f.frontCount < 512 else { return }
            f.front += v
            f.frontCount += 1
        }
    }

    /// Glow (and spikes) around one image of a star. Hidden where the shadow or the disk covers the image.
    private func addGlow(_ f: inout BodyFrame, at p: SIMD2<Float>, col: SIMD3<Float>, rhoPx: Float, glow: Float, mu: Float,
                         cam: CamFrame, behind: Bool, spikes: Int, seed: UInt32, reachPx: Float? = nil, skyDir: SIMD3<Float>? = nil,
                         nearR: Float = 0) {
        let refine = skyDir.map { SIMD4($0, 1) } ?? .zero
        let dist = simd_length(p - cam.c)
        if behind && dist < cam.shadowPx * 1.03 { return }
        if glow > 0 {
            let reach = min(reachPx ?? rhoPx * 60, rhoPx * 70)
            let r = reach
            guard p.x + r > 0, p.x - r < cam.W, p.y + r > 0, p.y - r < cam.H else { return }
            push(&f, [SIMD4(p.x - r, p.y - r, p.x + r, p.y + r), SIMD4(1, 0, behind ? 2 : 0, 0), SIMD4(p.x, p.y, rhoPx, glow),
                      SIMD4(col, 0), refine, SIMD4(reach, mu, nearR, 0)])
        }
        if spikes > 0 {
            let fade = behind ? min(max((dist / cam.shadowPx - 3), 0), 1) : 1
            guard fade > 0 else { return }
            let lum = simd_dot(col, SIMD3(0.2126, 0.7152, 0.0722)) * mu
            let L = min(max(rhoPx * 90 * lum.squareRoot(), 30), 700)
            let n = spikes == 1 ? 2 : spikes == 2 ? 3 : 4
            let ang0: Float = spikes == 1 ? .pi / 4 : spikes == 2 ? .pi / 2 : 0
            let w = max(rhoPx * 0.5, 0.7)
            // One thin quad per line through the image.
            for k in 0..<n {
                let a = ang0 + .pi * Float(k) / Float(n)
                let d = SIMD2(cosf(a), sinf(a)) * L
                push(&f, [SIMD4(p.x - d.x, p.y - d.y, p.x + d.x, p.y + d.y), SIMD4(2, w * 5 + 2, behind ? 2 : 0, 0), SIMD4(p.x, p.y, 0, 0),
                          SIMD4(col * 0.18 * fade * mu.squareRoot(), 0), SIMD4(1, a, L, w), refine])
            }
        }
    }

    /// The material half of ShipP: the frame for the sky lookup with the sliders, the disk as seen from the ship,
    /// the design's hull finish. Also asks for the sky the ships mirror.
    private func shipMaterialParams(_ o: SpaceObject, _ d: ShipDesign?, look: Look, cam: CamFrame, X: SIMD3<Float>,
                                    ex: SIMD3<Float>, ey: SIMD3<Float>, ez: SIMD3<Float>, pal: [SIMD3<Float>], bright: Float,
                                    lightSize: Float, f: inout BodyFrame) -> [SIMD4<Float>] {
        if f.shipEnv == nil { f.shipEnv = ShipMaterials.sky(look) }
        func sp(_ v: SIMD3<Float>) -> SIMD3<Float> { SIMD3(simd_dot(v, ex), simd_dot(v, ey), simd_dot(v, ez)) }
        // Rows of sprite -> camera frame (the frame of the escape directions and the nebula).
        let rows = [cam.right, cam.up, cam.fwd].map { SIMD3(simd_dot(ex, $0), simd_dot(ey, $0), simd_dot(ez, $0)) }
        func grad(_ t: Float) -> SIMD3<Float> {
            let x = min(max(t, 0), 1) * 4
            let i = min(Int(x), 3)
            return simd_mix(pal[i], pal[i + 1], SIMD3(repeating: x - Float(i)))
        }
        func norm(_ c: SIMD3<Float>) -> SIMD3<Float> { c / max(simd_dot(c, SIMD3(0.2126, 0.7152, 0.0722)), 1e-3) }
        let disk = look.diskBrightness * bright
        let inner = simd_mix(norm(grad(0.95)), SIMD3(repeating: 1), SIMD3(repeating: 0.35)) * disk * 1.3
        let outer = simd_mix(norm(grad(0.45)), SIMD3(repeating: 1), SIMD3(repeating: 0.2)) * disk * 0.3
        let finish = d?.finish ?? SIMD2(0.2, 0.4)
        return [
            SIMD4(rows[0], o.param("gloss")), SIMD4(rows[1], o.param("wear")), SIMD4(rows[2], o.param("reflection")),
            SIMD4(sp(-X), look.isco), SIMD4(sp(SIMD3(0, 0, 1)), look.diskOuter),
            SIMD4(inner, look.nebula * bright * 1.5), SIMD4(outer, 5.2 - 0.9 * look.spin),
            SIMD4(finish.x, finish.y, Float(abs(f.shipEnv!.key.hashValue) % 997), lightSize),
        ]
    }

    /// Light of the disk on a ship's hull: less tinted than on rock, capped so painted metal does not burn out.
    private func shipLightColour(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let lum = simd_dot(c, SIMD3(0.2126, 0.7152, 0.0722))
        let m = simd_mix(c, SIMD3(repeating: lum), SIMD3(repeating: 0.4))
        return m * min(1, 1.0 / max(simd_reduce_max(m), 1e-3))
    }

    /// Engine halos, exhaust plumes and navigation lights of a ship, and the light of a running event.
    private func addShipLights(_ f: inout BodyFrame, _ o: SpaceObject, mesh: ShipMesh, R: simd_float3x3, centre: SIMD2<Float>, rp: Float,
                               cam: CamFrame, behind: Bool, event: ShipEventNow?, bright: Float, pl: Placement? = nil) {
        var look = event?.look ?? ShipLook()
        look.plume *= 1 + 2 * (pl?.burn ?? 0)
        let glowC = ObjectSystem.glowColour(o)
        let g = o.param("glow") * o.brightness
        let t = Float(phase("\(o.id).t").truncatingRemainder(dividingBy: 1000))
        let k = look.shrink
        func px(_ p: SIMD3<Float>) -> SIMD2<Float> {
            let s = R * (p * 2 * k)
            return centre + SIMD2(s.x, -s.y) * rp
        }
        let fwd = R * SIMD3<Float>(1, 0, 0)
        var f2 = SIMD2(fwd.x, -fwd.y)
        f2 = simd_length(f2) > 1e-4 ? simd_normalize(f2) : SIMD2(1, 0)
        if look.visible && look.fade > 0.02 {
            for (i, m) in mesh.data.markers.enumerated() {
                let p = px(m.p)
                switch m.kind {
                case .engine:
                    guard g > 0 else { continue }
                    let rho = max(m.r * 0.7 * rp * k, 0.6)
                    let col = (m.col ?? glowC) * g * 0.9 * look.fade * look.plume
                    addGlow(&f, at: p, col: col, rhoPx: rho, glow: 1, mu: 1, cam: cam, behind: behind, spikes: 0, seed: o.seed, reachPx: rho * 16)
                case .plume:
                    guard g > 0 else { continue }
                    let d = R * m.dir
                    var d2 = SIMD2(d.x, -d.y)
                    let flat = simd_length(d2)
                    guard flat > 0.05 else { continue }
                    d2 /= flat
                    let L = m.len * 2 * rp * k * flat * look.plume
                    let w = max(m.r * 2 * rp * k, 0.8)
                    let e = p + d2 * L
                    let col = (m.col ?? glowC) * g * look.fade
                    push(&f, [SIMD4(p.x - d2.x * w, p.y - d2.y * w, e.x, e.y), SIMD4(8, w * 3, behind ? 1 : 0, Float(o.seed % 100)),
                              SIMD4(p.x, p.y, e.x, e.y), SIMD4(col, min(look.plume, 3)), SIMD4(d2.x, d2.y, L, w), SIMD4(t, 0, 0, 0)])
                case .nav:
                    // Blinking: short flashes, port and starboard in turn.
                    let ph = (t * 0.8 + Float(i) * 0.37).truncatingRemainder(dividingBy: 1)
                    let on: Float = ph < 0.12 ? 1 : 0.15
                    let rho = max(rp * 0.012, 0.7)
                    addGlow(&f, at: p, col: (m.col ?? SIMD3(1, 1, 1)) * on * 1.6 * look.fade, rhoPx: rho, glow: 1, mu: 1, cam: cam,
                            behind: behind, spikes: 0, seed: o.seed, reachPx: rho * 14)
                }
            }
        }
        // Thrusters: short puffs on the side away from the turn while the path bends hard.
        if let pl, pl.edge, look.visible, look.fade > 0.02 {
            let v = pl.screenVel, a = pl.screenAcc
            let vl = max(simd_length(v), 1)
            let lat = (v.x * a.y - v.y * a.x) / vl
            let on = min(max(abs(lat) / 30 - 0.35, 0), 1)
            let pulse = (t * 2.7 + Float(o.seed % 13) * 0.1).truncatingRemainder(dividingBy: 1)
            if on > 0, pulse < 0.22 {
                let n = SIMD2(-v.y, v.x) / vl * (lat > 0 ? -1 : 1)
                let rho = max(rp * 0.03, 0.7)
                for s in [Float(-0.45), 0.4] {
                    let p = centre + SIMD2(v.x, v.y) / vl * rp * s + n * rp * 0.42
                    addGlow(&f, at: p, col: SIMD3(0.85, 0.9, 1.0) * 1.6 * on * look.fade, rhoPx: rho, glow: 1, mu: 1, cam: cam,
                            behind: behind, spikes: 0, seed: o.seed, reachPx: rho * 10)
                }
            }
        }
        guard let ev = event else { return }
        // The event's own light: streaks, flash, ring, vortex, shimmer, sparkle or light tunnel.
        var fx = ev.spec.fx
        guard fx != 7 && fx < 9 else { return }
        // Into a wormhole: a flash and a ring where the ship vanishes.
        var phase = ev.arrival ? 1 - ev.phase : ev.phase
        if fx == 8 { fx = 2; phase *= 0.5 }
        let R0 = rp * k
        // Where the ship rests: the event shifts it along its nose, `fs` ship lengths per unit on the screen.
        let fs = SIMD2(fwd.x, -fwd.y) * 2 * rp
        let rest = centre - fs * look.shift
        // An arrival's streaks and vortex lie behind the ship, a departure's ahead of it.
        let back: Float = ev.arrival ? -1 : 1
        if ev.arrival && (fx <= 1 || fx == 3) { f2 = -f2 }
        var c = centre
        // Half size of the quad; the light fades to zero inside it (shipEventLight), so no edge shows.
        var reach = rp * 2.5
        switch fx {
        case 0, 1: c = centre + f2 * rp; reach = rp * 24
        // The vortex stays where it opened, 0.9 ship lengths ahead of (arrival: behind) the resting ship;
        // the ship flies into it, or comes out of it. Before it moved along with the ship.
        case 3: c = rest + fs * 0.9 * back; reach = rp * 3.6
        case 2: reach = rp * 3.4
        case 6: reach = rp * 7.5
        default: break
        }
        let a = c - f2 * reach, b = c + f2 * reach
        push(&f, [SIMD4(a.x, a.y, b.x, b.y), SIMD4(7, reach, behind ? 1 : 0, Float(o.seed % 100)),
                  SIMD4(c.x, c.y, max(R0, rp * 0.3), Float(fx)), SIMD4(ev.spec.col * min(bright, 2), phase),
                  SIMD4(f2.x, f2.y, ev.spec.rainbow ? 1 : 0, ev.arrival ? 1 : 0), SIMD4(rp, 0, 0, 0)])
    }

    /// Ion tail straight away from the light, dust tail bent back along the orbit.
    private func addTail(_ f: inout BodyFrame, _ o: SpaceObject, pl: Placement, cam: CamFrame, rp: Float, act: Float,
                         holeCol: SIMD3<Float>, behind: Bool, centre: SIMD2<Float>) {
        let X = pl.world
        let anti = simd_normalize(X + SIMD3(0, 0, 1e-4))
        let L = o.param("tailLength") * min(act, 1.6).squareRoot()
        var v = pl.vel
        if simd_length(v) < 1e-5 { v = simd_cross(SIMD3(0, 0, 1), anti) }
        let vh = simd_normalize(v - anti * simd_dot(v, anti) + SIMD3(1e-5, 0, 0))
        func proj(_ Y: SIMD3<Float>) -> SIMD2<Float> {
            if let s = pl.screen {
                // Screen-placed comets: the tail points away from the hole on the screen.
                let away = simd_normalize(s - cam.c + SIMD2(1e-3, 0))
                let d = Y - X
                let k = cam.pxPerM * 0.3
                let along = simd_dot(d, anti), side = simd_dot(d, vh)
                return s + away * along * k + SIMD2(-away.y, away.x) * side * k
            }
            let q = cam.cam(Y)
            return cam.px(dir: SIMD3(q.x, q.y, max(q.z, 0.5)))
        }
        let N = centre
        let ion = proj(X + anti * L)
        let dEnd = proj(X + (anti * 0.8 - vh * 0.5) * L * 0.85)
        let ctrl = proj(X + anti * L * 0.42)
        let Lpx = max(simd_length(ion - N), simd_length(dEnd - N))
        let headW = max(rp * 0.6, 1.2)
        let ionW = headW + Lpx * 0.035
        let dustW = headW * 1.4 + Lpx * 0.16
        let green = o.variant == "green"
        let ionC = (green ? SIMD3<Float>(0.30, 0.65, 1.0) : SIMD3(0.35, 0.55, 1.0)) * o.param("ionTail") * act * 0.22
        let dust = o.param("dustTail") * act * 0.16 * simd_reduce_max(holeCol) * o.brightness
        // An oriented quad along the tails: from just behind the nucleus past the farthest end,
        // wide enough for both tails.
        let far = simd_length(ion - N) > simd_length(dEnd - N) ? ion : dEnd
        var axis = far - N
        let len = max(simd_length(axis), 1)
        axis /= len
        let nrm = SIMD2(-axis.y, axis.x)
        var half: Float = headW * 3
        for p in [ion, dEnd, ctrl] { half = max(half, abs(simd_dot(p - N, nrm)) + dustW * 2) }
        let s0 = N - axis * headW * 3, s1 = far + axis * dustW
        let box = SIMD4(s0.x, s0.y, s1.x, s1.y)
        let t = Float(phase("\(o.id).t").truncatingRemainder(dividingBy: 1000))
        push(&f, [box, SIMD4(3, half, behind ? 1 : 0, Float(o.seed % 100)), SIMD4(N.x, N.y, ion.x, ion.y),
                  SIMD4(ionC, headW), SIMD4(dEnd.x, dEnd.y, ionW, dustW), SIMD4(ctrl.x, ctrl.y, dust, t)])
    }

    /// Meteors that are alight right now: slots of 60/rate seconds, one meteor per slot at a hashed time.
    private func addMeteors(_ f: inout BodyFrame, _ o: SpaceObject, cam: CamFrame) {
        let t = phase("\(o.id).t")
        let W = cam.W, H = cam.H
        let hue = o.param("hue")
        let base = simd_mix(SIMD3<Float>(repeating: 1), ObjectSystem.hueColour(hue, sat: 0.55), SIMD3(repeating: 0.55)) * o.brightness
        let fire = o.variant == "fireball", shower = o.variant == "shower"
        var rate = Double(max(o.param("rate"), 0.05))
        var tt = t
        if shower {
            let burst = Double(max(o.param("burst"), 1)), cycle = burst + Double(max(o.param("pause"), 0))
            let k = floor(t / cycle)
            tt = t - k * cycle
            guard tt < burst + 3 else { return }
            tt += k * 1000
            rate = Double(o.param("rate"))
        }
        let slot = 60 / rate
        let k0 = Int(floor(tt / slot))
        for k in (k0 - 3)...k0 {
            guard k >= 0 else { continue }
            func h(_ i: Int) -> Float { ObjectSystem.hash(o.seed &+ 11, k * 13 + i) }
            let dur = Double(fire ? 1.4 + 1.2 * h(1) : 0.35 + 0.55 * h(1)) / Double(max(o.param("flySpeed") == 0 ? 1 : o.param("flySpeed"), 0.2))
            let start = (Double(k) + Double(h(0)) * 0.6) * slot
            let smoke = fire ? Double(o.param("smoke")) : 0
            let tl = tt - start
            guard tl >= 0, tl <= dur + smoke else { continue }
            if shower && start - floor(start / 1000) * 1000 > Double(o.param("burst")) { continue }
            let trail = o.param("trail") * H
            var p0 = SIMD2(W * (0.05 + 0.9 * h(2)), H * (0.05 + 0.6 * h(3)))
            var dir: SIMD2<Float>
            if shower {
                let rad = SIMD2(o.param("radiantX") * W, o.param("radiantY") * H)
                let a = h(4) * 2 * .pi
                p0 = rad + SIMD2(cosf(a), sinf(a)) * H * (0.08 + 0.5 * h(5))
                dir = simd_normalize(p0 - rad)
            } else {
                let a = (0.15 + 0.7 * h(4)) * .pi   // mostly downwards
                dir = SIMD2(cosf(a) * (h(6) < 0.5 ? 1 : -1), sinf(a))
            }
            let travel = trail * 1.3
            let u = Float(min(tl / dur, 1))
            // Air drag: fast at first, slower towards the end (a fireball brakes harder).
            let drag: Float = fire ? 0.5 : 0.35
            let s = u + drag * u * (1 - u)
            // The hole bends the path a little towards itself, more the closer it passes.
            let hd = cam.c - p0
            var bendN = hd - dir * simd_dot(hd, dir)
            bendN = simd_length(bendN) > 1e-3 ? simd_normalize(bendN) : .zero
            let bendEnd = min(travel * travel * cam.shadowPx * 0.8 / max(simd_length_squared(hd), 9 * cam.shadowPx * cam.shadowPx), travel * 0.12)
            func at(_ q: Float) -> SIMD2<Float> { p0 + dir * travel * q + bendN * bendEnd * q * q }
            let head = at(s)
            let tail = at(max(s - trail / travel, 0))
            dir = simd_normalize(dir + bendN * 2 * bendEnd * s / travel)
            let wid: Float = fire ? 2.4 : 1.3
            // Light curve: flares up, peaks late as the air thickens, a fireball ends in a burst.
            let peak = 0.5 + 0.8 * expf(-powf((u - 0.7) / 0.2, 2)) + (fire ? 1.5 * expf(-powf((u - 0.86) / 0.05, 2)) : 0)
            let life = Float(smoothstepD(0, 0.12, Double(u)) * (1 - smoothstepD(0.88, 1, Double(u))))
            let col = base * (fire ? 6 : 3) * (0.6 + 0.8 * h(7)) * peak
            if tl <= dur {
                let pad = wid * 14
                let h0 = head + dir * pad, t0 = tail - dir * pad
                push(&f, [SIMD4(h0.x, h0.y, t0.x, t0.y), SIMD4(4, pad, 0, Float(k % 97)), SIMD4(head.x, head.y, tail.x, tail.y), SIMD4(col, life),
                          SIMD4(wid, 0, 0, 0), .zero])
                // A fireball breaks up near its end.
                if fire && s > 0.6 {
                    let n = Int(o.param("fragments").rounded())
                    for j in 0..<n {
                        let off = (s - 0.6) / 0.4
                        let side = (Float(j) - Float(n - 1) / 2) * 0.07 + (h(20 + j) - 0.5) * 0.05
                        let fd = simd_normalize(dir + SIMD2(-dir.y, dir.x) * side)
                        let fh = head + fd * travel * 0.12 * off * (0.6 + 0.6 * h(30 + j))
                        let ft = fh - fd * travel * 0.08 * off
                        let fb = SIMD4(fh.x + fd.x * 8, fh.y + fd.y * 8, ft.x - fd.x * 8, ft.y - fd.y * 8)
                        push(&f, [fb, SIMD4(4, 8, 0, 0), SIMD4(fh.x, fh.y, ft.x, ft.y), SIMD4(col * 0.5, life * (1 - off * 0.5)),
                                  SIMD4(1.0, 0, 0, 0), .zero])
                    }
                }
            }
            if fire && smoke > 0 {
                let age = max(tl - dur * 0.3, 0)
                let fadeS = Float(max(1 - age / (smoke + dur * 0.7), 0))
                let e0 = p0, e1 = head
                let sw = (4 + 6 * Float(age)) * 2.5 * 3
                push(&f, [SIMD4(e1.x, e1.y, e0.x, e0.y), SIMD4(5, sw, 0, Float(k % 97)), SIMD4(e1.x, e1.y, e0.x, e0.y),
                          SIMD4(SIMD3(0.35, 0.38, 0.45) * 0.08, fadeS * fadeS), SIMD4(4 + 6 * Float(age), 0, 0, 0), .zero])
            }
        }
    }

    private func smoothstepD(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    // MARK: Particles

    private func particles(_ o: SpaceObject, look: Look, cam: CamFrame, layout: ScreenLayout, pxScale: Float, edgeTime: Float,
                           holeCol: SIMD3<Float>) -> PartJob? {
        let rt = Int(o.param("rockType").rounded())
        let albedo: [SIMD3<Float>] = [SIMD3(0.16, 0.15, 0.14), SIMD3(0.34, 0.30, 0.25), SIMD3(0.38, 0.37, 0.36), SIMD3(0.62, 0.68, 0.74)]
        var alb = albedo[min(max(rt, 0), 3)]
        let m = o.motion
        let az = Orbits.planeNormal(m)
        let node = m.node * .pi / 180
        let ax = SIMD3<Float>(cosf(node), sinf(node), 0)
        let ay = simd_cross(az, ax)
        let clock = Float(phase("\(o.id).belt").truncatingRemainder(dividingBy: 2 * .pi * 1024))
        let seed = Float(o.seed % 1000)
        let light = holeCol * 2.6 * o.brightness
        switch o.variant {
        case "stream":
            guard m.mode == .edge else { return nil }
            let top = m.edge == "top"
            let line = Orbits.edgeLine(top: top, cam: cam, layout: layout, pxScale: pxScale)
            let speed = m.edgeSpeed * pxScale * (m.direction == "left" ? -1 : 1)
            let count = Int(o.param("count"))
            return PartJob(params: [
                SIMD4(2, Float(count), seed, 0), .zero, .zero, .zero, .zero,
                SIMD4(o.param("sizeMin"), o.param("sizeMax"), 0, look.isco), SIMD4(alb, look.spin),
                SIMD4(light * 0.5, 1), SIMD4(line, top ? 1 : -1, speed, o.param("spread") * pxScale),
                SIMD4(edgeTime, m.offset * pxScale, m.wobble * 10 * pxScale, 0),
            ], count: count, edge: true)
        case "dust":
            let hue = o.param("hue")
            alb = simd_mix(SIMD3<Float>(repeating: 0.8), ObjectSystem.hueColour(hue, sat: 0.7), SIMD3(repeating: 0.6))
            let count = Int(6000 + o.param("density") * 14000)
            return PartJob(params: [
                SIMD4(1, Float(count), seed, clock),
                SIMD4(o.param("rInner"), max(o.param("rOuter"), o.param("rInner") + 1), o.param("thickness") * .pi / 180, 0),
                SIMD4(ax, 0), SIMD4(ay, 0), SIMD4(az, 0),
                SIMD4(0.8, 2.2, 0.35 + 0.65 * o.param("density"), look.isco), SIMD4(alb, look.spin),
                SIMD4(light * 0.7, 1), .zero, .zero,
            ], count: count, edge: false)
        default:
            let count = Int(o.param("count"))
            return PartJob(params: [
                SIMD4(0, Float(count), seed, clock),
                SIMD4(o.param("rInner"), max(o.param("rOuter"), o.param("rInner") + 1), o.param("thickness") * .pi / 180, o.param("clumping")),
                SIMD4(ax, 0), SIMD4(ay, 0), SIMD4(az, 0),
                SIMD4(o.param("sizeMin"), max(o.param("sizeMax"), o.param("sizeMin")), o.param("dustGlow"), look.isco), SIMD4(alb, look.spin),
                SIMD4(light, 1), .zero, .zero,
            ], count: count, edge: false)
        }
    }

    /// Where the haze of a belt or dust ring can be on the screen: the ring's outline at both edges and
    /// thicknesses, widened by the largest haze blob, and the hole for the counter images. Nil when part
    /// of the ring is behind the camera.
    private func beltRect(_ o: SpaceObject, cam: CamFrame) -> SIMD4<Float>? {
        let m = o.motion
        let az = Orbits.planeNormal(m)
        let node = m.node * .pi / 180
        let ax = SIMD3<Float>(cosf(node), sinf(node), 0)
        let ay = simd_cross(az, ax)
        let rin = o.param("rInner"), rout = max(o.param("rOuter"), rin + 1)
        let th = tanf(max(o.param("thickness"), 0) * .pi / 180 * 2.5)
        var r = SIMD4<Float>(1e9, 1e9, -1e9, -1e9)
        for k in 0..<72 {
            let a = Float(k) / 72 * 2 * .pi
            for rad in [rin, rout] {
                for z in [-th * rad, th * rad] {
                    let p = (ax * cosf(a) + ay * sinf(a)) * rad + az * z
                    let q = cam.cam(p)
                    guard q.z > 1 else { return nil }
                    let s = cam.px(dir: q)
                    r = SIMD4(min(r.x, s.x), min(r.y, s.y), max(r.z, s.x), max(r.w, s.y))
                }
            }
        }
        let e: Float = 260
        let c = cam.c, h = cam.shadowPx * 3
        return SIMD4(min(r.x - e, c.x - h), min(r.y - e, c.y - h), max(r.z + e, c.x + h), max(r.w + e, c.y + h))
    }

    // MARK: Rows of the band objects

    /// Rows (from the top) the band objects can reach, per band, for the strips of edges-only mode.
    static func edgeRows(look: Look, layout: ScreenLayout, height: Int, pxScale: Float) -> (top: (Int, Int)?, bottom: (Int, Int)?) {
        var top: (Float, Float)?, bottom: (Float, Float)?
        let cam = CamFrame(look: look, layout: layout, width: 100, height: height)
        for o in look.objects.active where o.motion.mode == .edge {
            let m = o.motion
            let off = m.offset * pxScale
            var r: Float
            if o.objectKind == .belt {
                r = o.param("spread") * pxScale * 1.6 + o.param("sizeMax") + m.wobble * 10 * pxScale
            } else {
                r = max(o.size, 1) * pxScale * 0.5
                if o.objectKind == .planet && o.param("rings") > 0.5 { r *= max(o.param("ringOuter"), 1) * 1.05 }
                if o.objectKind == .planet || o.objectKind == .moon { r *= 1.2 }
                if o.objectKind == .comet { r *= 2.6 }
                if o.objectKind == .star { r *= 2.2 }
                r += m.wobble * 17 * pxScale
            }
            let inPic = off + r + 4, inBar = max(r - off, 0) + 4
            for isTop in m.edge == "both" ? [true, false] : [m.edge == "top"] {
                let line = Orbits.edgeLine(top: isTop, cam: cam, layout: layout, pxScale: pxScale)
                let span = isTop ? (max(line - inBar, 0), min(line + inPic, Float(height)))
                                 : (max(line - inPic, 0), min(line + inBar, Float(height)))
                if isTop { top = top.map { (min($0.0, span.0), max($0.1, span.1)) } ?? span }
                else { bottom = bottom.map { (min($0.0, span.0), max($0.1, span.1)) } ?? span }
            }
        }
        func i(_ s: (Float, Float)?) -> (Int, Int)? { s.map { (Int($0.0.rounded(.down)), Int($0.1.rounded(.up))) } }
        return (i(top), i(bottom))
    }

    // MARK: Atlas packing

    /// Shelf packer; tiles shrink until all fit.
    private func pack(_ tiles: inout [BodyTile], size: Int) {
        var scale: Float = 1
        for _ in 0..<8 {
            let order = tiles.indices.sorted { tiles[$0].side != tiles[$1].side ? tiles[$0].side > tiles[$1].side : tiles[$0].key < tiles[$1].key }
            var x = 0, y = 0, shelf = 0
            var ok = true
            for i in order {
                let s = max(Int(Float(tiles[i].side) * scale), 8)
                if x + s > size { x = 0; y += shelf + 1; shelf = 0 }
                if y + s > size { ok = false; break }
                tiles[i].rect = (x, y, s, s)
                x += s + 1
                shelf = max(shelf, s)
            }
            if ok { return }
            scale *= 0.8
        }
    }

    // MARK: Colour helpers

    static func hueColour(_ hue: Float, sat: Float) -> SIMD3<Float> {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        func f(_ n: Float) -> Float {
            let k = (n + h).truncatingRemainder(dividingBy: 6)
            return 1 - sat * max(min(min(k, 4 - k), 1), 0)
        }
        let c = SIMD3(f(5), f(3), f(1))
        return SIMD3(powf(c.x, 2.2), powf(c.y, 2.2), powf(c.z, 2.2))
    }

    /// Display colour (sRGB) of a near star's disc centre by temperature: a little more saturated than
    /// a blackbody, so M stars read orange-red and O stars blue-white after tone mapping.
    static let nearStarTable: [(Float, SIMD3<Float>)] = [
        (1300, SIMD3(0.52, 0.10, 0.06)), (2000, SIMD3(0.82, 0.22, 0.07)), (2800, SIMD3(0.98, 0.36, 0.10)),
        (3300, SIMD3(1.00, 0.45, 0.13)), (4000, SIMD3(1.00, 0.58, 0.22)), (4600, SIMD3(1.00, 0.69, 0.34)),
        (5300, SIMD3(1.00, 0.81, 0.50)), (5800, SIMD3(1.00, 0.89, 0.64)), (6900, SIMD3(1.00, 0.95, 0.84)),
        (8000, SIMD3(0.94, 0.96, 1.00)), (10000, SIMD3(0.84, 0.90, 1.00)), (15000, SIMD3(0.78, 0.86, 1.00)),
        (25000, SIMD3(0.72, 0.82, 1.00)), (40000, SIMD3(0.68, 0.79, 1.00)),
    ]

    static func nearStarDisplay(_ T: Float) -> SIMD3<Float> {
        let t = nearStarTable
        let lt = logf(max(T, 1))
        if lt <= logf(t[0].0) { return t[0].1 }
        for i in 1..<t.count where lt <= logf(t[i].0) {
            let a = logf(t[i - 1].0), b = logf(t[i].0)
            return simd_mix(t[i - 1].1, t[i].1, SIMD3(repeating: (lt - a) / (b - a)))
        }
        return t[t.count - 1].1
    }

    /// Inverse of the ACES curve in the shaders, per channel.
    static func acesInverse(_ y: Float) -> Float {
        let y = min(max(y, 0), 0.99)
        let a = 2.51 - 2.43 * y, b = 0.03 - 0.59 * y, c = -0.14 * y
        return (-b + (b * b - 4 * a * c).squareRoot()) / (2 * a)
    }

    /// Linear colours of a near star: disc centre, limb (cooler and redder) and the glow around it.
    /// Set so the centre comes out of the tone mapping at its display colour, just under white.
    static func nearStarColours(_ T: Float, exposure: Float) -> (centre: SIMD3<Float>, limb: SIMD3<Float>, halo: SIMD3<Float>) {
        func lin(_ d: SIMD3<Float>, _ k: Float) -> SIMD3<Float> {
            let e = max(exposure, 0.05)
            return SIMD3(acesInverse(powf(d.x * k, 2.2)), acesInverse(powf(d.y * k, 2.2)), acesInverse(powf(d.z * k, 2.2))) / e
        }
        let c = nearStarDisplay(T)
        let l = nearStarDisplay(T * 0.7)
        // Glow: the colour of the disc, more saturated; hot stars get a bluish corona.
        var h = SIMD3(powf(c.x, 2.2), powf(c.y, 2.2), powf(c.z, 2.2))
        let lum = simd_dot(h, SIMD3(0.2126, 0.7152, 0.0722))
        h = simd_max(SIMD3(repeating: lum) + (h - lum) * 1.5, .zero)
        if T > 9000 { h = simd_mix(h, SIMD3(0.35, 0.55, 1.0), SIMD3(repeating: min((T - 9000) / 15000, 1) * 0.6)) }
        h /= max(simd_reduce_max(h), 1e-3)
        return (lin(c, 0.95), lin(l, 0.95), h)
    }

    static func rotateHue(_ c: SIMD3<Float>, _ a: Float) -> SIMD3<Float> {
        guard a != 0 else { return c }
        let k = SIMD3<Float>(repeating: 0.57735)
        let ca = cosf(a)
        return c * ca + simd_cross(k, c) * sinf(a) + k * simd_dot(k, c) * (1 - ca)
    }
}
