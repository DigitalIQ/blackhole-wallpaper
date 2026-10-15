import Foundation

/// Own 3D models: copied into Application Support/BlackHoleWallpaper/Models, loaded once with ModelIO.
/// The screen saver reads the same folder inside its container; the app copies the files over.
enum ModelStore {
    /// BH_MODELS=/path overrides the folder (tests); otherwise next to settings.json.
    static var directory: URL {
        if let p = ProcessInfo.processInfo.environment["BH_MODELS"], !p.isEmpty { return URL(fileURLWithPath: p, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlackHoleWallpaper/Models", isDirectory: true)
    }

    private static var cache: [String: ShipMesh] = [:]
    private static var failed: [String: String] = [:]
    private static let lock = NSLock()

    /// Copies a file into the models folder (a free name if taken) and returns its new name. A `.gltf` with
    /// buffers and pictures next to it goes into a folder of its own, with its files at their relative paths;
    /// its name is then "folder/file.gltf".
    static func importFile(_ url: URL) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = url.pathExtension.lowercased()
        let stem = url.deletingPathExtension().lastPathComponent
        let extra = GLTFLoader.externalFiles(url)
        if !extra.isEmpty {
            var folder = stem, n = 2
            while fm.fileExists(atPath: directory.appendingPathComponent(folder).path) {
                let same = directory.appendingPathComponent(folder).appendingPathComponent(url.lastPathComponent)
                if let a = try? Data(contentsOf: url), let b = try? Data(contentsOf: same), a == b { return "\(folder)/\(url.lastPathComponent)" }
                folder = "\(stem) \(n)"
                n += 1
            }
            let dest = directory.appendingPathComponent(folder, isDirectory: true)
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            try fm.copyItem(at: url, to: dest.appendingPathComponent(url.lastPathComponent))
            let src = url.deletingLastPathComponent()
            for rel in extra where !rel.hasPrefix("/") && !rel.contains("..") {
                let to = dest.appendingPathComponent(rel)
                try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !fm.fileExists(atPath: to.path) { try? fm.copyItem(at: src.appendingPathComponent(rel), to: to) }
            }
            return "\(folder)/\(url.lastPathComponent)"
        }
        var name = "\(stem).\(ext)"
        var n = 2
        while fm.fileExists(atPath: directory.appendingPathComponent(name).path) {
            if let a = try? Data(contentsOf: url), let b = try? Data(contentsOf: directory.appendingPathComponent(name)), a == b { return name }
            name = "\(stem) \(n).\(ext)"
            n += 1
        }
        try fm.copyItem(at: url, to: directory.appendingPathComponent(name))
        // An OBJ brings its material file along.
        if ext == "obj" {
            let mtl = url.deletingPathExtension().appendingPathExtension("mtl")
            let dst = directory.appendingPathComponent(mtl.lastPathComponent)
            if fm.fileExists(atPath: mtl.path) && !fm.fileExists(atPath: dst.path) { try? fm.copyItem(at: mtl, to: dst) }
        }
        return name
    }

    /// Mesh of a model file in the folder, nil when missing or unreadable (see `problem`).
    static func mesh(named name: String) -> ShipMesh? {
        guard !name.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let m = cache[name] { return m }
        if failed[name] != nil { return nil }
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { failed[name] = L("Die Datei fehlt im Ordner Models."); return nil }
        switch ModelImport.load(url) {
        case .success(var d):
            let r = d.normalise()
            d.bakeOcclusion()
            let m = ShipMesh(key: "model \(name)", data: d, radius: r)
            cache[name] = m
            return m
        case .failure(let e):
            failed[name] = e.description
            return nil
        }
    }

    /// Why a model cannot be shown, or nil.
    static func problem(_ name: String) -> String? {
        _ = mesh(named: name)
        lock.lock(); defer { lock.unlock() }
        return failed[name]
    }

    /// Forget a model, e.g. after it was replaced.
    static func reload(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        cache[name] = nil
        failed[name] = nil
    }

    /// Copies the models a look uses into the screen saver's container.
    static func exportForSaver(names: [String], to dir: URL) {
        let fm = FileManager.default
        let dest = dir.appendingPathComponent("Models", isDirectory: true)
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        var all = Set(names.filter { !$0.isEmpty })
        for n in all where n.lowercased().hasSuffix(".obj") { all.insert(String(n.dropLast(4)) + ".mtl") }
        // A glTF in its own folder brings its buffers and pictures.
        for n in all where n.contains("/") {
            let url = directory.appendingPathComponent(n)
            let base = (n as NSString).deletingLastPathComponent
            for rel in GLTFLoader.externalFiles(url) where !rel.contains("..") { all.insert(base + "/" + rel) }
        }
        for n in all {
            let src = directory.appendingPathComponent(n), dst = dest.appendingPathComponent(n)
            guard fm.fileExists(atPath: src.path) else { continue }
            if let a = try? fm.attributesOfItem(atPath: src.path), let b = try? fm.attributesOfItem(atPath: dst.path),
               (a[.size] as? Int) == (b[.size] as? Int), (a[.modificationDate] as? Date) ?? .distantPast <= (b[.modificationDate] as? Date) ?? .distantPast {
                continue
            }
            try? fm.removeItem(at: dst)
            try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: src, to: dst)
        }
    }
}
