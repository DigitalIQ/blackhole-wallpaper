import Foundation
import simd

/// One ship or station: where it belongs in the menu, how it looks by default and how to build it.
struct ShipDesign {
    let id: String
    let title: String
    let universe: String
    var station = false
    var events: [String] = []
    var size: Float = 4                  // length in M on an orbit
    var glowHue: Float = 210             // engines and nacelles
    var panels: Float = 50               // hull plates per length
    var windows: Float = 0.6
    var spin: Float = 0                  // stations: degrees per second about spinAxis
    var spinAxis = SIMD3<Float>(0, 0, 1)
    var yaw: Float = -32, pitch: Float = 22, roll: Float = 0
    var finish = SIMD2<Float>(0.2, 0.4)   // hull: metallic, roughness
    var wear: Float = 0.3                 // default of the slider "Abnutzung"
    let build: (inout MeshBuilder) -> Void
}

/// The sky ships mirror, per look: ShipEnvP for bakeShipEnv and a key that changes with it.
enum ShipMaterials {
    static func sky(_ look: Look) -> (key: String, params: [SIMD4<Float>]) {
        let pal = look.linearPalette
        var p = (0..<7).map { SIMD4<Float>(pal[min($0, pal.count - 1)], 0) }
        p.append(SIMD4(look.nebulaScale, look.nebulaSeed, look.nebulaSwirl, look.stars))
        let key = p.map { "\($0.x),\($0.y),\($0.z),\($0.w)" }.joined(separator: ";")
        return (key, p)
    }
}

/// A built mesh, shared by all objects of a variant (or of one model file).
final class ShipMesh {
    let key: String
    let data: MeshData
    let radius: Float
    init(key: String, data: MeshData, radius: Float) { self.key = key; self.data = data; self.radius = radius }

    /// Centre and radius of the membrane (gates), in the normalised model frame; nil without one.
    lazy var aperture: (centre: SIMD3<Float>, radius: Float)? = {
        var pts: [SIMD3<Float>] = []
        for i in stride(from: 0, to: data.v.count, by: MeshData.stride) where data.v[i].w == ShipMat.membrane.rawValue {
            pts.append(SIMD3(data.v[i].x, data.v[i].y, data.v[i].z))
        }
        guard !pts.isEmpty else { return nil }
        let c = pts.reduce(SIMD3<Float>.zero, +) / Float(pts.count)
        let r = pts.map { simd_length($0 - c) }.max() ?? 0
        return (c, r)
    }()
}

/// How one event looks: duration, effect in path F and colour.
struct ShipEventSpec {
    let id: String, title: String
    let duration: Float
    let fx: Int          // 0 warp streak, 1 hyperspace, 2 flash and ring, 3 vortex, 4 cloak, 5 sparkle, 6 light tunnel, 7 plume flare,
                         // 8 into a wormhole, 9 kawoosh and 10 transit (gates: drawn in the ring, see Lenses)
    let col: SIMD3<Float>
    var rainbow = false
}

enum ShipCatalog {
    static let eventSpecs: [ShipEventSpec] = [
        ShipEventSpec(id: "warp", title: "Warp", duration: 1.3, fx: 0, col: SIMD3(0.75, 0.88, 1.0), rainbow: true),
        ShipEventSpec(id: "hyperspace", title: "Hyperraum", duration: 1.1, fx: 1, col: SIMD3(0.78, 0.88, 1.0)),
        ShipEventSpec(id: "ftl", title: "FTL-Sprung", duration: 1.0, fx: 2, col: SIMD3(0.55, 0.75, 1.0)),
        ShipEventSpec(id: "jumppoint", title: "Sprungpunkt", duration: 2.6, fx: 3, col: SIMD3(1.0, 0.42, 0.12)),
        ShipEventSpec(id: "relay", title: "Relais-Sprung", duration: 1.3, fx: 1, col: SIMD3(0.35, 0.6, 1.0)),
        ShipEventSpec(id: "epstein", title: "Epstein-Zündung", duration: 2.2, fx: 7, col: SIMD3(0.55, 0.72, 1.0)),
        ShipEventSpec(id: "transwarp", title: "Transwarp", duration: 1.3, fx: 3, col: SIMD3(0.3, 1.0, 0.45)),
        ShipEventSpec(id: "cloak", title: "Tarnung", duration: 1.8, fx: 4, col: SIMD3(0.6, 0.9, 0.8)),
        ShipEventSpec(id: "materialize", title: "Materialisieren", duration: 3.2, fx: 5, col: SIMD3(0.75, 0.85, 1.0)),
        ShipEventSpec(id: "whirl", title: "Strudelstart", duration: 2.8, fx: 3, col: SIMD3(0.45, 0.75, 1.0)),
        ShipEventSpec(id: "emerge", title: "Auftauchen", duration: 1.8, fx: 5, col: SIMD3(0.55, 1.0, 0.8)),
        ShipEventSpec(id: "ignition", title: "Zündung", duration: 2.2, fx: 7, col: SIMD3(1.0, 0.62, 0.32)),
        ShipEventSpec(id: "fullburn", title: "Full Burn", duration: 1.8, fx: 7, col: SIMD3(1.0, 0.6, 0.3)),
        ShipEventSpec(id: "stargate", title: "Sternentor", duration: 2.8, fx: 6, col: SIMD3(1, 1, 1), rainbow: true),
        ShipEventSpec(id: "transition", title: "Transition", duration: 1.0, fx: 2, col: SIMD3(1.0, 0.95, 0.85)),
        ShipEventSpec(id: "improbability", title: "Unwahrscheinlichkeitssprung", duration: 1.8, fx: 5, col: SIMD3(1, 1, 1), rainbow: true),
        // Stage 4: into the nearest wormhole; the gates' own events play in their ring, not on the station.
        ShipEventSpec(id: "wormhole", title: "Durchs Wurmloch", duration: 3.4, fx: 8, col: SIMD3(0.75, 0.85, 1.0)),
        ShipEventSpec(id: "kawoosh", title: "Kawoosh", duration: 3.2, fx: 9, col: SIMD3(0.55, 0.78, 1.0)),
        ShipEventSpec(id: "transit", title: "Durchflug", duration: 2.6, fx: 10, col: SIMD3(0.6, 0.75, 1.0)),
    ]

    static func event(_ id: String) -> ShipEventSpec? { eventSpecs.first { $0.id == id } }

    static func design(_ id: String) -> ShipDesign? { designs.first { $0.id == id } }

    private static var cache: [String: ShipMesh] = [:]
    private static let lock = NSLock()

    /// The mesh of a ship, station or model object; built once.
    static func mesh(for o: SpaceObject) -> ShipMesh? {
        if o.objectKind == .model { return ModelStore.mesh(named: o.model) }
        lock.lock(); defer { lock.unlock() }
        if let m = cache[o.variant] { return m }
        guard let d = design(o.variant) else { return nil }
        var b = MeshBuilder()
        d.build(&b)
        var data = b.d
        let r = data.normalise()
        data.bakeOcclusion()
        data.splitTranslucent()
        let m = ShipMesh(key: "ship \(d.id)", data: data, radius: r)
        cache[d.id] = m
        return m
    }

    /// Mesh of a design without the cache, for the export test.
    static func build(_ id: String) -> MeshData? {
        guard let d = design(id) else { return nil }
        var b = MeshBuilder()
        d.build(&b)
        b.d.normalise()
        return b.d
    }

    // MARK: Colours

    static let white = SIMD3<Float>(0.80, 0.80, 0.80)
    static let grey = SIMD3<Float>(0.55, 0.56, 0.58)
    static let darkGrey = SIMD3<Float>(0.24, 0.24, 0.26)
    static let red = SIMD3<Float>(1.0, 0.12, 0.06)
    static let orange = SIMD3<Float>(1.0, 0.45, 0.12)
    static let blue = SIMD3<Float>(0.35, 0.6, 1.0)
    static let navRed = SIMD3<Float>(1.0, 0.1, 0.05)
    static let navGreen = SIMD3<Float>(0.1, 1.0, 0.25)
    static let navWhite = SIMD3<Float>(1.0, 1.0, 1.0)

    // MARK: Designs

    static let designs: [ShipDesign] = starTrek + starWars + galactica + orion + expanse + babylon5 + firefly + odyssey + interstellar + massEffect + realSpace + others

    static let starTrek: [ShipDesign] = [
        ShipDesign(id: "enterprise", title: "Enterprise NCC-1701", universe: "Star Trek", events: ["warp"], size: 4.5, glowHue: 215, panels: 46, finish: SIMD2(0.15, 0.38), wear: 0.1) { b in
            let hull = PartMat.hull(SIMD3(0.78, 0.78, 0.76), windows: 0.7)
            // Saucer: a disc with a dome and the bridge on top, around the vertical axis.
            let sx: Float = 2.75, sz: Float = 1.05
            b.lathe([(-0.10, 0), (-0.12, 0.5), (-0.09, 1.6), (-0.04, 2.15), (0.0, 2.2), (0.05, 2.1), (0.12, 1.55), (0.18, 0.9),
                     (0.22, 0.42), (0.30, 0.28), (0.34, 0.12), (0.35, 0)],
                    Xf(SIMD3(sx, 0, sz), rot: SIMD3(0, -90, 0)), seg: 56, hull)
            b.lathe([(0.0, 0), (0.06, 0.45), (0.12, 0.3), (0.16, 0)], Xf(SIMD3(sx, 0, sz - 0.12), rot: SIMD3(0, 90, 0)), seg: 32, hull)
            // Neck, slanted from under the saucer down to the secondary hull.
            b.prism([SIMD2(2.0, 1.0), SIMD2(1.15, 1.0), SIMD2(-0.2, -0.35), SIMD2(0.7, -0.35)], h: 0.34, top: 1, Xf(rot: SIMD3(90, 0, 0)), hull)
            // Secondary hull with the deflector dish in front.
            b.lathe([(-3.4, 0), (-3.4, 0.38), (-2.6, 0.5), (-0.5, 0.58), (0.6, 0.56), (1.15, 0.45), (1.25, 0.32), (1.18, 0)],
                    Xf(SIMD3(0, 0, -0.55), scale: SIMD3(1, 0.95, 1.05)), seg: 36, hull)
            b.lathe([(1.12, 0), (1.22, 0.22), (1.26, 0.3)], Xf(SIMD3(0.02, 0, -0.55)), seg: 24, caps: false, .glow(SIMD3(1.0, 0.62, 0.3), 1.2))
            b.engine(SIMD3(1.25, 0, -0.55), r: 0.08, SIMD3(1.0, 0.6, 0.3))
            b.mirrored { b, s in
                // Pylons up and out to the nacelles.
                b.beam(SIMD3(-1.9, 0.25 * s, -0.25), SIMD3(-2.5, 1.45 * s, 0.95), width: 0.75, thick: 0.12, up: SIMD3(1, 0, 0), hull)
                // Nacelles with the red Bussard collectors and blue glowing grilles.
                b.lathe([(-5.1, 0), (-5.1, 0.24), (-4.9, 0.3), (0.0, 0.3), (0.25, 0.27)], Xf(SIMD3(0, 1.55 * s, 1.05)), seg: 24, hull)
                b.ellipsoid(SIMD3(0.28, 1.55 * s, 1.05), SIMD3(0.32, 0.27, 0.27), seg: 20, .glow(SIMD3(1.0, 0.16, 0.08), 1.3))
                b.box(SIMD3(-2.4, 1.55 * s - 0.23 * s, 1.05), SIMD3(3.8, 0.06, 0.16), .engine(0.9))
                b.engine(SIMD3(0.45, 1.55 * s, 1.05), r: 0.22, SIMD3(1.0, 0.2, 0.1))
                b.nav(SIMD3(sx, 2.2 * s, sz), s > 0 ? navRed : navGreen)
            }
            b.engine(SIMD3(-3.45, 0, -0.55), r: 0.15, SIMD3(1.0, 0.4, 0.2))
        },
    
        ShipDesign(id: "enterpriseD", title: "Enterprise-D", universe: "Star Trek", events: ["warp"], size: 5.5, glowHue: 215, panels: 70, finish: SIMD2(0.15, 0.34), wear: 0.12) { b in
            let hull = PartMat.hull(SIMD3(0.70, 0.71, 0.72), windows: 0.8)
            // Wide elliptical saucer.
            b.lathe([(-0.13, 0), (-0.15, 0.5), (-0.11, 0.88), (-0.04, 1.0), (0.03, 0.99), (0.10, 0.82), (0.17, 0.45), (0.21, 0.15), (0.23, 0)],
                    Xf(SIMD3(2.0, 0, 0.55), rot: SIMD3(0, -90, 0), scale: SIMD3(1, 3.0, 2.6)), seg: 64, hull)
            b.prism([SIMD2(0.9, 0.5), SIMD2(-0.2, 0.5), SIMD2(-1.1, -0.5), SIMD2(0.2, -0.5)], h: 0.8, top: 0.8, Xf(rot: SIMD3(90, 0, 0)), hull)
            b.ellipsoid(SIMD3(-1.3, 0, -0.62), SIMD3(2.5, 0.85, 0.55), seg: 32, hull)
            b.ellipsoid(SIMD3(0.98, 0, -0.66), SIMD3(0.12, 0.42, 0.28), seg: 20, .glow(SIMD3(0.45, 0.65, 1.0), 1.2))
            b.engine(SIMD3(1.08, 0, -0.66), r: 0.1, SIMD3(0.45, 0.65, 1.0))
            b.mirrored { b, s in
                b.beam(SIMD3(-2.1, 0.6 * s, -0.7), SIMD3(-2.9, 2.2 * s, 0.05), width: 0.75, thick: 0.13, up: SIMD3(1, 0, 0), hull)
                b.lathe([(-5.3, 0), (-5.3, 0.2), (-5.1, 0.28), (0.0, 0.28), (0.3, 0.2), (0.36, 0)], Xf(SIMD3(0, 2.3 * s, 0.15), scale: SIMD3(1, 1.25, 0.75)), seg: 20, hull)
                b.ellipsoid(SIMD3(0.22, 2.3 * s, 0.15), SIMD3(0.24, 0.3, 0.19), seg: 18, .glow(SIMD3(1.0, 0.15, 0.08), 1.3))
                b.box(SIMD3(-2.5, 2.3 * s + 0.34 * s, 0.15), SIMD3(4.4, 0.04, 0.12), .engine(1))
                b.box(SIMD3(-2.5, 2.3 * s - 0.34 * s, 0.15), SIMD3(4.4, 0.04, 0.12), .engine(1))
                b.engine(SIMD3(0.4, 2.3 * s, 0.15), r: 0.16, SIMD3(1.0, 0.2, 0.1))
                b.nav(SIMD3(2.0, 3.0 * s, 0.55), s > 0 ? navRed : navGreen)
            }
        },
        ShipDesign(id: "voyager", title: "Voyager", universe: "Star Trek", events: ["warp"], size: 4, glowHue: 215, panels: 60, finish: SIMD2(0.15, 0.36), wear: 0.15) { b in
            let hull = PartMat.hull(SIMD3(0.70, 0.71, 0.72), windows: 0.8)
            let half: [SIMD2<Float>] = [SIMD2(3.0, 0), SIMD2(2.3, 0.8), SIMD2(1.2, 1.45), SIMD2(0.0, 1.6), SIMD2(-0.8, 1.2), SIMD2(-1.0, 0.4)]
            let outline = half + half.reversed().map { SIMD2($0.x, -$0.y) }.filter { $0.y != 0 }
            b.prism(outline, h: 0.45, top: 0.82, bottom: 0.9, Xf(SIMD3(0, 0, 0.3)), hull)
            b.ellipsoid(SIMD3(1.0, 0, 0.55), SIMD3(0.5, 0.45, 0.14), seg: 20, hull)
            b.ellipsoid(SIMD3(-1.7, 0, -0.05), SIMD3(2.1, 0.8, 0.5), seg: 28, hull)
            b.ellipsoid(SIMD3(0.25, 0, -0.2), SIMD3(0.1, 0.35, 0.18), seg: 16, .glow(SIMD3(1.0, 0.6, 0.3), 1.1))
            b.mirrored { b, s in
                b.beam(SIMD3(-2.3, 0.55 * s, 0.0), SIMD3(-2.6, 1.85 * s, 0.25), width: 0.6, thick: 0.1, up: SIMD3(1, 0, 0), hull)
                b.lathe([(-4.4, 0), (-4.4, 0.15), (-4.2, 0.2), (-1.4, 0.2), (-1.2, 0.12), (-1.15, 0)], Xf(SIMD3(0, 1.95 * s, 0.25), scale: SIMD3(1, 1.3, 0.9)), seg: 18, hull)
                b.ellipsoid(SIMD3(-1.25, 1.95 * s, 0.25), SIMD3(0.14, 0.2, 0.15), seg: 14, .glow(SIMD3(1.0, 0.15, 0.08), 1.3))
                b.box(SIMD3(-2.8, 1.95 * s, 0.43), SIMD3(2.6, 0.12, 0.03), .engine(1))
                b.engine(SIMD3(-1.1, 1.95 * s, 0.25), r: 0.12, SIMD3(1.0, 0.2, 0.1))
            }
        },
        ShipDesign(id: "defiant", title: "Defiant", universe: "Star Trek", events: ["warp"], size: 2.2, glowHue: 215, panels: 40, finish: SIMD2(0.35, 0.4), wear: 0.3) { b in
            let hull = PartMat.hull(SIMD3(0.52, 0.53, 0.55), windows: 0.4)
            let half: [SIMD2<Float>] = [SIMD2(3.0, 0), SIMD2(2.0, 0.85), SIMD2(-0.6, 1.5), SIMD2(-2.1, 1.35), SIMD2(-2.3, 0.6)]
            let outline = half + half.reversed().map { SIMD2($0.x, -$0.y) }.filter { $0.y != 0 }
            b.prism(outline, h: 0.75, top: 0.72, bottom: 0.85, Xf(), hull)
            b.ellipsoid(SIMD3(0.4, 0, 0.36), SIMD3(0.9, 0.5, 0.18), seg: 18, hull)
            b.ellipsoid(SIMD3(2.25, 0, -0.18), SIMD3(0.3, 0.38, 0.14), seg: 16, .glow(SIMD3(1.0, 0.2, 0.08), 1.2))
            b.mirrored { b, s in
                b.capsule(SIMD3(-2.3, 1.45 * s, -0.05), SIMD3(0.7, 1.35 * s, -0.05), r: 0.36, hull)
                b.ellipsoid(SIMD3(0.85, 1.35 * s, -0.05), SIMD3(0.18, 0.24, 0.22), seg: 14, .glow(SIMD3(1.0, 0.15, 0.06), 1.3))
                b.box(SIMD3(-1.0, 1.45 * s + 0.33 * s, -0.05), SIMD3(2.0, 0.04, 0.1), .engine(1))
                b.box(SIMD3(-2.32, 0.6 * s, 0.05), SIMD3(0.04, 0.6, 0.16), .glow(SIMD3(1.0, 0.2, 0.1), 1.0))
                b.engine(SIMD3(-2.35, 0.6 * s, 0.05), r: 0.1, SIMD3(1.0, 0.25, 0.1))
            }
        },
        ShipDesign(id: "birdOfPrey", title: "Bird-of-Prey (Klingonen)", universe: "Star Trek", events: ["cloak", "warp"], size: 2.4, glowHue: 0, panels: 40, windows: 0.2, yaw: -18, pitch: 38, finish: SIMD2(0.45, 0.45), wear: 0.55) { b in
            let hull = PartMat.hull(SIMD3(0.42, 0.50, 0.40), windows: 0.2)
            b.ellipsoid(SIMD3(-1.0, 0, 0), SIMD3(1.3, 1.0, 0.45), seg: 26, hull)
            b.capsule(SIMD3(-0.2, 0, 0.12), SIMD3(2.7, 0, 0.12), r: 0.27, hull)
            b.ellipsoid(SIMD3(3.2, 0, 0.08), SIMD3(0.75, 0.6, 0.34), seg: 22, hull)
            b.ellipsoid(SIMD3(3.55, 0, 0.25), SIMD3(0.25, 0.22, 0.1), seg: 12, .glass)
            b.mirrored { b, s in
                // Wings swept back and down, disruptors at the tips.
                let w: [SIMD2<Float>] = [SIMD2(0.0, 0.6), SIMD2(-2.3, 0.6), SIMD2(-2.7, 4.3), SIMD2(-1.6, 4.4), SIMD2(-0.6, 2.0)]
                let pts = s > 0 ? w : w.map { SIMD2($0.x, -$0.y) }
                b.prism(pts, h: 0.14, top: 1, Xf(SIMD3(-0.6, 0, 0), rot: SIMD3(-24 * s, 0, 0)), hull)
                let tip = SIMD3<Float>(-1.9, 4.35 * cosf(24 * .pi / 180) * s, -4.35 * sinf(24 * .pi / 180))
                b.tube(tip + SIMD3(-0.6, 0, 0), tip + SIMD3(1.8, 0, 0), r0: 0.12, hull)
                b.ellipsoid(tip + SIMD3(1.85, 0, 0), SIMD3(0.08, 0.1, 0.1), seg: 10, .glow(SIMD3(0.4, 1.0, 0.4), 0.8))
                b.box(SIMD3(-1.0, 0.7 * s, -0.3), SIMD3(1.6, 0.05, 0.12), .glow(SIMD3(1.0, 0.25, 0.08), 0.6))
            }
            b.box(SIMD3(-2.25, 0, 0.0), SIMD3(0.05, 1.2, 0.2), .glow(SIMD3(1.0, 0.2, 0.08), 1.1))
            b.engine(SIMD3(-2.3, 0, 0), r: 0.15, SIMD3(1.0, 0.2, 0.08))
        },
        ShipDesign(id: "warbird", title: "Romulanischer Warbird", universe: "Star Trek", events: ["cloak", "warp"], size: 6, glowHue: 130, panels: 50, windows: 0.4, finish: SIMD2(0.25, 0.38), wear: 0.3) { b in
            let hull = PartMat.hull(SIMD3(0.36, 0.52, 0.40), windows: 0.4)
            // Upper and lower hull: broad bands bent into an open ring, the head out in front.
            let t = Xf(SIMD3(-0.6, 0, 0), rot: SIMD3(90, 0, 0))
            b.torus(t, R: 3.0, r: 0.3, arc: 22...158, seg: 40, side: 12, rz: 7, hull)
            b.torus(t, R: 3.0, r: 0.3, arc: 202...338, seg: 40, side: 12, rz: 7, hull)
            b.beam(SIMD3(2.0, 0, 1.15), SIMD3(3.0, 0, 0.15), width: 0.9, thick: 0.5, up: SIMD3(0, 1, 0), hull)
            b.beam(SIMD3(2.0, 0, -1.15), SIMD3(3.0, 0, -0.15), width: 0.9, thick: 0.5, up: SIMD3(0, 1, 0), hull)
            b.ellipsoid(SIMD3(3.7, 0, 0), SIMD3(0.95, 0.6, 0.4), seg: 24, hull)
            b.ellipsoid(SIMD3(4.3, 0, 0.1), SIMD3(0.3, 0.25, 0.12), seg: 12, .glass)
            b.beam(SIMD3(-3.4, 0, 1.0), SIMD3(-3.4, 0, -1.0), width: 1.2, thick: 0.4, up: SIMD3(0, 1, 0), hull)
            b.ellipsoid(SIMD3(-3.45, 0, 0), SIMD3(0.12, 0.5, 0.35), seg: 16, .engine(1))
            b.mirrored { b, s in b.box(SIMD3(-0.6, 2.05 * s, 0), SIMD3(4.0, 0.05, 0.12), .engine(0.8)) }
        },
        ShipDesign(id: "borg", title: "Borg-Würfel", universe: "Star Trek", events: ["transwarp"], size: 6, glowHue: 130, panels: 26, windows: 0, yaw: -30, pitch: 28, finish: SIMD2(0.7, 0.5), wear: 0.6) { b in
            b.borgCube()
        },
        ShipDesign(id: "ds9", title: "Deep Space 9", universe: "Star Trek", station: true, size: 8, glowHue: 30, panels: 70, windows: 0.8, yaw: 0, pitch: 28, finish: SIMD2(0.5, 0.42), wear: 0.4) { b in
            let hull = PartMat.hull(SIMD3(0.58, 0.55, 0.50), windows: 0.9)
            b.torus(Xf(), R: 3.0, r: 0.12, seg: 72, side: 10, rz: 1.3, hull)
            b.torus(Xf(), R: 1.9, r: 0.2, seg: 64, side: 12, rz: 1.3, hull)
            b.torus(Xf(), R: 0.95, r: 0.24, seg: 48, side: 12, rz: 1.2, hull)
            b.lathe([(-1.3, 0), (-1.2, 0.25), (-0.5, 0.42), (0.0, 0.62), (0.4, 0.45), (1.0, 0.3), (1.1, 0)], Xf(rot: SIMD3(0, -90, 0)), seg: 32, hull)
            for k in 0..<3 {
                let a = Float(k) * 2 * .pi / 3 + .pi / 6
                let d = SIMD3(cosf(a), sinf(a), 0)
                b.beam(d * 0.9, d * 3.0, width: 0.12, thick: 0.16, hull)
                // Docking pylons curving up and down from the outer ring.
                let ap = a + .pi / 3
                let dp = SIMD3(cosf(ap), sinf(ap), 0)
                let frame = Xf(m: simd_float3x3(columns: (dp, SIMD3(0, 0, 1), simd_cross(dp, SIMD3(0, 0, 1)))), o: dp * 2.15)
                b.torus(frame, R: 0.9, r: 0.08, arc: -5...118, seg: 16, side: 8, hull)
                b.torus(frame, R: 0.9, r: 0.08, arc: -118...5, seg: 16, side: 8, hull)
                b.engine(dp * 1.75 + SIMD3(0, 0, 0.85), r: 0.04, SIMD3(1.0, 0.6, 0.3))
                b.engine(dp * 1.75 - SIMD3(0, 0, 0.85), r: 0.04, SIMD3(1.0, 0.6, 0.3))
            }
            b.ellipsoid(SIMD3(0, 0, 1.1), SIMD3(0.15, 0.15, 0.08), seg: 10, .glow(SIMD3(1.0, 0.55, 0.25), 1))
        },
    ]

    static let starWars: [ShipDesign] = [
        ShipDesign(id: "falcon", title: "Millennium Falke", universe: "Star Wars", events: ["hyperspace"], size: 1.8, glowHue: 205, panels: 34, windows: 0.1, yaw: -25, pitch: 32, finish: SIMD2(0.15, 0.5), wear: 0.8) { b in
            let hull = PartMat.hull(SIMD3(0.70, 0.69, 0.65), windows: 0.1)
            b.lathe([(-0.17, 0), (-0.2, 0.6), (-0.15, 1.0), (-0.05, 1.06), (0.05, 1.06), (0.15, 1.0), (0.2, 0.6), (0.23, 0.3), (0.26, 0.12), (0.27, 0)],
                    Xf(rot: SIMD3(0, -90, 0)), seg: 48, hull)
            b.mirrored { b, s in
                // The two mandibles in front with the slot between them.
                b.prism([SIMD2(0.55, 0.13 * s), SIMD2(1.6, 0.13 * s), SIMD2(1.6, 0.46 * s), SIMD2(0.55, 0.5 * s)], h: 0.2, top: 1, Xf(), hull)
                b.box(SIMD3(1.0, 0.3 * s, 0.11), SIMD3(0.7, 0.2, 0.04), .dark())
            }
            // Cockpit tube on the starboard side.
            b.tube(SIMD3(0.2, -0.82, 0.0), SIMD3(0.78, -1.04, 0.0), r0: 0.1, r1: 0.12, hull)
            b.ellipsoid(SIMD3(0.84, -1.06, 0.0), SIMD3(0.14, 0.13, 0.13), seg: 14, hull)
            b.ellipsoid(SIMD3(0.95, -1.08, 0.02), SIMD3(0.05, 0.09, 0.08), seg: 12, .glass)
            b.tube(SIMD3(-0.15, 0.45, 0.2), SIMD3(-0.15, 0.45, 0.32), r0: 0.04, r1: 0.2, seg: 16, hull)
            b.tube(SIMD3(0, 0, 0.24), SIMD3(0, 0, 0.32), r0: 0.12, seg: 14, .dark())
            b.torus(Xf(), R: 0.97, r: 0.045, arc: 128...232, seg: 30, side: 8, rz: 1.6, .engine(1.3))
            for k in 0..<5 { let a = (140 + Float(k) * 20) * .pi / 180; b.engine(SIMD3(cosf(a), sinf(a), 0) * 1.0, r: 0.04) }
        },
        ShipDesign(id: "xwing", title: "X-Wing", universe: "Star Wars", events: ["hyperspace"], size: 1.4, glowHue: 8, panels: 30, windows: 0, yaw: -35, pitch: 22, finish: SIMD2(0.1, 0.48), wear: 0.6) { b in
            let hull = PartMat.hull(SIMD3(0.80, 0.80, 0.78))
            let red = PartMat.accent(SIMD3(0.65, 0.12, 0.08))
            b.prism([SIMD2(4.6, 0.08), SIMD2(1.0, 0.38), SIMD2(-2.8, 0.48), SIMD2(-2.8, -0.48), SIMD2(1.0, -0.38), SIMD2(4.6, -0.08)],
                    h: 0.7, top: 0.82, bottom: 0.9, Xf(SIMD3(0, 0, 0.05)), hull)
            b.ellipsoid(SIMD3(0.3, 0, 0.38), SIMD3(0.9, 0.27, 0.2), seg: 18, .glass)
            b.ellipsoid(SIMD3(-0.9, 0, 0.42), SIMD3(0.16, 0.16, 0.12), seg: 12, .accent(SIMD3(0.3, 0.45, 0.9)))
            b.box(SIMD3(2.8, 0, 0.32), SIMD3(0.5, 0.42, 0.06), red)
            for sz in [Float(1), -1] {
                b.mirrored { b, s in
                    let ang = 13 * s * sz
                    let w: [SIMD2<Float>] = [SIMD2(-1.1, 0.4), SIMD2(-2.7, 0.4), SIMD2(-2.7, 4.3), SIMD2(-1.8, 4.3)]
                    let pts = s > 0 ? w : w.map { SIMD2($0.x, -$0.y) }
                    b.prism(pts, h: 0.07, top: 1, Xf(SIMD3(0, 0, 0.12 * sz), rot: SIMD3(ang, 0, 0)), hull)
                    b.box(SIMD3(-2.25, 2.6 * s * cosf(ang * .pi / 180), 0.12 * sz + 2.6 * s * sinf(ang * .pi / 180)), SIMD3(0.5, 0.9, 0.09),
                          rot: SIMD3(ang, 0, 0), red)
                    let tip = SIMD3<Float>(0, 4.3 * s * cosf(ang * .pi / 180), 0.12 * sz + 4.3 * s * sinf(ang * .pi / 180))
                    b.tube(tip + SIMD3(-2.6, 0, 0), tip + SIMD3(2.4, 0, 0), r0: 0.07, hull)
                    b.tube(tip + SIMD3(2.4, 0, 0), tip + SIMD3(3.2, 0, 0), r0: 0.03, hull)
                    let e = SIMD3<Float>(0, 0.9 * s, 0.45 * sz)
                    b.tube(e + SIMD3(-3.2, 0, 0), e + SIMD3(-0.5, 0, 0), r0: 0.32, r1: 0.28, hull)
                    b.ellipsoid(e + SIMD3(-3.22, 0, 0), SIMD3(0.03, 0.26, 0.26), seg: 14, .engine(1.3))
                    b.engine(e + SIMD3(-3.3, 0, 0), r: 0.18)
                }
            }
        },
        ShipDesign(id: "tie", title: "TIE Fighter", universe: "Star Wars", size: 1.0, glowHue: 0, panels: 24, windows: 0, yaw: -55, pitch: 15, finish: SIMD2(0.4, 0.45), wear: 0.35) { b in
            let body = PartMat.hull(SIMD3(0.42, 0.43, 0.46))
            let dark = PartMat.dark(SIMD3(0.07, 0.07, 0.08))
            b.ellipsoid(.zero, SIMD3(1, 1, 1), seg: 28, body)
            b.ellipsoid(SIMD3(0.88, 0, 0), SIMD3(0.18, 0.5, 0.5), seg: 16, .glass)
            b.mirrored { b, s in
                b.tube(SIMD3(0, 0.7 * s, 0), SIMD3(0, 2.3 * s, 0), r0: 0.3, r1: 0.22, seg: 14, body)
                // Hexagonal wing panels, standing upright, with frame and spokes.
                let t = Xf(SIMD3(0, 2.4 * s, 0), rot: SIMD3(90, 0, 0))
                b.prism(MeshBuilder.ngon(6, 2.7, a0: 90), h: 0.1, top: 1, t, dark)
                let corners = MeshBuilder.ngon(6, 2.7, a0: 90).map { SIMD3<Float>($0.x, 2.4 * s, $0.y) }
                for k in 0..<6 {
                    b.beam(corners[k], corners[(k + 1) % 6], width: 0.16, thick: 0.18, up: SIMD3(0, 1, 0), body)
                    if k < 3 { b.beam(corners[k], corners[k + 3], width: 0.12, thick: 0.14, up: SIMD3(0, 1, 0), body) }
                }
            }
            b.engine(SIMD3(-1.0, 0.35, 0), r: 0.06, SIMD3(1.0, 0.3, 0.2))
            b.engine(SIMD3(-1.0, -0.35, 0), r: 0.06, SIMD3(1.0, 0.3, 0.2))
        },
        ShipDesign(id: "stardestroyer", title: "Sternzerstörer", universe: "Star Wars", events: ["hyperspace"], size: 9, glowHue: 205, panels: 150, windows: 0.4, yaw: -28, pitch: 26, finish: SIMD2(0.2, 0.42), wear: 0.35) { b in
            let hull = PartMat.hull(SIMD3(0.64, 0.65, 0.67), windows: 0.4)
            let tri: [SIMD2<Float>] = [SIMD2(6.67, 0), SIMD2(-3.33, 3.4), SIMD2(-3.33, -3.4)]
            let o = SIMD3<Float>(-1.67, 0, 0)
            // Upper and lower slopes of the wedge meeting at the wide edge.
            b.prism(tri, h: 0.6, top: 0.6, bottom: 1, Xf(o + SIMD3(0, 0, 0.3)), hull)
            b.prism(tri, h: 0.45, top: 1, bottom: 0.68, Xf(o + SIMD3(0, 0, -0.225)), hull)
            // Stepped superstructure.
            let tri2: [SIMD2<Float>] = [SIMD2(4.0, 0), SIMD2(-2.0, 1.55), SIMD2(-2.0, -1.55)]
            b.prism(tri2, h: 0.35, top: 0.85, Xf(SIMD3(-2.6, 0, 0.75)), hull)
            b.box(SIMD3(-3.7, 0, 1.0), SIMD3(1.3, 1.3, 0.35), hull)
            b.box(SIMD3(-3.8, 0, 1.3), SIMD3(0.9, 0.9, 0.3), hull)
            b.box(SIMD3(-3.9, 0, 1.62), SIMD3(0.45, 0.35, 0.4), hull)
            b.box(SIMD3(-3.9, 0, 1.95), SIMD3(0.55, 2.1, 0.32), hull)
            b.box(SIMD3(-3.62, 0, 1.97), SIMD3(0.02, 1.9, 0.06), .glow(SIMD3(1.0, 0.9, 0.7), 0.7))
            b.mirrored { b, s in b.ellipsoid(SIMD3(-3.9, 0.68 * s, 2.32), SIMD3(0.19, 0.19, 0.19), seg: 14, hull) }
            // Three main engines and four smaller ones.
            let eng: [(Float, Float, Float)] = [(0, 0.15, 0.42), (1.05, 0.15, 0.42), (-1.05, 0.15, 0.42), (0.55, -0.2, 0.2), (-0.55, -0.2, 0.2), (1.6, -0.12, 0.18), (-1.6, -0.12, 0.18)]
            for (y, z, r) in eng {
                b.tube(SIMD3(-5.45, y, z), SIMD3(-4.9, y, z), r0: r, seg: 18, hull)
                b.ellipsoid(SIMD3(-5.47, y, z), SIMD3(0.03, r * 0.85, r * 0.85), seg: 14, .engine(1.5))
                b.engine(SIMD3(-5.5, y, z), r: r * 0.7)
            }
        },
        ShipDesign(id: "tantive", title: "Tantive IV", universe: "Star Wars", events: ["hyperspace"], size: 3.5, glowHue: 205, panels: 50, windows: 0.5, yaw: -30, pitch: 20, finish: SIMD2(0.1, 0.32), wear: 0.2) { b in
            let hull = PartMat.hull(SIMD3(0.84, 0.82, 0.80), windows: 0.6)
            let red = PartMat.accent(SIMD3(0.7, 0.12, 0.08))
            b.prism([SIMD2(4.1, 0.45), SIMD2(2.5, 0.9), SIMD2(2.5, -0.9), SIMD2(4.1, -0.45)], h: 0.5, top: 0.85, Xf(SIMD3(0, 0, 0.05)), hull)
            b.box(SIMD3(3.3, 0, 0.32), SIMD3(1.2, 1.0, 0.05), red)
            b.tube(SIMD3(-1.3, 0, 0), SIMD3(2.6, 0, 0), r0: 0.52, r1: 0.42, seg: 22, sz: 0.85, hull)
            for x in [Float(-0.6), 0.4, 1.4] { b.torus(Xf(SIMD3(x, 0, 0), rot: SIMD3(0, 90, 0)), R: 0.5, r: 0.05, seg: 24, side: 6, hull) }
            b.box(SIMD3(-2.1, 0, 0), SIMD3(1.7, 2.0, 1.15), hull)
            b.box(SIMD3(-2.1, 0, 0.6), SIMD3(1.5, 1.6, 0.06), red)
            b.mirrored { b, s in b.ellipsoid(SIMD3(0.8, 0.45 * s, 0.45), SIMD3(0.18, 0.18, 0.12), seg: 10, hull) }
            let rows: [(Float, Float)] = [(-0.6, 0.32), (-0.2, 0.32), (0.2, 0.32), (0.6, 0.32), (-0.8, 0), (0, 0), (0.8, 0), (-0.6, -0.32), (-0.2, -0.32), (0.2, -0.32), (0.6, -0.32)]
            for (y, z) in rows {
                b.tube(SIMD3(-3.55, y, z), SIMD3(-2.9, y, z), r0: 0.16, seg: 12, hull)
                b.ellipsoid(SIMD3(-3.57, y, z), SIMD3(0.02, 0.13, 0.13), seg: 10, .engine(1.4))
                b.engine(SIMD3(-3.6, y, z), r: 0.1)
            }
        },
        ShipDesign(id: "deathstar", title: "Todesstern", universe: "Star Wars", station: true, size: 10, glowHue: 120, panels: 90, windows: 0.6, spin: 1.5, yaw: 10, pitch: 12, finish: SIMD2(0.5, 0.55), wear: 0.3) { b in
            b.ellipsoid(.zero, SIMD3(1, 1, 1), seg: 72, .deathStar)
        },
    ]

    static let galactica: [ShipDesign] = [
        ShipDesign(id: "galactica", title: "Galactica", universe: "Battlestar Galactica", events: ["ftl"], size: 9, glowHue: 28, panels: 120, windows: 0.25, yaw: -40, pitch: 40, finish: SIMD2(0.3, 0.5), wear: 0.65) { b in
            // Series of 2004: flat alligator head, narrower neck, long midship with two flight pods that reach
            // past it fore and aft, engine block with a cluster of large engines. x forward, z up.
            let hull = PartMat.hull(SIMD3(0.50, 0.51, 0.52), windows: 0.25)
            let plateA = PartMat.hull(SIMD3(0.42, 0.43, 0.44))
            let plateB = PartMat.hull(SIMD3(0.60, 0.61, 0.62))
            let dark = PartMat.dark(SIMD3(0.20, 0.21, 0.22))
            // Head: broad and flat, bevelled front corners, sloped sides.
            b.prism([SIMD2(5.0, 0.75), SIMD2(5.0, -0.75), SIMD2(4.65, -1.22), SIMD2(2.35, -1.3), SIMD2(1.8, -0.8),
                     SIMD2(1.8, 0.8), SIMD2(2.35, 1.3), SIMD2(4.65, 1.22)], h: 0.56, top: 0.84, bottom: 0.93, Xf(SIMD3(0, 0, -0.08)), hull)
            // Raised armour deck on the head, with plates of slightly different grey.
            b.prism([SIMD2(4.55, 0.42), SIMD2(4.55, -0.42), SIMD2(4.35, -0.72), SIMD2(2.3, -0.76), SIMD2(2.0, -0.5),
                     SIMD2(2.0, 0.5), SIMD2(2.3, 0.76), SIMD2(4.35, 0.72)], h: 0.16, top: 0.9, Xf(SIMD3(0.35, 0, 0.26)), hull)
            for i in 0..<6 {
                let x = 2.45 + Float(i) * 0.36
                b.box(SIMD3(x, 0.24 * (i % 2 == 0 ? 1 : -1), 0.355), SIMD3(0.3, 0.42, 0.03), i % 3 == 0 ? plateA : plateB)
            }
            b.mirrored { b, s in
                // Sloped side armour of the head and the dark notch where it meets the neck.
                b.box(SIMD3(3.45, 1.06 * s, -0.08), SIMD3(2.0, 0.08, 0.3), rot: SIMD3(-24 * s, 0, 0), plateA)
                b.box(SIMD3(1.83, 0.62 * s, -0.08), SIMD3(0.08, 0.3, 0.32), dark)
            }
            // Neck: narrower and lower than the back.
            b.prism([SIMD2(1.9, 0.48), SIMD2(1.9, -0.48), SIMD2(0.6, -0.56), SIMD2(0.6, 0.56)], h: 0.5, top: 0.88, Xf(SIMD3(0, 0, -0.04)), hull)
            b.box(SIMD3(1.25, 0, 0.21), SIMD3(1.1, 0.5, 0.06), dark)
            // Midship: higher, with a dorsal spine and armour ribs across it.
            b.prism([SIMD2(0.8, 0.6), SIMD2(0.8, -0.6), SIMD2(0.35, -0.86), SIMD2(-3.15, -0.9), SIMD2(-3.15, 0.9), SIMD2(0.35, 0.86)],
                    h: 0.96, top: 0.84, bottom: 0.92, Xf(SIMD3(0, 0, 0.02)), hull)
            b.prism([SIMD2(0.55, 0.3), SIMD2(0.55, -0.3), SIMD2(0.2, -0.42), SIMD2(-2.9, -0.44), SIMD2(-2.9, 0.44), SIMD2(0.2, 0.42)],
                    h: 0.22, top: 0.86, Xf(SIMD3(0, 0, 0.6)), hull)
            for i in 0..<9 {
                let x = -2.75 + Float(i) * 0.38
                b.box(SIMD3(x, 0, 0.715), SIMD3(0.07, 0.72, 0.03), dark)
                b.box(SIMD3(x + 0.19, 0.5 * (i % 2 == 0 ? 1 : -1), 0.505), SIMD3(0.3, 0.26, 0.03), i % 3 == 1 ? plateA : plateB)
            }
            b.mirrored { b, s in
                // Flight pods: long, flat, at mid height, reaching past the midship fore and aft.
                let pod: [SIMD2<Float>] = [SIMD2(1.6, -0.24), SIMD2(1.6, 0.18), SIMD2(1.35, 0.34), SIMD2(-3.75, 0.34), SIMD2(-4.0, 0.12), SIMD2(-4.0, -0.24),
                                           SIMD2(-3.7, -0.34), SIMD2(1.35, -0.34)].map { SIMD2($0.x, $0.y * s) }
                b.prism(pod, h: 0.4, top: 0.97, bottom: 0.99, Xf(SIMD3(0, 1.45 * s, -0.12)), hull)
                // Armour along the pod top and the landing bay mouths fore and aft.
                b.box(SIMD3(-1.2, 1.45 * s, 0.1), SIMD3(5.0, 0.42, 0.05), plateA)
                for i in 0..<7 { b.box(SIMD3(-3.5 + Float(i) * 0.78, 1.45 * s, 0.13), SIMD3(0.05, 0.5, 0.03), dark) }
                b.box(SIMD3(1.58, 1.42 * s, -0.14), SIMD3(0.06, 0.5, 0.2), dark)
                b.box(SIMD3(1.56, 1.42 * s, -0.14), SIMD3(0.04, 0.44, 0.14), .glow(SIMD3(1.0, 0.82, 0.55), 0.45))
                b.box(SIMD3(-3.98, 1.45 * s, -0.14), SIMD3(0.06, 0.4, 0.18), dark)
                // Struts between hull and pod.
                for x: Float in [-2.7, -1.4, -0.1] { b.box(SIMD3(x, 1.03 * s, -0.12), SIMD3(0.42, 0.4, 0.26), dark) }
            }
            // Engine block, slightly narrower, with the big engine cluster at the stern.
            b.prism([SIMD2(-3.1, 0.88), SIMD2(-3.1, -0.88), SIMD2(-4.6, -0.78), SIMD2(-4.6, 0.78)], h: 1.08, top: 0.86, bottom: 0.93, Xf(SIMD3(0, 0, 0.02)), hull)
            for i in 0..<3 { b.box(SIMD3(-3.35 - Float(i) * 0.42, 0, 0.56), SIMD3(0.2, 1.1, 0.04), i == 1 ? plateA : dark) }
            let big: [(Float, Float)] = [(-0.3, 0.26), (0.3, 0.26), (-0.3, -0.22), (0.3, -0.22)]
            for (y, z) in big {
                b.tube(SIMD3(-5.02, y, z), SIMD3(-4.5, y, z), r0: 0.27, r1: 0.25, seg: 18, dark)
                b.ellipsoid(SIMD3(-5.04, y, z), SIMD3(0.03, 0.22, 0.22), seg: 14, .engine(1.5))
                b.engine(SIMD3(-5.08, y, z), r: 0.2)
            }
            for (y, z) in [(Float(-0.66), Float(0.3)), (0.66, 0.3), (-0.66, -0.22), (0.66, -0.22)] {
                b.tube(SIMD3(-4.85, y, z), SIMD3(-4.5, y, z), r0: 0.14, seg: 12, dark)
                b.ellipsoid(SIMD3(-4.87, y, z), SIMD3(0.02, 0.11, 0.11), seg: 10, .engine(1.3))
                b.engine(SIMD3(-4.9, y, z), r: 0.1)
            }
        },
        ShipDesign(id: "viper", title: "Viper Mk II", universe: "Battlestar Galactica", size: 1.2, glowHue: 18, panels: 26, windows: 0, yaw: -35, pitch: 20, finish: SIMD2(0.15, 0.36), wear: 0.35) { b in
            let hull = PartMat.hull(SIMD3(0.78, 0.78, 0.76))
            b.lathe([(-2.2, 0), (-2.2, 0.38), (-1.5, 0.46), (0.5, 0.42), (1.8, 0.24), (2.8, 0.07), (3.0, 0)], Xf(scale: SIMD3(1, 1, 0.85)), seg: 22, hull)
            b.ellipsoid(SIMD3(0.9, 0, 0.3), SIMD3(0.7, 0.22, 0.2), seg: 14, .glass)
            b.box(SIMD3(1.6, 0, 0.0), SIMD3(1.4, 0.5, 0.04), .accent(SIMD3(0.65, 0.12, 0.1)))
            b.mirrored { b, s in
                b.prism([SIMD2(-0.5, 0.3 * s), SIMD2(-2.0, 0.3 * s), SIMD2(-2.1, 1.7 * s), SIMD2(-1.5, 1.8 * s)], h: 0.07, top: 1, Xf(SIMD3(0, 0, -0.05)), hull)
            }
            b.prism([SIMD2(-0.6, 0.3), SIMD2(-2.0, 0.3), SIMD2(-2.2, 1.1), SIMD2(-1.6, 1.1)], h: 0.07, top: 1, Xf(rot: SIMD3(90, 0, 0)), hull)
            for (y, z) in [(Float(0.33), Float(0.1)), (-0.33, 0.1), (0, -0.28)] {
                b.tube(SIMD3(-2.6, y, z), SIMD3(-1.6, y, z), r0: 0.2, r1: 0.22, seg: 12, hull)
                b.ellipsoid(SIMD3(-2.62, y, z), SIMD3(0.03, 0.17, 0.17), seg: 10, .engine(1.4))
                b.engine(SIMD3(-2.7, y, z), r: 0.13)
            }
        },
        ShipDesign(id: "basestar", title: "Basisstern", universe: "Battlestar Galactica", events: ["ftl"], size: 9, glowHue: 0, panels: 70, windows: 0.15, yaw: 0, pitch: 35, finish: SIMD2(0.6, 0.45), wear: 0.35) { b in
            let hull = PartMat.hull(SIMD3(0.56, 0.57, 0.59), windows: 0.2)
            b.tube(SIMD3(0, 0, -0.9), SIMD3(0, 0, 0.9), r0: 0.65, seg: 24, hull)
            for (z, off) in [(Float(0.45), Float(0)), (-0.45, 60)] {
                for k in 0..<3 {
                    let a = (Float(k) * 120 + off) * .pi / 180
                    let d = SIMD3(cosf(a), sinf(a), 0)
                    let bend = SIMD3<Float>(0, 0, z > 0 ? 0.3 : -0.3)
                    b.lathe([(0, 0.8), (0.7, 0.72), (1.0, 0.55)], Xf.along(d * 0.2 + SIMD3(0, 0, z), d * 2.3 + SIMD3(0, 0, z) + bend * 0.4), seg: 16, hull)
                    b.lathe([(0, 0.55), (0.7, 0.32), (1.0, 0.08), (1.02, 0)], Xf.along(d * 2.3 + SIMD3(0, 0, z) + bend * 0.4, d * 4.1 + SIMD3(0, 0, z) + bend * 1.6), seg: 16, hull)
                    b.engine(d * 1.2 + SIMD3(0, 0, z * 1.9), r: 0.05, SIMD3(1.0, 0.2, 0.1))
                }
            }
        },
        ShipDesign(id: "raider", title: "Cylon Raider", universe: "Battlestar Galactica", events: ["ftl"], size: 1.4, glowHue: 0, panels: 20, windows: 0, yaw: -20, pitch: 40, finish: SIMD2(0.9, 0.22), wear: 0.3) { b in
            let hull = PartMat.dark(SIMD3(0.42, 0.43, 0.46))
            // Crescent seen from above: the body in the middle, the wings swept back to sharp tips.
            var cres: [SIMD2<Float>] = []
            for i in 0...16 { let a = (-78 + Float(i) * 156 / 16) * .pi / 180; cres.append(SIMD2(-1.3 + cosf(a) * 2.0, sinf(a) * 2.0)) }
            for i in 0...16 { let a = (70 - Float(i) * 140 / 16) * .pi / 180; cres.append(SIMD2(-1.75 + cosf(a) * 1.55, sinf(a) * 1.75)) }
            b.prism(cres, h: 0.22, top: 0.92, bottom: 0.96, Xf(), hull)
            b.ellipsoid(SIMD3(0.2, 0, 0.05), SIMD3(0.8, 0.5, 0.3), seg: 20, hull)
            b.box(SIMD3(0.97, 0, 0.06), SIMD3(0.05, 0.42, 0.06), .glow(SIMD3(1.0, 0.08, 0.04), 2))
            b.engine(SIMD3(1.0, 0, 0.06), r: 0.05, SIMD3(1.0, 0.1, 0.05))
            b.mirrored { b, s in b.engine(SIMD3(-0.9, 0.5 * s, 0), r: 0.06, SIMD3(1.0, 0.3, 0.1)) }
        },
        ShipDesign(id: "raptor", title: "Raptor", universe: "Battlestar Galactica", events: ["ftl"], size: 1.4, glowHue: 25, panels: 22, windows: 0, yaw: -35, pitch: 20, finish: SIMD2(0.15, 0.48), wear: 0.55) { b in
            let hull = PartMat.hull(SIMD3(0.55, 0.56, 0.55))
            b.prism([SIMD2(2.2, -0.3), SIMD2(1.3, 0.45), SIMD2(-1.8, 0.45), SIMD2(-1.8, -0.45), SIMD2(1.2, -0.45)], h: 1.1, top: 0.92, Xf(rot: SIMD3(90, 0, 0)), hull)
            b.box(SIMD3(1.6, 0, 0.18), SIMD3(0.5, 0.9, 0.06), rot: SIMD3(0, -40, 0), .glass)
            b.mirrored { b, s in
                b.tube(SIMD3(-1.9, 0.78 * s, 0.1), SIMD3(-0.2, 0.78 * s, 0.1), r0: 0.28, seg: 14, hull)
                b.ellipsoid(SIMD3(-1.92, 0.78 * s, 0.1), SIMD3(0.03, 0.23, 0.23), seg: 10, .engine(1.3))
                b.engine(SIMD3(-2.0, 0.78 * s, 0.1), r: 0.16)
            }
        },
    ]

    static let orion: [ShipDesign] = [
        ShipDesign(id: "orion", title: "Orion VIII", universe: "Raumpatrouille Orion", events: ["whirl"], size: 3, glowHue: 190, panels: 40, windows: 0.3, yaw: -20, pitch: 24, finish: SIMD2(0.75, 0.22), wear: 0.15) { b in
            let hull = PartMat.hull(SIMD3(0.72, 0.74, 0.76), windows: 0.3)
            b.lathe([(-0.16, 0), (-0.18, 0.5), (-0.12, 1.3), (-0.03, 1.6), (0.03, 1.6), (0.12, 1.3), (0.18, 0.5), (0.16, 0)], Xf(rot: SIMD3(0, -90, 0)), seg: 56, hull)
            b.torus(Xf(), R: 1.56, r: 0.07, seg: 56, side: 10, rz: 1.5, hull)
            b.ellipsoid(SIMD3(0, 0, 0.24), SIMD3(0.55, 0.55, 0.36), seg: 28, hull)
            b.ellipsoid(SIMD3(0, 0, 0.5), SIMD3(0.26, 0.26, 0.2), seg: 20, .glass)
            b.ellipsoid(SIMD3(0, 0, -0.24), SIMD3(0.45, 0.45, 0.26), seg: 24, hull)
            // The glowing window band around the dome.
            b.torus(Xf(SIMD3(0, 0, 0.32)), R: 0.5, r: 0.035, seg: 40, side: 6, rz: 1.6, .glow(SIMD3(0.75, 0.92, 1.0), 1.1))
            b.torus(Xf(SIMD3(0, 0, -0.05)), R: 1.45, r: 0.03, seg: 56, side: 6, .engine(0.8))
            b.engine(SIMD3(0, 0, -0.5), r: 0.18)
        },
        ShipDesign(id: "frog", title: "Frog-Raumer", universe: "Raumpatrouille Orion", events: ["emerge"], size: 2.6, glowHue: 140, panels: 20, windows: 0, spin: 25, yaw: 0, pitch: 30, finish: SIMD2(0.6, 0.3), wear: 0.2) { b in
            let dark = PartMat.dark(SIMD3(0.16, 0.19, 0.18))
            b.lathe([(-0.12, 0), (-0.08, 1.0), (0, 1.1), (0.08, 1.0), (0.12, 0)], Xf(rot: SIMD3(0, -90, 0)), seg: 40, dark)
            var star: [SIMD2<Float>] = []
            for k in 0..<32 {
                let a = Float(k) / 32 * 2 * .pi
                let r: Float = k % 2 == 0 ? 1.5 : 1.08
                star.append(SIMD2(cosf(a) * r, sinf(a) * r))
            }
            b.prism(star, h: 0.05, top: 1, Xf(), .engine(0.45))
            b.ellipsoid(SIMD3(0, 0, 0.1), SIMD3(0.32, 0.32, 0.12), seg: 18, .engine(0.9))
            b.ellipsoid(SIMD3(0, 0, -0.1), SIMD3(0.32, 0.32, 0.12), seg: 18, .engine(0.9))
            b.engine(.zero, r: 0.08)
        },
    ]

    static let expanse: [ShipDesign] = [
        ShipDesign(id: "rocinante", title: "Rocinante", universe: "The Expanse", events: ["epstein"], size: 2.6, glowHue: 215, panels: 40, windows: 0.2, yaw: -35, pitch: 14, finish: SIMD2(0.2, 0.45), wear: 0.5) { b in
            let hull = PartMat.hull(SIMD3(0.40, 0.41, 0.42), windows: 0.2)
            let light = PartMat.hull(SIMD3(0.62, 0.62, 0.6))
            b.prism([SIMD2(4.6, 0.15), SIMD2(3.4, 0.9), SIMD2(-3.6, 1.0), SIMD2(-4.2, 0.6), SIMD2(-4.2, -0.9), SIMD2(-3.0, -1.0), SIMD2(3.0, -0.55)],
                    h: 1.2, top: 0.86, bottom: 0.86, Xf(rot: SIMD3(90, 0, 0)), hull)
            b.box(SIMD3(1.0, 0, 0.95), SIMD3(2.4, 0.5, 0.06), light)
            b.mirrored { b, s in
                b.box(SIMD3(-0.6, 0.72 * s, -0.25), SIMD3(2.8, 0.4, 1.0), hull)
                b.ellipsoid(SIMD3(-1.0, 0.92 * s, 0.4), SIMD3(0.16, 0.16, 0.16), seg: 10, .dark())
            }
            b.ellipsoid(SIMD3(2.0, 0, 0.95), SIMD3(0.16, 0.16, 0.16), seg: 10, .dark())
            b.ellipsoid(SIMD3(-1.0, 0, -1.0), SIMD3(0.16, 0.16, 0.16), seg: 10, .dark())
            b.tube(SIMD3(-4.2, 0, -0.1), SIMD3(-5.0, 0, -0.1), r0: 0.45, r1: 0.65, seg: 20, .dark())
            b.ellipsoid(SIMD3(-4.95, 0, -0.1), SIMD3(0.04, 0.56, 0.56), seg: 16, .engine(1.6))
            b.engine(SIMD3(-5.0, 0, -0.1), r: 0.35)
            b.plume(SIMD3(-5.0, 0, -0.1), r: 0.38, len: 7)
        },
        ShipDesign(id: "donnager", title: "Donnager", universe: "The Expanse", events: ["epstein"], size: 9, glowHue: 215, panels: 110, windows: 0.4, yaw: -32, pitch: 16, finish: SIMD2(0.25, 0.45), wear: 0.4) { b in
            let hull = PartMat.hull(SIMD3(0.42, 0.43, 0.45), windows: 0.4)
            let seg: [(Float, Float, Float)] = [(3.6, 0.9, 1.0), (1.8, 1.1, 1.4), (0.0, 1.2, 1.6), (-1.8, 1.2, 1.6), (-3.6, 1.1, 1.4)]
            for (x, y, z) in seg {
                b.box(SIMD3(x, 0, 0), SIMD3(1.76, y, z), hull)
                b.box(SIMD3(x - 0.9, 0, 0), SIMD3(0.08, y * 0.8, z * 0.8), .dark())
            }
            b.prism([SIMD2(5.7, 0.1), SIMD2(4.5, 0.5), SIMD2(4.5, -0.5)], h: 0.8, top: 0.8, Xf(rot: SIMD3(90, 0, 0)), hull)
            b.tube(SIMD3(-4.5, 0, 0), SIMD3(-5.3, 0, 0), r0: 0.45, r1: 0.72, seg: 20, .dark())
            b.ellipsoid(SIMD3(-5.25, 0, 0), SIMD3(0.04, 0.62, 0.62), seg: 16, .engine(1.6))
            b.engine(SIMD3(-5.3, 0, 0), r: 0.4)
            b.plume(SIMD3(-5.3, 0, 0), r: 0.45, len: 7)
        },
        ShipDesign(id: "tycho", title: "Tycho-Station", universe: "The Expanse", station: true, size: 8, glowHue: 40, panels: 70, windows: 0.8, spin: 3, yaw: 0, pitch: 30, finish: SIMD2(0.4, 0.45), wear: 0.45) { b in
            let hull = PartMat.hull(SIMD3(0.6, 0.6, 0.62), windows: 0.9)
            b.torus(Xf(), R: 3.0, r: 0.32, seg: 72, side: 12, rz: 1.3, hull)
            for k in 0..<4 { let a = Float(k) * .pi / 2; b.beam(.zero, SIMD3(cosf(a), sinf(a), 0) * 3.0, width: 0.15, thick: 0.15, hull) }
            // The construction sphere: a frame of rings.
            let dark = PartMat.dark(SIMD3(0.3, 0.3, 0.32))
            for r in [SIMD3<Float>(0, 0, 0), SIMD3(90, 0, 0), SIMD3(0, 90, 0), SIMD3(90, 0, 45), SIMD3(90, 0, -45)] {
                b.torus(Xf(SIMD3(0, 0, 0.9), rot: r), R: 1.3, r: 0.05, seg: 40, side: 6, dark)
            }
            b.ellipsoid(SIMD3(0, 0, 0.9), SIMD3(0.5, 0.5, 0.5), seg: 16, .hull(SIMD3(0.7, 0.68, 0.6), windows: 1))
            b.beam(SIMD3(0, 0, 2.2), SIMD3(2.6, 0, 3.0), width: 0.18, thick: 0.18, dark)
            b.beam(SIMD3(0, 0, 2.2), SIMD3(-2.4, 0.4, 2.9), width: 0.18, thick: 0.18, dark)
            b.tube(SIMD3(0, 0, 0.0), SIMD3(0, 0, 2.3), r0: 0.2, seg: 12, hull)
            b.engine(SIMD3(2.6, 0, 3.0), r: 0.05, SIMD3(1.0, 0.8, 0.5))
        },
        ShipDesign(id: "ringgate", title: "Ring-Tor", universe: "The Expanse", station: true, events: ["transit"], size: 10, glowHue: 220, panels: 80, windows: 0, yaw: -62, pitch: 6, finish: SIMD2(0.6, 0.55), wear: 0.5) { b in
            let t = Xf(rot: SIMD3(0, 90, 0))
            b.torus(t, R: 3.0, r: 0.38, seg: 96, side: 12, rz: 1.4, .dark(SIMD3(0.30, 0.31, 0.34)))
            b.plate(MeshBuilder.ngon(64, 2.66), t, .membrane(SIMD3(0.45, 0.6, 1.0)))
        },
    ]

    static let babylon5: [ShipDesign] = [
        ShipDesign(id: "b5", title: "Babylon 5", universe: "Babylon 5", station: true, size: 9, glowHue: 210, panels: 80, windows: 0.8, spin: 6,
                   spinAxis: SIMD3(1, 0, 0), yaw: -25, pitch: 14, finish: SIMD2(0.35, 0.45), wear: 0.4) { b in
            let hull = PartMat.hull(SIMD3(0.62, 0.62, 0.6), windows: 0.9)
            b.tube(SIMD3(-3.0, 0, 0), SIMD3(2.0, 0, 0), r0: 0.55, seg: 28, hull)
            for x in stride(from: Float(-2.6), through: 1.8, by: 0.9) { b.torus(Xf(SIMD3(x, 0, 0), rot: SIMD3(0, 90, 0)), R: 0.57, r: 0.05, seg: 28, side: 6, hull) }
            b.ellipsoid(SIMD3(2.6, 0, 0), SIMD3(0.75, 0.8, 0.8), seg: 28, hull)
            for k in 0..<6 {
                let a = Float(k) * .pi / 3
                let d = SIMD3<Float>(0, cosf(a), sinf(a))
                b.beam(SIMD3(2.0, 0, 0) + d * 0.82, SIMD3(3.35, 0, 0) + d * 0.35, width: 0.1, thick: 0.12, up: SIMD3(1, 0, 0), hull)
            }
            b.ellipsoid(SIMD3(3.3, 0, 0), SIMD3(0.05, 0.28, 0.28), seg: 14, .glow(SIMD3(1.0, 0.95, 0.8), 1.2))
            b.tube(SIMD3(-3.0, 0, 0), SIMD3(-5.0, 0, 0), r0: 0.12, seg: 10, hull)
            b.mirrored { b, s in
                b.box(SIMD3(-4.1, 1.35 * s, 0), SIMD3(1.5, 2.0, 0.03), .solar)
                b.beam(SIMD3(-4.1, 0, 0), SIMD3(-4.1, 0.4 * s, 0), width: 0.08, thick: 0.08, hull)
            }
            b.engine(SIMD3(3.35, 0, 0), r: 0.15, SIMD3(1.0, 0.95, 0.8))
        },
        ShipDesign(id: "whitestar", title: "White Star", universe: "Babylon 5", events: ["jumppoint"], size: 3, glowHue: 255, panels: 30, windows: 0, yaw: -30, pitch: 22, finish: SIMD2(0.3, 0.22), wear: 0.1) { b in
            let hull = PartMat.hull(SIMD3(0.52, 0.48, 0.70))
            b.ellipsoid(.zero, SIMD3(3.0, 0.45, 0.35), seg: 26, hull)
            b.ellipsoid(SIMD3(1.0, 0, 0.25), SIMD3(1.0, 0.25, 0.15), seg: 16, hull)
            b.mirrored { b, s in
                let w: [SIMD2<Float>] = [SIMD2(-1.8, 0.3), SIMD2(-0.2, 0.42), SIMD2(1.6, 1.0), SIMD2(2.9, 1.9), SIMD2(2.3, 2.0), SIMD2(0.6, 1.2), SIMD2(-1.6, 0.75)]
                b.prism(s > 0 ? w : w.map { SIMD2($0.x, -$0.y) }, h: 0.1, top: 1, Xf(), hull)
                b.box(SIMD3(0.4, 0.95 * s, 0.06), SIMD3(1.6, 0.08, 0.02), .engine(1.0))
            }
            b.ellipsoid(SIMD3(-2.95, 0, 0), SIMD3(0.08, 0.3, 0.22), seg: 14, .engine(1.6))
            b.engine(SIMD3(-3.0, 0, 0), r: 0.22)
        },
        ShipDesign(id: "starfury", title: "Starfury", universe: "Babylon 5", size: 1.2, glowHue: 25, panels: 22, windows: 0, yaw: -40, pitch: 25, finish: SIMD2(0.2, 0.45), wear: 0.5) { b in
            let hull = PartMat.hull(SIMD3(0.62, 0.62, 0.63))
            b.box(.zero, SIMD3(1.3, 0.7, 0.6), hull)
            b.box(SIMD3(0.75, 0, 0.05), SIMD3(0.3, 0.5, 0.4), hull)
            b.ellipsoid(SIMD3(0.92, 0, 0.12), SIMD3(0.1, 0.22, 0.15), seg: 12, .glass)
            for sz in [Float(1), -1] {
                b.mirrored { b, s in
                    b.beam(SIMD3(-0.2, 0.3 * s, 0.25 * sz), SIMD3(-0.55, 1.7 * s, 1.1 * sz), width: 0.28, thick: 0.12, up: SIMD3(1, 0, 0), hull)
                    let e = SIMD3<Float>(-0.55, 1.7 * s, 1.1 * sz)
                    b.tube(e + SIMD3(-0.55, 0, 0), e + SIMD3(0.45, 0, 0), r0: 0.18, seg: 12, hull)
                    b.ellipsoid(e + SIMD3(-0.57, 0, 0), SIMD3(0.03, 0.15, 0.15), seg: 10, .engine(1.4))
                    b.engine(e + SIMD3(-0.62, 0, 0), r: 0.12)
                }
            }
        },
    ]

    static let firefly: [ShipDesign] = [
        ShipDesign(id: "serenity", title: "Serenity", universe: "Firefly", events: ["fullburn"], size: 2.4, glowHue: 30, panels: 30, windows: 0.3, yaw: -30, pitch: 20, finish: SIMD2(0.1, 0.5), wear: 0.75) { b in
            let hull = PartMat.hull(SIMD3(0.66, 0.63, 0.57), windows: 0.4)
            b.ellipsoid(SIMD3(2.0, 0, 0.3), SIMD3(0.7, 0.62, 0.45), seg: 22, hull)
            b.box(SIMD3(2.5, 0, 0.45), SIMD3(0.3, 0.7, 0.15), rot: SIMD3(0, -25, 0), .glass)
            b.tube(SIMD3(1.4, 0, 0.25), SIMD3(0.2, 0, 0.1), r0: 0.32, r1: 0.42, seg: 18, hull)
            b.ellipsoid(SIMD3(-0.8, 0, -0.1), SIMD3(1.45, 1.0, 0.78), seg: 28, hull)
            b.mirrored { b, s in
                b.beam(SIMD3(-1.0, 0.85 * s, -0.25), SIMD3(-1.0, 1.35 * s, -0.25), width: 0.3, thick: 0.15, up: SIMD3(1, 0, 0), hull)
                b.tube(SIMD3(-1.7, 1.45 * s, -0.25), SIMD3(-0.4, 1.45 * s, -0.25), r0: 0.33, r1: 0.3, seg: 16, hull)
                b.ellipsoid(SIMD3(-1.72, 1.45 * s, -0.25), SIMD3(0.03, 0.27, 0.27), seg: 12, .engine(1.2))
                b.engine(SIMD3(-1.8, 1.45 * s, -0.25), r: 0.18)
            }
            b.torus(Xf(SIMD3(-2.25, 0, -0.05), rot: SIMD3(0, 90, 0)), R: 0.55, r: 0.11, seg: 28, side: 8, .engine(1.3))
            b.tube(SIMD3(-2.3, 0, -0.05), SIMD3(-2.0, 0, -0.05), r0: 0.22, seg: 12, hull)
            b.engine(SIMD3(-2.35, 0, -0.05), r: 0.3)
            b.plume(SIMD3(-2.35, 0, -0.05), r: 0.25, len: 1.2)
        },
        ShipDesign(id: "allianceCruiser", title: "Allianz-Kreuzer", universe: "Firefly", size: 9, glowHue: 40, panels: 110, windows: 1, yaw: -30, pitch: 18, finish: SIMD2(0.35, 0.35), wear: 0.25) { b in
            let hull = PartMat.hull(SIMD3(0.32, 0.33, 0.35), windows: 1)
            b.lathe([(-5, 0), (-5, 0.55), (-4, 0.9), (3, 0.9), (4.5, 0.5), (5, 0)], Xf(scale: SIMD3(1, 1, 0.6)), seg: 28, hull)
            for i in 0..<4 {
                let w = 1.4 - Float(i) * 0.25
                b.box(SIMD3(-1.0 + Float(i) * 0.4, 0, 0.6 + Float(i) * 0.3), SIMD3(6.0 - Float(i) * 1.2, w, 0.3), hull)
            }
            b.tube(SIMD3(-5.0, 0, 0), SIMD3(-5.4, 0, 0), r0: 0.4, seg: 16, .dark())
            b.ellipsoid(SIMD3(-5.4, 0, 0), SIMD3(0.03, 0.34, 0.34), seg: 12, .engine(1.2))
            b.engine(SIMD3(-5.45, 0, 0), r: 0.25)
        },
    ]

    static let odyssey: [ShipDesign] = [
        ShipDesign(id: "discovery", title: "Discovery One", universe: "2001", size: 9, glowHue: 40, panels: 60, windows: 0.2, yaw: -25, pitch: 15, finish: SIMD2(0.0, 0.6), wear: 0.15) { b in
            let hull = PartMat.hull(SIMD3(0.82, 0.82, 0.80))
            b.ellipsoid(SIMD3(4.3, 0, 0), SIMD3(0.55, 0.55, 0.55), seg: 26, hull)
            b.ellipsoid(SIMD3(4.8, 0, 0.05), SIMD3(0.08, 0.2, 0.12), seg: 12, .glass)
            b.tube(SIMD3(-2.6, 0, 0), SIMD3(3.8, 0, 0), r0: 0.08, seg: 10, hull)
            for i in 0..<8 {
                let x = 3.5 - Float(i) * 0.75
                b.tube(SIMD3(x - 0.62, 0, 0), SIMD3(x, 0, 0), r0: 0.18, seg: 12, hull)
            }
            b.box(SIMD3(-3.2, 0, 0), SIMD3(1.3, 0.9, 0.9), hull)
            for y in [Float(-0.3), 0, 0.3] {
                b.tube(SIMD3(-3.85, y, 0), SIMD3(-4.3, y, 0), r0: 0.14, r1: 0.24, seg: 12, .dark())
                b.engine(SIMD3(-4.3, y, 0), r: 0.1)
            }
        },
        ShipDesign(id: "monolith", title: "Monolith", universe: "2001", events: ["stargate"], size: 2.5, glowHue: 40, panels: 1, windows: 0, yaw: -30, pitch: 6, finish: SIMD2(0.0, 0.06), wear: 0.0) { b in
            b.box(.zero, SIMD3(1, 4, 9), .glass)
        },
        ShipDesign(id: "stationV", title: "Raumstation V", universe: "2001", station: true, size: 9, glowHue: 45, panels: 70, windows: 0.9, spin: 4, yaw: 0, pitch: 34, finish: SIMD2(0.05, 0.45), wear: 0.15) { b in
            let hull = PartMat.hull(SIMD3(0.82, 0.82, 0.8), windows: 1)
            b.tube(SIMD3(0, 0, -1.2), SIMD3(0, 0, 1.2), r0: 0.35, seg: 18, hull)
            for z in [Float(0.55), -0.55] {
                b.torus(Xf(SIMD3(0, 0, z)), R: 3.0, r: 0.3, seg: 80, side: 10, rz: 1.5, hull)
                for k in 0..<4 { let a = Float(k) * .pi / 2; b.beam(SIMD3(0, 0, z), SIMD3(cosf(a) * 3.0, sinf(a) * 3.0, z), width: 0.14, thick: 0.14, hull) }
            }
            b.ellipsoid(SIMD3(0, 0, 1.25), SIMD3(0.12, 0.12, 0.06), seg: 10, .glow(SIMD3(1.0, 0.9, 0.7), 1))
        },
    ]

    static let interstellar: [ShipDesign] = [
        ShipDesign(id: "endurance", title: "Endurance", universe: "Interstellar", events: ["wormhole"], size: 6, glowHue: 40, panels: 40, windows: 0.3, spin: 10, yaw: 0, pitch: 40, finish: SIMD2(0.1, 0.5), wear: 0.25) { b in
            let hull = PartMat.hull(SIMD3(0.82, 0.82, 0.80), windows: 0.3)
            b.torus(Xf(), R: 2.5, r: 0.07, seg: 72, side: 6, hull)
            for k in 0..<12 {
                let a = Float(k) * 30
                let d = SIMD3(cosf(a * .pi / 180), sinf(a * .pi / 180), 0)
                b.box(d * 2.5, SIMD3(0.55, 0.9, 0.5), rot: SIMD3(0, 0, a), k % 3 == 0 ? .gold : hull)
            }
            for k in 0..<4 { let a = Float(k) * .pi / 2 + .pi / 4; b.beam(.zero, SIMD3(cosf(a), sinf(a), 0) * 2.5, width: 0.08, thick: 0.08, hull) }
            b.tube(SIMD3(0, 0, -0.45), SIMD3(0, 0, 0.45), r0: 0.45, seg: 18, hull)
            b.box(SIMD3(0, 0, 0.62), SIMD3(0.9, 0.5, 0.18), hull)
        },
        ShipDesign(id: "ranger", title: "Ranger", universe: "Interstellar", size: 1.4, glowHue: 210, panels: 24, windows: 0, yaw: -35, pitch: 22, finish: SIMD2(0.1, 0.55), wear: 0.35) { b in
            let hull = PartMat.hull(SIMD3(0.78, 0.77, 0.74))
            b.prism([SIMD2(2.2, 0), SIMD2(0.8, 0.75), SIMD2(-1.6, 1.0), SIMD2(-1.6, -1.0), SIMD2(0.8, -0.75)], h: 0.5, top: 0.6, bottom: 0.9, Xf(), hull)
            b.box(SIMD3(-0.4, 0, 0.18), SIMD3(1.4, 0.5, 0.12), .dark())
            b.ellipsoid(SIMD3(0.9, 0, 0.18), SIMD3(0.45, 0.28, 0.1), seg: 12, .glass)
            b.mirrored { b, s in
                b.tube(SIMD3(-1.75, 0.4 * s, 0), SIMD3(-1.4, 0.4 * s, 0), r0: 0.2, r1: 0.15, seg: 12, .dark())
                b.ellipsoid(SIMD3(-1.76, 0.4 * s, 0), SIMD3(0.02, 0.16, 0.16), seg: 10, .engine(1.3))
                b.engine(SIMD3(-1.8, 0.4 * s, 0), r: 0.12)
            }
        },
    ]

    static let massEffect: [ShipDesign] = [
        ShipDesign(id: "normandy", title: "Normandy SR-2", universe: "Mass Effect", events: ["relay"], size: 2.6, glowHue: 205, panels: 34, windows: 0.2, yaw: -32, pitch: 20, finish: SIMD2(0.2, 0.26), wear: 0.15) { b in
            let hull = PartMat.hull(SIMD3(0.86, 0.87, 0.89), windows: 0.2)
            let black = PartMat.dark(SIMD3(0.1, 0.1, 0.11))
            b.prism([SIMD2(4.5, 0), SIMD2(2.0, 0.6), SIMD2(-1.8, 1.1), SIMD2(-3.6, 0.8), SIMD2(-3.6, -0.8), SIMD2(-1.8, -1.1), SIMD2(2.0, -0.6)],
                    h: 0.7, top: 0.72, bottom: 0.82, Xf(), hull)
            b.box(SIMD3(0.5, 0, 0.36), SIMD3(4.5, 0.3, 0.03), black)
            b.ellipsoid(SIMD3(2.6, 0, 0.22), SIMD3(0.6, 0.25, 0.1), seg: 12, .glass)
            b.mirrored { b, s in
                b.capsule(SIMD3(-3.8, 1.25 * s, -0.35), SIMD3(-1.0, 1.25 * s, -0.35), r: 0.28, hull)
                b.prism([SIMD2(-1.0, 0.9 * s), SIMD2(-2.6, 0.9 * s), SIMD2(-3.3, 2.2 * s), SIMD2(-2.5, 2.2 * s)], h: 0.07, top: 1, Xf(SIMD3(0, 0, -0.35)), hull)
                b.ellipsoid(SIMD3(-3.95, 1.25 * s, -0.35), SIMD3(0.06, 0.22, 0.22), seg: 12, .engine(1.5))
                b.engine(SIMD3(-4.0, 1.25 * s, -0.35), r: 0.18)
                b.prism([SIMD2(-2.4, 0.0), SIMD2(-3.4, 0.0), SIMD2(-3.6, 0.75), SIMD2(-3.0, 0.75)], h: 0.06, top: 1,
                        Xf(SIMD3(0, 0.55 * s, 0.25), rot: SIMD3(90 - 20 * s, 0, 0)), hull)
            }
        },
        ShipDesign(id: "reaper", title: "Reaper (Sovereign)", universe: "Mass Effect", events: ["relay"], size: 9, glowHue: 0, panels: 50, windows: 0, yaw: -30, pitch: 15, finish: SIMD2(0.55, 0.4), wear: 0.35) { b in
            let hull = PartMat.dark(SIMD3(0.22, 0.20, 0.19))
            b.lathe([(-3.6, 0), (-3.5, 0.45), (-1.0, 0.95), (1.8, 0.65), (3.2, 0)], Xf(), seg: 28, hull)
            for k in 0..<5 {
                let a = Float(k) / 5 * 2 * .pi + .pi / 2
                let d = SIMD3<Float>(0, cosf(a), sinf(a))
                b.capsule(SIMD3(-2.6, 0, 0) + d * 0.5, SIMD3(0.8, 0, 0) + d * 1.5, r: 0.2, hull)
                b.capsule(SIMD3(0.8, 0, 0) + d * 1.5, SIMD3(3.8, 0, 0) + d * 1.0, r: 0.12, hull)
            }
            b.ellipsoid(SIMD3(2.4, 0, -0.35), SIMD3(0.18, 0.18, 0.1), seg: 12, .glow(SIMD3(1.0, 0.15, 0.08), 1.5))
            b.engine(SIMD3(2.5, 0, -0.4), r: 0.12, SIMD3(1.0, 0.15, 0.08))
        },
        ShipDesign(id: "citadel", title: "Citadel", universe: "Mass Effect", station: true, size: 10, glowHue: 200, panels: 90, windows: 1, spin: 1, yaw: 0, pitch: 34, finish: SIMD2(0.4, 0.35), wear: 0.2) { b in
            let hull = PartMat.hull(SIMD3(0.62, 0.63, 0.66), windows: 1)
            b.torus(Xf(), R: 1.1, r: 0.28, seg: 48, side: 12, rz: 1.2, hull)
            b.tube(SIMD3(0, 0, -0.6), SIMD3(0, 0, 0.3), r0: 0.35, r1: 0.25, seg: 16, hull)
            for k in 0..<5 {
                let a = Float(k) * 72 * .pi / 180
                let d = SIMD3(cosf(a), sinf(a), 0)
                b.lathe([(0, 0.32), (0.5, 0.36), (1.0, 0.14), (1.02, 0)], Xf.along(d * 1.2, d * 5.2 + SIMD3(0, 0, 0.7), sy: 1.4, sz: 0.55), seg: 14, hull)
            }
            b.ellipsoid(SIMD3(0, 0, 0.35), SIMD3(0.22, 0.22, 0.12), seg: 12, .glow(SIMD3(0.6, 0.85, 1.0), 1))
        },
        ShipDesign(id: "massrelay", title: "Massenportal", universe: "Mass Effect", station: true, events: ["relay"], size: 10, glowHue: 210, panels: 60, windows: 0, spin: 0,
                   yaw: -40, pitch: 22, finish: SIMD2(0.5, 0.4), wear: 0.35) { b in
            let hull = PartMat.hull(SIMD3(0.55, 0.56, 0.6))
            b.box(SIMD3(-2.6, 0, 0), SIMD3(1.2, 1.5, 0.6), hull)
            b.mirrored { b, s in
                b.lathe([(0, 0.4), (1.0, 0.3)], Xf.along(SIMD3(-2.2, 0.8 * s, 0), SIMD3(0.4, 1.15 * s, 0)), seg: 14, hull)
                b.lathe([(0, 0.3), (0.8, 0.14), (1.0, 0.05), (1.02, 0)], Xf.along(SIMD3(0.4, 1.15 * s, 0), SIMD3(3.8, 0.55 * s, 0)), seg: 14, hull)
            }
            b.ellipsoid(SIMD3(0, 0, 0), SIMD3(0.45, 0.45, 0.45), seg: 18, .engine(1.6))
            b.torus(Xf(rot: SIMD3(0, 90, 0)), R: 0.75, r: 0.06, seg: 32, side: 6, hull)
            b.torus(Xf(rot: SIMD3(0, 90, 60)), R: 0.95, r: 0.05, seg: 32, side: 6, hull)
            b.engine(.zero, r: 0.5)
        },
    ]

    static let realSpace: [ShipDesign] = [
        ShipDesign(id: "iss", title: "ISS", universe: "Echte Raumfahrt", station: true, size: 5, glowHue: 40, panels: 60, windows: 0, yaw: -20, pitch: 30, finish: SIMD2(0.1, 0.5), wear: 0.25) { b in
            let white = PartMat.hull(SIMD3(0.85, 0.85, 0.83))
            let amber = PartMat(kind: .solar, col: SIMD3(0.42, 0.28, 0.12))
            b.box(.zero, SIMD3(0.25, 9.0, 0.25), white)
            b.tube(SIMD3(-2.0, 0, -0.35), SIMD3(2.4, 0, -0.35), r0: 0.3, seg: 16, white)
            b.tube(SIMD3(0.7, -1.0, -0.35), SIMD3(0.7, 1.0, -0.35), r0: 0.26, seg: 16, white)
            b.tube(SIMD3(-1.0, 0, -0.35), SIMD3(-1.0, 0, -1.3), r0: 0.24, seg: 14, white)
            for y in [Float(3.3), 4.3, -3.3, -4.3] {
                for x in [Float(1.5), -1.5] { b.box(SIMD3(x, y, 0), SIMD3(2.5, 0.75, 0.02), amber) }
                b.box(SIMD3(0, y, 0), SIMD3(0.5, 0.15, 0.15), white)
            }
            b.mirrored { b, s in b.box(SIMD3(0, 1.6 * s, 0.75), SIMD3(1.4, 0.45, 0.02), white) }
        },
        ShipDesign(id: "hubble", title: "Hubble", universe: "Echte Raumfahrt", size: 1.6, glowHue: 40, panels: 30, windows: 0, yaw: -35, pitch: 18, finish: SIMD2(0.6, 0.3), wear: 0.15) { b in
            let foil = PartMat.foil
            b.tube(SIMD3(-0.5, 0, 0), SIMD3(1.5, 0, 0), r0: 0.55, seg: 24, foil)
            b.tube(SIMD3(-1.6, 0, 0), SIMD3(-0.5, 0, 0), r0: 0.62, seg: 24, .steel(SIMD3(0.62, 0.62, 0.64), rough: 0.35))
            b.box(SIMD3(1.65, 0, 0.62), SIMD3(0.04, 1.1, 0.75), rot: SIMD3(0, -35, 0), foil)
            b.mirrored { b, s in
                b.box(SIMD3(0.0, 1.35 * s, 0), SIMD3(2.6, 1.3, 0.02), .solar)
                b.beam(SIMD3(0, 0.55 * s, 0), SIMD3(0, 0.75 * s, 0), width: 0.05, thick: 0.05, foil)
            }
        },
        ShipDesign(id: "jwst", title: "James Webb", universe: "Echte Raumfahrt", size: 3, glowHue: 40, panels: 30, windows: 0, yaw: -40, pitch: 20, finish: SIMD2(0.1, 0.5), wear: 0.1) { b in
            let shield = PartMat.hull(SIMD3(0.72, 0.62, 0.78))
            let kite: [SIMD2<Float>] = [SIMD2(2.6, 0), SIMD2(1.3, 1.35), SIMD2(-2.6, 1.35), SIMD2(-2.6, -1.35), SIMD2(1.3, -1.35)]
            for i in 0..<5 { b.prism(kite, h: 0.02, top: 1, Xf(SIMD3(0, 0, -0.9 + Float(i) * 0.08), scale: SIMD3(1 - Float(i) * 0.04, 1 - Float(i) * 0.04, 1)), shield) }
            // 18 gold hexagons of the primary mirror, facing forward and tilted up.
            let m = Xf(SIMD3(0.6, 0, 0.6), rot: SIMD3(0, -60, 0))
            let r: Float = 0.3
            let dx = r * 1.5, dy = r * sqrtf(3)
            var centres: [SIMD2<Float>] = []
            for q in -2...2 { for k in -2...2 {
                let p = SIMD2(Float(q) * dx, Float(k) * dy + Float(q) * dy / 2)
                let ring = max(abs(q), abs(k), abs(q + k))
                if ring >= 1 && ring <= 2 { centres.append(p) }
            } }
            for c in centres.prefix(18) {
                let hex = MeshBuilder.ngon(6, r * 0.96).map { $0 + c }
                b.prism(hex, h: 0.03, top: 1, m, .gold)
            }
            let tip = m.p(SIMD3(0, 0, 1.6))
            for a in [Float(0), 2.1, 4.2] { b.beam(m.p(SIMD3(cosf(a) * 1.1, sinf(a) * 1.1, 0)), tip, width: 0.03, thick: 0.03, shield) }
            b.ellipsoid(tip, SIMD3(0.12, 0.12, 0.05), seg: 10, .gold)
            b.box(SIMD3(-0.4, 0, -1.15), SIMD3(0.6, 0.6, 0.35), .dark())
        },
        ShipDesign(id: "voyagerProbe", title: "Voyager-Sonde", universe: "Echte Raumfahrt", size: 1.6, glowHue: 40, panels: 20, windows: 0, yaw: -30, pitch: 20, finish: SIMD2(0.1, 0.5), wear: 0.25) { b in
            let white = PartMat.paint(SIMD3(0.85, 0.85, 0.83), rough: 0.5)
            b.lathe([(0, 0), (0.1, 0.5), (0.22, 0.9), (0.26, 1.0), (0.24, 1.0)], Xf(SIMD3(0.1, 0, 0)), seg: 32, caps: false, white)
            b.tube(SIMD3(0.1, 0, 0), SIMD3(0.7, 0, 0), r0: 0.03, seg: 8, white)
            b.prism(MeshBuilder.ngon(10, 0.42), h: 0.35, top: 1, Xf(SIMD3(-0.15, 0, 0), rot: SIMD3(0, 90, 0)), .gold)
            b.tube(SIMD3(-0.15, 0, 0), SIMD3(-0.3, 4.4, 0.4), r0: 0.015, seg: 6, white)
            b.tube(SIMD3(-0.15, 0, 0), SIMD3(-0.4, -1.9, -0.3), r0: 0.04, seg: 8, white)
            b.tube(SIMD3(-0.42, -1.6, -0.25), SIMD3(-0.42, -2.1, -0.32), r0: 0.12, seg: 10, .dark())
            b.tube(SIMD3(-0.15, 0, 0), SIMD3(-0.3, 1.7, -0.2), r0: 0.04, seg: 8, white)
            b.box(SIMD3(-0.3, 1.75, -0.2), SIMD3(0.3, 0.3, 0.25), .dark())
        },
        ShipDesign(id: "apollo", title: "Apollo CSM", universe: "Echte Raumfahrt", size: 1.5, glowHue: 40, panels: 24, windows: 0, yaw: -35, pitch: 14, finish: SIMD2(0.9, 0.15), wear: 0.1) { b in
            // Command module and service module: polished aluminium, mirror-like.
            let silver = PartMat.steel(SIMD3(0.88, 0.88, 0.9), rough: 0.2)
            b.tube(SIMD3(1.0, 0, 0), SIMD3(2.2, 0, 0), r0: 0.75, r1: 0.12, seg: 28, silver)
            b.tube(SIMD3(-1.6, 0, 0), SIMD3(1.0, 0, 0), r0: 0.75, seg: 28, .steel(SIMD3(0.8, 0.8, 0.82), rough: 0.38))
            b.tube(SIMD3(-1.6, 0, 0), SIMD3(-2.6, 0, 0), r0: 0.25, r1: 0.55, seg: 20, .dark())
            b.ellipsoid(SIMD3(-2.58, 0, 0), SIMD3(0.02, 0.5, 0.5), seg: 14, .dark(SIMD3(0.05, 0.05, 0.05)))
            for k in 0..<4 { let a = Float(k) * .pi / 2 + .pi / 4; b.box(SIMD3(0.4, cosf(a) * 0.78, sinf(a) * 0.78), SIMD3(0.2, 0.12, 0.12), silver) }
            b.tube(SIMD3(-1.4, 0, -0.7), SIMD3(-1.4, 0, -1.3), r0: 0.03, seg: 6, silver)
            b.tube(SIMD3(-1.4, 0, -1.25), SIMD3(-1.4, 0, -1.35), r0: 0.1, r1: 0.25, seg: 12, silver)
        },
        ShipDesign(id: "starship", title: "Starship", universe: "Echte Raumfahrt", events: ["ignition"], size: 2.6, glowHue: 25, panels: 40, windows: 0, yaw: -32, pitch: 12, finish: SIMD2(0.95, 0.26), wear: 0.2) { b in
            let steel = PartMat.steel(SIMD3(0.72, 0.73, 0.75), rough: 0.26)
            b.tube(SIMD3(-4.0, 0, 0), SIMD3(3.0, 0, 0), r0: 0.6, seg: 28, steel)
            b.lathe([(3.0, 0.6), (3.6, 0.55), (4.2, 0.38), (4.6, 0.12), (4.7, 0)], Xf(), seg: 28, steel)
            b.mirrored { b, s in
                b.prism([SIMD2(3.0, 0.55 * s), SIMD2(3.9, 0.45 * s), SIMD2(3.7, 1.0 * s), SIMD2(3.0, 1.05 * s)], h: 0.05, top: 1, Xf(SIMD3(0, 0, -0.1)), .dark())
                b.prism([SIMD2(-2.4, 0.55 * s), SIMD2(-3.9, 0.55 * s), SIMD2(-3.9, 1.4 * s), SIMD2(-2.8, 1.3 * s)], h: 0.05, top: 1, Xf(SIMD3(0, 0, -0.1)), .dark())
            }
            for k in 0..<6 {
                let a = Float(k) * .pi / 3
                let r: Float = k % 2 == 0 ? 0.2 : 0.42
                let p = SIMD3<Float>(-4.0, cosf(a) * r, sinf(a) * r)
                b.tube(p, p + SIMD3(-0.35, 0, 0), r0: 0.08, r1: 0.13, seg: 10, .dark())
                b.engine(p + SIMD3(-0.4, 0, 0), r: 0.08)
            }
            b.plume(SIMD3(-4.4, 0, 0), r: 0.4, len: 3.5)
        },
    ]

    static let others: [ShipDesign] = [
        ShipDesign(id: "tardis", title: "TARDIS", universe: "Weitere", events: ["materialize"], size: 0.9, glowHue: 200, panels: 6, windows: 0, spin: 14,
                   spinAxis: SIMD3(0.4, 0.3, 1), yaw: -30, pitch: 10, finish: SIMD2(0.0, 0.55), wear: 0.35) { b in
            let blue = PartMat.accent(SIMD3(0.06, 0.16, 0.42))
            b.box(.zero, SIMD3(1.0, 1.0, 2.0), blue)
            b.box(SIMD3(0, 0, 1.06), SIMD3(1.1, 1.1, 0.12), blue)
            b.box(SIMD3(0, 0, 1.17), SIMD3(0.88, 0.88, 0.1), blue)
            b.box(SIMD3(0, 0, 0.86), SIMD3(1.06, 1.06, 0.16), .dark(SIMD3(0.03, 0.03, 0.04)))
            b.tube(SIMD3(0, 0, 1.22), SIMD3(0, 0, 1.42), r0: 0.07, seg: 12, .glow(SIMD3(0.85, 0.92, 1.0), 1.4))
            b.engine(SIMD3(0, 0, 1.35), r: 0.07, SIMD3(0.85, 0.92, 1.0))
            for k in 0..<4 {
                let a = Float(k) * .pi / 2
                let n = SIMD3(cosf(a), sinf(a), 0), t = SIMD3(-sinf(a), cosf(a), 0)
                for side in [Float(-1), 1] {
                    b.box(n * 0.505 + t * 0.2 * side + SIMD3(0, 0, 0.55), SIMD3(abs(n.x) * 0.01 + abs(t.x) * 0.3, abs(n.y) * 0.01 + abs(t.y) * 0.3, 0.22),
                          .glow(SIMD3(1.0, 0.95, 0.8), 0.7))
                }
                b.box(n * 0.53 + SIMD3(0, 0, 0.86), SIMD3(abs(n.x) * 0.01 + abs(t.x) * 0.7, abs(n.y) * 0.01 + abs(t.y) * 0.7, 0.08), .glow(SIMD3(0.9, 0.9, 0.95), 0.25))
            }
        },
        ShipDesign(id: "stargate", title: "Stargate-Tor", universe: "Weitere", station: true, events: ["kawoosh"], size: 5, glowHue: 25, panels: 40, windows: 0, yaw: -62, pitch: 4, finish: SIMD2(0.6, 0.45), wear: 0.45) { b in
            let stone = PartMat.hull(SIMD3(0.44, 0.44, 0.46))
            let t = Xf(rot: SIMD3(0, 90, 0))
            b.torus(t, R: 2.0, r: 0.3, seg: 72, side: 10, rz: 0.55, stone)
            b.torus(t, R: 1.72, r: 0.1, seg: 72, side: 8, rz: 1.2, .dark(SIMD3(0.2, 0.2, 0.22)))
            for k in 0..<9 {
                let a = (90 + Float(k) * 40) * .pi / 180
                let p = SIMD3<Float>(0, cosf(a) * 2.28, sinf(a) * 2.28)
                b.box(p, SIMD3(0.24, 0.26, 0.2), rot: SIMD3(Float(k) * 40, 0, 0), stone)
                b.box(p + SIMD3(0.13, 0, 0), SIMD3(0.04, 0.16, 0.1), rot: SIMD3(Float(k) * 40, 0, 0), .glow(SIMD3(1.0, 0.45, 0.12), 1.4))
            }
            b.plate(MeshBuilder.ngon(48, 1.64), t, .membrane(SIMD3(0.35, 0.6, 1.0)))
        },
        ShipDesign(id: "hatak", title: "Ha'tak", universe: "Weitere", events: ["hyperspace"], size: 8, glowHue: 35, panels: 50, windows: 0.3, yaw: -25, pitch: 30, finish: SIMD2(0.85, 0.3), wear: 0.3) { b in
            b.prism(MeshBuilder.ngon(4, 1.7, a0: 45), h: 2.0, top: 0.02, Xf(SIMD3(0, 0, 0.6)), .gold)
            let frame = PartMat.hull(SIMD3(0.55, 0.5, 0.42), windows: 0.4)
            b.prism(MeshBuilder.ngon(8, 1.9, a0: 22.5), h: 0.3, top: 0.95, Xf(SIMD3(0, 0, -0.35)), frame)
            b.torus(Xf(SIMD3(0, 0, -0.2)), R: 3.1, r: 0.14, seg: 64, side: 8, rz: 1.5, frame)
            for k in 0..<8 {
                let a = Float(k) * .pi / 4
                let d = SIMD3(cosf(a), sinf(a), 0)
                b.beam(d * 1.6 + SIMD3(0, 0, -0.3), d * 3.4 + SIMD3(0, 0, -0.1), width: 0.3, thick: 0.22, frame)
            }
            b.engine(SIMD3(0, 0, 1.62), r: 0.08, SIMD3(1.0, 0.8, 0.4))
        },
        ShipDesign(id: "kugelraumer", title: "Kugelraumer", universe: "Weitere", events: ["transition"], size: 8, glowHue: 50, panels: 70, windows: 0.9, yaw: 0, pitch: 16, finish: SIMD2(0.6, 0.32), wear: 0.25) { b in
            let hull = PartMat.hull(SIMD3(0.70, 0.70, 0.70), windows: 0.9)
            b.ellipsoid(.zero, SIMD3(1.5, 1.5, 1.5), seg: 48, hull)
            b.torus(Xf(), R: 1.55, r: 0.17, seg: 64, side: 10, rz: 0.75, .hull(SIMD3(0.55, 0.55, 0.56), windows: 0.4))
            b.torus(Xf(), R: 1.72, r: 0.02, seg: 64, side: 6, .engine(0.9))
            for k in 0..<4 {
                let a = Float(k) * .pi / 2 + .pi / 4
                b.beam(SIMD3(cosf(a) * 1.0, sinf(a) * 1.0, -1.05), SIMD3(cosf(a) * 1.45, sinf(a) * 1.45, -1.75), width: 0.12, thick: 0.12, hull)
            }
        },
        ShipDesign(id: "nostromo", title: "Nostromo", universe: "Weitere", size: 7, glowHue: 30, panels: 80, windows: 0.3, yaw: -30, pitch: 18, finish: SIMD2(0.35, 0.55), wear: 0.85) { b in
            let hull = PartMat.hull(SIMD3(0.36, 0.36, 0.35), windows: 0.4)
            let dark = PartMat.dark(SIMD3(0.2, 0.2, 0.2))
            b.box(SIMD3(0.3, 0, 0), SIMD3(4.0, 1.6, 1.1), hull)
            b.prism([SIMD2(3.4, -0.4), SIMD2(2.3, 0.55), SIMD2(1.8, 0.55), SIMD2(1.8, -0.55), SIMD2(3.0, -0.55)], h: 1.2, top: 0.9, Xf(rot: SIMD3(90, 0, 0)), hull)
            b.box(SIMD3(2.45, 0, 0.22), SIMD3(0.3, 0.9, 0.1), rot: SIMD3(0, -40, 0), .glass)
            var rng = SeedRNG(7)
            for _ in 0..<14 {
                let p = SIMD3(rng.range(-1.4...1.8), rng.range(-0.7...0.7), 0.55)
                let sz = SIMD3(rng.range(0.2...0.7), rng.range(0.2...0.6), rng.range(0.15...0.9))
                b.box(p + SIMD3(0, 0, sz.z / 2), sz, rng.next() < 0.5 ? dark : hull)
            }
            b.box(SIMD3(-0.4, 0.3, 1.25), SIMD3(0.5, 0.4, 0.9), hull)
            b.box(SIMD3(0.6, -0.4, 1.15), SIMD3(0.4, 0.35, 1.2), hull)
            b.box(SIMD3(-2.4, 0, 0), SIMD3(1.3, 2.4, 1.7), hull)
            for (y, z) in [(Float(-0.7), Float(0.3)), (0.7, 0.3), (0, -0.4)] {
                b.tube(SIMD3(-3.05, y, z), SIMD3(-3.5, y, z), r0: 0.32, r1: 0.42, seg: 14, dark)
                b.ellipsoid(SIMD3(-3.48, y, z), SIMD3(0.03, 0.36, 0.36), seg: 12, .engine(1.2))
                b.engine(SIMD3(-3.55, y, z), r: 0.25)
            }
        },
        ShipDesign(id: "heartOfGold", title: "Heart of Gold", universe: "Weitere", events: ["improbability"], size: 3, glowHue: 50, panels: 6, windows: 0, yaw: -30, pitch: 18, finish: SIMD2(0.0, 0.14), wear: 0.05) { b in
            let white = PartMat(kind: .glass, col: SIMD3(0.88, 0.88, 0.9))
            b.ellipsoid(SIMD3(0, 0, 0.25), SIMD3(3.0, 1.0, 0.85), seg: 40, white)
            b.ellipsoid(SIMD3(0.05, 0, -0.32), SIMD3(3.15, 1.08, 0.2), seg: 40, white)
            b.ellipsoid(SIMD3(1.4, 0, 0.9), SIMD3(0.8, 0.5, 0.35), seg: 24, white)
            b.ellipsoid(SIMD3(-2.95, 0, -0.1), SIMD3(0.06, 0.4, 0.2), seg: 14, .engine(1.2))
        },
    ]
}
