import Foundation
import Metal
import simd

/// Second holes, wormholes and gates as lenses in the picture (stage 4). Each lens bends the rays of the
/// pixels around it before (in front of the hole plane) or after the hole does (behind it), and adds what it
/// shows itself. A second hole has its own small ray map, traced once for its shape, used at any distance.
struct LensFrame {
    /// LensObj (`stride` float4) per lens; behind the hole plane first, then in front far ones first.
    var data: [SIMD4<Float>] = []
    var count = 0
    /// Small ray maps of the holes, per slot.
    var maps: [HoleMapSpec?] = [nil, nil]
    /// Screen centres of the wormholes (px), for ships that fly through.
    var wormholes: [SIMD2<Float>] = []
    /// lensA, appended to FrameParams.
    var params: SIMD4<Float> { SIMD4(Float(count), 0, 0, 0) }
    static let stride = 13
    /// Lenses in front of the hole plane: their light is drawn over the picture (lensFrontFrag).
    var frontCount: Int { (0..<count).filter { data[$0 * LensFrame.stride].w < 0.5 }.count }
    var behindCount: Int { count - frontCount }
    /// Lenses that bend rays (holes, wormholes); gates only add their light and need no lens passes.
    var bendCount: Int { (0..<count).filter { data[$0 * LensFrame.stride].x < 2.5 }.count }
}

/// What a second hole's ray map is traced for. Equal specs share one map.
struct HoleMapSpec: Equatable {
    var geo: [SIMD4<Float>]     // GeoParams
    var res: Int
    var jet: Bool
    var key: String { "hole \(res) \(jet) \(geo)" }
}

/// A gate station seen this frame (from the body pass): its ring on the screen and its event.
struct GateView {
    var object: SpaceObject
    var centre: SIMD2<Float>
    var u: SIMD2<Float>, v: SIMD2<Float>      // half axes of the ring's inside on the screen (px)
    var normal: SIMD2<Float>                  // the ring's axis on the screen, towards you, px per inner radius
    var event: ShipEventNow?
}

extension ObjectSystem {
    static let maxLenses = 2
    static let maxHoles = 2
    /// Camera distance the hole maps are traced for (M of that hole): far enough to stand for any distance.
    static let holeMapR0: Float = 400

    private static func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Clocks of a second hole or wormhole: body motion, disk, jet knots.
    func lensRates(_ o: SpaceObject, look: Look, sp: Double) -> [(String, Double)] {
        var out = bodyRates(o, look: look, sp: sp)
        if o.objectKind == .blackHole {
            out.append(("\(o.id).disk", 2 * .pi / Double(max(o.param("diskPeriod"), 0.5)) * sp))
            out.append(("\(o.id).kf", 1 / 0.1 / 24 * sp))
            out.append(("\(o.id).kb", 1 / 0.1 / 24 * 0.4 * sp))
        }
        return out
    }

    /// Holes and wormholes of this frame. Gates come later from the body pass (addGates).
    func lenses(look: Look, layout: ScreenLayout, width: Int, height: Int, pxScale: Float) -> LensFrame {
        var f = LensFrame()
        let items = look.objects.active.filter { $0.objectKind == .blackHole || $0.objectKind == .wormhole }
        guard !items.isEmpty else { wormholeTargets = []; return f }
        let cam = CamFrame(look: look, layout: layout, width: width, height: height)
        var list: [(depth: Float, behind: Bool, data: [SIMD4<Float>], map: HoleMapSpec?)] = []
        var holes = 0
        for o in items {
            if o.objectKind == .blackHole && holes >= ObjectSystem.maxHoles { continue }
            guard let (centre, depth, radiusPx) = lensPlace(o, look: look, cam: cam, pxScale: pxScale) else { continue }
            let behind = depth > cam.holeDepth
            let w = behind ? cam.lensWeight(depth: depth) : 0
            let k = behind ? 0 : min(max((cam.holeDepth - depth) / cam.holeDepth, 0), 1)
            if o.objectKind == .blackHole {
                let (data, spec) = packHole(o, look: look, cam: cam, centre: centre, depth: depth, behind: behind, weight: behind ? w : k,
                                            slot: holes)
                list.append((depth, behind, data, spec))
                holes += 1
            } else {
                let R = radiusPx
                guard R > 0.5 else { continue }
                let rot = ObjectSystem.otherRotation(o.seed)
                let data: [SIMD4<Float>] = [
                    SIMD4(2, centre.x, centre.y, behind ? 1 : 0),
                    SIMD4(R, o.param("lens") * 1.25 * R, 0, 0),
                    SIMD4(0, 0, behind ? w : k, 0),
                    .zero, .zero,
                    SIMD4(o.param("otherBright") * o.brightness, o.param("otherStars"), 0, 0),
                    .zero,
                    SIMD4(o.param("otherHue") * .pi / 180, o.param("otherSide").rounded(), o.param("rimGlow"), o.param("ripple")),
                    SIMD4(rot.columns.0, Float(phase("\(o.id).t").truncatingRemainder(dividingBy: 1000))),
                    SIMD4(rot.columns.1, 0), SIMD4(rot.columns.2, 0),
                    SIMD4(centre.x - R * 1.25, centre.y - R * 1.25, centre.x + R * 1.25, centre.y + R * 1.25),
                    SIMD4(R * 4, 0, 0, 0),
                ]
                list.append((depth, behind, data, nil))
                f.wormholes.append(centre)
            }
        }
        // Behind the plane first (order does not matter there), then in front from far to near.
        list.sort { a, b in a.behind != b.behind ? a.behind : a.depth > b.depth }
        for e in list.prefix(ObjectSystem.maxLenses) {
            f.data += e.data
            f.count += 1
            if let m = e.map { f.maps[Int(e.data[2].w)] = m }
        }
        wormholeTargets = f.wormholes
        return f
    }

    /// Where a lens object is: screen centre of its middle (px), depth along the view, and for a wormhole
    /// its radius on the screen (px). nil when it is not around (a pass between two flybys, behind the camera).
    private func lensPlace(_ o: SpaceObject, look: Look, cam: CamFrame, pxScale: Float) -> (SIMD2<Float>, Float, Float)? {
        if o.motion.mode == .fixed {
            let p = SIMD2(o.motion.x * cam.W, o.motion.y * cam.H)
            let depth = o.motion.depth == "behind" ? cam.holeDepth * 2 : cam.holeDepth * 0.55
            return (p, depth, max(o.size, 1) * pxScale * 0.5)
        }
        guard let pl = place(o, look: look, cam: cam, layout: ScreenLayout(holeX: 0.5, holeY: 0.5, topBar: 0, bottomBar: 0),
                             pxScale: pxScale, edgeTime: 0, parent: nil) else { return nil }
        let q = cam.cam(pl.world)
        guard q.z > 8 else { return nil }
        return (cam.px(dir: q), q.z, max(o.size, 0.05) * cam.scale(depth: q.z))
    }

    /// LensObj of a second hole and the ray map it needs.
    private func packHole(_ o: SpaceObject, look: Look, cam: CamFrame, centre: SIMD2<Float>, depth: Float, behind: Bool,
                          weight: Float, slot: Int) -> ([SIMD4<Float>], HoleMapSpec) {
        let mass = max(o.size, 0.02)
        let spin = min(max(o.param("spin"), 0), 0.998)
        let incl = min(max(o.param("inclination"), 1), 89) * .pi / 180
        let rOut = o.param("diskBrightness") > 0 ? o.param("diskOuter") : 0
        let jet = o.param("jet") > 0.5
        let jetL = o.param("jetLength")
        var hb = max(24, rOut * 1.15)
        if jet { hb = max(hb, jetL * 0.9) }
        hb = min(hb, 40)
        let res = quality.holeMapRes
        let r0 = ObjectSystem.holeMapR0
        let rH = 1 + (1 - spin * spin).squareRoot()
        let geo: [SIMD4<Float>] = [
            SIMD4(Float(res), Float(res), 0.5, 0.5),
            SIMD4(spin, incl, r0, 2 * hb),
            SIMD4(rOut, rH, 1, 0),
            SIMD4(0, 0, 1, 1),
        ] + (jet ? ObjectSystem.jetGeo(r0: r0, incl: incl, spin: spin, length: jetL, beta: o.param("jetBeta")) : [.zero, .zero, .zero, .zero])
        let spec = HoleMapSpec(geo: geo, res: res, jet: jet)

        var dummy = Look()
        dummy.spin = spin
        let isco = dummy.isco
        let roll = o.param("roll") * .pi / 180
        let clock = Float(phase("\(o.id).disk").truncatingRemainder(dividingBy: Double(3 * Float.pi * 64)))
        // Jet colour as the main one's default, its brightness divided by the boost at this angle.
        var jc = SIMD3<Float>(0.55, 0.72, 1.0)
        jc /= simd_dot(jc, SIMD3(0.2126, 0.7152, 0.0722))
        let b = min(o.param("jetBeta"), 0.99), cth = cosf(incl)
        func boost(_ beta: Float) -> Float { powf(1 / ((1 / (1 - beta * beta).squareRoot()) * (1 - beta * cth)), 2.7) }
        let front = 0.25 * boost(b) + 0.75 * boost(min(b, 0.3))
        let jetB: Float = jet ? o.param("jetBrightness") * o.brightness * 1.2 / max(front, 0.05) : 0
        let kf = Float(phase("\(o.id).kf").truncatingRemainder(dividingBy: 256))
        let kb = Float(phase("\(o.id).kb").truncatingRemainder(dividingBy: 256))
        let rcPx = hb * 0.98 * cam.scale(depth: depth) * mass
        // Weak-field bend at the map's edge (Schwarzschild to third order), as a shift on the screen.
        let be = hb * 0.98
        let alpha = 4 / be + 15 * .pi / (4 * be * be) + 128 / (3 * be * be * be)
        let farShift = alpha * cam.pxPerM * cam.r0
        let data: [SIMD4<Float>] = [
            SIMD4(1, centre.x, centre.y, behind ? 1 : 0),
            SIMD4(cam.scale(depth: depth) * mass, hb, r0, 2 * spin * sinf(incl)),
            SIMD4(cosf(roll), sinf(roll), weight, Float(slot)),
            SIMD4(isco, rOut, spin, look.diskBrightness * o.param("diskBrightness") * o.brightness),
            SIMD4(clock, look.diskShear, o.param("hueShift") * .pi / 180, o.param("ringGlow") * o.brightness),
            SIMD4(jc, jetB),
            SIMD4(0.4, kf, kb, 0.1),
            .zero, .zero, .zero, .zero,
            SIMD4(centre.x - rcPx - 2, centre.y - rcPx - 2, centre.x + rcPx + 2, centre.y + rcPx + 2),
            SIMD4(rcPx * quality.lensReach, farShift, rcPx, 0),
        ]
        return (data, spec)
    }

    /// GeoParams jet0...jet3 for a jet with the default shape (second holes).
    static func jetGeo(r0: Float, incl: Float, spin: Float, length: Float, beta: Float) -> [SIMD4<Float>] {
        let L = min(length, 1.5 * r0), base: Float = 3, w0: Float = 0.45, k: Float = 0.55
        let tanO = tanf(3.5 * .pi / 180)
        let zt = max(base * powf(max(k * w0 / (tanO * base), 1e-3), 1 / max(1 - k, 0.05)), base)
        return [
            SIMD4(1, max(L, base * 2), w0, k),
            SIMD4(min(beta, 0.995), 1, base, 1),
            SIMD4(max(0.6 * r0 * sinf(incl), 0.3), 0.75, min(zt, 1e4), tanO),
            SIMD4(1.5, 0.3, -shadowCentre(spin: spin, incl: incl), cosf(incl) / r0),
        ]
    }

    /// Fixed rotation of the other side's sky, from the seed.
    static func otherRotation(_ seed: UInt32) -> simd_float3x3 {
        var rng = SeedRNG(seed &+ 1234)
        let a = rng.range(0...(2 * .pi)), b = rng.range(0.4...2.6), c = rng.range(0...(2 * .pi))
        return simd_float3x3(simd_quatf(angle: a, axis: SIMD3(0, 0, 1)) * simd_quatf(angle: b, axis: SIMD3(1, 0, 0))
                             * simd_quatf(angle: c, axis: SIMD3(0, 0, 1)))
    }

    /// The gates of the body pass as lenses, after the holes and wormholes (they sit in front, near you).
    static func addGates(_ f: inout LensFrame, gates: [GateView], time: Float) {
        for g in gates where f.count < maxLenses {
            let o = g.object
            let m = simd_float2x2(columns: (g.u, g.v))
            guard abs(m.determinant) > 1 else { continue }
            let inv = m.inverse
            let rot = otherRotation(o.seed)
            var ev: Float = 0, ph: Float = 0
            if let e = g.event {
                // A kawoosh plays when the gate opens; a transit both ways.
                if e.spec.fx == 9 && !e.arrival { ev = 9; ph = e.phase }
                if e.spec.fx == 10 { ev = 10; ph = e.phase }
            }
            let radius = (simd_length(g.u) + simd_length(g.v)) / 2
            // Ring and the kawoosh plume along its axis.
            let ex = (g.u.x * g.u.x + g.v.x * g.v.x).squareRoot(), ey = (g.u.y * g.u.y + g.v.y * g.v.y).squareRoot()
            let tip = g.centre + g.normal * 1.6
            let rect = SIMD4(min(g.centre.x, tip.x) - ex - 4, min(g.centre.y, tip.y) - ey - 4,
                             max(g.centre.x, tip.x) + ex + 4, max(g.centre.y, tip.y) + ey + 4)
            f.data += [
                SIMD4(3, g.centre.x, g.centre.y, 0),
                SIMD4(inv[0][0], inv[1][0], inv[0][1], inv[1][1]),
                SIMD4(0, 0, 0, 0),
                .zero,
                SIMD4(ev, ph, Float(o.seed % 997) * 0.731, radius),
                SIMD4(o.param("otherBright") * o.brightness, 1.2, g.normal.x, g.normal.y),
                .zero,
                SIMD4(o.param("otherHue") * .pi / 180, o.param("otherSide").rounded(), 0, 0.3),
                SIMD4(rot.columns.0, time.truncatingRemainder(dividingBy: 1000)), SIMD4(rot.columns.1, 0), SIMD4(rot.columns.2, 0),
                rect, .zero,
            ]
            f.count += 1
        }
    }
}

extension GPU {
    /// Ray maps of second holes, shared by all screens with the same hole.
    func holeMaps(_ spec: HoleMapSpec, _ cmd: MTLCommandBuffer) -> [MTLTexture] {
        if let t = holeMapCache[spec.key] {
            holeMapOrder.removeAll { $0 == spec.key }
            holeMapOrder.append(spec.key)
            return t
        }
        let maps = GPU.makeMaps(spec.res, spec.res, jet: spec.jet)
        let rp = MTLRenderPassDescriptor()
        for (i, t) in maps.enumerated() {
            rp.colorAttachments[i].texture = t
            rp.colorAttachments[i].loadAction = .dontCare
            rp.colorAttachments[i].storeAction = .store
        }
        if let enc = cmd.renderEncoder(rp, "hole map") {
            enc.setRenderPipelineState(spec.jet ? geoJetPipeline : geoPipeline)
            enc.setFragmentBytes(spec.geo, length: spec.geo.count * 16, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }
        holeMapCache[spec.key] = maps
        holeMapOrder.append(spec.key)
        while holeMapOrder.count > 4 { holeMapCache[holeMapOrder.removeFirst()] = nil }
        return maps
    }
}
