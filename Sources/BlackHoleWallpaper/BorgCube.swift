import simd

/// The Borg cube as real geometry: a glowing core inside a shell of machinery blocks.
///
/// Each face of the shell is cut by a seeded binary subdivision into panel blocks. Early cuts leave wide,
/// deep trenches, later ones narrow channels. Every leaf gets its own height: most sit near the outer plane,
/// some are sunk, a few stand proud, and some are missing so the core and its girders show through. Large
/// blocks carry a second, smaller layer of boxes and pipes. Blocks at the cube's edges are cut back at random,
/// so the silhouette and the corners break up. The channel floors and the foot of every wall glow green
/// (vertex emission, read by the greeble material); small green lights sit on the blocks.
/// Same seed, same mesh: the build is deterministic and cached by ShipCatalog like every ship.
extension MeshBuilder {
    /// One face of the cube: outward normal n and the two axes u, v across it.
    private struct BorgFace { let n, u, v: SIMD3<Float> }

    private static let borgHalf: Float = 2          // half the cube's edge
    private static let borgShell: Float = 0.34      // depth of the shell above the core
    private static var borgCore: Float { borgHalf - borgShell }

    mutating func borgCube(seed: UInt32 = 1701) {
        var rng = SeedRNG(seed)
        let C = MeshBuilder.borgCore
        // The core: dark machinery that glows where it shows between the blocks.
        var core = PartMat.greeble(SIMD3(0.10, 0.12, 0.11))
        core.emit = 0.6
        box(.zero, SIMD3(repeating: 2 * C), core)
        // Inner frame: girders along the core's edges and across its faces, seen through the trenches.
        let girder = PartMat.greeble(SIMD3(0.20, 0.21, 0.20))
        let faces: [BorgFace] = [
            BorgFace(n: SIMD3(1, 0, 0), u: SIMD3(0, 1, 0), v: SIMD3(0, 0, 1)),
            BorgFace(n: SIMD3(-1, 0, 0), u: SIMD3(0, 0, 1), v: SIMD3(0, 1, 0)),
            BorgFace(n: SIMD3(0, 1, 0), u: SIMD3(0, 0, 1), v: SIMD3(1, 0, 0)),
            BorgFace(n: SIMD3(0, -1, 0), u: SIMD3(1, 0, 0), v: SIMD3(0, 0, 1)),
            BorgFace(n: SIMD3(0, 0, 1), u: SIMD3(1, 0, 0), v: SIMD3(0, 1, 0)),
            BorgFace(n: SIMD3(0, 0, -1), u: SIMD3(0, 1, 0), v: SIMD3(1, 0, 0)),
        ]
        for f in faces {
            for k in [-1, 0, 1] as [Float] {
                let o = f.n * (C + 0.06)
                beam(o + f.v * (k * C * 0.62) - f.u * C, o + f.v * (k * C * 0.62) + f.u * C, width: 0.05, thick: 0.05, up: f.n, girder)
            }
        }
        for f in faces { borgFace(f, &rng) }
    }

    /// Splits one face into blocks: rects in face coordinates (u0, u1, v0, v1) with their cut depth on a stack.
    private mutating func borgFace(_ f: BorgFace, _ rng: inout SeedRNG) {
        let H = MeshBuilder.borgHalf
        var stack: [(SIMD4<Float>, Int)] = [(SIMD4(-H, H, -H, H), 0)]
        while let (r, k) = stack.popLast() {
            let w = r.y - r.x, h = r.w - r.z
            let minSide: Float = k < 2 ? 9 : 0.16 + 0.22 * rng.next()
            if k >= 8 || (max(w, h) < minSide && k >= 2) {
                borgLeaf(f, r, &rng)
                continue
            }
            // Cut across the longer side, off-centre; wide trenches first, narrow channels later.
            let alongU = w > h * (0.8 + 0.4 * rng.next())
            let gap: Float = k < 2 ? 0.075 : (k < 4 ? 0.04 : 0.022)
            let t = 0.3 + 0.4 * rng.next()
            if alongU {
                let s = r.x + w * t
                stack.append((SIMD4(r.x, s - gap / 2, r.z, r.w), k + 1))
                stack.append((SIMD4(s + gap / 2, r.y, r.z, r.w), k + 1))
            } else {
                let s = r.z + h * t
                stack.append((SIMD4(r.x, r.y, r.z, s - gap / 2), k + 1))
                stack.append((SIMD4(r.x, r.y, s + gap / 2, r.w), k + 1))
            }
        }
    }

    /// One panel: a block of its own height, sometimes missing, with smaller boxes, pipes and lights on top.
    private mutating func borgLeaf(_ f: BorgFace, _ r0: SIMD4<Float>, _ rng: inout SeedRNG) {
        let C = MeshBuilder.borgCore, T = MeshBuilder.borgShell
        var r = r0
        // Blocks reaching past the core's edge belong to the cube's edge: cut back at random so the edge is ragged.
        let edgeU = r.x < -C || r.y > C, edgeV = r.z < -C || r.w > C
        if r.x < -C + 0.01 { r.x += rng.next() * 0.16 }
        if r.y > C - 0.01 { r.y -= rng.next() * 0.16 }
        if r.z < -C + 0.01 { r.z += rng.next() * 0.16 }
        if r.w > C - 0.01 { r.w -= rng.next() * 0.16 }
        guard r.y - r.x > 0.03, r.w - r.z > 0.03 else { return }
        let corner = edgeU && edgeV
        let roll = rng.next()
        var top: Float
        if corner && roll < 0.35 || (edgeU || edgeV) && roll < 0.12 {
            top = T * (0.15 + 0.4 * rng.next())                 // a chunk broken out of the edge
        } else if roll < 0.07 {
            borgOpen(f, r, &rng)                                // missing: the core and its frame show
            return
        } else if roll < 0.24 {
            top = T * (0.4 + 0.3 * rng.next())                  // sunk
        } else if roll < 0.34 {
            top = T + 0.03 + 0.06 * rng.next()                  // standing proud
        } else {
            top = T - 0.05 + 0.08 * rng.next()                  // on the outer plane
        }
        // Edge blocks may not stick out past the cube: keep the silhouette square on the whole.
        if edgeU || edgeV { top = min(top, T + 0.02) }
        let tone = 0.10 + 0.09 * rng.next()
        let tint = SIMD3<Float>(tone, tone * (1.02 + 0.06 * rng.next()), tone * (0.95 + 0.06 * rng.next()))
        borgBlock(f, r, 0, top, PartMat.greeble(tint))
        borgDetail(f, r, top, &rng)
    }

    /// Smaller boxes, pipes and lights on top of a block.
    private mutating func borgDetail(_ f: BorgFace, _ r: SIMD4<Float>, _ top: Float, _ rng: inout SeedRNG) {
        let w = r.y - r.x, h = r.w - r.z
        let area = w * h
        let dark = PartMat.greeble(SIMD3(0.11, 0.12, 0.115))
        let mid = PartMat.greeble(SIMD3(0.22, 0.23, 0.22))
        if area > 0.025 {
            // Pipes along the longer side.
            let pipes = rng.next() < 0.45 ? 1 + Int(rng.next() * 3) : 0
            for _ in 0..<pipes {
                let d: Float = 0.018 + 0.02 * rng.next()
                if w >= h {
                    let v = r.z + d + (h - 2 * d) * rng.next()
                    borgBlock(f, SIMD4(r.x + 0.01, r.y - 0.01, v - d / 2, v + d / 2), top, top + d, mid)
                } else {
                    let u = r.x + d + (w - 2 * d) * rng.next()
                    borgBlock(f, SIMD4(u - d / 2, u + d / 2, r.z + 0.01, r.w - 0.01), top, top + d, mid)
                }
            }
            // Boxes, more on bigger blocks.
            let boxes = min(Int(area * 24 * rng.next()) + (rng.next() < 0.5 ? 1 : 0), 7)
            for _ in 0..<boxes {
                let bw = min(0.03 + 0.14 * rng.next() * rng.next() * 2, w * 0.7)
                let bh = min(0.03 + 0.14 * rng.next() * rng.next() * 2, h * 0.7)
                let u = r.x + bw / 2 + (w - bw) * rng.next(), v = r.z + bh / 2 + (h - bh) * rng.next()
                let up: Float = rng.next() < 0.3 ? -0.025 : 0.015 + 0.05 * rng.next()
                if up < 0 {
                    // A recess: a dark box sunk into the block, its rim shows as a hole.
                    borgBlock(f, SIMD4(u - bw / 2, u + bw / 2, v - bh / 2, v + bh / 2), top + up, top + 0.004, dark)
                } else {
                    borgBlock(f, SIMD4(u - bw / 2, u + bw / 2, v - bh / 2, v + bh / 2), top, top + up, rng.next() < 0.5 ? dark : mid)
                }
            }
        }
        // Lights: a few small green points, more on bigger blocks.
        let lights = area > 0.012 && rng.next() < 0.4 ? 1 + Int(rng.next() * min(area * 20, 2)) : 0
        for _ in 0..<lights {
            let s: Float = 0.022 + 0.02 * rng.next()
            let u = r.x + s + (w - 2 * s) * rng.next(), v = r.z + s + (h - 2 * s) * rng.next()
            borgBlock(f, SIMD4(u - s / 2, u + s / 2, v - s / 2, v + s / 2), top, top + 0.012, PartMat.engine())
        }
    }

    /// A missing panel: the core shows, crossed by a girder or two, with a few boxes on its floor.
    private mutating func borgOpen(_ f: BorgFace, _ r: SIMD4<Float>, _ rng: inout SeedRNG) {
        let T = MeshBuilder.borgShell
        let frame = PartMat.greeble(SIMD3(0.19, 0.20, 0.19))
        let n = 1 + Int(rng.next() * 2)
        for i in 0..<n {
            let d: Float = 0.035
            let depth = T * (0.35 + 0.35 * rng.next())
            if (i + Int(rng.next() * 2)) % 2 == 0 {
                let v = r.z + (r.w - r.z) * (0.25 + 0.5 * rng.next())
                borgBlock(f, SIMD4(r.x, r.y, v - d / 2, v + d / 2), depth - d, depth, frame)
            } else {
                let u = r.x + (r.y - r.x) * (0.25 + 0.5 * rng.next())
                borgBlock(f, SIMD4(u - d / 2, u + d / 2, r.z, r.w), depth - d, depth, frame)
            }
        }
        let boxes = 2 + Int(rng.next() * 3)
        for _ in 0..<boxes {
            let s: Float = 0.04 + 0.08 * rng.next()
            let u = r.x + (r.y - r.x) * rng.next(), v = r.z + (r.w - r.z) * rng.next()
            let ru = SIMD4(max(u - s / 2, r.x), min(u + s / 2, r.y), max(v - s / 2, r.z), min(v + s / 2, r.w))
            borgBlock(f, ru, 0, T * (0.1 + 0.25 * rng.next()), PartMat.greeble(SIMD3(0.14, 0.15, 0.14)))
        }
    }

    /// A box standing on the face: rect r in face coordinates, from height lo to hi above the core.
    /// Top and four walls, no floor. Walls glow green at their foot, fading with the height above the core.
    private mutating func borgBlock(_ f: BorgFace, _ r: SIMD4<Float>, _ lo: Float, _ hi: Float, _ m: PartMat) {
        let C = MeshBuilder.borgCore
        func p(_ u: Float, _ v: Float, _ z: Float) -> SIMD3<Float> { f.n * (C + z) + f.u * u + f.v * v }
        func mat(_ z: Float) -> PartMat {
            guard m.kind == .greeble else { return m }
            var q = m
            q.emit = max(m.emit, 0.9 * expf(-z / 0.07))
            return q
        }
        func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, _ n: SIMD3<Float>, _ za: Float, _ zb: Float) {
            let i0 = self.d.vertex(a, n, mat(za)), i1 = self.d.vertex(b, n, mat(za))
            let i2 = self.d.vertex(c, n, mat(zb)), i3 = self.d.vertex(d, n, mat(zb))
            self.d.tri(i0, i1, i2); self.d.tri(i0, i2, i3)
        }
        let (u0, u1, v0, v1) = (r.x, r.y, r.z, r.w)
        quad(p(u0, v0, hi), p(u1, v0, hi), p(u1, v1, hi), p(u0, v1, hi), f.n, hi, hi)
        quad(p(u0, v0, lo), p(u1, v0, lo), p(u1, v0, hi), p(u0, v0, hi), -f.v, lo, hi)
        quad(p(u1, v1, lo), p(u0, v1, lo), p(u0, v1, hi), p(u1, v1, hi), f.v, lo, hi)
        quad(p(u0, v1, lo), p(u0, v0, lo), p(u0, v0, hi), p(u0, v1, hi), -f.u, lo, hi)
        quad(p(u1, v0, lo), p(u1, v1, lo), p(u1, v1, hi), p(u1, v0, hi), f.u, lo, hi)
    }
}
