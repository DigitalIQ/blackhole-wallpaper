import AppKit
import CoreGraphics
import CoreText
import QuartzCore
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

/// Offscreen rendering to PNG. Used for look reviews now and for the lock-screen still later.
///
///   BlackHoleWallpaper --snapshot out.png --size 3440x1440 --top 24 --bottom 70 --hole 0.5,0.5 --time 20
enum Snapshot {
    static func run(_ args: [String]) -> Int32 {
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let i = args.firstIndex(of: "--diff"), i + 2 < args.count {
            return diff(args[i + 1], args[i + 2], tolerance: Int(value("--tol") ?? "1") ?? 1)
        }
        // --export-ship enterprise datei.obj|usda|usdc|usdz|ply: a ship from the building blocks as a model file.
        if let i = args.firstIndex(of: "--export-ship"), i + 2 < args.count {
            guard let mesh = ShipCatalog.build(args[i + 1]) else { FileHandle.standardError.write("unknown ship\n".data(using: .utf8)!); return 2 }
            let ok = ModelImport.export(mesh, to: URL(fileURLWithPath: args[i + 2]))
            print(ok ? "\(args[i + 2]): \(mesh.triangles) Dreiecke" : "Export nach \(args[i + 2]) ging nicht")
            return ok ? 0 : 1
        }
        // --import-check datei: loads a model like the app does and reports it.
        if let i = args.firstIndex(of: "--import-check"), i + 1 < args.count {
            switch ModelImport.load(URL(fileURLWithPath: args[i + 1])) {
            case .success(let m):
                let tex = Set(m.materials.flatMap { $0.textures.compactMap { $0.map(ObjectIdentifier.init) } }).count
                let parts = m.parts.isEmpty ? "" : ", \(m.parts.count) Teile, \(m.materials.count) Materialien, \(tex) Bilder"
                print("\(args[i + 1]): \(m.triangles) Dreiecke, \(m.vertexCount) Ecken\(parts)"); return 0
            case .failure(let e): print("\(args[i + 1]): \(e)"); return 1
            }
        }
        guard let out = value("--snapshot") else { return 2 }
        let size = (value("--size") ?? "3440x1440").split(separator: "x").compactMap { Int($0) }
        let hole = (value("--hole") ?? "0.5,0.5").split(separator: ",").compactMap { Float($0) }
        guard size.count == 2, hole.count == 2 else {
            FileHandle.standardError.write("bad --size or --hole\n".data(using: .utf8)!)
            return 2
        }
        let layout = ScreenLayout(holeX: hole[0], holeY: hole[1],
                                  topBar: Float(value("--top") ?? "24") ?? 24,
                                  bottomBar: Float(value("--bottom") ?? "0") ?? 0)
        let presetID = value("--preset") ?? "strudel"
        var look = Preset.factory.first { $0.id == presetID }?.look ?? Look()
        guard applyObjectFlags(args, to: &look) else { return 2 }
        if let kind = value("--catalog") {
            let only = value("--only").map { Set($0.split(separator: ",").map(String.init)) }
            return catalog(kind, base: look, out: out, scale: Float(value("--scale") ?? "1") ?? 1, only: only)
        }
        let r = Renderer(look: look, layout: layout)
        // --quality 0...3 (Akku sparen ... Ultra), --qa jet=3,hole=2 for single areas.
        func quality(_ spec: String?, areas: String?) -> RenderQuality {
            var q = RenderQuality(QualityLevel(rawValue: Int(spec ?? "1") ?? 1) ?? .balanced)
            for kv in (areas ?? "").split(separator: ",") {
                let p = kv.split(separator: "=")
                if p.count == 2, let a = QualityArea(rawValue: String(p[0])), let l = Int(p[1]).flatMap(QualityLevel.init) { q.levels[a] = l }
            }
            return q
        }
        r.quality = quality(value("--quality"), areas: value("--qa"))
        if let m = value("--map").flatMap(Float.init) { r.mapScale = m }
        if args.contains("--nobox") { r.detailBox = false }
        if let d = value("--debug").flatMap(Float.init) { r.debug = d }
        r.pixelScale = Float(value("--scale") ?? "1") ?? 1
        let mouse = (value("--mouse") ?? "").split(separator: ",").compactMap { Float($0) }
        if mouse.count == 3 { r.mouse = SIMD4(mouse[0], mouse[1], mouse[2], 1) }
        let t = Float(value("--time") ?? "20") ?? 20
        // Nur Ränder and Aus: the picture stands at the moment it froze (here 20 s), only the bands move on.
        switch value("--motion") ?? "all" {
        case "edges": r.setTime(20); r.setEdgeLead(t - 20)
        case "off": r.setTime(20)
        default: r.setTime(t)
        }
        if args.contains("--edgecheck") { return edgeCheck(r, width: size[0], height: size[1]) }
        // --event warp --phase 0.5 [--arrival]: freeze one event; --phases 0.2,0.45,0.7 lays several side by side.
        if let ev = value("--event") {
            guard ShipCatalog.event(ev) != nil else {
                FileHandle.standardError.write("unknown event \(ev), known: \(ShipCatalog.eventSpecs.map(\.id).joined(separator: ", "))\n".data(using: .utf8)!)
                return 2
            }
            let arrival = args.contains("--arrival")
            ObjectSystem.forcedEvent = (ev, Float(value("--phase") ?? "0.5") ?? 0.5, arrival)
            if let list = value("--phases") {
                let ps = list.split(separator: ",").compactMap { Float($0) }
                let crop = (value("--crop") ?? "").split(separator: ",").compactMap { Int($0) }
                return series(r, times: ps, width: size[0], height: size[1], crop: crop.count == 4 ? crop : nil, out: out, eventPhases: (ev, arrival))
            }
        }
        if let list = value("--series") {
            // "a,b,c" or "start:end:count".
            var times = list.split(separator: ",").compactMap { Float($0) }
            let rng = list.split(separator: ":").compactMap { Float($0) }
            if rng.count == 3, rng[2] >= 2 {
                let n = Int(rng[2])
                times = (0..<n).map { rng[0] + (rng[1] - rng[0]) * Float($0) / Float(n - 1) }
            }
            let crop = (value("--crop") ?? "").split(separator: ",").compactMap { Int($0) }
            return series(r, times: times, width: size[0], height: size[1], crop: crop.count == 4 ? crop : nil, out: out,
                          edgesOnly: value("--motion") == "edges", vertical: args.contains("--vertical"), stack: args.contains("--stack"))
        }
        if args.contains("--bench-geo") {
            var plain = look
            plain.objects = ObjectScene()
            benchGeo(Renderer(look: plain, layout: layout), r, width: size[0], height: size[1])
            return 0
        }
        if args.contains("--jet-stats") { return jetStats(look, layout: layout, width: size[0], height: size[1]) }
        let pace = Double(value("--pace") ?? "0") ?? 0
        // --bench-q 1 [--bench-qa ...]: the same scene at another quality (a) against --quality (b).
        if let qa = value("--bench-q") {
            let a = Renderer(look: look, layout: layout)
            a.pixelScale = r.pixelScale
            a.quality = quality(qa, areas: value("--bench-qa"))
            benchAB(a, r, width: size[0], height: size[1], edgesOnly: false, pace: pace, labels: ("quality A", "B"))
            return 0
        }
        if args.contains("--bench-ab") || args.contains("--bench-passes") {
            var plain = look
            plain.objects = ObjectScene()
            let a = Renderer(look: plain, layout: layout)
            a.pixelScale = r.pixelScale
            a.quality = r.quality
            if args.contains("--bench-passes") {
                benchPasses(a, r, width: size[0], height: size[1], pace: pace)
            } else {
                benchAB(a, r, width: size[0], height: size[1], edgesOnly: args.contains("--edges"), pace: pace)
            }
            return 0
        }
        if args.contains("--bench") { bench(r, width: size[0], height: size[1], edgesOnly: args.contains("--edges")); return 0 }
        let start = Date()
        guard let img = render(r, width: size[0], height: size[1]) else { return 1 }
        if args.contains("--mem") {
            print(String(format: "GPU allocated: %.1f MB", Double(GPU.shared.device.currentAllocatedSize) / 1e6))
        }
        if let atlasOut = value("--dump-atlas"), let a = r.galaxyTex { dumpTexture(a, to: atlasOut) }
        let ok = writePNG(img, to: URL(fileURLWithPath: out))
        print(String(format: "%@ (%.0f ms)", out, Date().timeIntervalSince(start) * 1000))
        return ok ? 0 : 1
    }

    static func render(_ r: Renderer, width: Int, height: Int) -> CGImage? {
        let gpu = GPU.shared
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: GPU.outFormat, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let tex = gpu.device.makeTexture(descriptor: d), let cmd = gpu.queue.makeCommandBuffer() else { return nil }
        r.encode(cmd, target: tex, width: width, height: height)
        cmd.commit()
        cmd.waitUntilCompleted()
        let rowBytes = width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * height)
        tex.getBytes(&bytes, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                       space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Times the per-frame pass alone (the geodesic map is built once before).
    /// With edgesOnly it times what that mode draws per frame: the two band strips.
    static func bench(_ r: Renderer, width: Int, height: Int, edgesOnly: Bool = false) {
        _ = render(r, width: width, height: height)
        let gpu = GPU.shared
        func target(_ w: Int, _ h: Int) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: GPU.outFormat, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget]
            d.storageMode = .private
            return gpu.device.makeTexture(descriptor: d)!
        }
        let tex = target(width, height)
        let rows = r.stripRows(height: height)
        let strips = [rows.top, rows.bottom].compactMap { $0 }.map { (EdgeStrip(), target(width, $0.1 - $0.0), $0) }
        if edgesOnly {
            print("strips: " + strips.map { "\($0.2.0)..\($0.2.1)" }.joined(separator: ", "))
        }
        let n = 240
        var cmds: [MTLCommandBuffer] = []
        let t0 = CACurrentMediaTime()
        for i in 0..<n {
            let cmd = gpu.queue.makeCommandBuffer()!
            r.setTime(Float(i) / 60)
            if edgesOnly {
                for s in strips { r.encodeStrip(cmd, strip: s.0, target: s.1, screenW: width, screenH: height, rows: s.2) }
            } else {
                r.encode(cmd, target: tex, width: width, height: height)
            }
            cmd.commit()
            cmds.append(cmd)
        }
        let cpu = CACurrentMediaTime() - t0
        cmds.last!.waitUntilCompleted()
        // Back-to-back submission keeps the GPU clocked up; count only the second half.
        let tail = cmds[(n / 2)...]
        let span = tail.last!.gpuEndTime - tail.first!.gpuStartTime
        print(String(format: "%dx%d: %.2f ms GPU per frame (sustained), CPU %.3f ms per frame", width, height,
                     span / Double(tail.count) * 1000, cpu / Double(n) * 1000))
    }

    /// The same scene without (a) and with (b) objects, in alternating blocks inside one run,
    /// so both see the same temperature of the GPU. Prints the medians and the difference.
    static func benchAB(_ a: Renderer, _ b: Renderer, width: Int, height: Int, edgesOnly: Bool, pace: Double = 0,
                        labels: (String, String) = ("without objects", "with")) {
        let gpu = GPU.shared
        func target(_ w: Int, _ h: Int) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: GPU.outFormat, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget]
            d.storageMode = .private
            return gpu.device.makeTexture(descriptor: d)!
        }
        _ = render(a, width: width, height: height)
        _ = render(b, width: width, height: height)
        let tex = target(width, height)
        let rows = a.stripRows(height: height)
        let spans = [rows.top, rows.bottom].compactMap { $0 }
        let stripsA = spans.map { (EdgeStrip(), target(width, $0.1 - $0.0), $0) }
        let stripsB = spans.map { (EdgeStrip(), target(width, $0.1 - $0.0), $0) }
        // Frames alternate without (a) and with (b) objects, back to back; each frame's own GPU time
        // is measured, medians compared. Alternating every frame cancels warming and clock changes.
        func frame(_ r: Renderer, _ strips: [(EdgeStrip, MTLTexture, (Int, Int))], _ i: Int) -> MTLCommandBuffer {
            let cmd = gpu.queue.makeCommandBuffer()!
            r.setTime(Float(i) / 60)
            if edgesOnly {
                for s in strips { r.encodeStrip(cmd, strip: s.0, target: s.1, screenW: width, screenH: height, rows: s.2) }
            } else {
                r.encode(cmd, target: tex, width: width, height: height)
            }
            cmd.commit()
            return cmd
        }
        // Each frame alone on the GPU (wait after each), so its time is its own and not the queue's.
        var ca: [MTLCommandBuffer] = [], cb: [MTLCommandBuffer] = []
        for i in 0..<40 { frame(a, stripsA, i).waitUntilCompleted(); frame(b, stripsB, i).waitUntilCompleted() }
        // With pace (frames per second) the frames are spaced like the live view, so the GPU clocks down between them.
        let clock = Pacer(pace)
        for i in 0..<480 {
            clock.wait(); let x = frame(a, stripsA, i); x.waitUntilCompleted(); ca.append(x)
            clock.wait(); let y = frame(b, stripsB, i); y.waitUntilCompleted(); cb.append(y)
        }
        let ta = ca.map { ($0.gpuEndTime - $0.gpuStartTime) * 1000 }, tb = cb.map { ($0.gpuEndTime - $0.gpuStartTime) * 1000 }
        func median(_ v: [Double]) -> Double { let s = v.sorted(); return (s[s.count / 2 - 1] + s[s.count / 2]) / 2 }
        let diffs = zip(tb, ta).map { $0 - $1 }
        print(String(format: "%dx%d%@: %@ %.3f ms, %@ %.3f ms, difference %+.3f ms (median of 480 alternating frames)",
                     width, height, edgesOnly ? " edges" : "", labels.0, median(ta), labels.1, median(tb), median(diffs)))
    }

    /// GPU time per pass (stage-boundary timestamps), without (a) and with (b) objects in alternating frames.
    /// Prints the median per pass name, the frame's total and how much of it no pass covers (gaps between passes).
    static func benchPasses(_ a: Renderer, _ b: Renderer, width: Int, height: Int, pace: Double) {
        guard let prof = PassProfiler(device: GPU.shared.device) else { print("no stage-boundary counters"); return }
        let gpu = GPU.shared
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: GPU.outFormat, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget]
        d.storageMode = .private
        let tex = gpu.device.makeTexture(descriptor: d)!
        _ = render(a, width: width, height: height)
        _ = render(b, width: width, height: height)
        PassProfiler.shared = prof
        defer { PassProfiler.shared = nil }
        var runs: [[String: Double]] = [[:], [:]]
        var lists: [[String: [Double]]] = [[:], [:]]
        var totals: [[Double]] = [[], []]
        let clock = Pacer(pace)
        let n = 360
        for i in 0..<(n + 40) {
            for (k, r) in [a, b].enumerated() {
                clock.wait()
                prof.begin()
                let cmd = gpu.queue.makeCommandBuffer()!
                r.setTime(Float(i) / Float(pace > 0 ? pace : 60))
                r.encode(cmd, target: tex, width: width, height: height)
                cmd.commit()
                cmd.waitUntilCompleted()
                let res = prof.collect()
                guard i >= 40 else { continue }
                totals[k].append((cmd.gpuEndTime - cmd.gpuStartTime) * 1000)
                for (name, ms) in res { lists[k][name, default: []].append(ms) }
                runs[k] = res
            }
        }
        // Passes that run only in some frames (the nebula) count as zero in the others.
        func median(_ v: [Double], _ count: Int) -> Double {
            var s = v + [Double](repeating: 0, count: max(count - v.count, 0))
            s.sort()
            return (s[s.count / 2 - 1] + s[s.count / 2]) / 2
        }
        func mean(_ v: [Double], _ count: Int) -> Double { v.reduce(0, +) / Double(max(count, 1)) }
        let names = Set(lists[0].keys).union(lists[1].keys).sorted()
        print(String(format: "%dx%d%@: per pass, mean (median) ms, without -> with objects", width, height,
                     pace > 0 ? String(format: ", paced %.0f fps", pace) : ""))
        var sum = [0.0, 0.0]
        for name in names {
            let va = lists[0][name] ?? [], vb = lists[1][name] ?? []
            let ma = mean(va, n), mb = mean(vb, n)
            sum[0] += ma; sum[1] += mb
            print(String(format: "  %-22@ %7.3f (%6.3f)  ->  %7.3f (%6.3f)   %+.3f  [%d/%d frames]", name as NSString,
                         ma, median(va, n), mb, median(vb, n), mb - ma, va.count, vb.count))
        }
        let ta = mean(totals[0], n), tb = mean(totals[1], n)
        print(String(format: "  %-22@ %7.3f (%6.3f)  ->  %7.3f (%6.3f)   %+.3f", "frame" as NSString,
                     ta, median(totals[0], n), tb, median(totals[1], n), tb - ta))
        print(String(format: "  %-22@ %7.3f           ->  %7.3f             %+.3f", "not in a pass" as NSString,
                     ta - sum[0], tb - sum[1], (tb - sum[1]) - (ta - sum[0])))
    }

    /// Edges-only mode must look exactly like the full picture: draws both, compares the strips.
    static func edgeCheck(_ r: Renderer, width: Int, height: Int) -> Int32 {
        let gpu = GPU.shared
        r.edgeObjectsInStrips = false
        guard let full = render(r, width: width, height: height),
              let fullData = full.dataProvider?.data as Data? else { return 1 }
        // Objects on a band are drawn by the strips, over a still without them.
        r.edgeObjectsInStrips = true
        let rows = r.stripRows(height: height)
        var worst = 0
        for span in [rows.top, rows.bottom].compactMap({ $0 }) {
            let h = span.1 - span.0
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: GPU.outFormat, width: width, height: h, mipmapped: false)
            d.usage = [.renderTarget]
            d.storageMode = .shared
            let tex = gpu.device.makeTexture(descriptor: d)!
            let cmd = gpu.queue.makeCommandBuffer()!
            r.encodeStrip(cmd, strip: EdgeStrip(), target: tex, screenW: width, screenH: height, rows: span)
            cmd.commit()
            cmd.waitUntilCompleted()
            var bytes = [UInt8](repeating: 0, count: width * 4 * h)
            tex.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, h), mipmapLevel: 0)
            fullData.withUnsafeBytes { (f: UnsafeRawBufferPointer) in
                for y in 0..<h {
                    for x in 0..<width {
                        for c in 0..<3 {
                            let a = Int(bytes[(y * width + x) * 4 + c]), b = Int(f[((y + span.0) * width + x) * 4 + c])
                            worst = max(worst, abs(a - b))
                        }
                    }
                }
            }
            print("rows \(span.0)..\(span.1)")
        }
        print("largest difference: \(worst) of 255")
        return worst <= 3 ? 0 : 1
    }

    // MARK: Objects

    /// --objects file.json, --add kind:variant[:key=value,...] (repeatable), --no-objects.
    static func applyObjectFlags(_ args: [String], to look: inout Look) -> Bool {
        if let i = args.firstIndex(of: "--objects"), i + 1 < args.count {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: args[i + 1])) else {
                FileHandle.standardError.write("cannot read \(args[i + 1])\n".data(using: .utf8)!)
                return false
            }
            if let scene = try? JSONDecoder().decode(ObjectScene.self, from: data), (try? JSONSerialization.jsonObject(with: data)) is [String: Any] {
                look.objects = scene
            } else if let list = try? JSONDecoder().decode(ObjectScene.self, from: Data(#"{"items":"#.utf8) + data + Data("}".utf8)) {
                look.objects.items = list.items
            }
        }
        for (i, a) in args.enumerated() where a == "--add" && i + 1 < args.count {
            guard let o = parseAdd(args[i + 1]) else {
                FileHandle.standardError.write("bad --add \(args[i + 1]), e.g. galaxy:spiral:tilt=40\n".data(using: .utf8)!)
                return false
            }
            look.objects.items.append(o)
        }
        if args.contains("--no-objects") { look.objects = ObjectScene() }
        // --drop kind,kind: remove those kinds, e.g. to time one part of a preset scene.
        if let i = args.firstIndex(of: "--drop"), i + 1 < args.count {
            let kinds = Set(args[i + 1].split(separator: ",").map(String.init))
            look.objects.items.removeAll { kinds.contains($0.kind) }
        }
        return true
    }

    /// "galaxy:spiral:tilt=40,size=8,az=0" -> catalog default plus the given values.
    static func parseAdd(_ spec: String) -> SpaceObject? {
        let parts = spec.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2, let v = ObjectCatalog.variant(parts[0], parts[1]) else { return nil }
        var o = v.make(1)
        if parts.count == 3 {
            for kv in parts[2].split(separator: ",") {
                let p = kv.split(separator: "=", maxSplits: 1).map(String.init)
                guard p.count == 2 else { return nil }
                let key = p[0], f = Float(p[1])
                switch key {
                case "tint": o.tint = p[1]
                case "name": o.name = p[1]
                case "on": o.on = p[1] != "0"
                case "mode":
                    guard let m = MotionMode(rawValue: p[1]) else { return nil }
                    o.motion.mode = m
                case "depth": o.motion.depth = p[1] == "1" ? "behind" : p[1] == "0" ? "front" : p[1]
                case "edge": o.motion.edge = p[1]
                case "dir", "direction": o.motion.direction = p[1]
                case "side": o.motion.side = p[1]
                case "attach": o.attach = p[1]
                case "model": o.model = p[1]
                case "events": o.events.on = p[1] != "0"
                case "eventKinds": o.events.kinds = p[1].split(separator: "+").map(String.init)
                case "eventInterval": o.events.interval = Float(p[1]) ?? o.events.interval
                case "near":
                    if let v = ObjectCatalog.spec(for: o) { let n = ObjectCatalog.makeNear(v, seed: o.seed); o.size = n.size; o.motion = n.motion; o.params.merge(n.params) { a, _ in a } }
                default:
                    guard let f else { return nil }
                    switch key {
                    case "size": o.size = f
                    case "brightness": o.brightness = f
                    case "seed": o.seed = UInt32(max(f, 0))
                    case "az", "azimuth": o.motion.azimuth = f
                    case "el", "elevation": o.motion.elevation = f
                    case "drift": o.motion.drift = f
                    case "driftAngle": o.motion.driftAngle = f
                    case "tintAmount": o.tintAmount = f
                    case "radius": o.motion.radius = f
                    case "ecc": o.motion.eccentricity = f
                    case "incl": o.motion.inclination = f
                    case "node": o.motion.node = f
                    case "peri": o.motion.periapsis = f
                    case "phase": o.motion.phase = f
                    case "tempo": o.motion.tempo = f
                    case "x": o.motion.x = f
                    case "y": o.motion.y = f
                    case "offset": o.motion.offset = f
                    case "edgeSpeed": o.motion.edgeSpeed = f
                    case "edgeGap": o.motion.edgeGap = f
                    case "wobble": o.motion.wobble = f
                    case "passMin": o.motion.passMin = f
                    case "passMax": o.motion.passMax = f
                    case "interval": o.motion.interval = f
                    case "fly": o.motion.flySpeed = f
                    default: o.params[key] = f
                    }
                }
            }
        }
        return o
    }

    /// Every variant of one kind (or all) as a labelled tile, 860 x 360 each, three per row.
    static func catalog(_ kind: String, base: Look, out: String, scale: Float, only: Set<String>? = nil) -> Int32 {
        let near = kind == "nearstar"
        let all = kind == "all" ? ObjectCatalog.all
            : near ? ObjectCatalog.variants(of: .star).filter { ObjectCatalog.nearStarIDs.contains($0.id) }
            : ObjectCatalog.all.filter { $0.kind.rawValue == kind }
        // --only id,id or a universe: just those tiles.
        let variants = only.map { set in all.filter { set.contains($0.id) || set.contains($0.menu.last ?? "") } } ?? all
        guard !variants.isEmpty else {
            FileHandle.standardError.write("unknown kind \(kind)\n".data(using: .utf8)!)
            return 2
        }
        let tw = 860, th = 360, cols = 3
        let rows = (variants.count + cols - 1) / cols
        let W = tw * cols, H = th * rows
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                  space: CGColorSpace(name: CGColorSpace.displayP3)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return 1 }
        for (n, v) in variants.enumerated() {
            var look = base
            var o = v.make(1)
            var t: Float = 20
            // Bodies sit beside the hole, fixed on the screen, big enough to show their surface.
            func fixed(_ size: Float, x: Float = 0.68) {
                o.motion = Motion()
                o.motion.mode = .fixed
                o.motion.x = x
                o.motion.y = 0.5
                o.size = size
            }
            switch v.kind {
            case .galaxy: o.size = min(o.size * 6, 30); o.motion.azimuth = 46; o.motion.elevation = 0
            case .star where near:
                o = ObjectCatalog.makeNear(v, seed: 1)
                fixed(v.id == "binary" ? 120 : 150)
                if v.id == "redSupergiant" || v.id == "redGiant" { o.size = 210 }
                if v.id == "whiteDwarf" || v.id == "brownDwarf" { o.size = 90 }
            case .star: o.size *= 2.5; o.motion.azimuth = 40; o.motion.elevation = 0
            case .planet: fixed(o.param("rings") > 0.5 ? 150 : 250)
            case .moon: fixed(200)
            case .asteroid: fixed(180)
            case .ship, .station, .model:
                // Length so the whole ship fits the tile: compact ones (cube, ring) smaller.
                let r = ShipCatalog.mesh(for: o)?.radius ?? 0.5
                fixed((v.kind == .station ? 300 : 330) * min(0.56 / max(r, 0.3), 1.2), x: 0.67)
                o.events.on = false
            case .blackHole: fixed(0.45, x: 0.72)
            case .wormhole: fixed(220, x: 0.7)
            case .comet: fixed(36, x: 0.55)
            case .meteor:
                o.params["rate"] = 40
                t = 20.4
            case .belt where v.id == "stream": o.motion.edge = "bottom"; o.motion.offset = 40
            default: break
            }
            if v.kind == .moon {
                // A moon beside its planet, both lit from the hole.
                o.size = 200
            }
            look.objects = ObjectScene()
            look.objects.items = [o]
            look.edgeTop.on = false
            look.edgeBottom.on = false
            let r = Renderer(look: look, layout: ScreenLayout(holeX: 0.25, holeY: 0.5, topBar: 0, bottomBar: 0))
            r.pixelScale = scale
            r.setTime(t)
            guard let img = render(r, width: tw, height: th) else { return 1 }
            let x = (n % cols) * tw, y = H - (n / cols + 1) * th
            ctx.draw(img, in: CGRect(x: x, y: y, width: tw, height: th))
            let label = NSAttributedString(string: "\(v.title)  (\(v.kind.rawValue):\(v.id))", attributes: [
                .font: CTFontCreateWithName("Helvetica Neue" as CFString, 20, nil),
                .foregroundColor: CGColor(gray: 1, alpha: 0.92),
            ])
            let line = CTLineCreateWithAttributedString(label)
            ctx.textPosition = CGPoint(x: x + 16, y: y + th - 32)
            CTLineDraw(line, ctx)
        }
        ctx.setStrokeColor(CGColor(gray: 0.35, alpha: 1))
        ctx.setLineWidth(2)
        for c in 1..<cols { ctx.stroke(CGRect(x: c * tw, y: 0, width: 0, height: H)) }
        for rr in 1..<max(rows, 1) { ctx.stroke(CGRect(x: 0, y: rr * th, width: W, height: 0)) }
        guard let img = ctx.makeImage() else { return 1 }
        let ok = writePNG(img, to: URL(fileURLWithPath: out))
        print(out)
        return ok ? 0 : 1
    }

    /// Frames at several times side by side, optionally cropped (x, y, w, h), each labelled with its time.
    static func series(_ r: Renderer, times: [Float], width: Int, height: Int, crop: [Int]?, out: String, edgesOnly: Bool = false,
                       eventPhases: (String, Bool)? = nil, vertical: Bool = false, stack: Bool = false) -> Int32 {
        let cw = crop?[2] ?? width, ch = crop?[3] ?? height
        // Side by side, or (--vertical) one under the other, first on top; --stack lays all over one
        // another (lighter wins), so a path and its speed show as a trail of images.
        let n = stack ? 1 : times.count
        let W = vertical ? cw : cw * n, H = vertical ? ch * n : ch
        func origin(_ i: Int) -> (Int, Int) { stack ? (0, 0) : vertical ? (0, (n - 1 - i) * ch) : (i * cw, 0) }
        guard !times.isEmpty, let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                                  space: CGColorSpace(name: CGColorSpace.displayP3)!,
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return 1 }
        if stack { ctx.setBlendMode(.lighten) }
        for (i, t) in times.enumerated() {
            if let (ev, arr) = eventPhases { ObjectSystem.forcedEvent = (ev, t, arr) }
            else if edgesOnly { r.setTime(20); r.setEdgeLead(t - 20) } else { r.setTime(t) }
            guard var img = render(r, width: width, height: height) else { return 1 }
            if let c = crop, let part = img.cropping(to: CGRect(x: c[0], y: c[1], width: c[2], height: c[3])) { img = part }
            let (ox, oy) = origin(i)
            ctx.draw(img, in: CGRect(x: ox, y: oy, width: cw, height: ch))
            if stack { continue }
            let text = eventPhases.map { String(format: "%@ %@, Phase %g", ShipCatalog.event($0.0)?.title ?? $0.0, $0.1 ? "Ankunft" : "Abflug", t) } ?? String(format: "t = %g s", t)
            let label = NSAttributedString(string: text, attributes: [
                .font: CTFontCreateWithName("Helvetica Neue" as CFString, 22, nil),
                .foregroundColor: CGColor(gray: 1, alpha: 0.9),
            ])
            ctx.textPosition = CGPoint(x: ox + 14, y: oy + ch - 34)
            CTLineDraw(CTLineCreateWithAttributedString(label), ctx)
            if i > 0 {
                ctx.setStrokeColor(CGColor(gray: 0.4, alpha: 1))
                ctx.setLineWidth(2)
                ctx.stroke(vertical ? CGRect(x: 0, y: oy + ch, width: cw, height: 0) : CGRect(x: ox, y: 0, width: 0, height: ch))
            }
        }
        if stack, let a = times.first, let b = times.last {
            ctx.setBlendMode(.normal)
            let label = NSAttributedString(string: String(format: "t = %g bis %g s, %d Bilder", a, b, times.count), attributes: [
                .font: CTFontCreateWithName("Helvetica Neue" as CFString, 22, nil),
                .foregroundColor: CGColor(gray: 1, alpha: 0.9),
            ])
            ctx.textPosition = CGPoint(x: 14, y: ch - 34)
            CTLineDraw(CTLineCreateWithAttributedString(label), ctx)
        }
        guard let img = ctx.makeImage() else { return 1 }
        let ok = writePNG(img, to: URL(fileURLWithPath: out))
        print(out)
        return ok ? 0 : 1
    }

    /// Largest channel difference and number of differing pixels of two PNGs of the same size.
    static func diff(_ a: String, _ b: String, tolerance: Int) -> Int32 {
        func load(_ p: String) -> (Int, Int, [UInt8])? {
            guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
            let w = img.width, h = img.height
            var buf = [UInt8](repeating: 0, count: w * h * 4)
            guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: img.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return (w, h, buf)
        }
        guard let x = load(a), let y = load(b) else { print("cannot read images"); return 2 }
        guard x.0 == y.0, x.1 == y.1 else { print("sizes differ: \(x.0)x\(x.1) vs \(y.0)x\(y.1)"); return 1 }
        var worst = 0, count = 0
        for i in stride(from: 0, to: x.2.count, by: 4) {
            var m = 0
            for c in 0..<3 { m = max(m, abs(Int(x.2[i + c]) - Int(y.2[i + c]))) }
            if m > 0 { count += 1 }
            worst = max(worst, m)
        }
        print("largest difference: \(worst) of 255, differing pixels: \(count) of \(x.0 * x.1)")
        return worst <= tolerance ? 0 : 1
    }

    /// Brightness of the approaching jet against the counter jet, from the traced emission
    /// (before colour and tone mapping): traced once without and once with the counter jet.
    static func jetStats(_ look: Look, layout: ScreenLayout, width: Int, height: Int) -> Int32 {
        guard let i = look.objects.items.firstIndex(where: { $0.kind == "jet" }) else { print("no jet"); return 2 }
        func trace(counter: Bool) -> [Float]? {
            var l = look
            l.objects.items[i].params["counterJet"] = counter ? 1 : 0
            let r = Renderer(look: l, layout: layout)
            let cmd = GPU.shared.queue.makeCommandBuffer()!
            r.encodeRays(cmd, width: width, height: height)
            cmd.commit()
            cmd.waitUntilCompleted()
            return r.jetMapValues()
        }
        guard let front = trace(counter: false), let all = trace(counter: true) else { return 1 }
        let back = zip(all, front).map { max($0 - $1, 0) }
        func top(_ v: [Float], _ q: Double) -> Float { let s = v.sorted(); return s[min(Int(Double(s.count - 1) * q), s.count - 1)] }
        let f = top(front, 0.999), b = top(back, 0.999)
        print(String(format: "jet (99.9th percentile of traced emission): approaching %.3f, counter %.4f, ratio %.1f", f, b, f / max(b, 1e-9)))
        print(String(format: "peak: approaching %.3f, counter %.4f, ratio %.1f", front.max() ?? 0, back.max() ?? 0,
                     (front.max() ?? 0) / max(back.max() ?? 0, 1e-9)))
        return 0
    }

    /// Times the ray pass alone (whole screen plus detail box, as after a view change), without
    /// objects (a) and with them (b), alternating so both see the same GPU temperature.
    static func benchGeo(_ a: Renderer, _ b: Renderer, width: Int, height: Int) {
        let gpu = GPU.shared
        _ = render(a, width: width, height: height)
        _ = render(b, width: width, height: height)
        func pass(_ r: Renderer) -> Double {
            let cmd = gpu.queue.makeCommandBuffer()!
            r.encodeRays(cmd, width: width, height: height)
            cmd.commit()
            cmd.waitUntilCompleted()
            return (cmd.gpuEndTime - cmd.gpuStartTime) * 1000
        }
        var ta: [Double] = [], tb: [Double] = []
        for _ in 0..<7 { ta.append(pass(a)); tb.append(pass(b)) }
        let ma = ta.sorted()[3], mb = tb.sorted()[3]
        let ratio = zip(tb, ta).map { $0 / $1 }.sorted()[3]
        print(String(format: "%dx%d: ray pass without objects %.1f ms, with %.1f ms, %+.0f %% (median of 7 pairs)",
                     width, height, ma, mb, (ratio - 1) * 100))
    }

    /// Debug: level 0 of an rgba8 texture as PNG (the galaxy atlas).
    static func dumpTexture(_ t: MTLTexture, to path: String) {
        let gpu = GPU.shared
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: t.width, height: t.height, mipmapped: false)
        d.storageMode = .shared
        guard let copy = gpu.device.makeTexture(descriptor: d), let cmd = gpu.queue.makeCommandBuffer(),
              let blit = cmd.makeBlitCommandEncoder() else { return }
        blit.copy(from: t, sourceSlice: 0, sourceLevel: 0, to: copy, destinationSlice: 0, destinationLevel: 0, sliceCount: 1, levelCount: 1)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: t.width * t.height * 4)
        copy.getBytes(&bytes, bytesPerRow: t.width * 4, from: MTLRegionMake2D(0, 0, t.width, t.height), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let img = CGImage(width: t.width, height: t.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: t.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info, provider: provider,
                                decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return }
        _ = writePNG(img, to: URL(fileURLWithPath: path))
    }

    static func writePNG(_ img: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, img, nil)
        return CGImageDestinationFinalize(dest)
    }
}

/// Spaces frames like the live view: wait() returns at the next tick of a clock running at fps (0: at once).
final class Pacer {
    private let period: Double
    private var next = 0.0
    init(_ fps: Double) { period = fps > 0 ? 1 / fps : 0 }
    func wait() {
        guard period > 0 else { return }
        let now = CACurrentMediaTime()
        if next == 0 || next < now - period { next = now }
        if next > now { usleep(useconds_t((next - now) * 1e6)) }
        next += period
    }
}
