import Foundation
import simd

/// What an event does to a ship's tile at one moment.
struct ShipLook {
    var visible = true
    var stretch: Float = 1     // along the flight direction, from the tail
    var shrink: Float = 1      // towards the centre
    var fade: Float = 1
    var flash: Float = 0
    var shift: Float = 0       // ship lengths along the flight direction
    var plume: Float = 1       // exhaust plumes
    var toTarget: Float = 0    // share of the way to the wormhole it flies into (event 8)
    var turn: Float = 0        // how far the nose is turned onto the line to the wormhole (event 8)
}

/// An event running right now.
struct ShipEventNow {
    var spec: ShipEventSpec
    var phase: Float           // 0...1 through the event
    var arrival: Bool
    var look: ShipLook { arrival ? ShipEventNow.arrivalLook(spec.fx, phase) : ShipEventNow.look(spec.fx, phase) }

    private static func ss(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Tile state of a departure at phase p (an arrival is the same, played backwards).
    static func look(_ fx: Int, _ p: Float) -> ShipLook {
        var l = ShipLook()
        func bump(_ c: Float, _ w: Float) -> Float { expf(-((p - c) / w) * ((p - c) / w)) }
        switch fx {
        case 0:   // warp: stretched forward, a short flash at the nose, gone
            let u = min(p / 0.5, 1)
            l.stretch = 1 + 3 * u * u * u
            l.fade = 1 - ss(0.44, 0.52, p)
            l.flash = 0.3 * bump(0.48, 0.05)
            l.visible = p < 0.52
        case 1:   // hyperspace: pulls back a little, then a long streak
            l.shift = -0.1 * sinf(min(p / 0.22, 1) * .pi)
            let u = min(max((p - 0.22) / 0.22, 0), 1)
            l.stretch = 1 + 5 * u * u
            l.fade = 1 - ss(0.38, 0.46, p)
            l.flash = 0.25 * bump(0.43, 0.05)
            l.visible = p < 0.46
        case 2:   // FTL, transition: contracts to a point with a bluish light
            l.shrink = max(1 - ss(0.05, 0.4, p), 0.02)
            l.flash = 0.6 * ss(0.15, 0.4, p)
            l.visible = p < 0.4
        case 3:   // vortex: flies into it and shrinks
            l.shift = 0.9 * ss(0.25, 0.6, p)
            l.shrink = 1 - 0.85 * ss(0.3, 0.6, p)
            l.fade = 1 - ss(0.45, 0.62, p)
            l.visible = p < 0.62
        case 4:   // cloak: fades out under a shimmer
            l.fade = 1 - ss(0.15, 0.75, p)
            l.visible = p < 0.75
        case 5:   // materialise: pulsing in and out
            l.fade = (1 - ss(0.1, 0.9, p)) * (0.62 + 0.38 * cosf(p * 6 * .pi))
            l.visible = p < 0.9
        case 6:   // light tunnel: falls into a point
            l.shrink = 1 - 0.95 * ss(0.2, 0.55, p)
            l.fade = 1 - ss(0.45, 0.6, p)
            l.visible = p < 0.6
        case 8:   // into a wormhole: turns its nose to it, flies in faster and faster, shrinks with the distance and is gone
            l.turn = ss(0, 0.22, p)
            let t = min(max((p - 0.22) / 0.58, 0), 1)
            l.toTarget = t * t
            l.shrink = 1 - 0.9 * ss(0.25, 0.8, p)
            l.fade = 1 - ss(0.66, 0.82, p)
            l.visible = p < 0.82
        case 9, 10:   // gate events play in the ring; the station stays as it is
            break
        default:  // plume flare: the drive flares and the ship races away
            l.shift = 4 * p * p
            l.plume = 1 + 4 * ss(0, 0.3, p)
            l.fade = 1 - ss(0.65, 1, p)
            l.visible = p < 1
        }
        if !l.visible { l.fade = 0 }
        return l
    }

    /// Tile state of an arrival at phase u (0...1, forward in time). Light, fades and size play the departure
    /// backwards, the motion does not: played backwards, a departure's stretch pulls the nose back to the tail
    /// and the hyperspace hop ends with a slide backwards, so the ship backed into place. Here it drops out of
    /// its jump nose first, fast, the streak behind it, and brakes hard: the nose sits `drop * r^3` ship lengths
    /// short of its place (r runs from 1 to 0), so its speed only ever falls. A stretch hangs back from the nose.
    static func arrivalLook(_ fx: Int, _ u: Float) -> ShipLook {
        var l = look(fx, 1 - u)
        // 1 when the ship drops out at u0, 0 when it is in place at u1.
        func left(_ u0: Float, _ u1: Float) -> Float { 1 - min(max((u - u0) / (u1 - u0), 0), 1) }
        switch fx {
        case 0:   // warp: out of the streak at u 0.48
            let r = left(0.48, 1)
            l.stretch = 1 + 3 * r * r
            l.shift = -1.6 * r * r * r - (l.stretch - 1)
        case 1:   // hyperspace: the streak collapses onto the nose in the first half, then the ship brakes
            let r = left(0.54, 1)
            let q = max(2 * r - 1, 0)
            l.stretch = 1 + 5 * q * q
            l.shift = -1.2 * r * r * r - (l.stretch - 1)
        case 3:   // vortex: comes out of it (it opens behind the ship) fast and brakes
            let r = left(0.38, 0.9)
            l.shift = -0.9 * r * r
        case 7:   // plume flare: coasts in from behind as the burn dies down
            l.shift = -4 * (1 - u) * (1 - u)
        case 8:   // out of a wormhole: nose away from it, braking to its place, then turns back to its heading
            let r = left(0.18, 0.78)
            l.toTarget = r * r
            l.turn = 1 - ss(0.78, 1, u)
            l.shift = 0
        default:  // no motion along the path
            l.shift = 0
        }
        return l
    }

    /// Where the nose sits along the flight direction (ship lengths, 0 = in place), from shift and stretch:
    /// the stretch runs forward from the tail at -0.5.
    var nose: Float { let l = look; return l.shift + l.stretch - 1 }
}

extension ObjectSystem {
    /// Freezes one event for snapshots: `--event warp --phase 0.5`.
    static var forcedEvent: (id: String, phase: Float, arrival: Bool)?

    static let shipKinds: Set<ObjectKind> = [.ship, .station, .model]

    /// Clocks of a ship: its own time, self-spin, orbit or pass.
    func shipRates(_ o: SpaceObject, look: Look, sp: Double) -> [(String, Double)] {
        var out: [(String, Double)] = [("\(o.id).t", sp), ("\(o.id).spin", Double(o.param("selfSpin")) / 360 * sp)]
        switch o.motion.mode {
        case .orbit:
            let T = Orbits.period(min(max(o.motion.radius, 6), look.cameraDistance * 0.92), look: look)
            out.append(("\(o.id).kep", sp * Double(max(o.motion.tempo, 0)) / max(T, 0.1)))
        case .flyby: out.append(("\(o.id).fly", sp * Double(max(o.motion.tempo, 0))))
        default: break
        }
        return out
    }

    /// Events this object may show: the chosen ones, or all the variant offers.
    static func shipEvents(_ o: SpaceObject) -> [ShipEventSpec] {
        let allowed = ObjectCatalog.spec(for: o)?.events ?? []
        let pick = o.events.kinds.filter { allowed.contains($0) || o.objectKind == .model }
        return (pick.isEmpty ? allowed : pick).compactMap(ShipCatalog.event)
    }

    /// The event running now, or nil; `hidden` when the ship is away between departure and arrival.
    func shipEvent(_ o: SpaceObject, cam: CamFrame, pxScale: Float, edgeTime: Float, sizePx: Float) -> (ShipEventNow?, hidden: Bool) {
        if let f = ObjectSystem.forcedEvent, let spec = ShipCatalog.event(f.id) {
            return (ShipEventNow(spec: spec, phase: min(max(f.phase, 0), 1), arrival: f.arrival), false)
        }
        guard o.events.on else { return (nil, false) }
        let list = ObjectSystem.shipEvents(o)
        guard !list.isEmpty else { return (nil, false) }
        if o.motion.mode == .edge {
            guard let e = edgeSchedule(o, list: list, cam: cam, pxScale: pxScale, edgeTime: edgeTime, sizePx: sizePx) else { return (nil, true) }
            let D = Double(e.spec.duration)
            if e.tl < e.arrive - D { return (nil, true) }
            if e.tl < e.arrive { return (ShipEventNow(spec: e.spec, phase: Float((e.tl - e.arrive + D) / D), arrival: true), false) }
            if e.tl < e.leave { return (nil, false) }
            if e.tl < e.leave + D { return (ShipEventNow(spec: e.spec, phase: Float((e.tl - e.leave) / D), arrival: false), false) }
            return (nil, true)
        }
        // Elsewhere: now and then away and back, at hashed times within slots of the mean interval.
        let gap: Double = 4
        let longest = Double(list.map(\.duration).max() ?? 1)
        let slot = max(Double(o.events.interval), 3 * longest + gap + 4)
        let t = phase("\(o.id).t")
        let k = Int(floor(t / slot))
        let spec = list[min(Int(ObjectSystem.hash(o.seed &+ 47, k) * Float(list.count)), list.count - 1)]
        let D = Double(spec.duration)
        let s = Double(k) * slot + Double(ObjectSystem.hash(o.seed &+ 41, k)) * (slot - 2 * D - gap)
        let tl = t - s
        if tl < 0 || tl > 2 * D + gap { return (nil, false) }
        if tl < D { return (ShipEventNow(spec: spec, phase: Float(tl / D), arrival: false), false) }
        if tl < D + gap { return (nil, true) }
        return (ShipEventNow(spec: spec, phase: Float((tl - D - gap) / D), arrival: true), false)
    }

    /// A ship on a band with events: seconds into this run, when its arrival ends and when its departure
    /// starts. Arrives a little after entering the screen, leaves before the other side. nil during the pause.
    func edgeSchedule(_ o: SpaceObject, list: [ShipEventSpec], cam: CamFrame, pxScale: Float, edgeTime: Float,
                      sizePx: Float) -> (tl: Double, arrive: Double, leave: Double, spec: ShipEventSpec)? {
        let m = o.motion
        let margin = Double(sizePx) * 2.5 + 20
        let speed = Double(max(m.edgeSpeed, 1) * pxScale)
        let W = Double(cam.W)
        let run = (W + 2 * margin) / speed
        let per = run + Double(max(m.edgeGap, 0))
        let t = Double(edgeTime)
        let n = Int(floor(t / per))
        let tl = t - Double(n) * per
        guard tl <= run, !list.isEmpty else { return nil }
        let h0 = Double(ObjectSystem.hash(o.seed &+ 41, n)), h1 = Double(ObjectSystem.hash(o.seed &+ 43, n))
        let spec = list[min(Int(ObjectSystem.hash(o.seed &+ 47, n) * Float(list.count)), list.count - 1)]
        let fa = (margin + (0.08 + 0.14 * h0) * W) / (W + 2 * margin)
        let fd = (margin + (0.68 + 0.16 * h1) * W) / (W + 2 * margin)
        return (tl, fa * run + Double(spec.duration), fd * run, spec)
    }

    /// Speed profile of a ship on a band with events: it drops out of its jump fast and brakes to cruise,
    /// and speeds up for a few seconds before it jumps. Returns the shift along the run (px), the extra speed
    /// (px/s) and how hard the engines work (0...1).
    func edgeBurn(_ o: SpaceObject, cam: CamFrame, pxScale: Float, edgeTime: Float, sizePx: Float) -> (shift: Float, dv: Float, burn: Float) {
        guard o.events.on, ObjectSystem.forcedEvent == nil,
              let e = edgeSchedule(o, list: ObjectSystem.shipEvents(o), cam: cam, pxScale: pxScale, edgeTime: edgeTime, sizePx: sizePx)
        else { return (0, 0, 0) }
        let v0 = Double(max(o.motion.edgeSpeed, 1) * pxScale)
        let k = 2.0, tau = 1.2, k2 = 1.5, Ta = 2.5
        var shift = 0.0, dv = 0.0, burn = 0.0
        let x = e.tl - e.arrive
        if x < 0 { shift += k * v0 * x; dv += k * v0 } else {
            let d = exp(-x / tau)
            shift += k * v0 * tau * (1 - d); dv += k * v0 * d; burn = max(burn, d)
        }
        let u = min(max((e.tl - (e.leave - Ta)) / Ta, 0), 1)
        if e.tl > e.leave {
            shift += k2 * v0 * (Ta / 2 + (e.tl - e.leave)); dv += k2 * v0; burn = 1
        } else if u > 0 {
            let s = u * u * (3 - 2 * u)
            shift += k2 * v0 * Ta * (u * u * u - u * u * u * u / 2); dv += k2 * v0 * s; burn = max(burn, s)
        }
        return (Float(shift), Float(dv), Float(burn))
    }

    /// Model frame into the sprite frame (x right, y up, z to the camera). Ships fly nose first along their
    /// path with the orbit's normal up; stations and ships fixed on the screen keep the attitude of the
    /// sliders. Self-spin turns about the design's axis.
    func shipRotation(_ o: SpaceObject, pl: Placement, ex: SIMD3<Float>, ey: SIMD3<Float>, ez: SIMD3<Float>) -> simd_float3x3 {
        let d = ShipCatalog.design(o.variant)
        let spinA = Float(phase("\(o.id).spin").truncatingRemainder(dividingBy: 1)) * 2 * .pi
        let ax = simd_normalize(d?.spinAxis ?? SIMD3(0, 0, 1))
        let spin = simd_float3x3(simd_quatf(angle: spinA, axis: ax))
        let roll = simd_float3x3(simd_quatf(angle: o.param("roll") * .pi / 180, axis: SIMD3(1, 0, 0)))
        let flies = o.objectKind == .ship || o.objectKind == .model
        if flies && pl.screen == nil && simd_length(pl.vel) > 1e-6 {
            let f = simd_normalize(pl.vel)
            var up = o.motion.mode == .orbit ? Orbits.planeNormal(o.motion) : SIMD3<Float>(0, 0, 1)
            if abs(simd_dot(up, f)) > 0.95 { up = simd_normalize(simd_cross(f, SIMD3(1, 0, 0))) }
            let left = simd_normalize(simd_cross(up, f))
            let u = simd_cross(f, left)
            func s(_ v: SIMD3<Float>) -> SIMD3<Float> { SIMD3(simd_dot(v, ex), simd_dot(v, ey), simd_dot(v, ez)) }
            return simd_float3x3(columns: (s(f), s(left), s(u))) * roll * spin
        }
        // On the screen: nose to the right (or left when running leftwards), top up, then yaw and pitch.
        var yaw = o.param("yaw") * .pi / 180
        let banded = pl.edge && flies && abs(pl.screenVel.x) > 1e-3
        // On a band the nose points ahead: a yaw past 90° would fly tail first, so mirror it to the front.
        if banded && cosf(yaw) < 0 { yaw = .pi - yaw }
        if pl.edge && simd_dot(pl.vel, ex) < 0 { yaw = .pi - yaw }
        let pitch = o.param("pitch") * .pi / 180
        let base = simd_float3x3(columns: (SIMD3(1, 0, 0), SIMD3(0, 0, -1), SIMD3(0, 1, 0)))
        let ry = simd_float3x3(simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)))
        let rx = simd_float3x3(simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0)))
        if banded {
            // Nose along the path on the screen, and a slight bank into each turn, as in the films.
            // Yaw and pitch together tilt the projected nose off the horizontal (yaw -32°, pitch 22° by about 12°
            // down), so the turn in the screen plane goes from that projected nose to the path, not from the
            // horizontal. Turning about the view axis keeps the 3/4 look; the bank turns about the nose itself.
            let v = pl.screenVel, a = pl.screenAcc
            let sx: Float = v.x < 0 ? -1 : 1
            let lat = (v.x * a.y - v.y * a.x) / max(simd_length(v), 1)
            let bank = min(max(lat / 40, -1), 1) * 0.45 * sx
            let f = rx * ry * base * SIMD3<Float>(1, 0, 0)
            let n = SIMD2(f.x, f.y), d = SIMD2(v.x, -v.y)
            let turn = simd_length(n) < 1e-4 ? atan2f(-v.y * sx, abs(v.x)) * sx
                : atan2f(n.x * d.y - n.y * d.x, simd_dot(n, d))
            let rz = simd_float3x3(simd_quatf(angle: turn, axis: SIMD3(0, 0, 1)))
            let rb = simd_float3x3(simd_quatf(angle: bank, axis: SIMD3(1, 0, 0)))
            return rz * rx * ry * base * rb * roll * spin
        }
        return rx * ry * base * roll * spin
    }

    /// Through a wormhole (event 8): the ship turns its nose onto the line between its place and the wormhole
    /// in a short flat turn about its own up axis, banked into the turn, then flies along it nose first in both
    /// directions: in towards `target` on departure, out and away from it on arrival. `R` is its attitude
    /// without the event, `rest` its place on the screen. Returns the attitude and the centre on the screen.
    func wormholeSteer(_ o: SpaceObject, R: simd_float3x3, look: ShipLook, arrival: Bool, rest: SIMD2<Float>,
                       target: SIMD2<Float>) -> (R: simd_float3x3, centre: SIMD2<Float>) {
        let centre = simd_mix(rest, target, SIMD2(repeating: look.toTarget))
        var d = arrival ? rest - target : target - rest
        guard look.turn > 0, simd_length(d) > 1 else { return (R, centre) }
        d = simd_normalize(d)
        func rot(_ a: Float, _ axis: SIMD3<Float>) -> simd_float3x3 { simd_float3x3(simd_quatf(angle: a, axis: axis)) }
        func nose(_ M: simd_float3x3) -> SIMD2<Float> { let f = M * SIMD3<Float>(1, 0, 0); return SIMD2(f.x, -f.y) }
        // How well a turn of a (about the ship's up axis) and a climb of b point the nose along d on the screen;
        // a nose pointing at the camera does not count.
        func fit(_ a: Float, _ b: Float) -> Float {
            let n = nose(R * rot(a, SIMD3(0, 0, 1)) * rot(b, SIMD3(0, 1, 0)))
            let l = simd_length(n)
            return l < 0.25 ? -2 : simd_dot(n / l, d)
        }
        var a: Float = 0, b: Float = 0, best: Float = -3
        for k in 0..<72 { let x = Float(k) / 72 * 2 * .pi - .pi; let f = fit(x, 0); if f > best { best = f; a = x } }
        let a0 = a
        for k in -25...25 { let x = a0 + Float(k) * 0.002; let f = fit(x, 0); if f > best { best = f; a = x } }
        // Seen nearly edge-on the turn alone cannot point up or down the screen: climb for the rest.
        for k in -60...60 { let x = Float(k) * 0.02; let f = fit(a, x); if f > best + 1e-6 { best = f; b = x } }
        // The last few hundredths in the screen plane, so the nose lies exactly on the line.
        let n1 = simd_normalize(nose(R * rot(a, SIMD3(0, 0, 1)) * rot(b, SIMD3(0, 1, 0))))
        let err = atan2f(n1.x * d.y - n1.y * d.x, simd_dot(n1, d))
        let t = min(look.turn, 1)
        // Bank into the turn (a turn to the left, a > 0, lowers the left side), none once on the line.
        let bank = -0.45 * sinf(.pi * t) * (a > 0 ? 1 : -1) * min(abs(a) / 0.5, 1)
        let M = rot(-err * t, SIMD3(0, 0, 1)) * R * rot(a * t, SIMD3(0, 0, 1)) * rot(b * t, SIMD3(0, 1, 0)) * rot(bank, SIMD3(1, 0, 0))
        return (M, centre)
    }

    /// Colour of the engines and nacelles from the glow hue.
    static func glowColour(_ o: SpaceObject) -> SIMD3<Float> {
        var c = ObjectSystem.hueColour(o.param("glowHue"), sat: 0.78)
        c /= max(simd_reduce_max(c), 1e-3)
        return c
    }
}
