import Foundation
import ModelIO
import simd

/// Surface kinds of ship meshes, read by shipFrag.
enum ShipMat: Float {
    case hull = 0, dark = 1, accent = 2, glow = 3, gold = 4, solar = 5, glass = 6, greeble = 7, deathStar = 8,
         membrane = 9, glowParam = 10, lamp = 11, model = 12
}

/// Material of one part: kind, colour, window lights allowed, emission strength, and its finish:
/// metallic and roughness (negative: the kind's default, for the hull the design's finish).
struct PartMat {
    var kind: ShipMat
    var col: SIMD3<Float>
    var windows: Float = 0
    var emit: Float = 0
    var metal: Float = -1
    var rough: Float = -1

    /// The finish packed into one float for the vertex: metal and roughness in 1/255 steps, -1 for the default.
    var finish: Float {
        guard metal >= 0, rough >= 0 else { return -1 }
        return (min(max(metal, 0), 1) * 255).rounded() * 256 + (min(max(rough, 0), 1) * 255).rounded()
    }
    func finish(metal m: Float, rough r: Float) -> PartMat { var p = self; p.metal = m; p.rough = r; return p }

    /// Bare metal: polished aluminium, stainless steel. Plates and windows as on the hull.
    static func steel(_ c: SIMD3<Float> = SIMD3(0.80, 0.80, 0.82), rough: Float = 0.22, windows: Float = 0) -> PartMat {
        PartMat(kind: .hull, col: c, windows: windows, metal: 1, rough: rough)
    }
    /// Painted armour: a dielectric coat with a satin sheen.
    static func paint(_ c: SIMD3<Float>, rough: Float = 0.42, windows: Float = 0) -> PartMat {
        PartMat(kind: .hull, col: c, windows: windows, metal: 0, rough: rough)
    }
    /// Matt ceramic tiles and composites.
    static func ceramic(_ c: SIMD3<Float>, windows: Float = 0) -> PartMat { PartMat(kind: .hull, col: c, windows: windows, metal: 0, rough: 0.78) }
    /// Crinkled insulation foil in silver (gold is `.gold`).
    static let foil = PartMat(kind: .gold, col: SIMD3(0.86, 0.86, 0.88))

    static func hull(_ c: SIMD3<Float> = SIMD3(0.62, 0.63, 0.66), windows: Float = 0) -> PartMat { PartMat(kind: .hull, col: c, windows: windows) }
    static func dark(_ c: SIMD3<Float> = SIMD3(0.16, 0.16, 0.17), windows: Float = 0) -> PartMat { PartMat(kind: .dark, col: c, windows: windows) }
    static func accent(_ c: SIMD3<Float>) -> PartMat { PartMat(kind: .accent, col: c) }
    static func glow(_ c: SIMD3<Float>, _ e: Float = 1) -> PartMat { PartMat(kind: .glow, col: c, emit: e) }
    /// Glows in the object's own glow colour (slider "Glühfarbe").
    static func engine(_ e: Float = 1) -> PartMat { PartMat(kind: .glowParam, col: SIMD3(1, 1, 1), emit: e) }
    static let gold = PartMat(kind: .gold, col: SIMD3(0.85, 0.62, 0.22))
    static let solar = PartMat(kind: .solar, col: SIMD3(0.10, 0.14, 0.30))
    static let glass = PartMat(kind: .glass, col: SIMD3(0.02, 0.025, 0.03))
    static func greeble(_ c: SIMD3<Float> = SIMD3(0.20, 0.21, 0.20)) -> PartMat { PartMat(kind: .greeble, col: c) }
    static let deathStar = PartMat(kind: .deathStar, col: SIMD3(0.50, 0.51, 0.53))
    static func membrane(_ c: SIMD3<Float>) -> PartMat { PartMat(kind: .membrane, col: c, emit: 1) }
}

/// A point of a ship that the front pass lights: engine halo, exhaust plume, navigation light.
struct ShipMarker {
    enum Kind { case engine, plume, nav }
    var kind: Kind
    var p: SIMD3<Float>
    var r: Float                         // halo radius, plume width (model units)
    var col: SIMD3<Float>? = nil         // nil: the object's glow colour
    var dir = SIMD3<Float>(-1, 0, 0)     // plume direction
    var len: Float = 0                   // plume length
}

/// Triangle mesh of a ship: four float4 per vertex (position + material, normal + windows, colour + emission,
/// texture coordinates + occlusion + packed finish). Imported models add parts with their own materials.
struct MeshData {
    static let stride = 4
    var v: [SIMD4<Float>] = []
    var idx: [UInt32] = []
    var markers: [ShipMarker] = []
    var parts: [MeshPart] = []           // empty: one part, the whole index list, built-in materials
    var materials: [ModelMaterial] = []
    var vertexCount: Int { v.count / MeshData.stride }
    var triangles: Int { idx.count / 3 }

    mutating func vertex(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ m: PartMat, uv: SIMD2<Float> = .zero) -> UInt32 {
        v.append(SIMD4(p, m.kind.rawValue))
        v.append(SIMD4(n, m.windows))
        v.append(SIMD4(m.col, m.emit))
        v.append(SIMD4(uv.x, uv.y, 1, m.finish))
        return UInt32(vertexCount - 1)
    }

    func position(_ i: Int) -> SIMD3<Float> { let p = v[i * MeshData.stride]; return SIMD3(p.x, p.y, p.z) }
    func normal(_ i: Int) -> SIMD3<Float> { let p = v[i * MeshData.stride + 1]; return SIMD3(p.x, p.y, p.z) }

    mutating func tri(_ a: UInt32, _ b: UInt32, _ c: UInt32) { idx += [a, b, c] }

    var bounds: (SIMD3<Float>, SIMD3<Float>) {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for i in Swift.stride(from: 0, to: v.count, by: MeshData.stride) {
            let p = SIMD3(v[i].x, v[i].y, v[i].z)
            lo = simd_min(lo, p); hi = simd_max(hi, p)
        }
        return (lo, hi)
    }

    /// Centres the mesh and scales it so its longest extent is 1. Returns the radius of the bounding sphere.
    @discardableResult mutating func normalise() -> Float {
        guard vertexCount > 0 else { return 0.5 }
        let (lo, hi) = bounds
        let c = (lo + hi) / 2
        let s = 1 / max(simd_reduce_max(hi - lo), 1e-6)
        var r: Float = 0
        for i in Swift.stride(from: 0, to: v.count, by: MeshData.stride) {
            let p = (SIMD3(v[i].x, v[i].y, v[i].z) - c) * s
            v[i] = SIMD4(p, v[i].w)
            r = max(r, simd_length(p))
        }
        for i in markers.indices {
            markers[i].p = (markers[i].p - c) * s
            markers[i].r *= s
            markers[i].len *= s
        }
        return r
    }

    /// Moves every vertex: used by the importer to turn models into the ship frame.
    mutating func transform(_ m: simd_float3x3) {
        let nm = m.inverse.transpose
        for i in Swift.stride(from: 0, to: v.count, by: MeshData.stride) {
            v[i] = SIMD4(m * SIMD3(v[i].x, v[i].y, v[i].z), v[i].w)
            v[i + 1] = SIMD4(simd_normalize(nm * SIMD3(v[i + 1].x, v[i + 1].y, v[i + 1].z)), v[i + 1].w)
        }
    }
}

/// A range of the index list drawn with one material of a model file.
struct MeshPart {
    var start: Int
    var count: Int
    var material: Int                    // -1: built-in materials in the vertices
    var blend = false                    // drawn after the opaque parts, with blending
}

/// A picture of a model file, decoded to RGBA8 and at most `ModelTexture.maxSide` pixels on its longer side.
final class ModelTexture {
    static let maxSide = 1024
    let width: Int, height: Int
    let rgba: Data
    init(width: Int, height: Int, rgba: Data) { self.width = width; self.height = height; self.rgba = rgba }
}

/// Material of a model file in the metallic-roughness model of glTF. Textures: base colour, metallic-roughness
/// (blue metal, green roughness), normal map, emission, occlusion (red).
struct ModelMaterial {
    var base = SIMD4<Float>(1, 1, 1, 1)
    var emissive = SIMD3<Float>(0, 0, 0)
    var metal: Float = 0.3
    var rough: Float = 0.5
    var normalScale: Float = 1
    var occlusion: Float = 1
    var alphaCutoff: Float = 0           // 0 opaque, > 0 cut below, < 0 blended
    var baseTex: ModelTexture? = nil
    var mrTex: ModelTexture? = nil
    var normalTex: ModelTexture? = nil
    var emissiveTex: ModelTexture? = nil
    var occlusionTex: ModelTexture? = nil
    var textures: [ModelTexture?] { [baseTex, mrTex, normalTex, emissiveTex, occlusionTex] }
}

extension MeshData {
    /// Built-in meshes: opaque triangles first, see-through membranes last, as two parts.
    mutating func splitTranslucent() {
        guard parts.isEmpty else { return }
        var solid: [UInt32] = [], clear: [UInt32] = []
        for t in Swift.stride(from: 0, to: idx.count - 2, by: 3) {
            let see = v[Int(idx[t]) * MeshData.stride].w == ShipMat.membrane.rawValue
            if see { clear += idx[t..<t + 3] } else { solid += idx[t..<t + 3] }
        }
        idx = solid + clear
        parts = [MeshPart(start: 0, count: solid.count, material: -1)]
        if !clear.isEmpty { parts.append(MeshPart(start: solid.count, count: clear.count, material: -1, blend: true)) }
    }

    /// File frame (y up) into the ship frame (x forward, z up): the longer of x and z becomes the length.
    /// Centres and scales the mesh as well.
    mutating func toShipFrame() {
        let (lo, hi) = bounds
        let e = hi - lo
        let toShip: simd_float3x3 = e.x >= e.z
            ? simd_float3x3(columns: (SIMD3(1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, -1, 0)))     // x stays, y -> z, z -> -y
            : simd_float3x3(columns: (SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(-1, 0, 0)))    // -z -> x (forward), y -> z
        transform(toShip)
        normalise()
    }

    /// Soft self-shadowing: how much of the sky each vertex sees. The mesh is drawn into a coarse voxel grid,
    /// and from each vertex a dozen rays look out over the hemisphere around its normal. Stored in the
    /// vertex (third component of the fourth float4). Run after `normalise`.
    mutating func bakeOcclusion(grid: Int = 56) {
        let n = vertexCount
        guard n > 0, idx.count >= 3 else { return }
        let (lo, hi) = bounds
        let size = max(simd_reduce_max(hi - lo), 1e-6)
        let vox = size / Float(grid - 4)
        let origin = lo - SIMD3(repeating: 2 * vox)
        let g = grid
        let dims = SIMD3<Int>(min(Int(((hi.x - origin.x) / vox).rounded(.up)) + 2, g), min(Int(((hi.y - origin.y) / vox).rounded(.up)) + 2, g),
                              min(Int(((hi.z - origin.z) / vox).rounded(.up)) + 2, g))
        var occ = [UInt8](repeating: 0, count: dims.x * dims.y * dims.z)
        func cell(_ p: SIMD3<Float>) -> Int? {
            let q = (p - origin) / vox
            let i = Int(q.x), j = Int(q.y), k = Int(q.z)
            guard q.x >= 0, q.y >= 0, q.z >= 0, i < dims.x, j < dims.y, k < dims.z else { return nil }
            return (k * dims.y + j) * dims.x + i
        }
        // Surfaces into the grid: points on each triangle, closer than half a voxel.
        let stride = MeshData.stride
        for t in Swift.stride(from: 0, to: idx.count - 2, by: 3) {
            let a = position(Int(idx[t])), b = position(Int(idx[t + 1])), c = position(Int(idx[t + 2]))
            // Glowing and see-through parts cast no shadow.
            let kind = v[Int(idx[t]) * stride].w
            if kind == ShipMat.membrane.rawValue || kind == ShipMat.glow.rawValue || kind == ShipMat.glowParam.rawValue { continue }
            let e = max(simd_length(b - a), simd_length(c - a), simd_length(c - b))
            let steps = min(max(Int((e / (vox * 0.5)).rounded(.up)), 1), 400)
            let inv = 1 / Float(steps)
            for i in 0...steps {
                for j in 0...(steps - i) {
                    let u = Float(i) * inv, w = Float(j) * inv
                    if let k = cell(a + (b - a) * u + (c - a) * w) { occ[k] = 1 }
                }
            }
        }
        // Hemisphere directions: a fixed spiral, cosine weighted towards the normal.
        let rays = 14
        let dirs: [SIMD3<Float>] = (0..<rays).map { i in
            let z = (Float(i) + 0.5) / Float(rays)
            let r = (1 - z).squareRoot()
            let a = Float(i) * 2.39996
            return SIMD3(r * cosf(a), r * sinf(a), z.squareRoot())
        }
        let reach = 14
        for vi in 0..<n {
            let p = position(vi)
            var nn = normal(vi)
            if simd_length(nn) < 1e-4 { nn = SIMD3(0, 0, 1) }
            nn = simd_normalize(nn)
            var t1 = simd_cross(nn, abs(nn.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0))
            t1 = simd_normalize(t1)
            let t2 = simd_cross(nn, t1)
            var seen: Float = 0
            for d in dirs {
                let dir = t1 * d.x + t2 * d.y + nn * d.z
                var vis: Float = 1
                // Start clear of the vertex's own surface; steps grow a little with distance.
                var s: Float = 1.6
                for k in 0..<reach {
                    guard let c = cell(p + dir * (s * vox)) else { break }
                    if occ[c] != 0 { vis = Float(k) / Float(reach) * 0.6; break }
                    s += 1 + Float(k) * 0.25
                }
                seen += vis
            }
            v[vi * stride + 3].z = seen / Float(rays)
        }
    }
}

/// Placement of a part: origin, rotation (degrees about x, then y, then z) and scale.
struct Xf {
    var m: simd_float3x3
    var o: SIMD3<Float>

    init(_ o: SIMD3<Float> = .zero, rot: SIMD3<Float> = .zero, scale: SIMD3<Float> = SIMD3(1, 1, 1)) {
        let r = rot * .pi / 180
        let rx = simd_float3x3(rows: [SIMD3(1, 0, 0), SIMD3(0, cosf(r.x), -sinf(r.x)), SIMD3(0, sinf(r.x), cosf(r.x))])
        let ry = simd_float3x3(rows: [SIMD3(cosf(r.y), 0, sinf(r.y)), SIMD3(0, 1, 0), SIMD3(-sinf(r.y), 0, cosf(r.y))])
        let rz = simd_float3x3(rows: [SIMD3(cosf(r.z), -sinf(r.z), 0), SIMD3(sinf(r.z), cosf(r.z), 0), SIMD3(0, 0, 1)])
        m = rz * ry * rx * simd_float3x3(diagonal: scale)
        self.o = o
    }

    init(m: simd_float3x3, o: SIMD3<Float>) { self.m = m; self.o = o }

    /// Local x runs from a to b; local y and z are scaled by sy and sz. `up` picks the roll.
    static func along(_ a: SIMD3<Float>, _ b: SIMD3<Float>, up: SIMD3<Float> = SIMD3(0, 0, 1), sy: Float = 1, sz: Float = 1) -> Xf {
        let d = b - a
        let len = max(simd_length(d), 1e-6)
        let x = d / len
        var y = simd_cross(up, x)
        if simd_length(y) < 1e-4 { y = simd_cross(SIMD3(0, 1, 0), x) }
        y = simd_normalize(y)
        let z = simd_cross(x, y)
        return Xf(m: simd_float3x3(columns: (x * len, y * sy, z * sz)), o: a)
    }

    func p(_ v: SIMD3<Float>) -> SIMD3<Float> { m * v + o }
    func n(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let k = m.inverse.transpose * v
        return simd_length(k) > 0 ? simd_normalize(k) : v
    }
}

/// Builds ship meshes from simple parts: box, frustum, lathe, ellipsoid, torus, prism.
struct MeshBuilder {
    var d = MeshData()

    // MARK: Parts in local coordinates, placed by Xf

    /// Unit box (-0.5...0.5) scaled by size.
    mutating func box(_ c: SIMD3<Float>, _ size: SIMD3<Float>, rot: SIMD3<Float> = .zero, _ m: PartMat) {
        let t = Xf(c, rot: rot, scale: size)
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)), (SIMD3(-1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 1, 0)),
            (SIMD3(0, 1, 0), SIMD3(0, 0, 1), SIMD3(1, 0, 0)), (SIMD3(0, -1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1)),
            (SIMD3(0, 0, 1), SIMD3(1, 0, 0), SIMD3(0, 1, 0)), (SIMD3(0, 0, -1), SIMD3(0, 1, 0), SIMD3(1, 0, 0)),
        ]
        for (n, u, w) in faces {
            let nn = t.n(n)
            let q = [n - u - w, n + u - w, n + u + w, n - u + w].map { t.p($0 * 0.5) }
            let i = q.map { d.vertex($0, nn, m) }
            d.tri(i[0], i[1], i[2]); d.tri(i[0], i[2], i[3])
        }
    }

    /// Beam from a to b: a box whose long side runs along the segment, `width` towards `up`, `thick` across.
    mutating func beam(_ a: SIMD3<Float>, _ b: SIMD3<Float>, width: Float, thick: Float, up: SIMD3<Float> = SIMD3(0, 0, 1), _ m: PartMat) {
        var t = Xf.along(a, b, up: up, sy: thick, sz: width)
        t.o = (a + b) / 2
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)), (SIMD3(-1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 1, 0)),
            (SIMD3(0, 1, 0), SIMD3(0, 0, 1), SIMD3(1, 0, 0)), (SIMD3(0, -1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1)),
            (SIMD3(0, 0, 1), SIMD3(1, 0, 0), SIMD3(0, 1, 0)), (SIMD3(0, 0, -1), SIMD3(0, 1, 0), SIMD3(1, 0, 0)),
        ]
        for (n, u, w) in faces {
            let nn = t.n(n)
            let q = [n - u - w, n + u - w, n + u + w, n - u + w].map { t.p($0 * 0.5) }
            let i = q.map { d.vertex($0, nn, m) }
            d.tri(i[0], i[1], i[2]); d.tri(i[0], i[2], i[3])
        }
    }

    /// Surface of revolution around local x: profile points (x, r). Ends with r = 0 close by themselves;
    /// open ends get a flat cap. `ry`, `rz` scale the cross-section (elliptical hulls).
    mutating func lathe(_ prof: [(Float, Float)], _ t: Xf, seg: Int = 32, caps: Bool = true, arc: ClosedRange<Float> = 0...360, _ m: PartMat) {
        guard prof.count >= 2 else { return }
        let n = prof.count
        // Profile normals from the neighbouring tangents (smooth); a corner stays sharp only when split by the caller.
        var pn: [SIMD2<Float>] = []
        for i in 0..<n {
            let a = prof[max(i - 1, 0)], b = prof[min(i + 1, n - 1)]
            let tx = b.0 - a.0, tr = b.1 - a.1
            var q = SIMD2<Float>(-tr, tx)
            if simd_length(q) < 1e-6 { q = SIMD2(0, 1) }
            pn.append(simd_normalize(q))
        }
        let full = arc.upperBound - arc.lowerBound >= 359.9
        let cols = full ? seg : seg + 1
        var rows: [[UInt32]] = []
        for i in 0..<n {
            var row: [UInt32] = []
            for j in 0..<cols {
                let a = (arc.lowerBound + (arc.upperBound - arc.lowerBound) * Float(j) / Float(seg)) * .pi / 180
                let c = cosf(a), s = sinf(a)
                let p = SIMD3(prof[i].0, prof[i].1 * c, prof[i].1 * s)
                let nl = SIMD3(pn[i].x, pn[i].y * c, pn[i].y * s)
                row.append(d.vertex(t.p(p), t.n(nl), m))
            }
            rows.append(row)
        }
        for i in 0..<(n - 1) {
            for j in 0..<seg {
                let j1 = full ? (j + 1) % seg : j + 1
                d.tri(rows[i][j], rows[i + 1][j], rows[i + 1][j1])
                d.tri(rows[i][j], rows[i + 1][j1], rows[i][j1])
            }
        }
        guard caps && full else { return }
        for (k, dir) in [(0, Float(-1)), (n - 1, Float(1))] where prof[k].1 > 1e-4 {
            let c = d.vertex(t.p(SIMD3(prof[k].0, 0, 0)), t.n(SIMD3(dir, 0, 0)), m)
            var ring: [UInt32] = []
            for j in 0..<seg {
                let a = Float(j) / Float(seg) * 2 * .pi
                ring.append(d.vertex(t.p(SIMD3(prof[k].0, prof[k].1 * cosf(a), prof[k].1 * sinf(a))), t.n(SIMD3(dir, 0, 0)), m))
            }
            for j in 0..<seg { d.tri(c, ring[j], ring[(j + 1) % seg]) }
        }
    }

    /// Frustum (cylinder when r0 == r1) from a to b.
    mutating func tube(_ a: SIMD3<Float>, _ b: SIMD3<Float>, r0: Float, r1: Float? = nil, seg: Int = 20, sy: Float = 1, sz: Float = 1,
                       up: SIMD3<Float> = SIMD3(0, 0, 1), _ m: PartMat) {
        let t = Xf.along(a, b, up: up, sy: sy, sz: sz)
        lathe([(0, r0), (1e-3, r0), (1, r1 ?? r0), (1 - 1e-3, r1 ?? r0)].sorted { $0.0 < $1.0 }, t, seg: seg, m)
    }

    /// Ellipsoid around c with radii r.
    mutating func ellipsoid(_ c: SIMD3<Float>, _ r: SIMD3<Float>, rot: SIMD3<Float> = .zero, seg: Int = 28, _ m: PartMat) {
        var prof: [(Float, Float)] = []
        let rings = max(seg / 2, 6)
        for i in 0...rings {
            let a = Float.pi * Float(i) / Float(rings)
            prof.append((-cosf(a), sinf(a)))
        }
        lathe(prof, Xf(c, rot: rot, scale: r), seg: seg, m)
    }

    /// Capsule from a to b with radius r.
    mutating func capsule(_ a: SIMD3<Float>, _ b: SIMD3<Float>, r: Float, seg: Int = 18, sy: Float = 1, sz: Float = 1, _ m: PartMat) {
        let len = simd_length(b - a)
        let k = r / max(len, 1e-6)
        var prof: [(Float, Float)] = []
        for i in 0...5 { let q = Float(i) / 5 * .pi / 2; prof.append((k - k * cosf(q), r * sinf(q))) }
        for i in 0...5 { let q = Float(i) / 5 * .pi / 2; prof.append((1 - k + k * sinf(q), r * cosf(q))) }
        lathe(prof.map { ($0.0 * (1 + 2 * k) - k, $0.1) }, Xf.along(a, b, sy: sy, sz: sz), seg: seg, m)
    }

    /// Torus around local z (major radius R, tube radius r), optionally only an arc (degrees).
    mutating func torus(_ t: Xf, R: Float, r: Float, arc: ClosedRange<Float> = 0...360, seg: Int = 48, side: Int = 12, rz: Float = 1, _ m: PartMat) {
        let full = arc.upperBound - arc.lowerBound >= 359.9
        let cols = full ? seg : seg + 1
        var rows: [[UInt32]] = []
        for j in 0..<cols {
            let a = (arc.lowerBound + (arc.upperBound - arc.lowerBound) * Float(j) / Float(seg)) * .pi / 180
            let dir = SIMD3(cosf(a), sinf(a), 0)
            var row: [UInt32] = []
            for k in 0..<side {
                let b = Float(k) / Float(side) * 2 * .pi
                let nl = dir * cosf(b) + SIMD3(0, 0, sinf(b) / max(rz, 1e-3))
                let p = dir * (R + r * cosf(b)) + SIMD3(0, 0, r * rz * sinf(b))
                row.append(d.vertex(t.p(p), t.n(simd_normalize(nl)), m))
            }
            rows.append(row)
        }
        for j in 0..<(cols - (full ? 0 : 1)) {
            let j1 = (j + 1) % cols
            for k in 0..<side {
                let k1 = (k + 1) % side
                d.tri(rows[j][k], rows[j1][k], rows[j1][k1])
                d.tri(rows[j][k], rows[j1][k1], rows[j][k1])
            }
        }
    }

    /// Prism from a 2D outline in local x-y, from z = -h/2 to +h/2. The top face is the outline scaled by
    /// `top` towards (0, 0) and the bottom one by `bottom`: sloped sides, wedges, pyramids.
    mutating func prism(_ outline: [SIMD2<Float>], h: Float, top: Float = 1, bottom: Float = 1, _ t: Xf, _ m: PartMat) {
        var pts = outline
        // Counter-clockwise.
        var area: Float = 0
        for i in 0..<pts.count { let a = pts[i], b = pts[(i + 1) % pts.count]; area += a.x * b.y - b.x * a.y }
        if area < 0 { pts.reverse() }
        let n = pts.count
        let lo = pts.map { SIMD3($0.x * bottom, $0.y * bottom, -h / 2) }
        let hi = pts.map { SIMD3($0.x * top, $0.y * top, h / 2) }
        for i in 0..<n {
            let j = (i + 1) % n
            let a = lo[i], b = lo[j], c = hi[j], e = hi[i]
            var nl = simd_cross(b - a, e - a)
            if simd_length(nl) < 1e-8 { nl = simd_cross(c - b, a - b) }
            let nn = t.n(simd_normalize(nl))
            let q = [a, b, c, e].map { d.vertex(t.p($0), nn, m) }
            d.tri(q[0], q[1], q[2]); d.tri(q[0], q[2], q[3])
        }
        let tris = MeshBuilder.triangulate(pts)
        let nt = t.n(SIMD3(0, 0, 1)), nb = t.n(SIMD3(0, 0, -1))
        let ti = hi.map { d.vertex(t.p($0), nt, m) }
        let bi = lo.map { d.vertex(t.p($0), nb, m) }
        for (a, b, c) in tris {
            d.tri(ti[a], ti[b], ti[c])
            d.tri(bi[a], bi[c], bi[b])
        }
    }

    /// Flat polygon disc (one-sided, both faces lit): solar wings, mirror segments, membranes.
    mutating func plate(_ outline: [SIMD2<Float>], _ t: Xf, _ m: PartMat) {
        let tris = MeshBuilder.triangulate(outline)
        let nn = t.n(SIMD3(0, 0, 1))
        let ids = outline.map { d.vertex(t.p(SIMD3($0.x, $0.y, 0)), nn, m) }
        for (a, b, c) in tris { d.tri(ids[a], ids[b], ids[c]) }
    }

    /// Regular polygon outline (hexagon: n = 6), radius r, first corner at angle a0 (degrees).
    static func ngon(_ n: Int, _ r: Float, a0: Float = 0) -> [SIMD2<Float>] {
        (0..<n).map { i in let a = (a0 + 360 * Float(i) / Float(n)) * .pi / 180; return SIMD2(cosf(a) * r, sinf(a) * r) }
    }

    /// Ellipse outline with n points.
    static func ellipse(_ rx: Float, _ ry: Float, n: Int = 40, cx: Float = 0) -> [SIMD2<Float>] {
        (0..<n).map { i in let a = 2 * Float.pi * Float(i) / Float(n); return SIMD2(cx + cosf(a) * rx, sinf(a) * ry) }
    }

    /// Ear clipping for a simple counter-clockwise polygon.
    static func triangulate(_ p: [SIMD2<Float>]) -> [(Int, Int, Int)] {
        var idx = Array(0..<p.count)
        var out: [(Int, Int, Int)] = []
        func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var guardN = 0
        while idx.count > 3 && guardN < 10000 {
            guardN += 1
            var cut = false
            for k in 0..<idx.count {
                let i0 = idx[(k + idx.count - 1) % idx.count], i1 = idx[k], i2 = idx[(k + 1) % idx.count]
                let a = p[i0], b = p[i1], c = p[i2]
                if cross(a, b, c) <= 1e-9 { continue }
                var inside = false
                for q in idx where q != i0 && q != i1 && q != i2 {
                    let x = p[q]
                    if cross(a, b, x) >= 0 && cross(b, c, x) >= 0 && cross(c, a, x) >= 0 { inside = true; break }
                }
                if inside { continue }
                out.append((i0, i1, i2))
                idx.remove(at: k)
                cut = true
                break
            }
            if !cut { break }
        }
        if idx.count == 3 { out.append((idx[0], idx[1], idx[2])) }
        return out
    }

    // MARK: Markers

    mutating func engine(_ p: SIMD3<Float>, r: Float, _ c: SIMD3<Float>? = nil) { d.markers.append(ShipMarker(kind: .engine, p: p, r: r, col: c)) }
    mutating func plume(_ p: SIMD3<Float>, r: Float, len: Float, dir: SIMD3<Float> = SIMD3(-1, 0, 0), _ c: SIMD3<Float>? = nil) {
        d.markers.append(ShipMarker(kind: .plume, p: p, r: r, col: c, dir: simd_normalize(dir), len: len))
    }
    mutating func nav(_ p: SIMD3<Float>, _ c: SIMD3<Float>) { d.markers.append(ShipMarker(kind: .nav, p: p, r: 0, col: c)) }

    // MARK: Symmetry

    /// Runs `build` twice, the second time mirrored at the x-z plane (port and starboard).
    mutating func mirrored(_ build: (inout MeshBuilder, Float) -> Void) {
        build(&self, 1)
        build(&self, -1)
    }
}

// MARK: - Import and export with ModelIO

enum ModelImport {
    static let warnTriangles = 200_000
    static let maxTriangles = 1_000_000
    static let fileTypes = ["obj", "usdz", "usd", "usda", "usdc", "ply", "stl", "gltf", "glb"]

    enum Failure: Error, CustomStringConvertible {
        case unreadable, empty, tooBig(Int), gltf(String)
        var description: String {
            switch self {
            case .unreadable: L("Die Datei lässt sich nicht lesen.")
            case .empty: L("In der Datei ist kein Modell.")
            case .tooBig(let n): L("Das Modell hat %d Dreiecke, höchstens %d gehen.", n, ModelImport.maxTriangles)
            case .gltf(let s): s
            }
        }
    }

    /// Reads a model file into the ship frame: centred, longest side 1, its longest horizontal axis along x,
    /// the file's y axis up. glTF goes through `GLTFLoader`, everything else through ModelIO. Materials: base
    /// colour, metallic, roughness and emission where the file has them, a base colour texture as well.
    static func load(_ url: URL) -> Result<MeshData, Failure> {
        if ["gltf", "glb"].contains(url.pathExtension.lowercased()) {
            switch GLTFLoader.load(url) {
            case .success(var d):
                if d.triangles > maxTriangles { return .failure(.tooBig(d.triangles)) }
                d.toShipFrame()
                return .success(d)
            case .failure(let e): return .failure(.gltf(e.description))
            }
        }
        let vd = MDLVertexDescriptor()
        vd.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        vd.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: 12, bufferIndex: 0)
        vd.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: 24, bufferIndex: 0)
        vd.layouts[0] = MDLVertexBufferLayout(stride: 32)
        let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: nil)
        asset.loadTextures()
        let meshes = asset.childObjects(of: MDLMesh.self).compactMap { $0 as? MDLMesh }
        guard !meshes.isEmpty else { return .failure(asset.count == 0 ? .unreadable : .empty) }
        var out = MeshData()
        var matIndex: [ObjectIdentifier: Int] = [:]
        for mesh in meshes {
            if mesh.vertexDescriptor.attributeNamed(MDLVertexAttributeNormal) == nil {
                mesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.6)
            }
            let hasUV = mesh.vertexDescriptor.attributeNamed(MDLVertexAttributeTextureCoordinate) != nil
            mesh.vertexDescriptor = vd
            let world = MDLTransform.globalTransform(with: mesh, atTime: 0)
            let m3 = simd_float3x3(SIMD3(world.columns.0.x, world.columns.0.y, world.columns.0.z),
                                   SIMD3(world.columns.1.x, world.columns.1.y, world.columns.1.z),
                                   SIMD3(world.columns.2.x, world.columns.2.y, world.columns.2.z))
            let off = SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
            let nm = m3.inverse.transpose
            guard let vb = mesh.vertexBuffers.first else { continue }
            let map = vb.map()
            let count = mesh.vertexCount
            let raw = map.bytes.bindMemory(to: Float.self, capacity: count * 8)
            let submeshes = (mesh.submeshes as? [MDLSubmesh]) ?? []
            for sub in submeshes where sub.geometryType == .triangles {
                // One material per MDLMaterial; parts with the same one share it.
                let mi: Int
                if let m = sub.material, let k = matIndex[ObjectIdentifier(m)] { mi = k } else {
                    out.materials.append(material(sub.material, uv: hasUV))
                    mi = out.materials.count - 1
                    if let m = sub.material { matIndex[ObjectIdentifier(m)] = mi }
                }
                let mat = PartMat(kind: .model, col: SIMD3(1, 1, 1))
                let start = out.idx.count
                var used: [Int: UInt32] = [:]
                let ib = sub.indexBuffer(asIndexType: .uInt32).map()
                let ip = ib.bytes.bindMemory(to: UInt32.self, capacity: sub.indexCount)
                for k in 0..<sub.indexCount {
                    let vi = Int(ip[k])
                    guard vi < count else { continue }
                    if let e = used[vi] { out.idx.append(e); continue }
                    let p = m3 * SIMD3(raw[vi * 8], raw[vi * 8 + 1], raw[vi * 8 + 2]) + off
                    var n = nm * SIMD3(raw[vi * 8 + 3], raw[vi * 8 + 4], raw[vi * 8 + 5])
                    n = simd_length(n) > 0 ? simd_normalize(n) : SIMD3(0, 1, 0)
                    // ModelIO keeps texture rows bottom up; the renderer samples top down like glTF.
                    let uv = SIMD2(raw[vi * 8 + 6], 1 - raw[vi * 8 + 7])
                    let id = out.vertex(p, n, mat, uv: uv)
                    used[vi] = id
                    out.idx.append(id)
                }
                out.idx.removeLast((out.idx.count - start) % 3)
                if out.idx.count > start { out.parts.append(MeshPart(start: start, count: out.idx.count - start, material: mi)) }
                if out.triangles > maxTriangles { return .failure(.tooBig(out.triangles)) }
            }
        }
        guard out.triangles > 0 else { return .failure(.empty) }
        out.toShipFrame()
        return .success(out)
    }

    /// Material of a ModelIO submesh: factors where given, the base colour texture if there is one.
    private static func material(_ m: MDLMaterial?, uv: Bool) -> ModelMaterial {
        var out = ModelMaterial()
        out.base = SIMD4(0.62, 0.63, 0.66, 1)
        guard let m else { return out }
        if let p = m.property(with: .baseColor) {
            switch p.type {
            case .float3: out.base = SIMD4(simd_clamp(p.float3Value, SIMD3(repeating: 0.03), SIMD3(repeating: 1)), 1)
            case .float4: out.base = SIMD4(simd_clamp(SIMD3(p.float4Value.x, p.float4Value.y, p.float4Value.z), SIMD3(repeating: 0.03), SIMD3(repeating: 1)), 1)
            case .texture:
                if uv, let img = p.textureSamplerValue?.texture?.imageFromTexture()?.takeUnretainedValue() {
                    out.baseTex = ModelImage.texture(img)
                    out.base = SIMD4(1, 1, 1, 1)
                }
            default: break
            }
        }
        if let p = m.property(with: .metallic), p.type == .float { out.metal = min(max(p.floatValue, 0), 1) }
        if let p = m.property(with: .roughness), p.type == .float { out.rough = min(max(p.floatValue, 0.02), 1) }
        if let p = m.property(with: .emission) {
            if p.type == .float3 { out.emissive = p.float3Value } else if p.type == .float4 { out.emissive = SIMD3(p.float4Value.x, p.float4Value.y, p.float4Value.z) }
        }
        return out
    }

    /// Writes a mesh as OBJ, USD (usda, usdc, usdz) or PLY through ModelIO. Used to test the importer.
    @discardableResult static func export(_ mesh: MeshData, to url: URL) -> Bool {
        let n = mesh.vertexCount
        var buf = [Float](repeating: 0, count: n * 6)
        // Back from the ship frame into a y-up file frame.
        for i in 0..<n {
            let p = mesh.v[i * MeshData.stride], q = mesh.v[i * MeshData.stride + 1]
            buf[i * 6] = p.x; buf[i * 6 + 1] = p.z; buf[i * 6 + 2] = -p.y
            buf[i * 6 + 3] = q.x; buf[i * 6 + 4] = q.z; buf[i * 6 + 5] = -q.y
        }
        let alloc = MDLMeshBufferDataAllocator()
        let vb = alloc.newBuffer(with: Data(bytes: buf, count: buf.count * 4), type: .vertex)
        let ib = alloc.newBuffer(with: Data(bytes: mesh.idx, count: mesh.idx.count * 4), type: .index)
        let vd = MDLVertexDescriptor()
        vd.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        vd.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: 12, bufferIndex: 0)
        vd.layouts[0] = MDLVertexBufferLayout(stride: 24)
        let mat = MDLMaterial(name: "hull", scatteringFunction: MDLPhysicallyPlausibleScatteringFunction())
        mat.setProperty(MDLMaterialProperty(name: "baseColor", semantic: .baseColor, float3: SIMD3(0.7, 0.7, 0.72)))
        let sub = MDLSubmesh(indexBuffer: ib, indexCount: mesh.idx.count, indexType: .uInt32, geometryType: .triangles, material: mat)
        let m = MDLMesh(vertexBuffer: vb, vertexCount: n, descriptor: vd, submeshes: [sub])
        m.name = "ship"
        let asset = MDLAsset()
        asset.add(m)
        guard MDLAsset.canExportFileExtension(url.pathExtension) else { return false }
        do { try asset.export(to: url) } catch { return false }
        return true
    }
}
