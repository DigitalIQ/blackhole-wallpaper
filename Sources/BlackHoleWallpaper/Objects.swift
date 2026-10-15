import Foundation

/// All objects of one look. Lives in Look, so each preset (and via the monitor copies each screen) has its own.
struct ObjectScene: Codable, Equatable {
    var on = true
    var speed: Float = 1              // tempo factor for all object motion
    var detail = 1                    // 0 sparsam, 1 normal, 2 hoch (atlas scale, caps)
    var relativistic = true           // Doppler brightening of bodies on close orbits
    var items: [SpaceObject] = []

    /// Objects that are drawn: scene on, object on, kind known.
    var active: [SpaceObject] { on ? items.filter { $0.on && $0.objectKind != nil } : [] }

    /// The jet on the main hole, if one is drawn.
    var mainJet: SpaceObject? { active.first { $0.objectKind == .jet && ($0.attach.isEmpty || $0.attach == "main") } }

    /// Values of the main jet that change the traced rays. Empty without a jet, so looks
    /// without one keep their old geometry key.
    var jetGeometryKey: [Float] {
        guard let j = mainJet else { return [] }
        return [1] + ObjectCatalog.geometryParams(of: j)
    }
}

enum ObjectKind: String, Codable, CaseIterable {
    case galaxy, star, jet, planet, moon, asteroid, belt, comet, meteor, blackHole, wormhole, ship, station, model
}

struct SpaceObject: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name = ""
    var on = true
    var kind = "galaxy"               // ObjectKind raw value as String: unknown kinds survive a round trip, are not drawn
    var variant = ""                  // catalog id, e.g. "spiral", "G", "main"
    var seed: UInt32 = 1
    var size: Float = 1               // unit depends on motion.mode: sky = angular diameter in degrees
    var brightness: Float = 1
    var tint = "#FFFFFF"
    var tintAmount: Float = 0
    var motion = Motion()
    var params: [String: Float] = [:] // missing key = catalog default
    var events = ObjectEvents()
    var attach = ""                   // jet: "main" or id of a blackHole; moon: id of its planet
    var model = ""                    // kind model: file name in Models/

    var objectKind: ObjectKind? { ObjectKind(rawValue: kind) }

    /// Parameter value, or the catalog default when the key is missing.
    func param(_ key: String) -> Float {
        if let v = params[key] { return v }
        return ObjectCatalog.spec(for: self)?.param(key)?.def ?? 0
    }
}

enum MotionMode: String, Codable { case orbit, flyby, edge, fixed, sky, attached }

struct Motion: Codable, Equatable {
    var mode = MotionMode.orbit
    // orbit, in M and degrees, relative to the disk plane of the main hole
    var radius: Float = 40, eccentricity: Float = 0, inclination: Float = 0
    var node: Float = 0, periapsis: Float = 0, phase: Float = 0, tempo: Float = 1
    var precession = true
    // flyby
    var passMin: Float = 15, passMax: Float = 60, interval: Float = 90, flySpeed: Float = 1
    var side = "both"                 // front, behind, both
    // edge band
    var edge = "bottom"               // top, bottom, both
    var direction = "right"           // left, right, alternate, random
    var offset: Float = 10            // pt, positive into the picture
    var edgeSpeed: Float = 60         // pt/s
    var edgeGap: Float = 30           // s between passes
    var wobble: Float = 0
    // fixed
    var x: Float = 0.75, y: Float = 0.3   // screen uv
    var depth = "front"               // front, behind
    var spin: Float = 0               // deg/s
    // sky, camera frame, degrees from the line of sight through the hole
    var azimuth: Float = 0, elevation: Float = 0
    var drift: Float = 0, driftAngle: Float = 0   // deg/min, direction of drift

    static let titles: [MotionMode: String] = [
        .orbit: "Bahn ums Loch", .flyby: "Vorbeiflug", .edge: "Am Rand entlang",
        .fixed: "Fest im Bild", .sky: "Am Himmel", .attached: "Am Loch",
    ]
}

struct ObjectEvents: Codable, Equatable {
    var on = false
    var kinds: [String] = []          // subset of the variant's allowed events
    var interval: Float = 120         // mean seconds between events
}

// MARK: - Lenient decoding

// Every key is optional: missing ones keep their default, unknown ones are ignored.
// Kept in extensions so the memberwise and default initialisers stay available.

private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ def: T) -> T { ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? def }
}

/// Decodes one element of a list and turns a broken one into nil instead of failing the list.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

extension ObjectScene {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ObjectScene()
        on = c.value(.on, d.on)
        speed = c.value(.speed, d.speed)
        detail = c.value(.detail, d.detail)
        relativistic = c.value(.relativistic, d.relativistic)
        items = c.value(.items, [Lossy<SpaceObject>]()).compactMap(\.value)
    }
}

extension SpaceObject {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SpaceObject()
        // An element without an id or kind is not an object; skip it.
        guard let id = try c.decodeIfPresent(String.self, forKey: .id), !id.isEmpty,
              let kind = try c.decodeIfPresent(String.self, forKey: .kind) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "object without id or kind"))
        }
        self.id = id
        self.kind = kind
        name = c.value(.name, d.name)
        on = c.value(.on, d.on)
        variant = c.value(.variant, d.variant)
        seed = c.value(.seed, d.seed)
        size = c.value(.size, d.size)
        brightness = c.value(.brightness, d.brightness)
        tint = c.value(.tint, d.tint)
        tintAmount = c.value(.tintAmount, d.tintAmount)
        motion = c.value(.motion, d.motion)
        params = c.value(.params, d.params)
        events = c.value(.events, d.events)
        attach = c.value(.attach, d.attach)
        model = c.value(.model, d.model)
    }
}

extension Motion {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Motion()
        mode = c.value(.mode, d.mode)
        radius = c.value(.radius, d.radius)
        eccentricity = c.value(.eccentricity, d.eccentricity)
        inclination = c.value(.inclination, d.inclination)
        node = c.value(.node, d.node)
        periapsis = c.value(.periapsis, d.periapsis)
        phase = c.value(.phase, d.phase)
        tempo = c.value(.tempo, d.tempo)
        precession = c.value(.precession, d.precession)
        passMin = c.value(.passMin, d.passMin)
        passMax = c.value(.passMax, d.passMax)
        interval = c.value(.interval, d.interval)
        flySpeed = c.value(.flySpeed, d.flySpeed)
        side = c.value(.side, d.side)
        edge = c.value(.edge, d.edge)
        direction = c.value(.direction, d.direction)
        offset = c.value(.offset, d.offset)
        edgeSpeed = c.value(.edgeSpeed, d.edgeSpeed)
        edgeGap = c.value(.edgeGap, d.edgeGap)
        wobble = c.value(.wobble, d.wobble)
        x = c.value(.x, d.x)
        y = c.value(.y, d.y)
        depth = c.value(.depth, d.depth)
        spin = c.value(.spin, d.spin)
        azimuth = c.value(.azimuth, d.azimuth)
        elevation = c.value(.elevation, d.elevation)
        drift = c.value(.drift, d.drift)
        driftAngle = c.value(.driftAngle, d.driftAngle)
    }
}

extension ObjectEvents {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ObjectEvents()
        on = c.value(.on, d.on)
        kinds = c.value(.kinds, d.kinds)
        interval = c.value(.interval, d.interval)
    }
}

extension MotionMode {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MotionMode(rawValue: raw) ?? .orbit
    }
}
