import Foundation
import simd

/// Motion checks of `--selftest`: Kepler orbits keep energy and angular momentum, periods follow a^1.5,
/// a second hole orbits with both masses, passes are hyperbolas below light speed, plunges end, tides,
/// arrivals come in nose first and brake (every event, on bands both ways), and everything is a pure function of the clock.
extension SelfTest {
    static func motionChecks(_ check: (Bool, String) -> Void) -> Int {
        var failed = 0
        func c(_ ok: Bool, _ what: String) { check(ok, what); if !ok { failed += 1 } }
        func spread(_ v: [Float]) -> Float { (v.max()! - v.min()!) / max(abs(v.reduce(0, +) / Float(v.count)), 1e-6) }

        // Kepler ellipse: energy v^2/2 - M/r = -M/(2a) and angular momentum stay put round the orbit.
        for mass in [Float(1), 1.3] {
            var m = Motion()
            m.radius = 30; m.eccentricity = 0.6; m.inclination = 20; m.node = 40; m.periapsis = 70; m.precession = false
            var E: [Float] = [], L: [Float] = [], rs: [Float] = []
            for i in 0..<64 {
                let (p, v) = Orbits.kepler(m, orbits: Double(i) / 64, centreMass: mass)
                E.append(simd_length_squared(v) / 2 - mass / simd_length(p))
                L.append(simd_length(simd_cross(p, v)))
                rs.append(simd_length(p))
            }
            let e0 = -mass / (2 * 30)
            c(spread(E) < 2e-3 && abs(E[0] - e0) < abs(e0) * 2e-3,
              String(format: "Bewegung: Kepler-Bahn hält die Energie (Masse %.1f, Streuung %.1e)", mass, spread(E)))
            c(spread(L) < 2e-3, String(format: "Bewegung: Kepler-Bahn hält den Drehimpuls (Masse %.1f)", mass))
            c(abs(rs.min()! - 12) < 0.05 && abs(rs.max()! - 48) < 0.05, "Bewegung: Periapsis 12 M, Apoapsis 48 M")
        }

        // Period: a^1.5 (Schwarzschild); a second hole of 0.3 M orbits sqrt(1.3) times faster.
        var flat = Look()
        flat.spin = 0
        let ratio = Orbits.period(40, look: flat) / Orbits.period(10, look: flat)
        c(abs(ratio - 8) < 1e-3, String(format: "Bewegung: Umlaufzeit wächst mit a^1,5 (40 M gegen 10 M: %.3f)", ratio))
        let pm = Orbits.period(40, look: flat, mass: 1.3) / Orbits.period(40, look: flat)
        c(abs(pm - 1 / 1.3.squareRoot()) < 1e-4, "Bewegung: Doppelsystem läuft mit der Summe beider Massen")
        // Clock: at the ISCO one orbit takes exactly the disk's period.
        let spm = Orbits.secondsPerM(flat)
        let tIsco = 2 * Double.pi * pow(Double(flat.isco), 1.5) * spm
        c(abs(tIsco - Double(flat.diskPeriod)) < 1e-3, "Bewegung: Uhr der Objekte ist die Uhr der Scheibe")

        // Hyperbola: energy v_inf^2/2, periapsis where asked, deflection 2 asin(1/e).
        let h = Orbits.Hyperbola(rp: 20, v: 0.1, precess: false)
        var Eh: [Float] = []
        for i in 0...40 {
            let (p, v) = h.state(Double(i - 20) * 60)
            Eh.append(simd_length_squared(v) / 2 - 1 / simd_length(p))
        }
        c(spread(Eh) < 3e-3 && abs(Eh[20] - 0.005) < 1e-4, "Bewegung: Vorbeiflug hält die Energie (v fern = 0,1 c)")
        c(abs(simd_length(h.state(0).0) - 20) < 1e-3, "Bewegung: Vorbeiflug kommt bis auf den kleinsten Abstand heran")
        let far = h.half(4000)
        let vin = simd_normalize(h.state(-far).1), vout = simd_normalize(h.state(far).1)
        let turn = acosf(min(max(simd_dot(vin, vout), -1), 1))
        let expect = Float(2 * asin(1 / h.e))
        c(abs(turn - expect) < 0.03, String(format: "Bewegung: Swing-by lenkt um %.1f° ab (Kepler: %.1f°)", turn * 180 / .pi, expect * 180 / .pi))
        let hp = Orbits.Hyperbola(rp: 20, v: 0.1, precess: true)
        let turnP = acosf(min(max(simd_dot(simd_normalize(hp.state(-far).1), simd_normalize(hp.state(far).1)), -1), 1))
        c(hp.f > 1 && abs(turnP - turn) > 0.05, "Bewegung: Periheldrehung biegt den Vorbeiflug stärker")
        c(Orbits.Hyperbola(rp: 3, v: 0.1, precess: true).plunges && !h.plunges, "Bewegung: unter 4 M stürzt der Körper ab")

        // Passes on the screen: below light speed, the same at the same time, a plunge ends.
        var look = Look()
        look.objects.items = []
        let cam = CamFrame(look: look, layout: ScreenLayout(holeX: 0.5, holeY: 0.5, topBar: 0, bottomBar: 0), width: 1720, height: 720)
        var m = Motion()
        m.mode = .flyby; m.passMin = 6; m.passMax = 40; m.interval = 60
        var fastest: Float = 0, seen = 0, same = true
        for i in 0..<400 {
            let t = Double(i) * 23.7
            if let a = Orbits.flyby(m, seed: 7, t: t, cam: cam, look: look) {
                seen += 1
                fastest = max(fastest, simd_length(a.vel))
                let b = Orbits.flyby(m, seed: 7, t: t, cam: cam, look: look)
                same = same && b?.world == a.world
            }
        }
        c(seen > 50 && fastest < 0.99 && fastest > 0.1, String(format: "Bewegung: Vorbeiflüge unter Lichtgeschwindigkeit (schnellster %.2f c)", fastest))
        c(same, "Bewegung: Vorbeiflug ist eine reine Funktion der Uhr")
        m.passMin = 2.5; m.passMax = 2.5
        var fades: [Float] = []
        for i in 0..<3000 {
            if let a = Orbits.flyby(m, seed: 3, t: Double(i) * 2, cam: cam, look: look) { fades.append(a.fade) } else if !fades.isEmpty { break }
        }
        c(!fades.isEmpty && fades.first! > 0.9 && fades.last! < 0.2, "Bewegung: Absturz wird zum Horizont dunkel und endet")

        // Tides; arrivals nose first; moons locked by default.
        c(Orbits.tide(100) == 1 && Orbits.tide(6) > 2 && Orbits.tide(20) < 1.1, "Bewegung: Gezeiten nur nahe am Loch")
        if let spec = ShipCatalog.event("fullburn") {
            let a = ShipEventNow(spec: spec, phase: 0.2, arrival: true).look.shift
            let b = ShipEventNow(spec: spec, phase: 0.6, arrival: true).look.shift
            c(a < b && b <= 0, "Bewegung: Ankunft kommt mit der Nase voran von hinten und bremst")
        }
        failed += arrivalChecks(check)
        failed += bandHeadingChecks(check)
        if let moon = ObjectCatalog.variant("moon", "grey")?.make(1) {
            c(moon.param("locked") == 1, "Bewegung: Monde sind gebunden")
        }
        return failed
    }

    /// Arrivals of every event: the nose moves only forward along the heading, its speed only falls, and it
    /// ends in place. On a band also on the screen, at the top and bottom, running left and right.
    static func arrivalChecks(_ c: (Bool, String) -> Void) -> Int {
        var failed = 0
        func c2(_ ok: Bool, _ what: String) { c(ok, what); if !ok { failed += 1 } }
        for spec in ShipCatalog.eventSpecs where spec.fx < 8 {
            var pos: [Float] = []
            for i in 0...400 {
                let ev = ShipEventNow(spec: spec, phase: Float(i) / 400, arrival: true)
                if ev.look.visible { pos.append(ev.nose) }
            }
            let v = zip(pos.dropFirst(), pos).map { $0 - $1 }
            let forward = v.allSatisfy { $0 >= -1e-6 }
            let braking = zip(v.dropFirst(), v).allSatisfy { $0 <= $1 + 1e-5 }
            c2(forward && braking && abs(pos.last ?? 1) < 1e-4,
               "Ankunft \(spec.id): Nase nur vorwärts, Tempo fällt monoton, endet am Platz")
        }
        // Through a wormhole: the ship turns onto the line first, then moves only along its nose, in and out,
        // and brakes on the way out. Wormholes ahead, behind, above, below and diagonal.
        if let spec = ShipCatalog.event("wormhole"), var o = ObjectCatalog.variant("ship", "endurance")?.make(9) {
            o.motion.mode = .fixed
            let sys = ObjectSystem()
            let rest = SIMD2<Float>(960, 500)
            let pl = Placement(world: SIMD3(0, 0, 50), screen: rest, radiusPx: 150)
            let R0 = sys.shipRotation(o, pl: pl, ex: SIMD3(1, 0, 0), ey: SIMD3(0, 1, 0), ez: SIMD3(0, 0, 1))
            for off in [SIMD2<Float>(420, 0), SIMD2(-420, 0), SIMD2(0, -300), SIMD2(0, 300), SIMD2(-300, 220)] {
                for arrival in [false, true] {
                    var cs: [SIMD2<Float>] = [], ns: [SIMD2<Float>] = []
                    for i in 0...400 {
                        let ev = ShipEventNow(spec: spec, phase: Float(i) / 400, arrival: arrival)
                        guard ev.look.visible else { continue }
                        let (R, c) = sys.wormholeSteer(o, R: R0, look: ev.look, arrival: arrival, rest: rest, target: rest + off)
                        let f = R * SIMD3<Float>(1, 0, 0)
                        cs.append(c); ns.append(simd_normalize(SIMD2(f.x, -f.y)))
                    }
                    let way = simd_normalize(arrival ? -off : off)
                    var ok = cs.count > 100, speeds: [Float] = []
                    for k in 1..<cs.count {
                        let st = cs[k] - cs[k - 1]
                        let len = simd_length(st)
                        guard len > 1e-3 else { continue }
                        speeds.append(len)
                        let dir = st / len
                        // Moving: along the nose (within 2 degrees), the right way.
                        ok = ok && simd_dot(dir, ns[k]) > cosf(2 * .pi / 180) && simd_dot(dir, way) > 0.999
                    }
                    if arrival { ok = ok && zip(speeds.dropFirst(), speeds).allSatisfy { $0 <= $1 * 1.0005 + 1e-4 } }
                    // The turn is smooth: never more than 5 degrees between neighbouring samples, no flip.
                    ok = ok && !speeds.isEmpty && zip(ns.dropFirst(), ns).allSatisfy { simd_dot($0, $1) > cosf(5 * .pi / 180) }
                    c2(ok, String(format: "Wurmloch %@ (Ziel %.0f, %.0f): Geschwindigkeit folgt der Nase%@",
                                  arrival ? "Ankunft" : "Abflug", off.x, off.y, arrival ? ", bremst monoton" : ""))
                }
            }
        }
        // On a band: nose on the screen along the heading, slowing, for both bands and both directions.
        var look = Look()
        look.objects.items = []
        let layout = ScreenLayout(holeX: 0.5, holeY: 0.5, topBar: 0, bottomBar: 0)
        let cam = CamFrame(look: look, layout: layout, width: 1720, height: 720)
        for (eid, ship) in [("warp", "enterprise"), ("hyperspace", "falcon"), ("transwarp", "borg"), ("fullburn", "serenity")] {
            guard var o = ObjectCatalog.variant("ship", ship)?.make(5) else { c2(false, "Ankunft am Rand: \(ship) fehlt"); continue }
            o.events.on = true; o.events.kinds = [eid]
            for (edge, dir) in [("bottom", "right"), ("bottom", "left"), ("top", "right"), ("top", "left")] {
                o.motion.mode = .edge; o.motion.edge = edge; o.motion.direction = dir; o.motion.wobble = 0
                let sys = ObjectSystem()
                let rp = max(o.size, 1) * 0.5
                guard let sch = sys.edgeSchedule(o, list: ObjectSystem.shipEvents(o), cam: cam, pxScale: 1, edgeTime: 0, sizePx: rp)
                else { c2(false, "Ankunft am Rand: kein Lauf"); continue }
                let D = Double(sch.spec.duration)
                var noses: [SIMD2<Float>] = [], heads: [SIMD2<Float>] = []
                for i in 0...240 {
                    let t = Float(sch.arrive - D + (D + 1.5) * Double(i) / 240)
                    guard let pl = sys.place(o, look: look, cam: cam, layout: layout, pxScale: 1, edgeTime: t, parent: nil) else { continue }
                    let (ev, hidden) = sys.shipEvent(o, cam: cam, pxScale: 1, edgeTime: t, sizePx: rp)
                    if hidden || !(ev?.look.visible ?? true) { continue }
                    // Sprite frame as the renderer builds it: z to the camera, x along the screen's right.
                    let ez = simd_normalize(cam.pos - pl.world)
                    let ex = simd_normalize(simd_cross(cam.up, ez))
                    let R = sys.shipRotation(o, pl: pl, ex: ex, ey: simd_cross(ez, ex), ez: ez)
                    let f = R * SIMD3<Float>(1, 0, 0)
                    let fs = SIMD2(f.x, -f.y)
                    noses.append(pl.screen! + fs * rp * (2 * (ev?.nose ?? 0) + 1))
                    heads.append(simd_normalize(fs))
                }
                let steps = zip(noses.dropFirst(), noses).map { $0 - $1 }
                let along = zip(steps, heads).map { simd_dot($0, $1) }
                let side = zip(steps, heads).map { abs($0.x * $1.y - $0.y * $1.x) }
                // The arrival may not add an angle between nose and motion (no slide sideways), only speed
                // along the nose. bandHeadingChecks holds the nose on the path itself.
                let slip = zip(side, along).map { atan2f($0, $1) }
                let cruise = slip.last ?? 0
                let ok = noses.count > 100 && along.allSatisfy { $0 > 0 } && slip.allSatisfy { $0 <= cruise + 0.035 }
                    && zip(along.dropFirst(), along).allSatisfy { $0 <= $1 * 1.0005 + 1e-4 }
                c2(ok, "Ankunft \(eid) am Rand \(edge), nach \(dir): Nase voran, kein Seitwärts, bremst monoton")
            }
        }
        return failed
    }

    /// Ships on a band: the nose on the screen points along the motion on the screen, within 2 degrees, in the
    /// 3/4 view of their yaw and pitch, while banking through the wobble, on arrival and on departure. Both
    /// bands, both directions, against the analytic screen velocity and the measured step of the position.
    static func bandHeadingChecks(_ c: (Bool, String) -> Void) -> Int {
        var failed = 0
        func c2(_ ok: Bool, _ what: String) { c(ok, what); if !ok { failed += 1 } }
        var look = Look()
        look.objects.items = []
        let layout = ScreenLayout(holeX: 0.5, holeY: 0.5, topBar: 24, bottomBar: 70)
        let cam = CamFrame(look: look, layout: layout, width: 1720, height: 720)
        let lim = cosf(2 * .pi / 180)
        // (variant, event, yaw, pitch); nil keeps the design's attitude.
        let cases: [(String, String, Float?, Float?)] = [
            ("enterprise", "warp", nil, nil), ("falcon", "hyperspace", nil, nil), ("xwing", "hyperspace", -55, 15),
            ("serenity", "fullburn", nil, nil), ("enterprise", "warp", -62, 45), ("falcon", "hyperspace", 150, 30),
        ]
        for (ship, eid, yaw, pitch) in cases {
            guard var o = ObjectCatalog.variant("ship", ship)?.make(9) else { c2(false, "Nase am Rand: \(ship) fehlt"); continue }
            o.events.on = true; o.events.kinds = [eid]
            if let yaw { o.params["yaw"] = yaw }
            if let pitch { o.params["pitch"] = pitch }
            for (edge, dir) in [("top", "right"), ("top", "left"), ("bottom", "right"), ("bottom", "left")] {
                o.motion.mode = .edge; o.motion.edge = edge; o.motion.direction = dir
                o.motion.wobble = 1.5; o.motion.edgeGap = 5
                let sys = ObjectSystem()
                let rp = max(o.size, 1) * 0.5
                guard let sch = sys.edgeSchedule(o, list: ObjectSystem.shipEvents(o), cam: cam, pxScale: 1, edgeTime: 0, sizePx: rp)
                else { c2(false, "Nase am Rand: kein Lauf"); continue }
                let end = sch.leave + Double(sch.spec.duration)
                var worstV: Float = 1, worstStep: Float = 1, n = 0, banked = false
                func at(_ t: Float) -> Placement? { sys.place(o, look: look, cam: cam, layout: layout, pxScale: 1, edgeTime: t, parent: nil) }
                for i in 0...600 {
                    let t = Float(end * Double(i) / 600)
                    guard let pl = at(t), let a = at(t - 0.005), let b = at(t + 0.005) else { continue }
                    let (ev, hidden) = sys.shipEvent(o, cam: cam, pxScale: 1, edgeTime: t, sizePx: rp)
                    if hidden || !(ev?.look.visible ?? true) { continue }
                    let ez = simd_normalize(cam.pos - pl.world)
                    let ex = simd_normalize(simd_cross(cam.up, ez))
                    let R = sys.shipRotation(o, pl: pl, ex: ex, ey: simd_cross(ez, ex), ez: ez)
                    let f = R * SIMD3<Float>(1, 0, 0)
                    let nose = simd_normalize(SIMD2(f.x, -f.y))
                    worstV = min(worstV, simd_dot(nose, simd_normalize(pl.screenVel)))
                    worstStep = min(worstStep, simd_dot(nose, simd_normalize(b.screen! - a.screen!)))
                    banked = banked || abs(pl.screenVel.y) > 2   // the path really turns somewhere
                    n += 1
                }
                let deg = acosf(min(min(worstV, worstStep), 1)) * 180 / .pi
                c2(n > 300 && banked && worstV > lim && worstStep > lim,
                   String(format: "Nase am Rand: %@ (%@) %@ nach %@, Nase längs der Bewegung (höchstens %.2f°)",
                          ship, eid, edge == "top" ? "oben" : "unten", dir == "right" ? "rechts" : "links", deg))
            }
        }
        return failed
    }
}
