import AppKit
import CryptoKit
import Foundation

// The app's own small updater. It asks GitHub for the latest release, downloads the DMG and its
// checksum, swaps the app (and the screen saver, if installed) and starts the new version.
// Network: api.github.com and GitHub's download servers, nothing else. Details in README.md, "Updates".

/// Version numbers like 1.0.1, v1.2 or 2.0.0-beta.1 (semantic versioning, build part ignored).
struct SemVer: Comparable, CustomStringConvertible {
    /// Major, minor, patch; missing parts are 0.
    var parts: [Int]
    /// Prerelease part after "-", empty for a release.
    var pre: String

    init?(_ text: String) {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("v") || t.hasPrefix("V") { t.removeFirst() }
        if let plus = t.firstIndex(of: "+") { t = String(t[..<plus]) }
        var core = t
        pre = ""
        if let dash = t.firstIndex(of: "-") {
            core = String(t[..<dash])
            pre = String(t[t.index(after: dash)...])
            if pre.isEmpty { return nil }
        }
        let nums = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(nums.count), nums.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        parts = nums.map { $0 ?? 0 } + Array(repeating: 0, count: 3 - nums.count)
    }

    var isPrerelease: Bool { !pre.isEmpty }
    var description: String { parts.map(String.init).joined(separator: ".") + (pre.isEmpty ? "" : "-" + pre) }

    static func < (a: SemVer, b: SemVer) -> Bool {
        if a.parts != b.parts { return a.parts.lexicographicallyPrecedes(b.parts) }
        if a.pre == b.pre || a.pre.isEmpty { return false }
        if b.pre.isEmpty { return true }
        let x = a.pre.split(separator: "."), y = b.pre.split(separator: ".")
        for (p, q) in zip(x, y) where p != q {
            switch (Int(p), Int(q)) {
            case let (m?, n?): return m < n
            case (.some, nil): return true
            case (nil, .some): return false
            default: return p < q
            }
        }
        return x.count < y.count
    }
}

struct ReleaseAsset: Equatable {
    let name: String
    let url: URL
    let size: Int
}

/// One release as the GitHub API returns it (`/releases/latest`).
struct Release: Equatable {
    let tag: String
    let version: SemVer
    let notes: String
    let page: URL?
    let assets: [ReleaseAsset]
    let draft: Bool
    let prerelease: Bool

    var versionString: String { version.description }

    /// Reads tag_name, body, html_url, assets, draft and prerelease. Nil when the JSON is no release.
    static func parse(_ data: Data) -> Release? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = o["tag_name"] as? String, let v = SemVer(tag) else { return nil }
        let assets = (o["assets"] as? [[String: Any]] ?? []).compactMap { a -> ReleaseAsset? in
            guard let n = a["name"] as? String, let s = a["browser_download_url"] as? String, let u = URL(string: s) else { return nil }
            return ReleaseAsset(name: n, url: u, size: (a["size"] as? NSNumber)?.intValue ?? 0)
        }
        return Release(tag: tag, version: v, notes: o["body"] as? String ?? "",
                       page: (o["html_url"] as? String).flatMap(URL.init(string:)), assets: assets,
                       draft: o["draft"] as? Bool ?? false, prerelease: o["prerelease"] as? Bool ?? false)
    }

    /// The DMG of this version and its checksum file. Nil when one of them is missing.
    var installFiles: (dmg: ReleaseAsset, sha: ReleaseAsset)? {
        let name = "BlackHoleWallpaper-\(versionString).dmg"
        guard let dmg = assets.first(where: { $0.name == name }),
              let sha = assets.first(where: { $0.name == name + ".sha256" }) else { return nil }
        return (dmg, sha)
    }

    /// The start of the release notes as plain text, for the settings page.
    var excerpt: String { Release.excerpt(notes) }

    static func excerpt(_ notes: String, limit: Int = 240) -> String {
        var lines: [String] = []
        for raw in notes.replacingOccurrences(of: "\r", with: "").split(separator: "\n") {
            var l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("#") || l.hasPrefix("```") { continue }
            for mark in ["**", "__", "`"] { l = l.replacingOccurrences(of: mark, with: "") }
            if l.hasPrefix("- ") || l.hasPrefix("* ") { l = String(l.dropFirst(2)) }
            lines.append(l)
        }
        let text = lines.joined(separator: " ")
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        let end = cut.lastIndex(of: " ") ?? cut.endIndex
        return String(cut[..<end]) + " …"
    }
}

/// What a check found.
enum UpdateDecision: Equatable {
    case newer, upToDate, skipped, ignored
}

/// How this copy of the app can be updated.
enum InstallMode: Equatable {
    case selfInstall, homebrew, notWritable, notBundled
}

enum UpdateError: Error, Equatable {
    case network(String), http(Int), badResponse, noAsset, untrusted, download(String), checksum, mount, appMissing,
         wrongApp, signature, swap(String)

    var message: String {
        switch self {
        case .network(let why): L("Keine Verbindung zu GitHub: %@", why)
        case .http(let code): L("GitHub antwortet mit Fehler %d.", code)
        case .badResponse: L("Die Antwort von GitHub ist nicht lesbar.")
        case .noAsset: L("Zu dieser Version gibt es keine passende Image-Datei mit Prüfsumme.")
        case .untrusted: L("Die Datei liegt nicht bei GitHub. Das Update wurde nicht geladen.")
        case .download(let why): L("Download fehlgeschlagen: %@", why)
        case .checksum: L("Die Prüfsumme stimmt nicht. Das Update wurde nicht installiert.")
        case .mount: L("Die Image-Datei ließ sich nicht öffnen.")
        case .appMissing: L("In der Image-Datei fehlt die App.")
        case .wrongApp: L("Die App in der Image-Datei passt nicht zu diesem Update.")
        case .signature: L("Die Signatur der neuen App ist ungültig.")
        case .swap(let why): L("Die neue Version ließ sich nicht an ihren Platz legen: %@", why)
        }
    }
}

/// The parts without UI: feed, version, decision, install mode. The self-test and `--update-check` use them directly.
enum UpdateCore {
    static let bundleID = "io.github.digitaliq.blackholewallpaper"
    static let defaultFeed = URL(string: "https://api.github.com/repos/DigitalIQ/blackhole-wallpaper/releases/latest")!
    static let appName = "BlackHoleWallpaper.app"
    static let saverName = "Schwarzes Loch.saver"
    static let brewCommand = "brew upgrade --cask blackhole-wallpaper"
    /// At most one automatic check per day.
    static let interval: Double = 24 * 3600

    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    /// BH_UPDATE_FEED=<http(s) or file URL, or a path>: another feed, for tests.
    static var feedOverride: URL? {
        guard let s = env["BH_UPDATE_FEED"], !s.isEmpty else { return nil }
        if let u = URL(string: s), ["http", "https", "file"].contains(u.scheme?.lowercased() ?? "") { return u }
        return URL(fileURLWithPath: s)
    }

    static var feedURL: URL { feedOverride ?? defaultFeed }

    static var currentVersionString: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
    /// A build without Info.plist (swift build) counts as 0.0.0.
    static var currentVersion: SemVer { currentVersionString.flatMap(SemVer.init) ?? SemVer("0.0.0")! }

    static var userAgent: String { "BlackHoleWallpaper/\(currentVersionString ?? "dev") (macOS; +https://github.com/DigitalIQ/blackhole-wallpaper)" }

    /// Downloads land here: Application Support/BlackHoleWallpaper/Updates, next to a BH_SETTINGS copy in tests.
    static var workDir: URL {
        if let s = env["BH_SETTINGS"], !s.isEmpty {
            return URL(fileURLWithPath: s).deletingLastPathComponent().appendingPathComponent("Updates", isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlackHoleWallpaper/Updates", isDirectory: true)
    }

    /// Folder of the user's screen saver. BH_SAVER_DIR overrides it; a run on a settings copy
    /// (BH_SETTINGS) without BH_SAVER_DIR never touches the installed screen saver.
    static var saverDir: URL? {
        if let d = env["BH_SAVER_DIR"], !d.isEmpty { return URL(fileURLWithPath: d, isDirectory: true) }
        if env["BH_SETTINGS"] != nil { return nil }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers", isDirectory: true)
    }

    /// The running app bundle, symlinks resolved.
    static var appURL: URL { Bundle.main.bundleURL.resolvingSymlinksInPath() }

    static func decide(_ r: Release, current: SemVer, skipped: String, manual: Bool) -> UpdateDecision {
        if r.draft || r.prerelease || r.version.isPrerelease { return .ignored }
        guard r.version > current else { return .upToDate }
        if !manual, let s = SemVer(skipped), s == r.version { return .skipped }
        return .newer
    }

    /// An automatic check is due: switched on, not in Low Power Mode, last check a day ago or never.
    static func autoCheckDue(enabled: Bool, lowPower: Bool, lastCheck: Double, now: Double) -> Bool {
        guard enabled, !lowPower else { return false }
        return lastCheck <= 0 || now < lastCheck || now - lastCheck >= interval
    }

    /// Without a test feed, files and pages must come from GitHub over https.
    static func trusted(_ url: URL, overridden: Bool) -> Bool {
        if overridden { return ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") }
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host == "api.github.com"
    }

    // MARK: Homebrew and install mode

    static let caskrooms = ["/opt/homebrew/Caskroom/blackhole-wallpaper", "/usr/local/Caskroom/blackhole-wallpaper"]

    /// The app lives in a Caskroom, or a cask is installed and the app sits where casks put it
    /// (/Applications or ~/Applications).
    static func homebrewManages(app: URL, caskrooms: [String] = caskrooms, home: String = NSHomeDirectory()) -> Bool {
        let path = app.resolvingSymlinksInPath().standardizedFileURL.path
        if path.contains("/Caskroom/") { return true }
        guard caskrooms.contains(where: { FileManager.default.fileExists(atPath: $0) }) else { return false }
        let parent = (path as NSString).deletingLastPathComponent
        return parent == "/Applications" || parent == (home as NSString).appendingPathComponent("Applications")
    }

    static func installMode(app: URL, caskrooms: [String] = caskrooms) -> InstallMode {
        let real = app.resolvingSymlinksInPath()
        guard real.pathExtension == "app" else { return .notBundled }
        if homebrewManages(app: real, caskrooms: caskrooms) { return .homebrew }
        let parent = real.deletingLastPathComponent().path
        return FileManager.default.isWritableFile(atPath: parent) ? .selfInstall : .notWritable
    }

    // MARK: Network

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 600
        c.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: c)
    }()

    private static func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return r
    }

    /// Asks the feed for the latest release.
    static func fetchLatest(feed: URL = feedURL) async throws -> Release {
        let data: Data
        if feed.isFileURL {
            guard let d = try? Data(contentsOf: feed) else { throw UpdateError.badResponse }
            data = d
        } else {
            var req = request(feed)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (d, resp): (Data, URLResponse)
            do { (d, resp) = try await session.data(for: req) } catch { throw UpdateError.network(error.localizedDescription) }
            if let h = resp as? HTTPURLResponse, h.statusCode != 200 { throw UpdateError.http(h.statusCode) }
            data = d
        }
        guard let r = Release.parse(data) else { throw UpdateError.badResponse }
        return r
    }

    /// Downloads one file to `dest`, replacing an older one.
    static func download(_ url: URL, to dest: URL) async throws {
        let fm = FileManager.default
        try? fm.removeItem(at: dest)
        if url.isFileURL {
            do { try fm.copyItem(at: url, to: dest) } catch { throw UpdateError.download(error.localizedDescription) }
            return
        }
        do {
            let (tmp, resp) = try await session.download(for: request(url))
            if let h = resp as? HTTPURLResponse, h.statusCode != 200 {
                try? fm.removeItem(at: tmp)
                throw UpdateError.download("HTTP \(h.statusCode)")
            }
            try fm.moveItem(at: tmp, to: dest)
        } catch let e as UpdateError {
            throw e
        } catch {
            throw UpdateError.download(error.localizedDescription)
        }
    }

    // MARK: Checksum

    static func sha256(of file: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: file)
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The hash in a .sha256 file: the first word, 64 hex digits ("<hex>" or "<hex>  <name>").
    static func expectedHash(_ text: String) -> String? {
        guard let first = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }).first else { return nil }
        let hex = first.lowercased()
        guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        return hex
    }

    /// Throws .checksum unless the file matches the hash in shaFile.
    static func verify(file: URL, shaFile: URL) throws {
        guard let text = try? String(contentsOf: shaFile, encoding: .utf8), let want = expectedHash(text),
              let got = try? sha256(of: file), got == want else { throw UpdateError.checksum }
    }
}

/// Download, check, swap, relaunch. Blocking steps; run it off the main thread.
struct UpdateInstaller {
    enum Step { case download, verify, install }

    let release: Release
    let app: URL
    let saverDir: URL?
    let workDir: URL
    var overridden = UpdateCore.feedOverride != nil

    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: out, as: UTF8.self))
    }

    private static func plist(_ bundle: URL) -> [String: Any]? {
        NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
    }

    func install(progress: @escaping (Step) -> Void) async throws {
        let fm = FileManager.default
        guard let files = release.installFiles else { throw UpdateError.noAsset }
        guard UpdateCore.trusted(files.dmg.url, overridden: overridden), UpdateCore.trusted(files.sha.url, overridden: overridden)
        else { throw UpdateError.untrusted }
        try? fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        let dmg = workDir.appendingPathComponent(files.dmg.name)
        let sha = workDir.appendingPathComponent(files.sha.name)
        defer { try? fm.removeItem(at: dmg); try? fm.removeItem(at: sha) }

        progress(.download)
        try await UpdateCore.download(files.sha.url, to: sha)
        try await UpdateCore.download(files.dmg.url, to: dmg)
        progress(.verify)
        try UpdateCore.verify(file: dmg, shaFile: sha)
        progress(.install)
        try swapIn(dmg: dmg)
    }

    /// Mounts the image, copies app and screen saver next to the old ones, swaps them in and deletes the old ones.
    /// On any error the old versions stay in place.
    private func swapIn(dmg: URL) throws {
        let fm = FileManager.default
        let mnt = workDir.appendingPathComponent("mnt", isDirectory: true)
        UpdateInstaller.run("/usr/bin/hdiutil", ["detach", mnt.path, "-force", "-quiet"])
        try? fm.removeItem(at: mnt)
        try? fm.createDirectory(at: mnt, withIntermediateDirectories: true)
        guard UpdateInstaller.run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen",
                                                       "-mountpoint", mnt.path]).status == 0 else {
            try? fm.removeItem(at: mnt)
            throw UpdateError.mount
        }
        var mounted = true
        func detach() {
            guard mounted else { return }
            UpdateInstaller.run("/usr/bin/hdiutil", ["detach", mnt.path, "-force", "-quiet"])
            try? fm.removeItem(at: mnt)
            mounted = false
        }
        defer { detach() }

        // The new app: right bundle, right version, valid signature.
        let newApp = mnt.appendingPathComponent(UpdateCore.appName)
        guard fm.fileExists(atPath: newApp.path) else { throw UpdateError.appMissing }
        guard let info = UpdateInstaller.plist(newApp), info["CFBundleIdentifier"] as? String == UpdateCore.bundleID,
              let v = (info["CFBundleShortVersionString"] as? String).flatMap(SemVer.init), v == release.version
        else { throw UpdateError.wrongApp }
        guard UpdateInstaller.run("/usr/bin/codesign", ["--verify", "--strict", newApp.path]).status == 0 else { throw UpdateError.signature }

        // Pairs of (new copy next to the target, target).
        var moves: [(URL, URL)] = [(newApp, app)]
        let newSaver = mnt.appendingPathComponent(UpdateCore.saverName)
        if let dir = saverDir, fm.fileExists(atPath: newSaver.path) {
            let target = dir.appendingPathComponent(UpdateCore.saverName)
            if fm.fileExists(atPath: target.path) { moves.append((newSaver, target)) }
        }
        func temp(_ target: URL, _ suffix: String) -> URL {
            target.deletingLastPathComponent().appendingPathComponent("." + target.lastPathComponent + suffix)
        }
        var staged: [(URL, URL)] = []
        func cleanStaged() { for (t, _) in staged { try? fm.removeItem(at: t) } }
        for (src, target) in moves {
            let t = temp(target, ".new")
            try? fm.removeItem(at: t)
            let r = UpdateInstaller.run("/usr/bin/ditto", [src.path, t.path])
            guard r.status == 0 else { cleanStaged(); try? fm.removeItem(at: t); throw UpdateError.swap(r.output.trimmingCharacters(in: .whitespacesAndNewlines)) }
            staged.append((t, target))
        }
        detach()
        for (t, _) in staged { UpdateInstaller.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", t.path]) }

        // Swap: old to .old, new to the final name. If a step fails, everything goes back.
        var done: [(old: URL, target: URL)] = []
        func rollBack() {
            for d in done.reversed() {
                try? fm.removeItem(at: d.target)
                try? fm.moveItem(at: d.old, to: d.target)
            }
            cleanStaged()
        }
        for (t, target) in staged {
            let old = temp(target, ".old")
            try? fm.removeItem(at: old)
            do {
                try fm.moveItem(at: target, to: old)
            } catch {
                rollBack(); throw UpdateError.swap(error.localizedDescription)
            }
            do {
                try fm.moveItem(at: t, to: target)
            } catch {
                try? fm.moveItem(at: old, to: target)
                rollBack(); throw UpdateError.swap(error.localizedDescription)
            }
            done.append((old, target))
        }
        for d in done { try? fm.removeItem(at: d.old) }
        // Finder and Spotlight should see the new version.
        UpdateInstaller.run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-f", app.path])
    }

    /// Starts a tiny shell that waits until this process has ended, then opens the new app.
    /// Test variables (settings copy, feed, saver folder) go along, so a test run stays on its copies.
    static func relaunch(app: URL) throws {
        var envArgs: [String] = []
        let env = ProcessInfo.processInfo.environment
        for k in ["BH_SETTINGS", "BH_UPDATE_FEED", "BH_SAVER_DIR"] {
            if let v = env[k], !v.isEmpty { envArgs += ["--env", "\(k)=\(v)"] }
        }
        let script = "i=0; while /bin/kill -0 \(getpid()) 2>/dev/null && [ $i -lt 300 ]; do /bin/sleep 0.1; i=$((i+1)); done; exec /usr/bin/open -n \"$@\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "sh"] + envArgs + [app.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        try p.run()
    }
}

extension UpdateInstaller.Step {
    func text(_ version: String) -> String {
        switch self {
        case .download: L("Lädt Version %@ …", version)
        case .verify: L("Prüft die Prüfsumme …")
        case .install: L("Installiert …")
        }
    }
}

extension Notification.Name {
    /// Opens a page of the settings window; object is the page number.
    static let showSettingsPage = Notification.Name("BlackHoleShowSettingsPage")
}

/// The updater of the running app: schedule, state for the settings page and the menu.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater(store: Store.shared)

    enum State: Equatable {
        case idle, checking, upToDate
        case available(Release)
        case working(String)
        case failed(String, URL?)
    }

    @Published private(set) var state: State = .idle
    /// Found by the automatic check: the menu shows a line for it.
    @Published private(set) var foundAutomatically = false

    private let store: Store
    private var timer: Timer?

    init(store: Store) { self.store = store }

    var mode: InstallMode { UpdateCore.installMode(app: UpdateCore.appURL) }

    var available: Release? {
        if case .available(let r) = state { return r }
        return nil
    }

    var busy: Bool {
        switch state {
        case .checking, .working: true
        default: false
        }
    }

    /// First automatic check about a minute after launch, then the timer looks every hour whether a day has passed.
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.checkIfDue()
            self?.timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
                Task { @MainActor in Updater.shared.checkIfDue() }
            }
        }
    }

    func checkIfDue() {
        let u = store.settings.updates
        guard !busy, available == nil,
              UpdateCore.autoCheckDue(enabled: u.auto, lowPower: Power.lowPowerMode, lastCheck: u.lastCheck,
                                      now: Date().timeIntervalSince1970) else { return }
        Task { await check(manual: false) }
    }

    func checkNow() {
        guard !busy else { return }
        Task { await check(manual: true) }
    }

    private func check(manual: Bool) async {
        state = .checking
        defer { store.settings.updates.lastCheck = Date().timeIntervalSince1970 }
        do {
            let r = try await UpdateCore.fetchLatest()
            switch UpdateCore.decide(r, current: UpdateCore.currentVersion, skipped: store.settings.updates.skipped, manual: manual) {
            case .newer:
                state = .available(r)
                foundAutomatically = !manual
            default:
                state = manual ? .upToDate : .idle
            }
        } catch {
            // An automatic check stays quiet when GitHub is not reachable.
            let msg = (error as? UpdateError)?.message ?? error.localizedDescription
            state = manual ? .failed(msg, nil) : .idle
        }
    }

    func later() {
        state = .idle
        foundAutomatically = false
    }

    func skip() {
        if let r = available { store.settings.updates.skipped = r.versionString }
        later()
    }

    func openPage(_ url: URL?) {
        let fallback = URL(string: "https://github.com/DigitalIQ/blackhole-wallpaper/releases/latest")!
        let u = url.flatMap { UpdateCore.trusted($0, overridden: UpdateCore.feedOverride != nil) ? $0 : nil } ?? fallback
        NSWorkspace.shared.open(u)
    }

    /// Install button: self-install, or the download page when this copy cannot replace itself.
    func install() {
        guard let r = available else { return }
        switch mode {
        case .homebrew: return
        case .notWritable, .notBundled: openPage(r.page); return
        case .selfInstall: break
        }
        foundAutomatically = false
        let installer = UpdateInstaller(release: r, app: UpdateCore.appURL, saverDir: UpdateCore.saverDir, workDir: UpdateCore.workDir)
        state = .working(UpdateInstaller.Step.download.text(r.versionString))
        Task.detached {
            do {
                try await installer.install { step in
                    Task { @MainActor in Updater.shared.state = .working(step.text(r.versionString)) }
                }
                try UpdateInstaller.relaunch(app: installer.app)
                await MainActor.run {
                    Store.shared.save()
                    NSApp.terminate(nil)
                }
            } catch {
                let msg = (error as? UpdateError)?.message ?? error.localizedDescription
                await MainActor.run {
                    Updater.shared.state = .failed(L("Update fehlgeschlagen. Die bisherige Version bleibt installiert. %@", msg), r.page)
                }
            }
        }
    }
}

/// `--update-check` prints what the updater would do. `--update-install` also does it, without UI, for tests.
enum UpdateCLI {
    static func run(install: Bool) async -> Int32 {
        let store = Store(persist: false)
        let app = UpdateCore.appURL
        let mode = UpdateCore.installMode(app: app)
        print("installed version: \(UpdateCore.currentVersionString ?? "none (no Info.plist)")")
        print("feed: \(UpdateCore.feedURL.absoluteString)\(UpdateCore.feedOverride != nil ? " (BH_UPDATE_FEED)" : "")")
        let u = store.settings.updates
        print("automatic checks: \(u.auto ? "on" : "off"), last check: \(u.lastCheck > 0 ? Date(timeIntervalSince1970: u.lastCheck).description : "never")\(u.skipped.isEmpty ? "" : ", skipped: \(u.skipped)")")
        let r: Release
        do { r = try await UpdateCore.fetchLatest() } catch {
            print("check failed: \((error as? UpdateError)?.message ?? error.localizedDescription)")
            return 1
        }
        let decision = UpdateCore.decide(r, current: UpdateCore.currentVersion, skipped: u.skipped, manual: true)
        print("latest release: \(r.versionString) (tag \(r.tag)\(r.draft ? ", draft" : "")\(r.prerelease ? ", prerelease" : ""))")
        print("decision: \(decision)")
        if !r.excerpt.isEmpty { print("notes: \(r.excerpt)") }
        print("app: \(app.path)")
        print("install mode: \(mode)")
        if let f = r.installFiles {
            print("would download: \(f.dmg.url.absoluteString)")
            print("            and \(f.sha.url.absoluteString)")
        } else {
            print("would download: nothing, the release has no BlackHoleWallpaper-\(r.versionString).dmg with .sha256")
        }
        print("into: \(UpdateCore.workDir.path)")
        if let d = UpdateCore.saverDir {
            let s = d.appendingPathComponent(UpdateCore.saverName)
            print("screen saver: \(FileManager.default.fileExists(atPath: s.path) ? s.path + " (would be replaced)" : "not installed in " + d.path)")
        } else {
            print("screen saver: left alone (BH_SETTINGS without BH_SAVER_DIR)")
        }
        switch (decision, mode) {
        case (.newer, .selfInstall): print("action: install \(r.versionString), then relaunch")
        case (.newer, .homebrew): print("action: none, \(UpdateCore.brewCommand)")
        case (.newer, _): print("action: open \(r.page?.absoluteString ?? "the download page")")
        default: print("action: none")
        }
        guard install else { return 0 }
        guard decision == .newer, mode == .selfInstall else { print("nothing installed"); return 1 }
        let installer = UpdateInstaller(release: r, app: app, saverDir: UpdateCore.saverDir, workDir: UpdateCore.workDir)
        do {
            try await installer.install { step in print("step: \(step)") }
            try UpdateInstaller.relaunch(app: app)
            print("installed \(r.versionString), relaunching \(app.path) after pid \(getpid()) exits")
            return 0
        } catch {
            print("install failed, old version kept: \((error as? UpdateError)?.message ?? error.localizedDescription)")
            return 1
        }
    }
}
