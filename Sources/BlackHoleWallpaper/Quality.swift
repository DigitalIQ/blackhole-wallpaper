import Foundation

/// Quality levels like in games: one overall level per power source, each area can override it.
enum QualityLevel: Int, Codable, CaseIterable {
    case saver = 0, balanced, high, ultra

    /// German title, shown through L().
    var key: String {
        switch self {
        case .saver: "Akku sparen"
        case .balanced: "Ausgewogen"
        case .high: "Hoch"
        case .ultra: "Ultra"
        }
    }
}

/// Parts of the picture with their own level.
enum QualityArea: String, Codable, CaseIterable {
    case hole, jet, sky, bodies, lenses, particles

    var key: String {
        switch self {
        case .hole: "Loch und Scheibe"
        case .jet: "Jet"
        case .sky: "Nebel und Galaxien"
        case .bodies: "Körper und Schiffe"
        case .lenses: "Linsen"
        case .particles: "Partikel und Schweife"
        }
    }

    var help: String {
        switch self {
        case .hole: "Auflösung der Strahlenkarte und Größe der scharfen Zone ums Loch."
        case .jet: "Hochskalierung der Jet-Karte, ab Hoch eine feinere Karte."
        case .sky: "Auflösung des Nebels und der Galaxien."
        case .bodies: "Auflösung der Planeten, Monde, Sterne und Schiffe, ab Hoch geglättet."
        case .lenses: "Strahlenkarte des zweiten Lochs, Reichweite der Linsen."
        case .particles: "Lichtpuffer für Dunst, Schweife und Rauch."
        }
    }
}

/// What the user chose, stored in settings.json.
struct QualitySettings: Codable, Equatable {
    /// Defaults: Hoch at the power adapter, Ausgewogen on battery. A file without a level gets these;
    /// a stored level stays as it is.
    static let defaultPower = QualityLevel.high
    static let defaultBattery = QualityLevel.balanced

    var power = QualitySettings.defaultPower
    var battery = QualitySettings.defaultBattery
    /// Areas with their own level; missing ones follow the overall level.
    var areas: [String: QualityLevel] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        power = (try? c.decodeIfPresent(QualityLevel.self, forKey: .power)) ?? QualitySettings.defaultPower
        battery = (try? c.decodeIfPresent(QualityLevel.self, forKey: .battery)) ?? QualitySettings.defaultBattery
        // Unknown areas or levels are dropped, not fatal.
        let raw = (try? c.decodeIfPresent([String: Int].self, forKey: .areas)) ?? [:]
        areas = raw.reduce(into: [:]) { out, kv in
            if QualityArea(rawValue: kv.key) != nil, let l = QualityLevel(rawValue: kv.value) { out[kv.key] = l }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(power, forKey: .power)
        try c.encode(battery, forKey: .battery)
        try c.encode(areas.mapValues(\.rawValue), forKey: .areas)
    }

    private enum CodingKeys: String, CodingKey { case power, battery, areas }

    /// The levels per area for one power source.
    func resolved(battery onBattery: Bool) -> RenderQuality {
        let base = onBattery ? battery : power
        var q = RenderQuality()
        for a in QualityArea.allCases { q.levels[a] = areas[a.rawValue] ?? base }
        return q
    }

    /// Settings files before the levels had a ray map scale and a detail box switch: a changed
    /// scale becomes the level of the area "Loch und Scheibe", the box off becomes "Akku sparen".
    mutating func migrate(mapScale: Float?, detailBox: Bool?) {
        guard areas[QualityArea.hole.rawValue] == nil else { return }
        if detailBox == false { areas[QualityArea.hole.rawValue] = .saver; return }
        guard let m = mapScale, abs(m - 0.5) > 0.02 else { return }
        areas[QualityArea.hole.rawValue] = m < 0.5 ? .saver : (m < 0.74 ? .high : .ultra)
    }
}

/// The levels in effect for one renderer, and what they mean in numbers.
struct RenderQuality: Equatable {
    var levels: [QualityArea: QualityLevel] = Dictionary(uniqueKeysWithValues: QualityArea.allCases.map { ($0, .balanced) })

    init(_ all: QualityLevel = .balanced) {
        levels = Dictionary(uniqueKeysWithValues: QualityArea.allCases.map { ($0, all) })
    }

    func level(_ a: QualityArea) -> Int { (levels[a] ?? .balanced).rawValue }

    /// Above this many texels the ray maps stop growing (screens larger than 3440 x 1440 at Ultra): 2.8 M texels
    /// are 67 MB without and 90 MB with a jet.
    static let mapTexelCap: Float = 2.8e6

    /// Ray map scale against the screen. The jet's maps are traced with the main map, so a finer jet
    /// raises the whole map (only while there is a jet).
    func mapScale(width: Int, height: Int, jet: Bool) -> Float {
        var s: Float = [0.4, 0.5, 0.6, 0.75][level(.hole)]
        if jet { s = max(s, [0, 0, 0.6, 0.75][level(.jet)]) }
        if s > 0.5 {
            let cap = (RenderQuality.mapTexelCap / Float(max(width * height, 1))).squareRoot()
            s = max(min(s, cap), 0.5)
        }
        return s
    }

    /// Detail box half size in shadow radii (rays at twice the screen resolution).
    var boxRadius: Float { [1.5, 1.5, 2.0, 2.5][level(.hole)] }
    /// Jet maps upsampled bicubic.
    var jetCubic: Bool { level(.jet) >= 1 }
    /// Nebula and soft sky light: target scale against the screen, refresh interval (s).
    var nebulaScale: Float { [0.5, 0.5, 0.75, 1.0][level(.sky)] }
    var nebulaInterval: Float { level(.sky) == 0 ? 0.1 : 0.05 }
    /// Galaxy atlas tile size.
    var galaxyTile: Int { [256, 512, 1024, 1024][level(.sky)] }
    /// Body atlas: size, largest tile, tile pixels per screen pixel (above 1 smooths edges), planet surface scale.
    var atlasSize: Int { level(.bodies) >= 2 ? 2048 : 1024 }
    var maxTile: Int { [256, 512, 1024, 1024][level(.bodies)] }
    var tileScale: Float { [0.6, 1, 1.5, 2][level(.bodies)] }
    var planetScale: Int { level(.bodies) == 0 ? 1 : 2 }
    /// Second holes: ray map size, reach of the far field in map radii.
    var holeMapRes: Int { [384, 512, 640, 768][level(.lenses)] }
    var lensReach: Float { [2.4, 3.2, 3.2, 3.6][level(.lenses)] }
    /// Light buffer: screen px per buffer px, refresh interval (s, 0 = every frame).
    var lightScale: Float { level(.particles) >= 2 ? 2 : 4 }
    var lightInterval: Float { [0.1, 0.05, 0.05, 0][level(.particles)] }
}

/// Measured load per level (MacBook Air M4, 3440 x 1440, `--bench-q` and `--mem`), for the settings page.
enum QualityCost {
    /// Whole picture per overall level, scene Sternsystem: GPU ms per frame (`--bench` at Ausgewogen plus the
    /// `--bench-q` difference), graphics memory MB (`--mem`).
    static let overall: [(ms: Float, mb: Int)] = [(2.6, 86), (2.7, 108), (2.8, 193), (3.0, 258)]
    /// Extra cost of one area at a level against Ausgewogen: ms per frame, MB. Jet with a jet, lenses with a second hole.
    static let area: [QualityArea: [(ms: Float, mb: Int)]] = [
        .hole: [(-0.01, -15), (0, 0), (0.02, 34), (0.03, 83)],
        .jet: [(-0.04, 0), (0, 0), (0.0, 18), (0.01, 51)],
        .sky: [(0, 0), (0, 0), (0.02, 13), (0.03, 30)],
        .bodies: [(-0.01, -1), (0, 0), (0.0, 28), (0.01, 32)],
        .lenses: [(-0.08, -3), (0, 0), (0.01, 4), (0.05, 8)],
        .particles: [(-0.02, 0), (0, 0), (0.03, 0), (0.12, 0)],
    ]
}
