import Foundation
import simd

/// The pinhole camera of the ray tracer in world coordinates (Boyer-Lindquist cartesian,
/// spin axis z, disk in z = 0). A pixel's unlensed direction is (alpha, beta, r0) with the
/// same impact parameters as in traceRay, including the shift that centres the shadow.
struct CamFrame {
    var pos: SIMD3<Float>
    var right: SIMD3<Float>, up: SIMD3<Float>, fwd: SIMD3<Float>
    var r0: Float           // camera distance (M)
    var mPerS: Float        // M per shorter screen side at the hole
    var S: Float            // shorter screen side (px)
    var W: Float, H: Float
    var c: SIMD2<Float>     // hole (shadow centre) in px
    var shift: Float        // 2 a sin i (M): shadow offset the tracer removes
    var holeDepth: Float    // depth of the hole along fwd
    var pxPerM: Float { S / mPerS }
    /// Shadow radius on screen (px).
    var shadowPx: Float

    init(look: Look, layout: ScreenLayout, width: Int, height: Int) {
        let a = look.spin, th = look.inclinationDeg * .pi / 180
        r0 = look.cameraDistance
        pos = SIMD3((r0 * r0 + a * a).squareRoot() * sinf(th), 0, r0 * cosf(th))
        fwd = -simd_normalize(pos)
        var r = simd_cross(fwd, SIMD3(0, 0, 1))
        if simd_length(r) < 1e-4 { r = SIMD3(0, 1, 0) }
        right = simd_normalize(r)
        up = simd_cross(right, fwd)
        W = Float(width); H = Float(height)
        S = min(W, H)
        mPerS = 5.2 / look.holeSize
        c = SIMD2(layout.holeX * W, layout.holeY * H)
        shift = 2 * a * sinf(th)
        holeDepth = simd_length(pos)
        shadowPx = look.holeSize * S
    }

    /// Camera coordinates of a world point: x right, y up, z depth.
    func cam(_ X: SIMD3<Float>) -> SIMD3<Float> {
        let v = X - pos
        return SIMD3(simd_dot(v, right), simd_dot(v, up), simd_dot(v, fwd))
    }

    /// Screen position of a camera-frame direction (any length, in front of the camera). The tracer
    /// starts a ray at angle psi from the hole with impact parameter r0 sin(psi).
    func px(dir d: SIMD3<Float>) -> SIMD2<Float> {
        let n = d / max(simd_length(d), 1e-6)
        return c + SIMD2(n.x * r0 + shift, -n.y * r0) * pxPerM
    }

    /// Unlensed camera-frame direction of a pixel.
    func dir(px p: SIMD2<Float>) -> SIMD3<Float> {
        let s = SIMD2((p.x - c.x) / pxPerM - shift, -(p.y - c.y) / pxPerM) / r0
        return SIMD3(s.x, s.y, max(1 - simd_dot(s, s), 0).squareRoot())
    }

    /// Pixels per M of size at a given depth.
    func scale(depth z: Float) -> Float { pxPerM * r0 / max(z, 1e-3) }

    /// Lens weight of the thin-lens lookup: share of the depth behind the hole plane.
    func lensWeight(depth z: Float) -> Float { min(max((z - holeDepth) / max(z, 1e-3), 0), 1) }

    /// World point at a pixel and depth.
    func world(px p: SIMD2<Float>, depth z: Float) -> SIMD3<Float> {
        let d = dir(px: p)
        let t = z / d.z
        return pos + (right * d.x + up * d.y + fwd * d.z) * t
    }

    /// Images of a point behind the hole under a point lens (Schwarzschild, weak field), for
    /// glows and particles that are drawn forward. Returns (px, magnification) per image; one
    /// image in front of the hole plane.
    func images(_ X: SIMD3<Float>) -> [(SIMD2<Float>, Float)] {
        let q = cam(X)
        guard q.z > 0.5 else { return [] }
        let dls = q.z - holeDepth
        let beta = SIMD2(q.x / q.z, q.y / q.z)
        guard dls > 0 else { return [(px(dir: q), 1)] }
        return lensed(beta, thetaE2: 4 * dls / (holeDepth * q.z))
    }

    /// Images of a source at infinity (camera-frame direction) as the ray map has them: a ray with
    /// impact parameter b leaves the camera at sin(psi) = b / r0 and bends by
    /// (2 M / b) (cos at the camera + cos at 1.6 r0, where the tracer stops). Solved per image side.
    func skyImages(_ d: SIMD3<Float>) -> [(SIMD2<Float>, Float)] {
        let n = simd_normalize(d)
        let psiS = acosf(min(max(n.z, -1), 1))
        let phi = atan2f(n.y, n.x)
        let r1 = r0 * 1.6
        func f(_ b: Float) -> Float {
            asinf(min(b / r0, 1)) - (2 / b) * ((max(1 - b * b / (r1 * r1), 0)).squareRoot() + (max(1 - b * b / (r0 * r0), 0)).squareRoot())
        }
        func solve(_ target: Float) -> Float? {
            var lo: Float = 2.6, hi: Float = r0 * 0.999
            guard f(lo) < target, f(hi) > target else { return nil }
            for _ in 0..<40 {
                let m = (lo + hi) / 2
                if f(m) < target { lo = m } else { hi = m }
            }
            return (lo + hi) / 2
        }
        var out: [(SIMD2<Float>, Float)] = []
        for (side, target) in [(Float(1), psiS), (Float(-1), -psiS)] {
            guard let b = solve(target) else { continue }
            let h: Float = 0.002
            let db = ((solve(target + h) ?? b) - (solve(target - h) ?? b)) / (2 * h)
            let mu = abs(b * db / (r0 * r0 * max(sinf(psiS), 1e-4)))
            let dir = SIMD2(cosf(phi), sinf(phi)) * side
            out.append((c + SIMD2(dir.x * b + shift, -dir.y * b) * pxPerM, mu))
        }
        return out
    }

    /// Point lens for a source in direction beta (tan angles), Einstein angle squared thetaE2.
    func lensed(_ beta: SIMD2<Float>, thetaE2: Float) -> [(SIMD2<Float>, Float)] {
        let b = simd_length(beta)
        let te = thetaE2.squareRoot()
        let dirn = b > 1e-7 ? beta / b : SIMD2<Float>(1, 0)
        let root = (b * b + 4 * thetaE2).squareRoot()
        let tp = (b + root) / 2, tm = (b - root) / 2
        let u = b / max(te, 1e-9)
        let mu0 = (u * u + 2) / max(u * (u * u + 4).squareRoot(), 1e-6)
        let muP = min((mu0 + 1) / 2, 30), muM = min(max((mu0 - 1) / 2, 0), 30)
        func p(_ t: Float) -> SIMD2<Float> { px(dir: SIMD3(dirn.x * t, dirn.y * t, 1)) }
        return [(p(tp), muP), (p(tm), muM)]
    }
}

/// Where a body is this frame.
struct Placement {
    var world: SIMD3<Float>          // world position (M); for screen-placed bodies a virtual one
    var vel = SIMD3<Float>.zero      // world velocity (c), for Doppler and comet tails
    var screen: SIMD2<Float>? = nil  // set for edge and fixed: drawn at this pixel, not projected
    var radiusPx: Float = 0          // for screen-placed bodies
    var visible = true
    var edge = false                 // runs along a band (drawn in the strips in edges-only mode)
    var fade: Float = 1              // plunging into the hole: dims to 0 at the horizon
    var screenVel = SIMD2<Float>.zero   // edge paths: px/s and px/s^2 on the screen, for attitude and bank
    var screenAcc = SIMD2<Float>.zero
    var burn: Float = 0              // ships on a band: engines up while speeding up or braking (0...1)
}

enum Orbits {
    /// Seconds per orbit at semi-major axis a, in the disk's clock: the inner edge turns once per diskPeriod.
    /// `mass`: total mass of the pair in M (a second hole adds its own: the relative orbit is a Kepler orbit
    /// about the sum of both masses).
    static func period(_ a: Float, look: Look, mass: Float = 1) -> Double {
        let s = look.spin, isco = look.isco
        return Double(look.diskPeriod) * Double(powf(max(a, 1), 1.5) + s) / Double(powf(isco, 1.5) + s) / Double(max(mass, 0.05)).squareRoot()
    }

    /// Seconds of the scene clock per M of coordinate time: the clock the disk turns by (its inner edge
    /// turns once per diskPeriod). Everything bound by gravity runs on it, so all ratios stay physical.
    static func secondsPerM(_ look: Look) -> Double {
        Double(look.diskPeriod) / (2 * .pi * Double(powf(look.isco, 1.5) + look.spin))
    }

    /// Tidal stretch of a body at distance r (M): 1 far out, up to 2.6 close to the hole, along the radius.
    static func tide(_ r: Float) -> Float {
        guard r < 40 else { return 1 }
        return 1 + min(0.7 * powf(8 / max(r, 1), 3), 1.6)
    }

    /// Smallest periapsis that still escapes: inside it a pass plunges (marginally bound orbit, Schwarzschild).
    static let captureRadius: Float = 4

    /// Kepler ellipse: position and velocity (units of c) at orbit phase `orbits` (turns since start).
    /// Angles in degrees; the reference plane is the disk. Periapsis turns by the GR rate when asked.
    static func kepler(_ m: Motion, orbits: Double, centreMass: Float = 1, aScale: Float = 1) -> (SIMD3<Float>, SIMD3<Float>) {
        let a = max(m.radius * aScale, 0.5)
        let e = min(max(m.eccentricity, 0), 0.97)
        let total = orbits + Double(m.phase)
        let M = Float((total - floor(total)) * 2 * .pi)
        var E = e > 0.8 ? Float.pi : M
        for _ in 0..<8 { E -= (E - e * sinf(E) - M) / (1 - e * cosf(E)) }
        let b = a * (1 - e * e).squareRoot()
        let x = a * (cosf(E) - e), y = b * sinf(E)
        // Speed from vis-viva; direction along the ellipse.
        let r = max((x * x + y * y).squareRoot(), 0.5)
        let v = (centreMass * max(2 / r - 1 / a, 0)).squareRoot() / aScale.squareRoot()
        var t = SIMD2<Float>(-a * sinf(E), b * cosf(E))
        t = simd_length(t) > 0 ? simd_normalize(t) * v : .zero
        var w = m.periapsis * .pi / 180
        if m.precession && aScale == 1 {
            w += Float(total) * 6 * .pi * centreMass / (a * (1 - e * e))
        }
        let inc = m.inclination * .pi / 180, node = m.node * .pi / 180
        func rot(_ p: SIMD2<Float>) -> SIMD3<Float> {
            let px = p.x * cosf(w) - p.y * sinf(w), py = p.x * sinf(w) + p.y * cosf(w)
            let qy = py * cosf(inc), qz = py * sinf(inc)
            return SIMD3(px * cosf(node) - qy * sinf(node), px * sinf(node) + qy * cosf(node), qz)
        }
        return (rot(SIMD2(x, y)), rot(t))
    }

    /// Normal of an orbit plane (world).
    static func planeNormal(_ m: Motion) -> SIMD3<Float> {
        let inc = m.inclination * .pi / 180, node = m.node * .pi / 180
        return SIMD3(sinf(inc) * sinf(node), -sinf(inc) * cosf(node), cosf(inc))
    }

    /// A pass on a Kepler hyperbola: speed far out flySpeed x 0.1 c, closest distance between passMin and
    /// passMax, bent by the hole (swing-by) and, with precession on, wound further round it as in GR
    /// (angle stretched by 1 / (1 - 3 M / p)). Inside the capture radius the body plunges and is gone at
    /// periapsis. Slots of `interval` seconds of the scene clock, one pass per slot at a hashed time.
    static func flyby(_ m: Motion, seed: UInt32, t: Double, cam: CamFrame, look: Look) -> Placement? {
        let spm = secondsPerM(look)
        let v = Double(max(m.flySpeed, 0.05)) * 0.1
        let R = Double(cam.r0) * 1.3
        let lo = Double(min(m.passMin, m.passMax)), hi = Double(max(m.passMin, m.passMax))
        let cross = max(Hyperbola(rp: lo, v: v, precess: m.precession).span(R),
                        Hyperbola(rp: max(hi, 1), v: v, precess: m.precession).span(R)) * spm
        let slot = max(Double(m.interval), cross * 1.2)
        let k = Int(floor(t / slot))
        let h = { (i: Int) in Double(ObjectSystem.hash(seed &+ 31, k * 16 + i)) }
        let rp = max(lo + (hi - lo) * h(1), 1.5)
        let hyp = Hyperbola(rp: rp, v: v, precess: m.precession)
        let span = hyp.span(R) * spm
        let start = Double(k) * slot + h(0) * max(slot - span, 0)
        let tl = t - start
        guard tl >= 0, tl <= span else { return nil }
        let toCam = simd_normalize(cam.pos)
        var u = SIMD3<Float>(0, 0, 0), n = SIMD3<Float>(0, 0, 0)
        for tryN in 0..<6 {
            let ph = Float(h(2 + tryN)) * 2 * .pi, ct = Float(h(8 + tryN)) * 1.6 - 0.8
            u = SIMD3(sqrt(1 - ct * ct) * cosf(ph), sqrt(1 - ct * ct) * sinf(ph), ct)
            // Periapsis direction perpendicular to the velocity there, on the chosen side of the hole.
            var nn = simd_cross(u, SIMD3(Float(h(3 + tryN)) - 0.5, Float(h(4 + tryN)) - 0.5, Float(h(5 + tryN)) - 0.5))
            if simd_length(nn) < 1e-3 { nn = simd_cross(u, SIMD3(0, 0, 1)) }
            n = simd_normalize(nn)
            let side = m.side == "front" ? 1 : m.side == "behind" ? -1 : (h(14) < 0.5 ? 1 : -1)
            if simd_dot(n, toCam) * Float(side) < 0 { n = -n }
            // Keep the whole path clear of the camera.
            var clear = true
            for j in 0...12 {
                let (p, _) = hyp.state(-hyp.half(R) + 2 * hyp.half(R) * Double(j) / 12)
                if simd_length(n * p.x + u * p.y - cam.pos) < 12 { clear = false; break }
            }
            if clear { break }
        }
        let (p, w) = hyp.state((tl - span / 2) / spm - (hyp.plunges ? hyp.half(R) / 2 : 0))
        var pl = Placement(world: n * p.x + u * p.y, vel: n * w.x + u * w.y)
        if hyp.plunges {
            // Redder and darker towards the horizon (the rest of the dimming is the shader's redshift), gone at periapsis.
            let r = simd_length(p), q = Float(rp)
            pl.fade = min(max((r - q) / max(q * 1.5, 1), 0), 1)
            if pl.fade <= 0.001 { return nil }
        }
        return pl
    }

    /// Kepler hyperbola about a mass of 1 M in its own plane: x towards periapsis, y along the velocity there.
    struct Hyperbola {
        let rp: Double, e: Double, a: Double, n: Double, f: Double
        var plunges: Bool { rp < Double(Orbits.captureRadius) }

        init(rp: Double, v: Double, precess: Bool) {
            self.rp = rp
            a = 1 / max(v * v, 1e-6)                 // |semi-major axis|
            e = 1 + rp / a
            n = 1 / (a * a * a).squareRoot()         // mean motion
            // 1PN periapsis advance as a stretched angle; capped so the plunge winds round but stays readable.
            let p = rp * (1 + e)
            f = precess ? 1 / max(1 - 3 / p, 0.4) : 1
        }

        /// Hyperbolic anomaly at distance r on the way out.
        func anomaly(_ r: Double) -> Double { acosh(max((r / a + 1) / e, 1)) }
        /// Time (M) from periapsis to distance r.
        func time(_ r: Double) -> Double { let H = anomaly(r); return (e * sinh(H) - H) / n }
        /// Time from entering the sphere of radius R to leaving it, or to periapsis when it plunges.
        func half(_ R: Double) -> Double { time(max(R, rp * 1.01)) }
        func span(_ R: Double) -> Double { plunges ? half(R) : 2 * half(R) }

        /// Position (x, y) and velocity (c) at time tau (M) from periapsis.
        func state(_ tau: Double) -> (SIMD2<Float>, SIMD2<Float>) {
            let Mh = n * tau
            var H = asinh(Mh / e)
            for _ in 0..<30 {
                let d = (e * sinh(H) - H - Mh) / (e * cosh(H) - 1)
                H -= d
                if abs(d) < 1e-12 { break }
            }
            let q = (e * e - 1).squareRoot()
            let x = a * (e - cosh(H)), y = a * q * sinh(H)
            let r = a * (e * cosh(H) - 1)
            let dH = n / (e * cosh(H) - 1)
            var vx = -a * sinh(H) * dH, vy = a * q * cosh(H) * dH
            var px = x, py = y
            if f != 1 {
                // Turn by the extra angle (f - 1) nu and add its rate to the tangential speed.
                let nu = atan2(y, x)
                let c = cos((f - 1) * nu), s = sin((f - 1) * nu)
                px = x * c - y * s; py = x * s + y * c
                let rvx = vx * c - vy * s, rvy = vx * s + vy * c
                let h = (rp * (1 + e)).squareRoot()
                let extra = (f - 1) * h / r
                vx = rvx - py / r * extra; vy = rvy + px / r * extra
            }
            return (SIMD2(Float(px), Float(py)), SIMD2(Float(vx), Float(vy)))
        }
    }

    /// Run along a band: pixels, from left to right or back, then a pause. `top` says which band.
    static func edge(_ m: Motion, seed: UInt32, t: Double, cam: CamFrame, layout: ScreenLayout, pxScale: Float,
                     sizePx: Float) -> (Placement, Bool)? {
        let W = Double(cam.W), H = cam.H
        let margin = Double(sizePx) * 2.5 + 20
        let speed = Double(max(m.edgeSpeed, 1) * pxScale)
        let run = (W + 2 * margin) / speed
        let per = run + Double(max(m.edgeGap, 0))
        let n = Int(floor(t / per))
        let tl = t - Double(n) * per
        guard tl <= run else { return nil }
        let rightward: Bool
        switch m.direction {
        case "left": rightward = false
        case "alternate": rightward = n % 2 == 0
        case "random": rightward = ObjectSystem.hash(seed &+ 5, n) < 0.5
        default: rightward = true
        }
        let top: Bool
        switch m.edge {
        case "top": top = true
        case "both": top = n % 2 == 1
        default: top = false
        }
        let x = rightward ? -margin + tl * speed : W + margin - tl * speed
        let a1 = Float(t) * 0.9 + Float(seed % 100), a2 = Float(t) * 2.3 + Float(seed % 37)
        let w1 = m.wobble * 12 * pxScale, w2 = m.wobble * 5 * pxScale
        let wob = w1 * sinf(a1) + w2 * sinf(a2)
        let sy: Float = top ? 1 : -1
        let y = edgeLine(top: top, cam: cam, layout: layout, pxScale: pxScale) + sy * (m.offset * pxScale + wob)
        let p = SIMD2(Float(x), y)
        var pl = Placement(world: cam.world(px: p, depth: cam.holeDepth), screen: p, radiusPx: sizePx, edge: true)
        pl.vel = (rightward ? cam.right : -cam.right) * 0.01
        pl.screenVel = SIMD2(Float(rightward ? speed : -speed), sy * (w1 * 0.9 * cosf(a1) + w2 * 2.3 * cosf(a2)))
        pl.screenAcc = SIMD2(0, -sy * (w1 * 0.81 * sinf(a1) + w2 * 5.29 * sinf(a2)))
        _ = H
        return (pl, top)
    }

    /// The band line objects run along: the bar edge, or 3 % in from the screen edge without a bar
    /// (screen saver, hidden Dock).
    static func edgeLine(top: Bool, cam: CamFrame, layout: ScreenLayout, pxScale: Float) -> Float {
        let bar = (top ? layout.topBar : layout.bottomBar) * pxScale
        let d = bar > 3 * pxScale ? bar : cam.H * 0.03
        return top ? d : cam.H - d
    }
}
