import Foundation

/// One slider, toggle or picker of an object type.
struct ParamSpec {
    let key: String, title: String
    let range: ClosedRange<Float>, def: Float
    var format = "%.2f", unit = "", help: String? = nil, group = "Aussehen"
    var bake = false        // change re-bakes a texture (galaxy)
    var geometry = false    // change re-traces rays (main jet)
    var random: ClosedRange<Float>? = nil   // range for the dice, nil = range
    var toggle = false      // shown as Toggle, 0/1
    var options: [String]? = nil            // shown as Picker, index as Float

    func with(_ d: Float) -> ParamSpec {
        ParamSpec(key: key, title: title, range: range, def: d, format: format, unit: unit, help: help, group: group,
                  bake: bake, geometry: geometry, random: random, toggle: toggle, options: options)
    }
}

enum Cost: Int, Comparable {
    case leicht, mittel, schwer
    static func < (a: Cost, b: Cost) -> Bool { a.rawValue < b.rawValue }
    var title: String { L(["leicht", "mittel", "schwer"][rawValue]) }
}

struct VariantSpec {
    let id: String, title: String, kind: ObjectKind
    let menu: [String]                 // submenu path, e.g. ["Galaxien"]
    let params: [ParamSpec]            // shared kind params + variant params
    let modes: [MotionMode]            // allowed motion modes, first = default
    let events: [String]
    let cost: Cost, stage: Int
    /// Estimated GPU time per frame in ms (bench, 3440 x 1440), for the load line.
    let ms: Float
    let make: (UInt32) -> SpaceObject  // defaults incl. demo placement that is visible in frame

    func param(_ key: String) -> ParamSpec? { params.first { $0.key == key } }
}

/// Small deterministic generator, so a seed always gives the same object.
struct SeedRNG {
    private var s: UInt64
    init(_ seed: UInt32) { s = UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678 }
    mutating func next() -> Float {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Float(z >> 40) / Float(1 << 24)
    }
    mutating func range(_ r: ClosedRange<Float>) -> Float { r.lowerBound + (r.upperBound - r.lowerBound) * next() }
}

enum ObjectCatalog {
    /// Stage that is built; the add menu shows only variants up to it.
    static let builtStage = 4

    static let all: [VariantSpec] = galaxies + stars + jets + planets + moons + asteroids + belts + comets + meteors + exotics + ships + models

    static func spec(for o: SpaceObject) -> VariantSpec? {
        all.first { $0.kind.rawValue == o.kind && $0.id == o.variant } ?? all.first { $0.kind.rawValue == o.kind }
    }

    static func variants(of kind: ObjectKind) -> [VariantSpec] { all.filter { $0.kind == kind } }

    static func variant(_ kind: String, _ id: String) -> VariantSpec? {
        all.first { $0.kind.rawValue == kind && $0.id.lowercased() == id.lowercased() }
    }

    /// Jet values that change the traced rays, in a fixed order (also the shader's order).
    static let jetGeometryKeys = ["length", "width", "shape", "base", "opening", "falloff", "wobble", "beta", "doppler", "counterJet", "sheath"]

    static func geometryParams(of o: SpaceObject) -> [Float] { jetGeometryKeys.map { o.param($0) } }

    /// Random parameters for the dice: new seed, every slider somewhere sensible.
    static func rolled(_ o: SpaceObject, seed: UInt32) -> SpaceObject {
        var o = o
        o.seed = seed
        guard let spec = spec(for: o) else { return o }
        var rng = SeedRNG(seed &+ 77)
        for p in spec.params where !p.geometry || o.objectKind != .jet {
            if p.options != nil || p.toggle { continue }
            o.params[p.key] = rng.range(p.random ?? p.range)
        }
        return o
    }

    // MARK: Shared parts

    static func skyMotion(_ seed: UInt32, az: ClosedRange<Float>, el: ClosedRange<Float>) -> Motion {
        var rng = SeedRNG(seed)
        var m = Motion()
        m.mode = .sky
        m.azimuth = rng.range(az) * (rng.next() < 0.5 ? -1 : 1)
        m.elevation = rng.range(el) * (rng.next() < 0.5 ? -1 : 1)
        return m
    }

    // MARK: Galaxies

    private static let gArms = ParamSpec(key: "arms", title: "Arme", range: 2...6, def: 2, format: "%.0f", bake: true)
    private static let gWinding = ParamSpec(key: "winding", title: "Windung", range: 0.1...1.5, def: 0.6, help: "Klein heißt weit offene Arme wie bei Sc, groß eng gewickelte wie bei Sa.", bake: true)
    private static let gBar = ParamSpec(key: "bar", title: "Balken", range: 0...1, def: 0, bake: true)
    private static let gBulge = ParamSpec(key: "bulge", title: "Kern (Bulge)", range: 0...1, def: 0.4, bake: true)
    private static let gCore = ParamSpec(key: "core", title: "Kernhelligkeit", range: 0...3, def: 0.6, help: "Heller Punkt im Zentrum, beim Quasar das Hellste am ganzen Objekt.")
    private static let gDust = ParamSpec(key: "dust", title: "Staubbahnen", range: 0...1, def: 0.5, bake: true)
    private static let gStarForming = ParamSpec(key: "starForming", title: "Sternentstehung", range: 0...1, def: 0.5, help: "Blaue Sternhaufen und rosa Wasserstoff-Wolken in den Armen.", bake: true)
    private static let gYoung = ParamSpec(key: "youngMix", title: "Farbe jung oder alt", range: 0...1, def: 0.5, help: "0 ist gelblich alt, 1 ist blau jung.", bake: true)
    private static let gTilt = ParamSpec(key: "tilt", title: "Neigung", range: 0...90, def: 40, format: "%.0f°", help: "0° ist die Draufsicht, 90° die Kante.", group: "Lage", bake: true)
    private static let gAngle = ParamSpec(key: "angle", title: "Drehwinkel", range: 0...360, def: 30, format: "%.0f°", group: "Lage")
    private static let gFlatten = ParamSpec(key: "flatten", title: "Abplattung", range: 0...0.7, def: 0.3, help: "E0 ist rund, E7 stark abgeplattet.", bake: true)

    /// Members of an interacting pair: the picker's order. `pairTypeCodes` maps it to the subtypes' shader codes.
    static let pairTypes = ["Spirale", "Balkenspirale", "Elliptisch", "Linsenförmig (S0)", "Irregulär", "Ringgalaxie"]
    static let pairTypeCodes: [Float] = [0, 1, 3, 4, 5, 6]
    private static let gTypeA = ParamSpec(key: "typeA", title: "Galaxie A", range: 0...5, def: 0, format: "%.0f", help: "Art der größeren Galaxie links.", bake: true, options: pairTypes)
    private static let gTypeB = ParamSpec(key: "typeB", title: "Galaxie B", range: 0...5, def: 0, format: "%.0f", help: "Art der kleineren Galaxie rechts.", bake: true, options: pairTypes)

    private static func galaxy(_ id: String, _ title: String, _ params: [ParamSpec], size: Float = 5) -> VariantSpec {
        VariantSpec(id: id, title: title, kind: .galaxy, menu: ["Galaxien"], params: params, modes: [.sky], events: [],
                    cost: .leicht, stage: 1, ms: 0.025) { seed in
            var o = SpaceObject()
            o.kind = "galaxy"
            o.variant = id
            o.name = title
            o.seed = seed
            o.size = size
            o.motion = skyMotion(seed, az: 12...24, el: 4...10)
            return o
        }
    }

    static let galaxies: [VariantSpec] = [
        galaxy("spiral", "Spirale", [gArms, gWinding, gBulge, gCore, gDust, gStarForming, gYoung, gTilt, gAngle]),
        galaxy("barred", "Balkenspirale", [gArms, gWinding.with(0.45), gBar.with(0.7), gBulge.with(0.35), gCore, gDust, gStarForming, gYoung, gTilt.with(30), gAngle]),
        galaxy("edgeOn", "Kantenansicht", [gArms, gWinding, gBulge.with(0.35), gCore.with(0.3), gDust.with(0.9), gStarForming.with(0.3), gYoung.with(0.4), gTilt.with(86), gAngle.with(20)], size: 6),
        galaxy("elliptical", "Elliptisch", [gFlatten, gCore.with(0.4), gYoung.with(0), gTilt.with(0), gAngle], size: 4),
        galaxy("lenticular", "Linsenförmig (S0)", [gBulge.with(0.55), gCore.with(0.5), gDust.with(0.25), gYoung.with(0.15), gTilt.with(60), gAngle]),
        galaxy("irregular", "Irregulär", [gStarForming.with(0.8), gYoung.with(0.85), gDust.with(0.3), gTilt.with(30), gAngle], size: 3.5),
        galaxy("ring", "Ringgalaxie", [gBulge.with(0.5), gCore.with(0.4), gStarForming.with(0.7), gYoung.with(0.7), gTilt.with(20), gAngle], size: 4),
        galaxy("pair", "Wechselwirkendes Paar", [gTypeA, gTypeB, gArms, gWinding.with(0.5), gBulge.with(0.35), gDust.with(0.4), gStarForming.with(0.7), gYoung.with(0.6), gTilt.with(35), gAngle], size: 6),
        galaxy("quasar", "Quasar", [gCore.with(3), gYoung.with(0.3), gTilt.with(30), gAngle,
                                     ParamSpec(key: "jets", title: "Kleine Jets", range: 0...1, def: 0.6, bake: true)], size: 2.5),
    ]

    // MARK: Stars

    private static func temp(_ t: Float) -> ParamSpec {
        ParamSpec(key: "temperature", title: "Temperatur", range: 1000...40000, def: t, format: "%.0f K",
                  help: "Bestimmt die Farbe: kühl rot, um 5800 K gelblich weiß wie die Sonne, heiß blauweiß.")
    }
    private static let sGlow = ParamSpec(key: "glow", title: "Glühen", range: 0...3, def: 1, help: "Lichthof um den Stern, wie ihn eine Kamera zeigt.")
    static let sSpikes = ParamSpec(key: "spikes", title: "Beugungsstrahlen", range: 0...3, def: 0, help: "Strahlen, wie sie die Streben eines Teleskops um helle Sterne zeichnen. Sie gehören zur Kamera und werden nicht gebogen; nahe am Schatten fehlen sie.", group: "Kamera", options: ["Keine", "4 Strahlen", "6 Strahlen", "8 Strahlen"])
    /// Surface of a star seen up close (motion other than sky).
    static let nearParams: [ParamSpec] = [
        ParamSpec(key: "granulation", title: "Granulation", range: 0...1, def: 0.6, help: "Brodelnde Zellen auf der Oberfläche.", group: "Nah"),
        ParamSpec(key: "spots", title: "Flecken", range: 0...1, def: 0.3, group: "Nah"),
        ParamSpec(key: "prominences", title: "Protuberanzen", range: 0...1, def: 0.4, help: "Leuchtende Gasbögen am Rand.", group: "Nah"),
        ParamSpec(key: "corona", title: "Korona", range: 0...1, def: 0.5, group: "Nah"),
    ]
    /// Variants that can also be placed near the hole as a body.
    static let nearStarIDs: Set<String> = ["O", "B", "A", "F", "G", "K", "M", "redGiant", "redSupergiant", "blueSupergiant",
                                           "whiteDwarf", "brownDwarf", "wolfRayet", "cepheid", "binary"]

    private static func star(_ id: String, _ title: String, _ t: Float, size: Float, extra: [ParamSpec] = [],
                             cost: Cost = .leicht, menu: [String] = ["Sterne"], brightness: Float = 1,
                             az: ClosedRange<Float> = 8...22, el: ClosedRange<Float> = 4...12) -> VariantSpec {
        let near = nearStarIDs.contains(id)
        return VariantSpec(id: id, title: title, kind: .star, menu: menu,
                           params: [temp(t), sGlow] + extra + [sSpikes] + (near ? nearParams : []),
                           modes: near ? [.sky, .orbit, .fixed, .flyby] : [.sky], events: [],
                           cost: cost, stage: 1, ms: id == "pulsar" ? 0.02 : 0.01) { seed in
            var o = SpaceObject()
            o.kind = "star"
            o.variant = id
            o.name = title
            o.seed = seed
            o.size = size
            o.brightness = brightness
            o.motion = skyMotion(seed, az: az, el: el)
            return o
        }
    }

    static let stars: [VariantSpec] = [
        star("O", "Hauptreihe O", 38000, size: 0.5, brightness: 1.6),
        star("B", "Hauptreihe B", 18000, size: 0.45, brightness: 1.4),
        star("A", "Hauptreihe A", 9000, size: 0.4, brightness: 1.2),
        star("F", "Hauptreihe F", 6900, size: 0.35),
        star("G", "Hauptreihe G (Sonne)", 5800, size: 0.35),
        star("K", "Hauptreihe K", 4600, size: 0.3, brightness: 0.8),
        star("M", "Hauptreihe M", 3300, size: 0.28, brightness: 0.6),
        star("redGiant", "Roter Riese", 4000, size: 0.55, brightness: 1.3),
        star("redSupergiant", "Roter Überriese", 3500, size: 0.8, brightness: 1.8),
        star("blueSupergiant", "Blauer Überriese", 22000, size: 0.8, brightness: 2),
        star("whiteDwarf", "Weißer Zwerg", 14000, size: 0.2, brightness: 0.7),
        star("brownDwarf", "Brauner Zwerg", 1400, size: 0.25, brightness: 0.35),
        star("neutron", "Neutronenstern", 40000, size: 0.15, brightness: 0.6),
        star("pulsar", "Pulsar", 30000, size: 0.3, extra: [
            ParamSpec(key: "spinPeriod", title: "Drehperiode", range: 0.1...5, def: 1.2, format: "%.2f s", group: "Pulsar"),
            ParamSpec(key: "beamWidth", title: "Strahlbreite", range: 2...40, def: 12, format: "%.0f°", group: "Pulsar"),
            ParamSpec(key: "beamTilt", title: "Strahlneigung", range: 5...90, def: 50, format: "%.0f°", help: "Winkel zwischen Magnetachse und Drehachse. Die Kamera liegt auf dem Kegel, den der Strahl überstreicht.", group: "Pulsar"),
            ParamSpec(key: "coneGlow", title: "Sichtbare Lichtkegel", range: 0...1, def: 0.5, group: "Pulsar"),
            ParamSpec(key: "angle", title: "Lage der Drehachse", range: 0...360, def: 70, format: "%.0f°", group: "Pulsar"),
        ], az: 2.5...4.5, el: 0.8...2),
        star("magnetar", "Magnetar", 35000, size: 0.25, extra: [
            ParamSpec(key: "flareRate", title: "Ausbrüche pro Minute", range: 0.2...12, def: 3, format: "%.1f", group: "Magnetar"),
        ], brightness: 0.8),
        star("wolfRayet", "Wolf-Rayet mit Nebelhülle", 50000, size: 0.4, extra: [
            ParamSpec(key: "shell", title: "Größe der Hülle", range: 2...12, def: 6, format: "%.1f", help: "Radius der Nebelhülle in Sterngrößen.", group: "Hülle"),
            ParamSpec(key: "shellGlow", title: "Leuchten der Hülle", range: 0...2, def: 0.8, group: "Hülle"),
        ], brightness: 1.5),
        star("cepheid", "Cepheide", 6000, size: 0.45, extra: [
            ParamSpec(key: "pulseDepth", title: "Pulsieren", range: 0...1, def: 0.6, group: "Pulsieren"),
            ParamSpec(key: "pulsePeriod", title: "Periode", range: 1...60, def: 8, format: "%.0f s", group: "Pulsieren"),
        ], brightness: 1.3),
        star("binary", "Doppelstern", 5800, size: 0.35, extra: [
            ParamSpec(key: "separation", title: "Abstand", range: 1.5...12, def: 4, format: "%.1f", help: "In Sterngrößen.", group: "Doppelstern"),
            ParamSpec(key: "period", title: "Umlaufzeit", range: 2...300, def: 30, format: "%.0f s", group: "Doppelstern"),
            ParamSpec(key: "temperature2", title: "Temperatur Begleiter", range: 1000...40000, def: 12000, format: "%.0f K", group: "Doppelstern"),
            ParamSpec(key: "angle", title: "Lage der Bahn", range: 0...360, def: 20, format: "%.0f°", group: "Doppelstern"),
            ParamSpec(key: "stream", title: "Massenstrom", range: 0...1, def: 0.7, help: "Nah gesehen: Gas strömt vom großen Stern zum Begleiter und bildet dort eine leuchtende Scheibe.", group: "Doppelstern"),
        ]),
    ]

    // MARK: Jet

    static let jetParams: [ParamSpec] = [
        ParamSpec(key: "length", title: "Länge", range: 10...135, def: 26, format: "%.0f M", help: "Bis hierhin läuft der Jet weich aus. Höchstens das 1,5-Fache des Kamera-Abstands.", group: "Form", geometry: true),
        ParamSpec(key: "width", title: "Breite an der Basis", range: 0.2...4, def: 0.45, format: "%.2f M", group: "Form", geometry: true),
        ParamSpec(key: "shape", title: "Form am Fuß", range: 0.3...0.9, def: 0.55, help: "Um 0,55 öffnet sich der Jet am Fuß parabolisch wie bei M87.", group: "Form", geometry: true),
        ParamSpec(key: "opening", title: "Öffnungswinkel außen", range: 0.5...20, def: 3.5, format: "%.1f°", help: "Weiter draußen wird aus der Parabel ein schlanker Kegel mit diesem halben Öffnungswinkel.", group: "Form", geometry: true),
        ParamSpec(key: "base", title: "Basis-Höhe", range: 1.5...12, def: 3, format: "%.1f M", group: "Form", geometry: true),
        ParamSpec(key: "falloff", title: "Abklingen", range: 0...3, def: 1.5, help: "Wie schnell der Jet nach außen dunkler wird.", group: "Form", geometry: true),
        ParamSpec(key: "wobble", title: "Wackeln", range: 0...1, def: 0.3, help: "Die Achse windet sich leicht, wie bei echten Jets.", group: "Form", geometry: true),
        ParamSpec(key: "beta", title: "Tempo", range: 0.1...0.995, def: 0.8, format: "%.3f c", help: "Bei hohem Tempo strahlt der Jet, der auf dich zukommt, viel heller (Doppler). Von der Seite sind dann beide Jets schwächer.", group: "Physik", geometry: true),
        ParamSpec(key: "doppler", title: "Doppler-Stärke", range: 0...1, def: 1, help: "1 ist echt, 0 schaltet die Aufhellung aus.", group: "Physik", geometry: true),
        ParamSpec(key: "sheath", title: "Langsame Hülle", range: 0...1, def: 0.75, help: "Anteil des Lichts aus einer langsamen Hülle (0,3 c) um den schnellen Kern, wie bei M87 beobachtet. Sie hält den Gegenjet sichtbar, Jet zu Gegenjet liegt dann bei M87* um 20 zu 1.", group: "Physik", geometry: true),
        ParamSpec(key: "counterJet", title: "Gegenjet", range: 0...1, def: 1, group: "Physik", geometry: true, toggle: true),
        ParamSpec(key: "colourMode", title: "Farbe", range: 0...2, def: 0, group: "Farbe und Knoten", options: ["Synchrotron blauweiß", "Aus der Palette", "Tönung"]),
        ParamSpec(key: "knots", title: "Knoten", range: 0...1, def: 0.6, group: "Farbe und Knoten"),
        ParamSpec(key: "knotSpacing", title: "Knotenabstand", range: 0.03...0.5, def: 0.1, help: "Anteil der Jet-Länge.", group: "Farbe und Knoten"),
        ParamSpec(key: "knotPeriod", title: "Knotentempo", range: 2...120, def: 24, format: "%.0f s", help: "So lange braucht ein Knoten im Jet, der auf dich zukommt, für die ganze Länge. Der Gegenjet läuft im Verhältnis der scheinbaren Geschwindigkeiten.", group: "Farbe und Knoten"),
        ParamSpec(key: "filaments", title: "Filamente", range: 0...1, def: 0.35, help: "Feine Streifen entlang des Jets.", group: "Farbe und Knoten"),
        ParamSpec(key: "pulse", title: "Pulsieren", range: 0...1, def: 0.25, group: "Farbe und Knoten"),
        ParamSpec(key: "pulsePeriod", title: "Pulsperiode", range: 2...60, def: 14, format: "%.0f s", group: "Farbe und Knoten"),
    ]

    static let jets: [VariantSpec] = [
        VariantSpec(id: "main", title: "Jet am Hauptloch", kind: .jet, menu: ["Jets"], params: jetParams, modes: [.attached],
                    events: [], cost: .mittel, stage: 1, ms: 0.04) { seed in
            var o = SpaceObject()
            o.kind = "jet"
            o.variant = "main"
            o.name = "Jet"
            o.seed = seed
            o.attach = "main"
            o.motion.mode = .attached
            return o
        }
    ]

    // MARK: Bodies (stage 2)

    /// Helper for bodies: kind, variant, size (radius in M on an orbit), motion.
    private static func body(_ kind: ObjectKind, _ id: String, _ title: String, menu: [String], params: [ParamSpec],
                             modes: [MotionMode], cost: Cost = .leicht, ms: Float = 0.02, size: Float,
                             brightness: Float = 1, motion: @escaping (UInt32) -> Motion) -> VariantSpec {
        VariantSpec(id: id, title: title, kind: kind, menu: menu, params: params, modes: modes, events: [],
                    cost: cost, stage: 2, ms: ms) { seed in
            var o = SpaceObject()
            o.kind = kind.rawValue
            o.variant = id
            o.name = title
            o.seed = seed
            o.size = size
            o.brightness = brightness
            o.motion = motion(seed)
            return o
        }
    }

    /// A visible demo orbit: inclined a little, starting where the body is seen beside the hole.
    static func demoOrbit(_ seed: UInt32, radius: Float, ecc: Float = 0.05, incl: ClosedRange<Float> = 6...18) -> Motion {
        var rng = SeedRNG(seed &+ 3)
        var m = Motion()
        m.mode = .orbit
        m.radius = radius
        m.eccentricity = ecc
        m.inclination = rng.range(incl)
        m.node = rng.range(0...360)
        m.periapsis = rng.range(0...360)
        m.phase = rng.range(0...1)
        return m
    }

    private static let bodyModes: [MotionMode] = [.orbit, .flyby, .fixed, .edge]

    // Planets
    private static let pRotation = ParamSpec(key: "rotation", title: "Tageslänge", range: 5...600, def: 90, format: "%.0f s", help: "Eine Umdrehung in so vielen Sekunden.", group: "Drehung")
    private static let pTilt = ParamSpec(key: "axialTilt", title: "Achsneigung", range: 0...90, def: 20, format: "%.0f°", group: "Drehung")
    private static let pAtmo = ParamSpec(key: "atmosphere", title: "Atmosphäre", range: 0...1, def: 0, help: "Dunst am Rand und weicher Übergang zur Nachtseite.", group: "Atmosphäre")
    private static let pAtmoHue = ParamSpec(key: "atmoHue", title: "Farbe der Atmosphäre", range: 0...360, def: 210, format: "%.0f°", group: "Atmosphäre")
    private static let pClouds = ParamSpec(key: "clouds", title: "Wolken", range: 0...1, def: 0, group: "Atmosphäre", bake: true)
    private static let pCloudSpeed = ParamSpec(key: "cloudSpeed", title: "Wolkentempo", range: -1...1, def: 0.15, help: "Gegen die Oberfläche, Anteil einer Umdrehung pro Tag.", group: "Atmosphäre")
    private static let pOcean = ParamSpec(key: "ocean", title: "Ozean", range: 0...1, def: 0, help: "Anteil der Oberfläche unter Wasser.", group: "Oberfläche", bake: true)
    private static let pCraters = ParamSpec(key: "craters", title: "Krater", range: 0...1, def: 0, group: "Oberfläche", bake: true)
    private static let pBands = ParamSpec(key: "bands", title: "Bänder", range: 0...1, def: 0, group: "Oberfläche", bake: true)
    private static let pStorms = ParamSpec(key: "storms", title: "Stürme", range: 0...1, def: 0, group: "Oberfläche", bake: true)
    private static let pCracks = ParamSpec(key: "cracks", title: "Risse", range: 0...1, def: 0, group: "Oberfläche", bake: true)
    private static let pSpecular = ParamSpec(key: "specular", title: "Glanz", range: 0...1, def: 0, help: "Spiegelung des Lichts auf Wasser oder Eis.", group: "Oberfläche")
    private static let pNight = ParamSpec(key: "nightLights", title: "Lichter auf der Nachtseite", range: 0...1, def: 0, group: "Oberfläche")
    private static let pEmissive = ParamSpec(key: "emissive", title: "Glut", range: 0...2, def: 0, help: "Glühende Lava oder eine heiße Tagseite.", group: "Oberfläche")
    private static let pHue = ParamSpec(key: "hueShift", title: "Farbton", range: -180...180, def: 0, format: "%.0f°", group: "Oberfläche")
    private static let pRings = ParamSpec(key: "rings", title: "Ringe", range: 0...1, def: 0, group: "Ringe", toggle: true)
    private static let pRingIn = ParamSpec(key: "ringInner", title: "Innenrand", range: 1.05...3, def: 1.3, format: "%.2f", help: "In Planetenradien.", group: "Ringe")
    private static let pRingOut = ParamSpec(key: "ringOuter", title: "Außenrand", range: 1.2...4, def: 2.3, format: "%.2f", help: "In Planetenradien.", group: "Ringe")
    private static let pRingDensity = ParamSpec(key: "ringDensity", title: "Dichte", range: 0...1, def: 0.75, group: "Ringe")
    private static let pRingHue = ParamSpec(key: "ringHue", title: "Farbton der Ringe", range: -180...180, def: 0, format: "%.0f°", group: "Ringe")
    private static let pRingGap = ParamSpec(key: "ringGap", title: "Cassini-Teilung", range: 0...1, def: 0.5, group: "Ringe")

    private static func planetParams(_ d: [String: Float]) -> [ParamSpec] {
        [pOcean, pCraters, pBands, pStorms, pCracks, pSpecular, pNight, pEmissive, pHue,
         pAtmo, pAtmoHue, pClouds, pCloudSpeed, pRotation, pTilt,
         pRings, pRingIn, pRingOut, pRingDensity, pRingHue, pRingGap].map { p in d[p.key].map { p.with($0) } ?? p }
    }

    private static func planet(_ id: String, _ title: String, size: Float, _ d: [String: Float], radius: Float = 58) -> VariantSpec {
        body(.planet, id, title, menu: ["Planeten"], params: planetParams(d), modes: bodyModes, ms: 0.05, size: size) { seed in
            demoOrbit(seed, radius: radius)
        }
    }

    static let planets: [VariantSpec] = [
        planet("rocky", "Gestein (Merkur-artig)", size: 1.6, ["craters": 0.85, "rotation": 160]),
        planet("desert", "Wüste (Mars-artig)", size: 1.8, ["craters": 0.35, "atmosphere": 0.25, "atmoHue": 25, "clouds": 0.12, "rotation": 100]),
        planet("earth", "Erdähnlich", size: 2.2, ["ocean": 0.64, "clouds": 0.55, "atmosphere": 0.7, "atmoHue": 212, "specular": 0.7, "nightLights": 0.6, "craters": 0.05]),
        planet("ocean", "Ozeanwelt", size: 2.4, ["ocean": 0.94, "clouds": 0.65, "atmosphere": 0.8, "atmoHue": 205, "specular": 0.85]),
        planet("ice", "Eis (Europa-artig)", size: 1.5, ["cracks": 0.75, "craters": 0.1, "specular": 0.35, "rotation": 140]),
        planet("lava", "Lava", size: 1.7, ["emissive": 1.2, "craters": 0.2, "atmosphere": 0.2, "atmoHue": 15, "cracks": 0.6]),
        planet("gasGiant", "Gasriese (Jupiter-artig)", size: 4, ["bands": 0.85, "storms": 0.6, "atmosphere": 0.3, "atmoHue": 35, "rotation": 45, "axialTilt": 5]),
        planet("ringed", "Ringplanet (Saturn-artig)", size: 3.4, ["bands": 0.5, "storms": 0.15, "atmosphere": 0.25, "atmoHue": 40, "rotation": 50, "axialTilt": 26, "rings": 1]),
        planet("iceGiant", "Eisriese (Neptun-artig)", size: 3, ["bands": 0.35, "storms": 0.45, "atmosphere": 0.6, "atmoHue": 215, "rotation": 60, "axialTilt": 28]),
        planet("hotJupiter", "Heißer Jupiter", size: 3.8, ["bands": 0.6, "storms": 0.3, "emissive": 1, "atmosphere": 0.45, "atmoHue": 20, "rotation": 70], radius: 40),
    ]

    // Moons: orbit their planet (attach), radius in planet radii.
    private static func moon(_ id: String, _ title: String, size: Float, _ d: [String: Float]) -> VariantSpec {
        let params = [pCraters, pCracks, pSpecular, pEmissive, pHue, pAtmo, pAtmoHue, pRotation.with(40), pTilt.with(0),
                      ParamSpec(key: "locked", title: "Gebunden", range: 0...1, def: 1,
                                help: "Zeigt dem Planeten immer dieselbe Seite, wie der Mond der Erde. Tageslänge und Achsneigung gelten dann nicht.",
                                group: "Drehung", toggle: true)]
            .map { p in d[p.key].map { p.with($0) } ?? p }
            + (id == "knolle" ? [ParamSpec(key: "elongation", title: "Streckung", range: 1...3, def: 1.6, group: "Form")] : [])
        return body(.moon, id, title, menu: ["Monde"], params: params, modes: [.orbit, .fixed, .edge], size: size) { seed in
            var m = demoOrbit(seed, radius: 3.4, incl: 2...12)
            m.precession = false
            return m
        }
    }

    static let moons: [VariantSpec] = [
        moon("grey", "Grau verkratert", size: 0.55, ["craters": 0.9]),
        moon("io", "Io-artig vulkanisch", size: 0.55, ["emissive": 0.5, "craters": 0.05]),
        moon("europa", "Europa-artig", size: 0.5, ["cracks": 0.8, "specular": 0.3, "craters": 0.05]),
        moon("titan", "Titan-artig dunstig", size: 0.65, ["atmosphere": 1, "atmoHue": 35]),
        moon("knolle", "Knolle (Phobos)", size: 0.35, ["craters": 0.7]),
    ]

    // Asteroids
    static let rockTypes = ["Kohlig dunkel", "Silikatisch", "Metallisch", "Eis"]
    private static let aRock = ParamSpec(key: "rockType", title: "Gesteinsart", range: 0...3, def: 1, group: "Form", options: rockTypes)

    static let asteroids: [VariantSpec] = [
        body(.asteroid, "single", "Einzelner Asteroid", menu: ["Asteroiden und Gürtel"], params: [
            ParamSpec(key: "elongation", title: "Streckung", range: 1...3, def: 1.7, group: "Form"),
            pCraters.with(0.6), aRock,
            ParamSpec(key: "rotation", title: "Drehung", range: 3...120, def: 24, format: "%.0f s", help: "Eine Umdrehung in so vielen Sekunden.", group: "Drehung"),
        ], modes: bodyModes, size: 0.7) { seed in demoOrbit(seed, radius: 50, ecc: 0.1) },
    ]

    // Belts and rings of particles
    private static func beltMotion(_ seed: UInt32, incl: Float) -> Motion {
        var m = Motion()
        m.mode = .orbit
        m.inclination = incl
        m.node = Float(seed % 360)
        m.precession = false
        return m
    }

    static let belts: [VariantSpec] = [
        body(.belt, "ring", "Gürtel ums Loch", menu: ["Asteroiden und Gürtel"], params: [
            ParamSpec(key: "rInner", title: "Innenradius", range: 10...80, def: 52, format: "%.0f M", group: "Gürtel"),
            ParamSpec(key: "rOuter", title: "Außenradius", range: 12...85, def: 68, format: "%.0f M", group: "Gürtel"),
            ParamSpec(key: "thickness", title: "Dicke", range: 0...10, def: 1.2, format: "%.1f°", group: "Gürtel"),
            ParamSpec(key: "count", title: "Anzahl", range: 200...20000, def: 9000, format: "%.0f", group: "Gürtel"),
            ParamSpec(key: "sizeMin", title: "Kleinste Größe", range: 0.5...6, def: 0.9, format: "%.1f px", group: "Gürtel"),
            ParamSpec(key: "sizeMax", title: "Größte Größe", range: 1...30, def: 7, format: "%.1f px", group: "Gürtel"),
            ParamSpec(key: "clumping", title: "Klumpung", range: 0...1, def: 0.35, group: "Gürtel"),
            aRock,
            ParamSpec(key: "dustGlow", title: "Staubglühen", range: 0...1, def: 0.45, help: "Feiner Staub zwischen den Brocken, im Gegenlicht hell.", group: "Gürtel"),
        ], modes: [.orbit], cost: .mittel, ms: 0.05, size: 1) { seed in beltMotion(seed, incl: 4) },
        body(.belt, "stream", "Trümmerstrom am Rand", menu: ["Asteroiden und Gürtel"], params: [
            ParamSpec(key: "count", title: "Anzahl", range: 20...2000, def: 260, format: "%.0f", group: "Strom"),
            ParamSpec(key: "spread", title: "Streuung", range: 0...60, def: 16, format: "%.0f pt", group: "Strom"),
            ParamSpec(key: "sizeMin", title: "Kleinste Größe", range: 0.5...6, def: 1, format: "%.1f px", group: "Strom"),
            ParamSpec(key: "sizeMax", title: "Größte Größe", range: 1...30, def: 9, format: "%.1f px", group: "Strom"),
            aRock,
        ], modes: [.edge], cost: .leicht, ms: 0.01, size: 1) { _ in
            var m = Motion()
            m.mode = .edge
            m.edgeSpeed = 40
            m.edgeGap = 0
            m.offset = 18
            m.wobble = 0.3
            return m
        },
        body(.belt, "dust", "Staub- oder Eisring", menu: ["Asteroiden und Gürtel"], params: [
            ParamSpec(key: "rInner", title: "Innenradius", range: 10...80, def: 50, format: "%.0f M", group: "Ring"),
            ParamSpec(key: "rOuter", title: "Außenradius", range: 12...85, def: 62, format: "%.0f M", group: "Ring"),
            ParamSpec(key: "density", title: "Dichte", range: 0...1, def: 0.5, group: "Ring"),
            ParamSpec(key: "hue", title: "Farbton", range: 0...360, def: 200, format: "%.0f°", help: "Um 200° bläulich wie Eis, um 30° bräunlich wie Staub.", group: "Ring"),
            ParamSpec(key: "thickness", title: "Dicke", range: 0...10, def: 0.4, format: "%.1f°", group: "Ring"),
        ], modes: [.orbit], cost: .mittel, ms: 0.03, size: 1) { seed in beltMotion(seed, incl: 2) },
    ]

    // Comets
    private static func comet(_ id: String, _ title: String, _ d: [String: Float]) -> VariantSpec {
        let params = [
            ParamSpec(key: "coma", title: "Koma", range: 0...1, def: 0.6, help: "Leuchtende Gashülle um den Kern.", group: "Komet"),
            ParamSpec(key: "ionTail", title: "Ionenschweif", range: 0...1, def: 0.7, help: "Schmal und bläulich, zeigt genau vom Licht weg.", group: "Komet"),
            ParamSpec(key: "dustTail", title: "Staubschweif", range: 0...1, def: 0.8, help: "Breit und gelblich, entlang der Bahn gekrümmt.", group: "Komet"),
            ParamSpec(key: "tailLength", title: "Schweiflänge", range: 5...120, def: 40, format: "%.0f M", group: "Komet"),
        ].map { p in d[p.key].map { p.with($0) } ?? p }
        return body(.comet, id, title, menu: ["Kometen und Meteore"], params: params, modes: [.orbit, .flyby, .fixed, .edge],
                    ms: 0.06, size: 0.9) { seed in
            var m = demoOrbit(seed, radius: 46, ecc: 0.72, incl: 15...35)
            m.tempo = 1
            return m
        }
    }

    static let comets: [VariantSpec] = [
        comet("comet", "Komet", [:]),
        comet("green", "Grüner Komet", ["ionTail": 0.9, "dustTail": 0.35, "coma": 0.8]),
    ]

    // Meteors: fleeting streaks on the screen, not part of the scene around the hole.
    static let meteors: [VariantSpec] = [
        body(.meteor, "shootingStar", "Sternschnuppe", menu: ["Kometen und Meteore"], params: [
            ParamSpec(key: "rate", title: "Pro Minute", range: 0.2...30, def: 3, format: "%.1f", group: "Meteore"),
            ParamSpec(key: "trail", title: "Spur", range: 0.05...0.6, def: 0.2, help: "Länge der Spur, Anteil der Schirmhöhe.", group: "Meteore"),
            ParamSpec(key: "flySpeed", title: "Tempo", range: 0.3...3, def: 1, group: "Meteore"),
            ParamSpec(key: "hue", title: "Farbton", range: 0...360, def: 200, format: "%.0f°", group: "Meteore"),
        ], modes: [.fixed], size: 1) { _ in var m = Motion(); m.mode = .fixed; return m },
        body(.meteor, "shower", "Meteorschauer", menu: ["Kometen und Meteore"], params: [
            ParamSpec(key: "rate", title: "Pro Minute im Ausbruch", range: 1...120, def: 24, format: "%.0f", group: "Meteore"),
            ParamSpec(key: "burst", title: "Ausbruchsdauer", range: 3...120, def: 20, format: "%.0f s", group: "Meteore"),
            ParamSpec(key: "pause", title: "Pause dazwischen", range: 0...600, def: 90, format: "%.0f s", group: "Meteore"),
            ParamSpec(key: "radiantX", title: "Radiant waagrecht", range: 0...1, def: 0.82, group: "Meteore"),
            ParamSpec(key: "radiantY", title: "Radiant senkrecht", range: 0...1, def: 0.18, group: "Meteore"),
            ParamSpec(key: "trail", title: "Spur", range: 0.05...0.6, def: 0.14, group: "Meteore"),
            ParamSpec(key: "flySpeed", title: "Tempo", range: 0.3...3, def: 1.2, group: "Meteore"),
            ParamSpec(key: "hue", title: "Farbton", range: 0...360, def: 190, format: "%.0f°", group: "Meteore"),
        ], modes: [.fixed], size: 1) { _ in var m = Motion(); m.mode = .fixed; return m },
        body(.meteor, "fireball", "Feuerkugel", menu: ["Kometen und Meteore"], params: [
            ParamSpec(key: "rate", title: "Pro Minute", range: 0.1...10, def: 0.6, format: "%.1f", group: "Meteore"),
            ParamSpec(key: "fragments", title: "Fragmente", range: 0...8, def: 4, format: "%.0f", group: "Meteore"),
            ParamSpec(key: "smoke", title: "Rauchspur", range: 0...10, def: 3, format: "%.1f s", group: "Meteore"),
            ParamSpec(key: "trail", title: "Spur", range: 0.05...0.6, def: 0.3, group: "Meteore"),
            ParamSpec(key: "hue", title: "Farbton", range: 0...360, def: 110, format: "%.0f°", help: "Um 110° grünlich wie viele helle Feuerkugeln.", group: "Meteore"),
        ], modes: [.fixed], size: 1, brightness: 1.5) { _ in var m = Motion(); m.mode = .fixed; return m },
    ]

    // MARK: Second hole and wormhole (stage 4)

    /// Values of a second hole that change its own small ray map, in a fixed order.
    static let holeGeometryKeys = ["spin", "inclination", "diskOuter", "jet", "jetLength", "jetBeta"]

    private static let hSpin = ParamSpec(key: "spin", title: "Spin", range: 0...0.998, def: 0.7, format: "%.3f", group: "Loch", geometry: true)
    private static let hIncl = ParamSpec(key: "inclination", title: "Blickwinkel", range: 2...88, def: 76, format: "%.0f°", help: "Wie schräg du auf seine Scheibe schaust: 90° ist von der Kante.", group: "Loch", geometry: true)
    private static let hRoll = ParamSpec(key: "roll", title: "Lage der Achse", range: -180...180, def: -14, format: "%.0f°", help: "Dreht das Loch mit Scheibe in der Bildebene.", group: "Loch")
    private static let hRing = ParamSpec(key: "ringGlow", title: "Ringleuchten", range: 0...3, def: 1, help: "Leuchten des Photonenrings um den Schatten.", group: "Loch")
    private static let hDiskOuter = ParamSpec(key: "diskOuter", title: "Außenradius", range: 6...30, def: 13, format: "%.0f M", help: "In M des zweiten Lochs.", group: "Scheibe", geometry: true)
    private static let hDiskBright = ParamSpec(key: "diskBrightness", title: "Helligkeit", range: 0...3, def: 1.1, group: "Scheibe")
    private static let hDiskPeriod = ParamSpec(key: "diskPeriod", title: "Umlaufzeit innen", range: 2...60, def: 9, format: "%.0f s", group: "Scheibe")
    private static let hHue = ParamSpec(key: "hueShift", title: "Farbton", range: -180...180, def: 0, format: "%.0f°", help: "Gegen die Palette des Hauptlochs.", group: "Scheibe")
    private static let hJet = ParamSpec(key: "jet", title: "Eigener Jet", range: 0...1, def: 0, group: "Jet", geometry: true, toggle: true)
    private static let hJetLength = ParamSpec(key: "jetLength", title: "Länge", range: 8...40, def: 20, format: "%.0f M", group: "Jet", geometry: true)
    private static let hJetBeta = ParamSpec(key: "jetBeta", title: "Tempo", range: 0.1...0.99, def: 0.8, format: "%.2f c", group: "Jet", geometry: true)
    private static let hJetBright = ParamSpec(key: "jetBrightness", title: "Helligkeit", range: 0...3, def: 1, group: "Jet")

    private static func hole(_ id: String, _ title: String, params: [ParamSpec]) -> VariantSpec {
        VariantSpec(id: id, title: title, kind: .blackHole, menu: ["Exoten"], params: params, modes: [.orbit, .fixed, .flyby],
                    events: [], cost: .schwer, stage: 4, ms: 0.5) { seed in
            var o = SpaceObject()
            o.kind = "blackHole"
            o.variant = id
            o.name = title
            o.seed = seed
            o.size = 0.3
            // Binary: an inclined orbit that passes in front of the hole and behind it.
            var m = Motion()
            m.mode = .orbit
            m.radius = 46
            m.eccentricity = 0.05
            // Tilted so it passes close to the line of sight (at the default view): the holes lens each other.
            m.inclination = 21
            m.node = 270
            m.phase = 0.5
            m.tempo = 1
            m.precession = false
            o.motion = m
            return o
        }
    }

    static let wormholeSides = ["Fremder Himmel", "Unser Himmel von hinten", "Galaxie in der Mitte"]

    static let exotics: [VariantSpec] = [
        hole("bare", "Zweites Loch ohne Scheibe", params: [hSpin, hIncl, hRoll, hRing]),
        hole("disk", "Zweites Loch mit Scheibe", params: [hSpin, hIncl, hRoll, hRing, hDiskOuter, hDiskBright, hDiskPeriod, hHue, hJet, hJetLength, hJetBeta, hJetBright]),
        hole("diskJet", "Zweites Loch mit Scheibe und Jet", params: [hSpin, hIncl, hRoll, hRing, hDiskOuter, hDiskBright, hDiskPeriod, hHue,
                                                                  hJet.with(1), hJetLength, hJetBeta, hJetBright]),
        VariantSpec(id: "sphere", title: "Wurmloch", kind: .wormhole, menu: ["Exoten"], params: [
            ParamSpec(key: "lens", title: "Linsenstärke", range: 0...2, def: 1, help: "Wie stark es Sterne und Nebel um sich herum biegt.", group: "Wurmloch"),
            ParamSpec(key: "otherSide", title: "Andere Seite", range: 0...2, def: 2, group: "Andere Seite", options: wormholeSides),
            ParamSpec(key: "otherHue", title: "Farbton drüben", range: -180...180, def: 0, format: "%.0f°", help: "Drüben leuchtet der Nebel kühl blau. Der Regler dreht den Farbton.", group: "Andere Seite"),
            ParamSpec(key: "otherBright", title: "Helligkeit drüben", range: 0...3, def: 1.1, group: "Andere Seite"),
            ParamSpec(key: "otherStars", title: "Sterne drüben", range: 0...3, def: 1.4, group: "Andere Seite"),
            ParamSpec(key: "rimGlow", title: "Randleuchten", range: 0...2, def: 0.35, group: "Wurmloch"),
            ParamSpec(key: "ripple", title: "Schimmern", range: 0...1, def: 0.3, help: "Das Bild drüben wabert leicht.", group: "Wurmloch"),
        ], modes: [.fixed, .orbit, .flyby], events: [], cost: .mittel, stage: 4, ms: 0.12) { seed in
            var o = SpaceObject()
            o.kind = "wormhole"
            o.variant = "sphere"
            o.name = "Wurmloch"
            o.seed = seed
            o.size = 130
            var m = Motion()
            m.mode = .fixed
            m.x = 0.8
            m.y = 0.34
            m.depth = "front"
            o.motion = m
            return o
        },
    ]

    /// Stations whose ring is a wormhole gate: the inside shows another sky.
    static let gateIDs: Set<String> = ["ringgate", "stargate"]
    static let gateParams: [ParamSpec] = [
        ParamSpec(key: "portal", title: "Andere Seite zeigen", range: 0...1, def: 1, help: "Im Ring liegt ein Wurmloch: drinnen siehst du einen anderen Himmel.", group: "Tor", toggle: true),
        ParamSpec(key: "otherSide", title: "Andere Seite", range: 0...2, def: 0, group: "Tor", options: wormholeSides),
        ParamSpec(key: "otherHue", title: "Farbton drüben", range: -180...180, def: 0, format: "%.0f°", group: "Tor"),
        ParamSpec(key: "otherBright", title: "Helligkeit drüben", range: 0...3, def: 1.1, group: "Tor"),
    ]

    // MARK: Ships and stations (stage 3)

    static func shipParams(_ d: ShipDesign?) -> [ParamSpec] {
        [
            ParamSpec(key: "hullBright", title: "Helligkeit der Hülle", range: 0.2...2, def: 1, group: "Hülle"),
            ParamSpec(key: "windows", title: "Fensterlichter", range: 0...1, def: d?.windows ?? 0.5, help: "Kleine Lichtpunkte in Reihen auf der Hülle.", group: "Hülle"),
            ParamSpec(key: "glow", title: "Glühen", range: 0...3, def: 1, help: "Triebwerke, Warpgondeln und Lampen.", group: "Glühen"),
            ParamSpec(key: "glowHue", title: "Glühfarbe", range: 0...360, def: d?.glowHue ?? 210, format: "%.0f°", group: "Glühen"),
            ParamSpec(key: "gloss", title: "Glanz", range: 0...2, def: 1, help: "Wie glatt die Oberfläche ist. Höher spiegelt schärfer, niedriger wird matter.", group: "Material"),
            ParamSpec(key: "wear", title: "Abnutzung", range: 0...1, def: d?.wear ?? 0.25, help: "Schmutzspuren, Farbunterschiede zwischen den Platten und stumpfe Stellen.", group: "Material"),
            ParamSpec(key: "reflection", title: "Spiegelung", range: 0...2, def: 1, help: "Wie stark sich Himmel, Nebel und die Scheibe des Lochs in der Hülle spiegeln.", group: "Material"),
            ParamSpec(key: "yaw", title: "Drehung", range: -180...180, def: d?.yaw ?? -32, format: "%.0f°", help: "Fest im Bild und am Rand: wohin die Spitze zeigt. 0° ist nach rechts, negativ auf dich zu.", group: "Lage"),
            ParamSpec(key: "pitch", title: "Neigung", range: -90...90, def: d?.pitch ?? 22, format: "%.0f°", help: "Positiv zeigt die Oberseite.", group: "Lage"),
            ParamSpec(key: "roll", title: "Rollen", range: -180...180, def: d?.roll ?? 0, format: "%.0f°", group: "Lage"),
            ParamSpec(key: "selfSpin", title: "Eigendrehung", range: -40...40, def: d?.spin ?? 0, format: "%.1f° pro s", group: "Lage"),
        ]
    }

    private static func ship(_ d: ShipDesign) -> VariantSpec {
        let kind: ObjectKind = d.station ? .station : .ship
        let modes: [MotionMode] = d.station ? [.fixed, .orbit, .flyby, .edge] : [.orbit, .edge, .flyby, .fixed]
        return VariantSpec(id: d.id, title: d.title, kind: kind, menu: [d.station ? "Stationen" : "Raumschiffe", d.universe],
                           params: shipParams(d) + (gateIDs.contains(d.id) ? gateParams : []), modes: modes, events: d.events, cost: .leicht, stage: 3, ms: d.station ? 0.03 : 0.02) { seed in
            var o = SpaceObject()
            o.kind = kind.rawValue
            o.variant = d.id
            o.name = d.title
            o.seed = seed
            o.size = d.size
            if d.station {
                var m = Motion()
                m.mode = .fixed
                var rng = SeedRNG(seed &+ 5)
                m.x = rng.range(0.72...0.86)
                m.y = rng.range(0.25...0.4)
                o.motion = m
                o.size = 160
                // A gate opens now and then: kawoosh or a ship passing through.
                o.events.kinds = d.events
                o.events.on = !d.events.isEmpty
            } else {
                o.motion = demoOrbit(seed, radius: 54, ecc: 0.05, incl: 8...20)
                o.events.kinds = d.events
                o.events.on = !d.events.isEmpty
            }
            return o
        }
    }

    static let ships: [VariantSpec] = ShipCatalog.designs.map(ship)

    /// Own 3D model from a file; the file is chosen on the objects page.
    static let models: [VariantSpec] = [
        VariantSpec(id: "file", title: "Eigenes Modell", kind: .model, menu: ["Eigenes Modell"], params: shipParams(nil),
                    modes: [.orbit, .edge, .flyby, .fixed], events: ShipCatalog.eventSpecs.map(\.id), cost: .mittel, stage: 3, ms: 0.04) { seed in
            var o = SpaceObject()
            o.kind = "model"
            o.variant = "file"
            o.name = "Eigenes Modell"
            o.seed = seed
            o.size = 4
            o.motion = demoOrbit(seed, radius: 54, ecc: 0.05, incl: 8...20)
            return o
        },
    ]

    /// Star variant as a body near the hole: on an orbit, radius in M by type.
    static func makeNear(_ v: VariantSpec, seed: UInt32) -> SpaceObject {
        var o = v.make(seed)
        let radius: [String: Float] = ["O": 2.6, "B": 2.3, "A": 2, "F": 1.8, "G": 1.7, "K": 1.5, "M": 1.1, "redGiant": 4,
                                       "redSupergiant": 6, "blueSupergiant": 5, "whiteDwarf": 0.5, "brownDwarf": 1.1,
                                       "wolfRayet": 1.8, "cepheid": 3, "binary": 1.6]
        o.size = radius[v.id] ?? 1.7
        o.motion = demoOrbit(seed, radius: 72, ecc: 0.05, incl: 10...25)
        o.name = v.title + " (nah)"
        if v.id == "binary" {
            // Close binaries seen up close: a cool donor filling its lobe, a hot compact companion.
            o.params["temperature"] = 4300
            o.params["temperature2"] = 20000
            o.params["separation"] = 3.4
        }
        return o
    }

    // MARK: Scenes

    /// A scene with a bit of everything that stage 1 offers. The dice for "Szene würfeln".
    static func randomScene(_ seed: UInt32) -> [SpaceObject] {
        var rng = SeedRNG(seed)
        func pick(_ list: [VariantSpec]) -> VariantSpec { list[min(Int(rng.next() * Float(list.count)), list.count - 1)] }
        func next() -> UInt32 { UInt32(rng.next() * 999_999) + 1 }
        var out: [SpaceObject] = []
        let galaxies = variants(of: .galaxy).filter { $0.id != "quasar" }
        for _ in 0..<(1 + Int(rng.next() * 2)) { out.append(rolled(pick(galaxies).make(next()), seed: next())) }
        let plain = variants(of: .star).filter { ["O", "B", "A", "F", "G", "K", "M", "redGiant", "blueSupergiant", "whiteDwarf"].contains($0.id) }
        for _ in 0..<(2 + Int(rng.next() * 3)) { out.append(pick(plain).make(next())) }
        if rng.next() < 0.5 { out.append(pick(variants(of: .star).filter { ["pulsar", "cepheid", "binary", "wolfRayet", "magnetar"].contains($0.id) }).make(next())) }
        if rng.next() < 0.35, let jet = variants(of: .jet).first { out.append(jet.make(next())) }
        return out
    }

    /// The showcase scene of the preset "Sternsystem" and the standard set for the GPU budget:
    /// jet, ringed planet with a moon, belt, comet, two galaxies (one lensed into arcs), a pulsar.
    static func starSystemScene() -> ObjectScene {
        func make(_ kind: String, _ variant: String, _ id: String, _ name: String, seed: UInt32) -> SpaceObject {
            var o = ObjectCatalog.variant(kind, variant)!.make(seed)
            o.id = "sternsystem-" + id
            o.name = name
            return o
        }
        var jet = make("jet", "main", "jet", "Jet", seed: 11)
        jet.params["beta"] = 0.8
        var planet = make("planet", "ringed", "planet", "Ringplanet", seed: 4242)
        planet.size = 3.2
        planet.motion.radius = 66
        planet.motion.eccentricity = 0.06
        planet.motion.inclination = 13
        planet.motion.node = 200
        planet.motion.periapsis = 0
        planet.motion.phase = 0.71
        planet.params["axialTilt"] = 24
        var moon = make("moon", "grey", "moon", "Mond", seed: 77)
        moon.attach = planet.id
        moon.size = 0.55
        moon.motion.radius = 4.2
        moon.motion.inclination = 6
        moon.motion.phase = 0.15
        moon.motion.tempo = 1
        var belt = make("belt", "ring", "belt", "Asteroidengürtel", seed: 909)
        belt.params["rInner"] = 50
        belt.params["rOuter"] = 58
        belt.params["count"] = 7000
        belt.motion.inclination = 5
        belt.motion.node = 60
        var comet = make("comet", "comet", "comet", "Komet", seed: 31)
        comet.motion.radius = 52
        comet.motion.eccentricity = 0.74
        comet.motion.inclination = 28
        comet.motion.node = 300
        comet.motion.periapsis = 230
        comet.motion.phase = 0.93
        comet.motion.tempo = 1
        comet.motion.precession = false
        var arcs = make("galaxy", "spiral", "arcs", "Galaxie hinter dem Loch", seed: 4711)
        arcs.size = 4.5
        arcs.motion.azimuth = 3
        arcs.motion.elevation = 0.4
        var far = make("galaxy", "barred", "galaxy", "Balkenspirale", seed: 12)
        far.size = 5
        far.motion.azimuth = -27
        far.motion.elevation = 11
        var pulsar = make("star", "pulsar", "pulsar", "Pulsar", seed: 9)
        pulsar.motion.azimuth = 24
        pulsar.motion.elevation = 12
        pulsar.params["spikes"] = 1
        var scene = ObjectScene()
        scene.items = [jet, arcs, far, pulsar, belt, planet, moon, comet]
        return scene
    }

    /// The showcase scene of the preset "SciFi-Hafen" (stage 4): a wormhole beside the hole, Babylon 5 and a
    /// stargate fixed on the screen, ships from four universes on orbits and along the bands, with their jumps.
    static func sciFiScene() -> ObjectScene {
        func make(_ kind: String, _ variant: String, _ id: String, seed: UInt32) -> SpaceObject {
            var o = ObjectCatalog.variant(kind, variant)!.make(seed)
            o.id = "scifi-" + id
            return o
        }
        var worm = make("wormhole", "sphere", "wormhole", seed: 21)
        worm.motion.x = 0.83
        worm.motion.y = 0.3
        worm.size = 210
        worm.params["otherSide"] = 2
        var b5 = make("station", "b5", "b5", seed: 5)
        b5.motion.x = 0.13
        b5.motion.y = 0.28
        b5.size = 190
        var gate = make("station", "stargate", "stargate", seed: 7)
        gate.motion.x = 0.9
        gate.motion.y = 0.7
        gate.size = 150
        gate.params["yaw"] = -40
        gate.events.interval = 90
        var ent = make("ship", "enterpriseD", "enterprise", seed: 31)
        ent.motion.radius = 58
        ent.motion.inclination = 14
        ent.motion.phase = 0.2
        ent.events.interval = 70
        var endurance = make("ship", "endurance", "endurance", seed: 41)
        endurance.motion.radius = 66
        endurance.motion.inclination = 22
        endurance.motion.node = 140
        endurance.motion.phase = 0.3
        endurance.events.interval = 60
        var galactica = make("ship", "galactica", "galactica", seed: 51)
        galactica.motion.radius = 74
        galactica.motion.inclination = 9
        galactica.motion.node = 300
        galactica.motion.phase = 0.85
        galactica.events.interval = 80
        var falcon = make("ship", "falcon", "falcon", seed: 61)
        falcon.motion = Motion()
        falcon.motion.mode = .edge
        falcon.motion.edge = "bottom"
        falcon.motion.offset = 26
        falcon.motion.edgeSpeed = 70
        falcon.motion.edgeGap = 25
        falcon.size = 60
        var roci = make("ship", "rocinante", "rocinante", seed: 71)
        roci.motion = Motion()
        roci.motion.mode = .edge
        roci.motion.edge = "top"
        roci.motion.direction = "left"
        roci.motion.offset = 22
        roci.motion.edgeSpeed = 45
        roci.motion.edgeGap = 40
        roci.size = 70
        var white = make("ship", "whitestar", "whitestar", seed: 81)
        white.motion = Motion()
        white.motion.mode = .edge
        white.motion.edge = "bottom"
        white.motion.direction = "left"
        white.motion.offset = 46
        white.motion.edgeSpeed = 55
        white.motion.edgeGap = 50
        white.size = 64
        var scene = ObjectScene()
        scene.items = [worm, b5, gate, ent, endurance, galactica, falcon, roci, white]
        return scene
    }

    /// Fixed scene for the settings screenshot: the ringed planet of "Sternsystem" first, so its detail shows,
    /// then the galaxies, stars and the jet of stage 1.
    static func demoScene() -> [SpaceObject] {
        let system = starSystemScene().items
        let planet = system.first { $0.kind == "planet" }!
        return [planet] + system.filter { $0.kind != "planet" && $0.kind != "jet" } + stageOneDemo()
    }

    /// Fixed scene for the settings screenshot of stage 3: a ship with events first, then a station and more ships.
    static func shipDemoScene() -> [SpaceObject] {
        ["enterprise", "ds9", "falcon", "galactica", "rocinante"].compactMap { id in
            ships.first { $0.id == id }.map { $0.make(UInt32(id.count * 97)) }
        }
    }

    private static func stageOneDemo() -> [SpaceObject] {
        var g = variant("galaxy", "spiral")!.make(4711)
        g.name = "Spiralgalaxie"
        var e = variant("galaxy", "elliptical")!.make(42)
        e.name = "Elliptische Galaxie"
        let s1 = variant("star", "K")!.make(7), s2 = variant("star", "blueSupergiant")!.make(8)
        let p = variant("star", "pulsar")!.make(9)
        let j = variant("jet", "main")!.make(1)
        return [g, e, s1, s2, p, j]
    }
}
