import AppKit
import Foundation
import simd

/// The glowing line on one bar edge (menu bar or Dock).
struct EdgeStyle: Codable, Equatable {
    var on = true
    var intensity: Float = 1.0
    var lineWidth: Float = 1.1          // points
    var reachPicture: Float = 12        // points of glow into the picture
    var reachBar: Float = 12            // points of glow into the bar
    var darkenPicture: Float = 0.55
    var darkenBar: Float = 0.55
    var flowSpeed: Float = 1.0
    var flowMode: Int = 0               // 0 towards the hole, 1 away, 2 to the right, 3 to the left
    var focus: Float = 1.0              // 0 even along the edge, 1 bright near the hole
    var customColour = false
    var colour = "#FF8A3A"

    /// German source texts; shown through L().
    static let flowModes = ["Zum Loch hin", "Vom Loch weg", "Nach rechts", "Nach links"]
}

/// Everything that shapes the picture. One Look per preset.
struct Look: Codable, Equatable {
    // Loch
    var spin: Float = 0.9               // a/M, 0 = Schwarzschild, < 1
    var inclinationDeg: Float = 66      // 0 = looking down the spin axis, 90 = edge-on
    var cameraDistance: Float = 90      // in M
    var holeSize: Float = 0.085         // shadow radius as a fraction of the shorter screen side
    var ringGlow: Float = 0.8
    // Scheibe
    var diskOuter: Float = 46           // in M
    var diskBrightness: Float = 1.0
    var diskHueVariety: Float = 0.5
    // Farben: sRGB hex, slots see Palette.slotNames
    var palette: [String] = Palette.builtIn[0].colors
    // Nebel
    var nebula: Float = 1.0
    var nebulaSwirl: Float = 3.0        // radians of twist at the centre
    var nebulaScale: Float = 7.0
    var nebulaSeed: Float = 0
    // Sterne
    var stars: Float = 1.0
    var starDensity: Float = 1.0
    var twinkle: Float = 0.3
    var starColour: Float = 1.0         // 0 white, 1 true colour by temperature, 2 exaggerated
    // Ränder
    var edgeTop = EdgeStyle()
    var edgeBottom = EdgeStyle()
    // Bewegung
    var diskPeriod: Float = 20          // seconds per turn at the inner edge
    var diskShear: Float = 1.0          // 1 Kepler, 0 rigid
    var nebulaPeriod: Float = 240       // seconds per turn of the nebula near the centre
    // Bild
    var exposure: Float = 1.15
    // Objekte
    var objects = ObjectScene()

    var horizon: Float { 1 + (1 - spin * spin).squareRoot() }

    /// Innermost stable circular orbit, prograde (Bardeen, Press & Teukolsky 1972).
    var isco: Float {
        let a = Double(spin)
        let z1 = 1 + cbrt(1 - a * a) * (cbrt(1 + a) + cbrt(1 - a))
        let z2 = (3 * a * a + z1 * z1).squareRoot()
        return Float(3 + z2 - ((3 - z1) * (3 + z1 + 2 * z2)).squareRoot())
    }

    /// Fields that change the traced rays. Anything else is applied per frame.
    var geometryKey: [Float] { [spin, inclinationDeg, cameraDistance, holeSize, diskOuter] + objects.jetGeometryKey }

    /// Angular speed at the inner edge in the shader's units (G = M = c = 1, one unit per second).
    var iscoOmega: Float { 1 / (isco * isco.squareRoot() + spin) }

    var linearPalette: [SIMD3<Float>] {
        (0..<8).map { i in i < palette.count ? Palette.linear(palette[i]) : .zero }
    }

    /// Decodes with defaults for keys that older files do not have yet.
    static func decodeLenient(_ data: Data) -> Look? {
        guard let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(Look())) as? [String: Any]
        else { return nil }
        var merged = base.merging(stored) { _, new in new }
        // Nested styles: fill keys that older files lack.
        for key in ["edgeTop", "edgeBottom", "objects"] {
            if let b = base[key] as? [String: Any], let st = stored[key] as? [String: Any] {
                merged[key] = b.merging(st) { _, new in new }
            }
        }
        guard let d = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(Look.self, from: d)
    }
}

struct NamedPalette: Identifiable {
    var id: String { name }
    let name: String
    let colors: [String]
}

enum Palette {
    static let slotNames = ["Tiefe", "Violett", "Glut", "Feuer", "Kern", "Akzent kühl", "Akzent tief"]

    static let builtIn: [NamedPalette] = [
        NamedPalette(name: "Strudel", colors: ["#1A0633", "#6A1B7A", "#D23A78", "#FF7A1F", "#FFE0A0", "#2FC6D8", "#3A4DD8"]),
        NamedPalette(name: "Gargantua", colors: ["#140A04", "#5A2A0C", "#B8561A", "#F2A04A", "#FFF4E0", "#8FA8C8", "#2A3550"]),
        NamedPalette(name: "Ereignishorizont", colors: ["#120202", "#4A0A06", "#A8260C", "#F0701C", "#FFD27A", "#C0582A", "#3A1208"]),
        NamedPalette(name: "Eisblau", colors: ["#040A1E", "#16306A", "#2E6FD0", "#58C8F0", "#E8FBFF", "#9A6CF0", "#1E1A5A"]),
        NamedPalette(name: "Smaragd", colors: ["#02140E", "#0A4A3A", "#14A07A", "#7AE0A8", "#F4FFE8", "#C04AD8", "#26206A"]),
    ]

    /// sRGB hex to linear.
    static func linear(_ hex: String) -> SIMD3<Float> {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        func lin(_ c: UInt32) -> Float { powf(Float(c & 0xFF) / 255, 2.2) }
        return SIMD3(lin(v >> 16), lin(v >> 8), lin(v))
    }

    static func color(_ hex: String) -> NSColor {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    static func hex(_ c: NSColor) -> String {
        let s = c.usingColorSpace(.sRGB) ?? c
        func b(_ x: CGFloat) -> Int { Int((max(0, min(1, x)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", b(s.redComponent), b(s.greenComponent), b(s.blueComponent))
    }
}

struct Preset: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var look: Look
    var builtIn: Bool
    /// Built-in preset a copy was made from; its values are the defaults for the reset buttons.
    var basedOn: String?

    static let factory: [Preset] = {
        var strudel = Look()
        strudel.palette = Palette.builtIn[0].colors

        var gargantua = Look()
        gargantua.diskPeriod = 12
        gargantua.inclinationDeg = 84
        gargantua.spin = 0.6
        gargantua.cameraDistance = 70
        gargantua.diskOuter = 24
        gargantua.palette = Palette.builtIn[1].colors
        gargantua.nebula = 0.35
        gargantua.diskHueVariety = 0.15
        gargantua.ringGlow = 1.2

        var m87 = Look()
        m87.inclinationDeg = 17          // angle between jet and line of sight (EHT 2019)
        m87.spin = 0.9
        m87.diskOuter = 14
        m87.holeSize = 0.11
        m87.palette = Palette.builtIn[2].colors
        m87.nebula = 0.25
        m87.stars = 0.5
        m87.diskHueVariety = 0.1

        var top = Look()
        top.inclinationDeg = 12
        top.diskOuter = 55
        top.nebulaSwirl = 4.5

        var ice = Look()
        ice.palette = Palette.builtIn[3].colors
        ice.inclinationDeg = 74
        ice.nebulaSeed = 3

        var system = Look()
        system.palette = Palette.builtIn[0].colors
        system.objects = ObjectCatalog.starSystemScene()

        var port = Look()
        port.palette = Palette.builtIn[0].colors
        port.objects = ObjectCatalog.sciFiScene()

        return [
            Preset(id: "strudel", name: "Dein Strudel", look: strudel, builtIn: true),
            Preset(id: "gargantua", name: "Gargantua", look: gargantua, builtIn: true),
            Preset(id: "m87", name: "M87* wie auf dem Foto", look: m87, builtIn: true),
            Preset(id: "draufsicht", name: "Draufsicht", look: top, builtIn: true),
            Preset(id: "eisblau", name: "Eisblau", look: ice, builtIn: true),
            Preset(id: "sternsystem", name: "Sternsystem", look: system, builtIn: true),
            Preset(id: "scifi", name: "SciFi-Hafen", look: port, builtIn: true),
        ]
    }()
}

struct ScreenConfig: Codable, Equatable {
    var presetID: String = "strudel"
    var holeX: Float = 0.5
    var holeY: Float = 0.5
}

/// How much of the picture moves.
enum AnimationMode: String, Codable, CaseIterable {
    case all, edgesOnly, off

    var title: String {
        switch self {
        case .all: L("Alles")
        case .edgesOnly: L("Nur Ränder")
        case .off: L("Aus")
        }
    }
}

/// The updater's settings. Older files have none; then the defaults apply.
struct UpdateSettings: Codable, Equatable {
    /// Look for a new version once a day.
    var auto = true
    /// Last check, seconds since 1970; 0 means never.
    var lastCheck: Double = 0
    /// Version the user chose to skip; automatic checks do not offer it.
    var skipped = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        auto = (try? c.decodeIfPresent(Bool.self, forKey: .auto)) ?? true
        lastCheck = (try? c.decodeIfPresent(Double.self, forKey: .lastCheck)) ?? 0
        skipped = (try? c.decodeIfPresent(String.self, forKey: .skipped)) ?? ""
    }
}

struct AppSettings: Codable, Equatable {
    var animation = AnimationMode.all
    var freezeInLowPower = true
    var fpsPower = 30
    var fpsBattery = 30
    /// Quality levels per power source and area (replaces mapScale and detailBox).
    var quality = QualitySettings()
    var screens: [String: ScreenConfig] = [:]
    // Maus-Modus
    var mouseMode = false
    var mouseSize: Float = 70           // Einstein radius in points
    var mouseShadow = true
    // Sperrbildschirm und Mission Control
    var stillWallpaper = false
    var stillInterval: Double = 30      // minutes
    var originalWallpapers: [String: String] = [:]
    // Langsame Veränderung
    var dayDrift = false
    var dayDriftStrength: Float = 1.0
    // Menüleiste
    var hideMenuIcon = false
    var hideMenuIconConfirmed = false
    // Sprache: "system", "en" or "de"
    var language = "system"
    // Updates
    var updates = UpdateSettings()
    // Hitze: halbe Bildrate und eine Qualitätsstufe weniger bei "serious", Standbild bei "critical"
    var throttleWhenHot = true
    // Bedienungshilfen: "Bewegung reduzieren" von macOS macht die Animation zu "Aus"
    var respectReduceMotion = true
    // Das Willkommensfenster ist gezeigt worden
    var welcomeShown = false

    init() {}

    /// Files before the three animation levels stored a plain on/off.
    private enum LegacyKeys: String, CodingKey { case animationOn, animation, mapScale, detailBox }

    /// Decodes with defaults for keys that older files do not have yet.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.defaults
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        if let m = try? c.decodeIfPresent(AnimationMode.self, forKey: .animation) {
            animation = m
        } else {
            let old = try decoder.container(keyedBy: LegacyKeys.self)
            let on = (try? old.decodeIfPresent(Bool.self, forKey: .animationOn))
                ?? (try? old.decodeIfPresent(Bool.self, forKey: .animation))
            animation = on.map { $0 ? .all : .off } ?? d.animation
        }
        freezeInLowPower = v(.freezeInLowPower, d.freezeInLowPower)
        fpsPower = v(.fpsPower, d.fpsPower)
        fpsBattery = v(.fpsBattery, d.fpsBattery)
        quality = v(.quality, d.quality)
        if !c.contains(.quality), let old = try? decoder.container(keyedBy: LegacyKeys.self) {
            quality.migrate(mapScale: try? old.decodeIfPresent(Float.self, forKey: .mapScale),
                            detailBox: try? old.decodeIfPresent(Bool.self, forKey: .detailBox))
        }
        screens = v(.screens, d.screens)
        mouseMode = v(.mouseMode, d.mouseMode)
        mouseSize = v(.mouseSize, d.mouseSize)
        mouseShadow = v(.mouseShadow, d.mouseShadow)
        stillWallpaper = v(.stillWallpaper, d.stillWallpaper)
        stillInterval = v(.stillInterval, d.stillInterval)
        originalWallpapers = v(.originalWallpapers, d.originalWallpapers)
        dayDrift = v(.dayDrift, d.dayDrift)
        dayDriftStrength = v(.dayDriftStrength, d.dayDriftStrength)
        hideMenuIcon = v(.hideMenuIcon, d.hideMenuIcon)
        hideMenuIconConfirmed = v(.hideMenuIconConfirmed, d.hideMenuIconConfirmed)
        language = v(.language, d.language)
        updates = v(.updates, d.updates)
        throttleWhenHot = v(.throttleWhenHot, d.throttleWhenHot)
        respectReduceMotion = v(.respectReduceMotion, d.respectReduceMotion)
        welcomeShown = v(.welcomeShown, d.welcomeShown)
    }

    private static let defaults = AppSettings()
}

/// Where the hole sits on one screen and how tall menu bar and Dock are there.
struct ScreenLayout: Equatable {
    var holeX: Float
    var holeY: Float
    var topBar: Float      // points
    var bottomBar: Float   // points
}

/// What the screen saver needs: one look and where the hole sits.
struct SaverConfig: Codable {
    var look: Look
    var holeX: Float
    var holeY: Float
    /// The levels at the power adapter (the saver runs while the Mac is idle, mostly on power).
    var quality = QualitySettings()

    /// Lenient like the settings file: an older saver.json still loads.
    static func decode(_ data: Data) -> SaverConfig? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lookObj = raw["look"], let ld = try? JSONSerialization.data(withJSONObject: lookObj),
              let look = Look.decodeLenient(ld) else { return nil }
        var q = QualitySettings()
        if let qo = raw["quality"], let qd = try? JSONSerialization.data(withJSONObject: qo),
           let dq = try? JSONDecoder().decode(QualitySettings.self, from: qd) { q = dq }
        return SaverConfig(look: look, holeX: (raw["holeX"] as? NSNumber)?.floatValue ?? 0.5,
                           holeY: (raw["holeY"] as? NSNumber)?.floatValue ?? 0.5, quality: q)
    }
}
