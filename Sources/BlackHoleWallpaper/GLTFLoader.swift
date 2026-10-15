import Foundation
import simd

/// A small glTF 2.0 reader: `.gltf` with external or embedded buffers and pictures, and `.glb`. Reads the
/// node tree with its transforms, meshes with several primitives, indices, normals (computed when missing),
/// the first set of texture coordinates, vertex colours and the metallic-roughness materials. No animation,
/// skins, morph targets, cameras, lights or compression; a model that requires an extension it cannot read
/// is refused with a message.
enum GLTFLoader {
    struct LoadError: Error, CustomStringConvertible {
        let description: String
        init(_ s: String) { description = s }
    }

    /// Extensions whose absence changes nothing essential; a file may require them.
    static let understood: Set<String> = ["KHR_materials_emissive_strength", "KHR_materials_ior", "KHR_materials_specular"]

    typealias JSON = [String: Any]

    static func load(_ url: URL) -> Result<MeshData, LoadError> {
        do { return .success(try read(url)) } catch let e as LoadError { return .failure(e) } catch { return .failure(LoadError(UIText.gltfUnreadable)) }
    }

    /// Files next to a `.gltf` that belong to it (buffers and pictures by relative path), for copying.
    static func externalFiles(_ url: URL) -> [String] {
        guard url.pathExtension.lowercased() == "gltf", let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? JSON else { return [] }
        let uris = ((json["buffers"] as? [JSON]) ?? []).compactMap { $0["uri"] as? String }
                 + ((json["images"] as? [JSON]) ?? []).compactMap { $0["uri"] as? String }
        return uris.filter { !$0.hasPrefix("data:") }.compactMap { $0.removingPercentEncoding }
    }

    // MARK: - Container

    private static func read(_ url: URL) throws -> MeshData {
        guard let data = try? Data(contentsOf: url) else { throw LoadError(UIText.gltfUnreadable) }
        var jsonData = data
        var bin: Data?
        // GLB: 12-byte header, then chunks (JSON first, then an optional binary one).
        if data.count >= 12, data.prefix(4) == Data("glTF".utf8) {
            func u32(_ o: Int) -> Int { Int(data.subdata(in: o..<o + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian) }
            guard u32(4) == 2 else { throw LoadError(UIText.gltfVersion(String(u32(4)))) }
            let total = min(u32(8), data.count)
            var o = 12
            var json: Data?
            while o + 8 <= total {
                let len = u32(o), type = u32(o + 4)
                let start = o + 8, end = min(start + len, total)
                if type == 0x4E4F_534A { json = data.subdata(in: start..<end) }      // "JSON"
                else if type == 0x004E_4942 && bin == nil { bin = data.subdata(in: start..<end) }   // "BIN"
                o = start + ((len + 3) & ~3)
            }
            guard let json else { throw LoadError(UIText.gltfUnreadable) }
            jsonData = json
        }
        let root: JSON
        do {
            guard let r = try JSONSerialization.jsonObject(with: jsonData) as? JSON else { throw LoadError(UIText.gltfBadJSON(L("kein Objekt"))) }
            root = r
        } catch let e as LoadError { throw e } catch { throw LoadError(UIText.gltfBadJSON(error.localizedDescription)) }
        if let v = (root["asset"] as? JSON)?["version"] as? String, !v.hasPrefix("2") { throw LoadError(UIText.gltfVersion(v)) }
        let required = (root["extensionsRequired"] as? [String]) ?? []
        let missing = required.filter { !understood.contains($0) }
        if !missing.isEmpty { throw LoadError(UIText.gltfExtension(missing)) }
        var doc = Doc(root: root, dir: url.deletingLastPathComponent(), bin: bin)
        return try doc.build()
    }

    // MARK: - Document

    private struct Doc {
        let root: JSON
        let dir: URL
        let bin: Data?
        var buffers: [Int: Data] = [:]
        var images: [Int: ModelTexture?] = [:]

        init(root: JSON, dir: URL, bin: Data?) { self.root = root; self.dir = dir; self.bin = bin }

        func list(_ k: String) -> [JSON] { (root[k] as? [JSON]) ?? [] }

        static func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
        static func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }
        static func floats(_ v: Any?) -> [Float]? { (v as? [Any])?.compactMap { num($0).map(Float.init) } }

        /// The bytes behind a `uri`: a data URI or a file next to the model.
        func resolve(_ uri: String) throws -> Data {
            if uri.hasPrefix("data:") {
                guard let comma = uri.firstIndex(of: ","), uri[..<comma].hasSuffix(";base64"),
                      let d = Data(base64Encoded: String(uri[uri.index(after: comma)...])) else { throw LoadError(UIText.gltfUnreadable) }
                return d
            }
            let name = uri.removingPercentEncoding ?? uri
            guard let d = try? Data(contentsOf: dir.appendingPathComponent(name)) else { throw LoadError(UIText.gltfMissingBuffer(name)) }
            return d
        }

        mutating func buffer(_ i: Int) throws -> Data {
            if let b = buffers[i] { return b }
            let bs = list("buffers")
            guard i < bs.count else { throw LoadError(UIText.gltfBrokenData) }
            let d: Data
            if let uri = bs[i]["uri"] as? String { d = try resolve(uri) } else if let bin { d = bin } else { throw LoadError(UIText.gltfBrokenData) }
            buffers[i] = d
            return d
        }

        /// Bytes of a buffer view and its stride (0: packed).
        mutating func view(_ i: Int) throws -> (Data, Int) {
            let vs = list("bufferViews")
            guard i < vs.count, let b = Doc.int(vs[i]["buffer"]) else { throw LoadError(UIText.gltfBrokenData) }
            let buf = try buffer(b)
            let off = Doc.int(vs[i]["byteOffset"]) ?? 0, len = Doc.int(vs[i]["byteLength"]) ?? 0
            guard off >= 0, len >= 0, off + len <= buf.count else { throw LoadError(UIText.gltfBrokenData) }
            return (buf.subdata(in: off..<off + len), Doc.int(vs[i]["byteStride"]) ?? 0)
        }

        /// An accessor as floats, `comps` per element; normalised integers are scaled to 0...1 or -1...1.
        mutating func floats(_ a: Int) throws -> (values: [Float], comps: Int) {
            let acc = list("accessors")
            guard a < acc.count, let count = Doc.int(acc[a]["count"]), let ct = Doc.int(acc[a]["componentType"]),
                  let type = acc[a]["type"] as? String else { throw LoadError(UIText.gltfBrokenData) }
            let comps = ["SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16][type] ?? 1
            let size = [5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4][ct] ?? 4
            let norm = (acc[a]["normalized"] as? Bool) ?? false
            var out = [Float](repeating: 0, count: count * comps)
            guard let vi = Doc.int(acc[a]["bufferView"]) else { return (out, comps) }    // all zero
            let (d, stride0) = try view(vi)
            let off = Doc.int(acc[a]["byteOffset"]) ?? 0
            let stride = stride0 > 0 ? stride0 : size * comps
            guard count == 0 || off + (count - 1) * stride + size * comps <= d.count else { throw LoadError(UIText.gltfBrokenData) }
            d.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                for e in 0..<count {
                    for c in 0..<comps {
                        let o = off + e * stride + c * size
                        let v: Float
                        switch ct {
                        case 5126: v = raw.loadUnaligned(fromByteOffset: o, as: Float.self)
                        case 5121: let x = raw.loadUnaligned(fromByteOffset: o, as: UInt8.self); v = norm ? Float(x) / 255 : Float(x)
                        case 5120: let x = raw.loadUnaligned(fromByteOffset: o, as: Int8.self); v = norm ? max(Float(x) / 127, -1) : Float(x)
                        case 5123: let x = raw.loadUnaligned(fromByteOffset: o, as: UInt16.self); v = norm ? Float(x) / 65535 : Float(x)
                        case 5122: let x = raw.loadUnaligned(fromByteOffset: o, as: Int16.self); v = norm ? max(Float(x) / 32767, -1) : Float(x)
                        default: v = Float(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self))
                        }
                        out[e * comps + c] = v
                    }
                }
            }
            return (out, comps)
        }

        mutating func indices(_ a: Int) throws -> [UInt32] {
            let acc = list("accessors")
            guard a < acc.count, let count = Doc.int(acc[a]["count"]), let ct = Doc.int(acc[a]["componentType"]) else { throw LoadError(UIText.gltfBrokenData) }
            guard let vi = Doc.int(acc[a]["bufferView"]) else { return [UInt32](repeating: 0, count: count) }
            let (d, _) = try view(vi)
            let off = Doc.int(acc[a]["byteOffset"]) ?? 0
            let size = ct == 5125 ? 4 : ct == 5123 ? 2 : 1
            guard off + count * size <= d.count else { throw LoadError(UIText.gltfBrokenData) }
            return d.withUnsafeBytes { raw in
                (0..<count).map { e -> UInt32 in
                    let o = off + e * size
                    switch size {
                    case 4: return raw.loadUnaligned(fromByteOffset: o, as: UInt32.self)
                    case 2: return UInt32(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self))
                    default: return UInt32(raw.loadUnaligned(fromByteOffset: o, as: UInt8.self))
                    }
                }
            }
        }

        /// The picture of a texture, decoded once; nil when it cannot be read (the material then goes without).
        /// Base colour and normal maps keep up to 1024 px; the others (metal, roughness, occlusion, glow) are
        /// smooth enough for 512.
        mutating func texture(_ info: Any?, fine: Bool = true) -> ModelTexture? {
            guard let ti = info as? JSON, let t = Doc.int(ti["index"]) else { return nil }
            let ts = list("textures")
            guard t < ts.count, let src = Doc.int(ts[t]["source"]) else { return nil }
            if let cached = images[src] { return cached }
            let side = fine ? ModelTexture.maxSide : ModelTexture.maxSide / 2
            let ims = list("images")
            var tex: ModelTexture?
            if src < ims.count {
                if let uri = ims[src]["uri"] as? String, let d = try? resolve(uri) { tex = ModelImage.texture(data: d, maxSide: side) }
                else if let v = Doc.int(ims[src]["bufferView"]), let r = try? view(v) { tex = ModelImage.texture(data: r.0, maxSide: side) }
            }
            images[src] = tex
            return tex
        }

        mutating func material(_ i: Int?) -> ModelMaterial {
            var m = ModelMaterial()
            m.metal = 1; m.rough = 1
            let ms = list("materials")
            guard let i, i < ms.count else {
                // No material: glTF's default is a plain white, fully rough metal; a light grey satin reads better.
                m.base = SIMD4(0.75, 0.75, 0.77, 1); m.metal = 0.2; m.rough = 0.5
                return m
            }
            let j = ms[i]
            let pbr = (j["pbrMetallicRoughness"] as? JSON) ?? [:]
            if let f = Doc.floats(pbr["baseColorFactor"]), f.count == 4 { m.base = SIMD4(f[0], f[1], f[2], f[3]) }
            if let v = Doc.num(pbr["metallicFactor"]) { m.metal = Float(v) }
            if let v = Doc.num(pbr["roughnessFactor"]) { m.rough = Float(v) }
            m.baseTex = texture(pbr["baseColorTexture"])
            m.mrTex = texture(pbr["metallicRoughnessTexture"], fine: false)
            m.normalTex = texture(j["normalTexture"])
            if let s = Doc.num((j["normalTexture"] as? JSON)?["scale"]) { m.normalScale = Float(s) }
            m.occlusionTex = texture(j["occlusionTexture"], fine: false)
            if let s = Doc.num((j["occlusionTexture"] as? JSON)?["strength"]) { m.occlusion = Float(s) }
            m.emissiveTex = texture(j["emissiveTexture"], fine: false)
            if let f = Doc.floats(j["emissiveFactor"]), f.count == 3 { m.emissive = SIMD3(f[0], f[1], f[2]) }
            if let ext = (j["extensions"] as? JSON)?["KHR_materials_emissive_strength"] as? JSON, let s = Doc.num(ext["emissiveStrength"]) {
                m.emissive *= Float(s)
            }
            switch j["alphaMode"] as? String {
            case "MASK": m.alphaCutoff = Float(Doc.num(j["alphaCutoff"]) ?? 0.5)
            case "BLEND": m.alphaCutoff = -1
            default: m.alphaCutoff = 0
            }
            m.rough = min(max(m.rough, 0.02), 1)
            m.metal = min(max(m.metal, 0), 1)
            return m
        }

        // MARK: Scene

        static func matrix(_ n: JSON) -> simd_float4x4 {
            if let m = floats(n["matrix"]), m.count == 16 {
                return simd_float4x4(columns: (SIMD4(m[0], m[1], m[2], m[3]), SIMD4(m[4], m[5], m[6], m[7]),
                                               SIMD4(m[8], m[9], m[10], m[11]), SIMD4(m[12], m[13], m[14], m[15])))
            }
            var t = matrix_identity_float4x4
            if let s = floats(n["scale"]), s.count == 3 { t = simd_float4x4(diagonal: SIMD4(s[0], s[1], s[2], 1)) }
            if let q = floats(n["rotation"]), q.count == 4 {
                let r = simd_float4x4(simd_quatf(ix: q[0], iy: q[1], iz: q[2], r: q[3]).normalized)
                t = r * t
            }
            if let p = floats(n["translation"]), p.count == 3 {
                var m = matrix_identity_float4x4
                m.columns.3 = SIMD4(p[0], p[1], p[2], 1)
                t = m * t
            }
            return t
        }

        mutating func build() throws -> MeshData {
            var out = MeshData()
            var matIndex: [Int: Int] = [:]
            let nodes = list("nodes")
            // Roots: the default scene's nodes, else every node that is nobody's child.
            var roots: [Int] = []
            let scenes = list("scenes")
            if !scenes.isEmpty {
                let s = Doc.int(root["scene"]) ?? 0
                roots = ((scenes[min(max(s, 0), scenes.count - 1)]["nodes"] as? [Any]) ?? []).compactMap(Doc.int)
            }
            if roots.isEmpty {
                let children = Set(nodes.flatMap { ($0["children"] as? [Any] ?? []).compactMap(Doc.int) })
                roots = nodes.indices.filter { !children.contains($0) }
            }
            var stack: [(Int, simd_float4x4, Int)] = roots.map { ($0, matrix_identity_float4x4, 0) }
            var meshesDrawn = 0
            while let (ni, parent, depth) = stack.popLast() {
                guard ni >= 0, ni < nodes.count, depth < 64 else { continue }
                let n = nodes[ni]
                let world = parent * Doc.matrix(n)
                if let mi = Doc.int(n["mesh"]) {
                    try addMesh(mi, world, &out, &matIndex)
                    meshesDrawn += 1
                }
                for c in ((n["children"] as? [Any]) ?? []).compactMap(Doc.int) { stack.append((c, world, depth + 1)) }
                if out.triangles > ModelImport.maxTriangles { break }
            }
            // No nodes at all: every mesh as it is.
            if meshesDrawn == 0 { for mi in list("meshes").indices { try addMesh(mi, matrix_identity_float4x4, &out, &matIndex) } }
            guard out.triangles > 0 else { throw LoadError(UIText.gltfNoTriangles) }
            return out
        }

        mutating func addMesh(_ mi: Int, _ world: simd_float4x4, _ out: inout MeshData, _ matIndex: inout [Int: Int]) throws {
            let meshes = list("meshes")
            guard mi < meshes.count else { throw LoadError(UIText.gltfBrokenData) }
            let m3 = simd_float3x3(SIMD3(world.columns.0.x, world.columns.0.y, world.columns.0.z),
                                   SIMD3(world.columns.1.x, world.columns.1.y, world.columns.1.z),
                                   SIMD3(world.columns.2.x, world.columns.2.y, world.columns.2.z))
            let nm = m3.inverse.transpose
            for prim in (meshes[mi]["primitives"] as? [JSON]) ?? [] {
                let mode = Doc.int(prim["mode"]) ?? 4
                guard [4, 5, 6].contains(mode), let attr = prim["attributes"] as? JSON, let pa = Doc.int(attr["POSITION"]) else { continue }
                let (pos, pc) = try floats(pa)
                guard pc == 3 else { continue }
                let n = pos.count / 3
                var idx: [UInt32]
                if let ia = Doc.int(prim["indices"]) { idx = try indices(ia) } else { idx = (0..<UInt32(n)).map { $0 } }
                idx = idx.filter { Int($0) < n }
                // Strips and fans into a plain triangle list.
                if mode == 5 {
                    var t: [UInt32] = []
                    if idx.count >= 3 { for k in 0..<(idx.count - 2) { t += k % 2 == 0 ? [idx[k], idx[k + 1], idx[k + 2]] : [idx[k + 1], idx[k], idx[k + 2]] } }
                    idx = t
                } else if mode == 6 {
                    var t: [UInt32] = []
                    if idx.count >= 3 { for k in 1..<(idx.count - 1) { t += [idx[0], idx[k], idx[k + 1]] } }
                    idx = t
                }
                idx.removeLast(idx.count % 3)
                guard !idx.isEmpty else { continue }
                var normals: [Float] = []
                if let na = Doc.int(attr["NORMAL"]) { let r = try floats(na); if r.comps == 3 && r.values.count == pos.count { normals = r.values } }
                if normals.isEmpty { normals = Doc.smoothNormals(pos, idx) }
                var uv: [Float] = []
                if let ta = Doc.int(attr["TEXCOORD_0"]) { let r = try floats(ta); if r.comps == 2 && r.values.count == n * 2 { uv = r.values } }
                var col: [Float] = [], cc = 0
                if let ca = Doc.int(attr["COLOR_0"]) { let r = try floats(ca); if r.values.count == n * r.comps && r.comps >= 3 { col = r.values; cc = r.comps } }
                // Material, shared by all primitives that use it.
                let key = Doc.int(prim["material"]) ?? -1
                let matI: Int
                if let k = matIndex[key] { matI = k } else {
                    out.materials.append(material(key >= 0 ? key : nil))
                    matI = out.materials.count - 1
                    matIndex[key] = matI
                }
                let base = UInt32(out.vertexCount)
                for v in 0..<n {
                    let p = SIMD3(pos[v * 3], pos[v * 3 + 1], pos[v * 3 + 2])
                    let wp = m3 * p + SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
                    var nn = nm * SIMD3(normals[v * 3], normals[v * 3 + 1], normals[v * 3 + 2])
                    nn = simd_length(nn) > 1e-8 ? simd_normalize(nn) : SIMD3(0, 1, 0)
                    var pm = PartMat(kind: .model, col: SIMD3(1, 1, 1))
                    if cc >= 3 { pm.col = SIMD3(col[v * cc], col[v * cc + 1], col[v * cc + 2]) }
                    _ = out.vertex(wp, nn, pm, uv: uv.isEmpty ? .zero : SIMD2(uv[v * 2], uv[v * 2 + 1]))
                }
                let start = out.idx.count
                // A mirroring transform turns the winding; keep it consistent (culling is off, but normals agree).
                let flip = simd_determinant(m3) < 0
                for t in stride(from: 0, to: idx.count, by: 3) {
                    if flip { out.idx += [base + idx[t], base + idx[t + 2], base + idx[t + 1]] }
                    else { out.idx += [base + idx[t], base + idx[t + 1], base + idx[t + 2]] }
                }
                out.parts.append(MeshPart(start: start, count: idx.count, material: matI, blend: out.materials[matI].alphaCutoff != 0))
                if out.triangles > ModelImport.maxTriangles { return }
            }
        }

        /// Area-weighted vertex normals for primitives without them.
        static func smoothNormals(_ pos: [Float], _ idx: [UInt32]) -> [Float] {
            var acc = [SIMD3<Float>](repeating: .zero, count: pos.count / 3)
            func p(_ i: UInt32) -> SIMD3<Float> { let k = Int(i) * 3; return SIMD3(pos[k], pos[k + 1], pos[k + 2]) }
            for t in stride(from: 0, to: idx.count - 2, by: 3) {
                let a = idx[t], b = idx[t + 1], c = idx[t + 2]
                let fn = simd_cross(p(b) - p(a), p(c) - p(a))
                acc[Int(a)] += fn; acc[Int(b)] += fn; acc[Int(c)] += fn
            }
            return acc.flatMap { v -> [Float] in let n = simd_length(v) > 1e-12 ? simd_normalize(v) : SIMD3(0, 1, 0); return [n.x, n.y, n.z] }
        }
    }
}
