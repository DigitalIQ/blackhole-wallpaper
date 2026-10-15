import Foundation
import simd

/// One galaxy to bake into the atlas: shader parameters (GalBake) and its tile.
struct GalaxyBake: Equatable {
    var params: [SIMD4<Float>]
    var tile: Int
}

/// A far star's image source for the camera glow and spikes drawn in path F.
struct StarGlow {
    var dir: SIMD3<Float>       // camera frame
    var col: SIMD3<Float>
    var rho: Float              // core radius (rad)
    var glow: Float
    var reach: Float            // rad
    var spikes: Int
    var seed: UInt32
}

/// What the shaders need from the objects for one frame.
struct ObjectFrame {
    /// Path S: five float4 per sky object (SkyObj in ObjectShaders).
    var sky: [SIMD4<Float>] = []
    var skyCount = 0
    /// objA, jetC, jetK, jetP: appended to FrameParams.
    var params: [SIMD4<Float>] = Array(repeating: .zero, count: 4)
    var galaxies: [GalaxyBake] = []
    var starGlows: [StarGlow] = []
    var tileSize = 512
    var jetOn: Bool { params[0].z > 0.5 }

    /// Atlas size in tiles: up to four in a row.
    var atlasTiles: (Int, Int) {
        let n = max(galaxies.count, 1)
        return (min(n, 4), (n + 3) / 4)
    }

    var atlasKey: String { "galaxies \(tileSize) " + galaxies.map { "\($0.params)" }.joined(separator: "|") }
}

/// Per-frame state of the objects of one renderer: clocks and the packed shader data.
/// Motion is a pure function of the clock, the seed and the parameters; the phases only
/// integrate rates, so moving a tempo slider never makes anything jump.
final class ObjectSystem {
    private var phases: [String: Double] = [:]
    /// Screen centres of the wormholes of the last lens frame (ships fly into the nearest).
    var wormholeTargets: [SIMD2<Float>] = []
    /// Quality levels of the renderer that owns this system (galaxy tiles, body atlas, lens maps, light buffer).
    var quality = RenderQuality()

    static let maxSky = 32
    static let maxGalaxies = 8

    // MARK: Clocks

    /// Phase keys and their rates (units per second) for everything that moves.
    private func rates(_ look: Look) -> [(String, Double)] {
        let scene = look.objects
        let sp = Double(scene.speed)
        var out: [(String, Double)] = []
        for o in scene.active {
            let id = o.id
            switch (o.objectKind, o.variant) {
            case (.star, _) where o.motion.mode != .sky:
                out += bodyRates(o, look: look, sp: sp)
                if o.variant == "binary" { out.append(("\(id).orbit", 1 / Double(max(o.param("period"), 1)) * sp)) }
                if o.variant == "cepheid" { out.append(("\(id).pulse", 1 / Double(max(o.param("pulsePeriod"), 0.5)) * sp)) }
            case (.planet, _), (.moon, _), (.asteroid, _), (.comet, _):
                out += bodyRates(o, look: look, sp: sp)
            case (.ship, _), (.station, _), (.model, _):
                out += shipRates(o, look: look, sp: sp)
            case (.blackHole, _), (.wormhole, _):
                out += lensRates(o, look: look, sp: sp)
            case (.belt, _):
                out.append(("\(id).belt", 2 * .pi / Double(max(look.diskPeriod, 0.5)) * Double(o.motion.tempo) * sp))
            case (.meteor, _):
                out.append(("\(id).t", sp))
            case (.galaxy, _), (.star, _):
                if o.motion.drift != 0 { out.append(("\(id).drift", Double(o.motion.drift) / 60 * sp)) }
                switch o.variant {
                case "pulsar": out.append(("\(id).spin", 1 / Double(max(o.param("spinPeriod"), 0.05)) * sp))
                case "cepheid": out.append(("\(id).pulse", 1 / Double(max(o.param("pulsePeriod"), 0.5)) * sp))
                case "binary": out.append(("\(id).orbit", 1 / Double(max(o.param("period"), 1)) * sp))
                case "magnetar": out.append(("\(id).t", sp))
                default: break
                }
            case (.jet, _):
                let front = 1 / Double(max(o.param("knotSpacing"), 0.01)) / Double(max(o.param("knotPeriod"), 0.5))
                out.append(("\(id).kf", front * sp))
                out.append(("\(id).kb", front * Double(ObjectSystem.knotRatio(look, o)) * sp))
                out.append(("\(id).pulse", 1 / Double(max(o.param("pulsePeriod"), 0.5)) * sp))
            default: break
            }
        }
        return out
    }

    /// Clocks of one body: spin, clouds, surface time, orbit or pass.
    func bodyRates(_ o: SpaceObject, look: Look, sp: Double) -> [(String, Double)] {
        let id = o.id
        var out: [(String, Double)] = []
        let rot = o.objectKind == .star ? 80 : Double(max(o.param("rotation"), 1))
        out.append(("\(id).spin", sp / rot))
        out.append(("\(id).cloud", sp * Double(o.param("cloudSpeed")) / rot))
        out.append(("\(id).t", sp))
        switch o.motion.mode {
        case .orbit:
            let T: Double
            if o.objectKind == .moon {
                T = 25 * pow(Double(max(o.motion.radius, 1.2)) / 3, 1.5)
            } else {
                // A second hole orbits with the sum of both masses.
                let mass: Float = o.objectKind == .blackHole ? 1 + max(o.size, 0.02) : 1
                T = Orbits.period(min(max(o.motion.radius, 6), look.cameraDistance * 0.92), look: look, mass: mass)
            }
            out.append(("\(id).kep", sp * Double(max(o.motion.tempo, 0)) / max(T, 0.1)))
        case .flyby:
            out.append(("\(id).fly", sp * Double(max(o.motion.tempo, 0))))
        default: break
        }
        return out
    }

    func advance(_ dt: Float, look: Look) {
        for (k, r) in rates(look) { phases[k, default: 0] += Double(dt) * r }
    }

    func reset(_ t: Float, look: Look) {
        phases = [:]
        for (k, r) in rates(look) { phases[k] = Double(t) * r }
    }

    func phase(_ key: String) -> Double { phases[key] ?? 0 }

    /// Apparent speed of the counter jet's knots relative to the main jet's:
    /// beta sin(i) / (1 + beta cos(i)) over beta sin(i) / (1 - beta cos(i)).
    static func knotRatio(_ look: Look, _ jet: SpaceObject) -> Float {
        let b = jet.param("beta"), c = cosf(look.inclinationDeg * .pi / 180)
        return (1 - b * c) / (1 + b * c)
    }

    // MARK: Jet geometry for the ray pass

    /// jet0, jet1, jet2 of GeoParams; zeros without a jet.
    static func jetGeo(_ look: Look) -> [SIMD4<Float>] {
        guard let j = look.objects.mainJet else { return [.zero, .zero, .zero, .zero] }
        let r0 = look.cameraDistance
        let incl = look.inclinationDeg * .pi / 180
        let L = min(j.param("length"), 1.5 * r0)
        let base = j.param("base"), w0 = j.param("width"), k = j.param("shape")
        // The parabola turns into the cone where its slope k w / z drops to the cone's.
        let tanO = tanf(max(j.param("opening"), 0.2) * .pi / 180)
        let zt = max(base * powf(max(k * w0 / (tanO * base), 1e-3), 1 / max(1 - k, 0.05)), base)
        return [
            SIMD4(1, max(L, base * 2), w0, k),
            SIMD4(min(j.param("beta"), 0.995), j.param("doppler"), base, j.param("counterJet") > 0.5 ? 1 : 0),
            SIMD4(max(0.6 * r0 * sinf(incl), 0.3), j.param("sheath"), min(zt, 1e4), tanO),
            SIMD4(j.param("falloff"), j.param("wobble"), -shadowCentre(spin: look.spin, incl: incl), cosf(incl) / r0),
        ]
    }

    /// Horizontal centre of the Kerr shadow seen from far away, in M, measured from the projected spin
    /// axis (midpoint of the critical curve's left and right edge). The camera shifts the picture by
    /// about 2 a sin(i) so the shadow lands on the hole position; the exact centre is a little further
    /// out (a = 0.9, i = 66 degrees: 1.84 instead of 1.64). The jet is moved by this much so it stands
    /// on the shadow's centre line instead of on the true axis beside it.
    static func shadowCentre(spin: Float, incl: Float) -> Float {
        let a = Double(min(max(spin, 0), 0.999)), si = Double(sinf(incl)), ci = Double(cosf(incl))
        guard a > 1e-3, si > 1e-3 else { return 0 }
        let r1 = 2 * (1 + cos(2.0 / 3.0 * acos(-a))), r2 = 2 * (1 + cos(2.0 / 3.0 * acos(a)))
        var lo = Double.infinity, hi = -Double.infinity
        let n = 2000
        for k in 0...n {
            let r = r1 + (r2 - r1) * Double(k) / Double(n)
            let xi = (r * r * (3 - r) - a * a * (r + 1)) / (a * (r - 1))
            let eta = r * r * r * (4 * a * a - r * (r - 3) * (r - 3)) / (a * a * (r - 1) * (r - 1))
            guard eta + a * a * ci * ci - xi * xi * ci * ci / (si * si) >= 0 else { continue }
            lo = min(lo, -xi / si); hi = max(hi, -xi / si)
        }
        return lo <= hi ? Float((lo + hi) / 2) : Float(2 * a * si)
    }

    /// Where the jet axis stands on screen, as a fraction of the shorter side right of the hole position:
    /// the camera's shift 2 a sin(i) minus the shadow centre (a few pixels).
    static func jetAxisOffset(_ look: Look) -> Float {
        let incl = look.inclinationDeg * .pi / 180
        return (2 * look.spin * sinf(incl) - shadowCentre(spin: look.spin, incl: incl)) * look.holeSize / 5.2
    }

    // MARK: Packing

    func frame(look: Look, width: Int, height: Int) -> ObjectFrame {
        var f = ObjectFrame()
        let scene = look.objects
        let active = scene.active
        guard !active.isEmpty else { return f }
        f.tileSize = quality.galaxyTile
        let S = Float(min(width, height))
        let mPerS: Float = 5.2 / look.holeSize
        let pxAng = mPerS / (look.cameraDistance * S)   // rad per pixel, unlensed
        let pal = look.linearPalette

        for o in active {
            switch o.objectKind {
            case .galaxy: packGalaxy(o, &f)
            case .star where o.motion.mode == .sky: packStar(o, &f)
            case .jet:
                guard f.params[0].z == 0, o.attach.isEmpty || o.attach == "main" else { continue }
                packJet(o, look: look, pal: pal, &f)
            default: break
            }
        }
        f.params[0].x = Float(f.skyCount)
        f.params[0].y = Renderer.maskMargin
        f.params[0].w = pxAng
        // Galaxy tile rects in atlas uv, now that the atlas size is known.
        let (cols, rows) = f.atlasTiles
        for i in 0..<f.skyCount where f.sky[i * 5 + 1].w == 1 {
            let idx = Int(f.sky[i * 5 + 3].x)
            let cx = Float(idx % cols), cy = Float(idx / cols)
            f.sky[i * 5 + 3] = SIMD4(cx / Float(cols), cy / Float(rows), (cx + 1) / Float(cols), (cy + 1) / Float(rows))
        }
        return f
    }

    private static let deg: Float = .pi / 180

    /// Centre direction in the camera frame (x right, y up, z towards the hole) and a tangent basis.
    private func skyBasis(_ o: SpaceObject, angle: Float) -> (SIMD3<Float>, SIMD3<Float>) {
        let m = o.motion
        let drift = Float(phase("\(o.id).drift").truncatingRemainder(dividingBy: 360))
        let az = (m.azimuth + drift * cosf(m.driftAngle * ObjectSystem.deg)) * ObjectSystem.deg
        let el = (m.elevation + drift * sinf(m.driftAngle * ObjectSystem.deg)) * ObjectSystem.deg
        let d = SIMD3<Float>(sinf(az) * cosf(el), sinf(el), cosf(az) * cosf(el))
        let e = SIMD3<Float>(cosf(az), 0, -sinf(az))
        let n = simd_cross(d, e)
        let u = e * cosf(angle) + n * sinf(angle)
        return (d, simd_normalize(u))
    }

    private func colour(_ o: SpaceObject, base: SIMD3<Float>) -> SIMD3<Float> {
        let t = Palette.linear(o.tint)
        return simd_mix(base, t * simd_reduce_max(base), SIMD3(repeating: min(max(o.tintAmount, 0), 1)))
    }

    private func push(_ f: inout ObjectFrame, _ v: [SIMD4<Float>]) {
        guard f.skyCount < ObjectSystem.maxSky else { return }
        f.sky += v
        f.skyCount += 1
    }

    /// Picker index of a pair member to the subtype code of the galaxy shader (0 spiral for anything unknown).
    private func pairCode(_ i: Float) -> Float {
        let k = Int(i.rounded())
        return ObjectCatalog.pairTypeCodes.indices.contains(k) ? ObjectCatalog.pairTypeCodes[k] : 0
    }

    private func packGalaxy(_ o: SpaceObject, _ f: inout ObjectFrame) {
        guard f.galaxies.count < ObjectSystem.maxGalaxies, f.skyCount < ObjectSystem.maxSky else { return }
        let types = ["spiral": 0, "barred": 1, "edgeOn": 2, "elliptical": 3, "lenticular": 4,
                     "irregular": 5, "ring": 6, "pair": 7, "quasar": 8]
        let type = Float(types[o.variant] ?? 0)
        let tile = f.galaxies.count
        let bake: [SIMD4<Float>] = [
            SIMD4(type, Float(o.seed % 997) * 1.37, o.param("arms").rounded(), o.param("winding")),
            SIMD4(o.param("bar"), o.param("bulge"), 0, o.param("dust")),
            SIMD4(o.param("starForming"), o.param("youngMix"), min(o.param("tilt"), 89.5) * ObjectSystem.deg, o.param("flatten")),
            SIMD4(o.param("jets"), pairCode(o.param("typeA")), pairCode(o.param("typeB")), 0),
        ]
        f.galaxies.append(GalaxyBake(params: bake, tile: tile))
        let (d, u) = skyBasis(o, angle: o.param("angle") * ObjectSystem.deg)
        let R = max(o.size, 0.05) * 0.5 * ObjectSystem.deg
        let core = o.param("core") * (o.variant == "quasar" ? 1.6 : 0.5)
        let cr = R * (o.variant == "quasar" ? 0.006 : 0.012)
        let reach = max(R * 1.42, cr * 40)
        let col = colour(o, base: SIMD3(repeating: 1)) * o.brightness * 0.9
        // Tile rect filled in by the renderer once the atlas size is known; store the index for now.
        push(&f, [SIMD4(d, cosf(min(reach, 1.5))), SIMD4(u, 1), SIMD4(col, 0), SIMD4(Float(tile), 0, 0, 0),
                  SIMD4(R, Float(f.tileSize), core, cr)])
    }

    private func packStar(_ o: SpaceObject, _ f: inout ObjectFrame) {
        var T = o.param("temperature")
        var bright = o.brightness
        let size = max(o.size, 0.02)
        let rho = size * 0.12 * ObjectSystem.deg
        let glow = o.param("glow")
        let reach = min(rho * 40, 1.2)
        // The glow is drawn in path F; the sky pass only needs the core.
        let coreReach = rho * 4
        let spikes = Int(o.param("spikes").rounded())
        let seedF = Float(o.seed % 1000)
        switch o.variant {
        case "cepheid":
            let p = Float(phase("\(o.id).pulse").truncatingRemainder(dividingBy: 1))
            // Fast rise, slow decline, like a real Cepheid light curve.
            let lc = p < 0.15 ? p / 0.15 : 1 - (p - 0.15) / 0.85
            let s = lc * lc * (3 - 2 * lc)
            let depth = o.param("pulseDepth")
            bright *= 1 + depth * (s - 0.5) * 1.6
            T *= 1 + 0.12 * depth * (s - 0.5)
        case "magnetar":
            let t = phase("\(o.id).t")
            let per = 60 / Double(max(o.param("flareRate"), 0.1))
            let k = floor(t / per)
            var flare: Float = 0
            for j in [k - 1, k] where j >= 0 {
                let tk = (j + Double(ObjectSystem.hash(o.seed, Int(j))) * 0.8) * per
                let amp = 2 + 6 * ObjectSystem.hash(o.seed &+ 7, Int(j))
                if t >= tk { flare += amp * Float(exp(-(t - tk) / 0.35)) * Float(min((t - tk) / 0.04, 1)) }
            }
            bright *= 1 + flare
            T += 20000 * min(flare / 4, 1)
        default: break
        }

        if o.variant == "binary" {
            let p = Float(phase("\(o.id).orbit").truncatingRemainder(dividingBy: 1)) * 2 * .pi
            let ang = o.param("angle") * ObjectSystem.deg
            let (d, u) = skyBasis(o, angle: 0)
            let v = simd_cross(d, u)
            let sep = o.param("separation") * size * 0.5 * ObjectSystem.deg
            var off = SIMD2<Float>(cosf(p), sinf(p) * 0.45) * sep
            off = SIMD2(off.x * cosf(ang) - off.y * sinf(ang), off.x * sinf(ang) + off.y * cosf(ang))
            let T2 = o.param("temperature2")
            for (k, (temp, share, b)) in [(T, Float(-0.4), Float(1)), (T2, Float(0.6), Float(0.75))].enumerated() {
                let dd = simd_normalize(d + u * off.x * share + v * off.y * share)
                let col = colour(o, base: ObjectSystem.blackbody(temp)) * bright * b * 4
                push(&f, [SIMD4(dd, cosf(coreReach)), SIMD4(simd_normalize(u - dd * simd_dot(u, dd)), 0),
                          SIMD4(col, rho * (k == 0 ? 1 : 0.8)), SIMD4(glow, reach, 0, 0), .zero])
                f.starGlows.append(StarGlow(dir: dd, col: col, rho: rho * (k == 0 ? 1 : 0.8), glow: glow, reach: reach,
                                            spikes: spikes, seed: o.seed &+ UInt32(k)))
            }
            return
        }

        let ang = o.param("angle") * ObjectSystem.deg
        let (d, u) = skyBasis(o, angle: ang)
        if o.variant == "pulsar" {
            // The camera lies on the cone the beam sweeps: zeta = alpha.
            let alpha = o.param("beamTilt") * ObjectSystem.deg
            let w = max(o.param("beamWidth"), 1) * 0.5 * ObjectSystem.deg
            let p = Float(phase("\(o.id).spin").truncatingRemainder(dividingBy: 1)) * 2 * .pi
            let los = -d
            let spin = simd_normalize(los * cosf(alpha) + u * sinf(alpha))
            let xp = simd_normalize(los - spin * simd_dot(los, spin))
            let yp = simd_cross(spin, xp)
            let b = xp * (sinf(alpha) * cosf(p)) + yp * (sinf(alpha) * sinf(p)) + spin * cosf(alpha)
            func hit(_ beam: SIMD3<Float>) -> Float {
                let a = acosf(min(max(simd_dot(beam, los), -1), 1))
                return expf(-(a / w) * (a / w))
            }
            let flash = hit(b) + hit(-b)
            let v = simd_cross(d, u)
            let bp = b - los * simd_dot(b, los)
            let coneAng = atan2f(simd_dot(bp, v), simd_dot(bp, u))
            let inPlane = simd_length(bp)
            let toward = simd_dot(b, los)
            let col = colour(o, base: ObjectSystem.blackbody(T)) * bright * 4 * (0.3 + 3 * flash)
            let len = size * 3 * ObjectSystem.deg
            let pr = max(reach, len * 2.2)
            f.starGlows.append(StarGlow(dir: d, col: col, rho: rho, glow: glow, reach: reach, spikes: spikes, seed: o.seed))
            push(&f, [SIMD4(d, cosf(pr)), SIMD4(u, 2), SIMD4(col, rho),
                      SIMD4(cosf(coneAng), sinf(coneAng), tanf(w), o.param("coneGlow") / max(0.3 + 3 * flash, 0.3)),
                      SIMD4(inPlane * (0.6 + 0.4 * toward), inPlane * (0.6 - 0.4 * toward), glow, pr)])
            return
        }
        let col = colour(o, base: ObjectSystem.blackbody(T)) * bright * 4
        push(&f, [SIMD4(d, cosf(coreReach)), SIMD4(u, 0), SIMD4(col, rho), SIMD4(glow, reach, 0, 0), .zero])
        f.starGlows.append(StarGlow(dir: d, col: col, rho: rho, glow: glow, reach: reach, spikes: spikes, seed: o.seed))
        if o.variant == "wolfRayet" {
            let Rs = o.param("shell") * size * 0.5 * ObjectSystem.deg
            push(&f, [SIMD4(d, cosf(min(Rs * 1.7, 1.2))), SIMD4(u, 3), SIMD4(SIMD3(repeating: o.brightness), 0),
                      SIMD4(Rs, Rs * 0.12, seedF * 0.37, o.param("shellGlow")), .zero])
        }
    }

    private func packJet(_ o: SpaceObject, look: Look, pal: [SIMD3<Float>], _ f: inout ObjectFrame) {
        let mode = Int(o.param("colourMode").rounded())
        var c: SIMD3<Float>
        switch mode {
        case 1: c = simd_mix(pal[5], pal[4], SIMD3(repeating: 0.35))
        case 2: c = Palette.linear(o.tint)
        default: c = SIMD3(0.55, 0.72, 1.0)
        }
        c /= max(simd_dot(c, SIMD3(0.2126, 0.7152, 0.0722)), 1e-3)
        if mode != 2 { c = colour(o, base: c) }
        f.params[0].z = 1
        // Divide by the boost of the approaching jet seen from this angle, so the brightness
        // slider means the same at every angle; the ratio jet to counter jet stays physical.
        let b = min(o.param("beta"), 0.995), sh = o.param("sheath")
        let cth = cosf(look.inclinationDeg * .pi / 180)
        func boost(_ beta: Float) -> Float { powf(1 / ((1 / (1 - beta * beta).squareRoot()) * (1 - beta * cth)), 2.7) }
        let front = 1 + (((1 - sh) * boost(b) + sh * boost(min(b, 0.3))) - 1) * o.param("doppler")
        f.params[1] = SIMD4(c, o.brightness * 1.2 / max(front, 0.05))
        let kf = Float(phase("\(o.id).kf").truncatingRemainder(dividingBy: 256))
        let kb = Float(phase("\(o.id).kb").truncatingRemainder(dividingBy: 256))
        f.params[2] = SIMD4(o.param("knots"), kf, kb, o.param("knotSpacing"))
        f.params[3] = SIMD4(o.param("pulse"), Float(phase("\(o.id).pulse").truncatingRemainder(dividingBy: 1)), o.param("filaments"), ObjectSystem.jetAxisOffset(look))
    }

    // MARK: Helpers

    /// 0..1 from a seed and an index, for event times.
    static func hash(_ seed: UInt32, _ i: Int) -> Float {
        var r = SeedRNG(seed &+ UInt32(truncatingIfNeeded: i &* 7919))
        return r.next()
    }

    /// Star colour from temperature, like blackbody() in the shader. Linear RGB, luminance 1.
    static func blackbody(_ T: Float) -> SIMD3<Float> {
        let t = T / 100
        func sat(_ x: Float) -> Float { min(max(x, 0), 1) }
        let r: Float = t <= 66 ? 1 : sat(1.292936 * powf(t - 60, -0.1332047))
        let g: Float = t <= 66 ? sat(0.39008158 * logf(t) - 0.63184144) : sat(1.129890 * powf(t - 60, -0.0755148))
        let b: Float = t >= 66 ? 1 : (t <= 19 ? 0 : sat(0.54320679 * logf(t - 10) - 1.19625409))
        let c = SIMD3(powf(r, 2.2), powf(g, 2.2), powf(b, 2.2))
        return c / max(simd_dot(c, SIMD3(0.2126, 0.7152, 0.0722)), 1e-3)
    }
}
