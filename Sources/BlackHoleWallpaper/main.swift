import AppKit

let args = CommandLine.arguments

/// Every switch the app knows. Anything else starting with "--" ends the app before settings.json is read or written.
let knownSwitches: Set<String> = [
    "--help", "--lang",
    "--settings-shot", "--welcome", "--tab", "--height", "--all-screens", "--locked-demo", "--objects-demo", "--ships-demo", "--exotics-demo",
    "--selftest", "--settings-file", "--update-check", "--update-install",
    "--snapshot", "--diff", "--tol", "--export-ship", "--import-check",
    "--add", "--arrival", "--bench", "--bench-ab", "--bench-geo", "--bench-passes", "--bottom", "--catalog", "--crop", "--debug",
    "--drop", "--dump-atlas", "--edgecheck", "--edges", "--event", "--hole", "--jet-stats", "--map", "--mem", "--motion", "--mouse",
    "--no-objects", "--nobox", "--objects", "--only", "--pace", "--phase", "--phases", "--preset", "--scale", "--series", "--size",
    "--stack", "--time", "--top", "--vertical", "--quality", "--qa", "--bench-q", "--bench-qa",
]

func printHelp() {
    let lines = [
        L("Schwarzes Loch: animierter Schreibtisch-Hintergrund."),
        "",
        L("Ohne Schalter läuft die App als Hintergrund mit Symbol in der Menüleiste."),
        L("Werkzeuge für die Entwicklung (Details in README.md):"),
        "  --selftest [--settings-file x.json]   " + L("Selbsttest, schreibt keine Einstellungen"),
        "  --settings-shot x.png --tab 0...11    " + L("Einstellungsfenster als Bild, mit --lang en oder de"),
        "  --settings-shot x.png --welcome       " + L("Willkommensfenster als Bild"),
        "  --snapshot x.png --size 3440x1440     " + L("Bild ohne Fenster rendern"),
        "  --update-check                        " + L("sucht nach Updates und zeigt, was die App tun würde"),
        "  --update-install                      " + L("lädt und installiert ein Update ohne Fenster, für Tests mit BH_UPDATE_FEED"),
        "  --diff a.png b.png                    " + L("zwei Bilder vergleichen"),
        "  --help                                " + L("diese Hilfe"),
    ]
    print(lines.joined(separator: "\n"))
}

// -h, --help and unknown switches: print help and quit before the store loads or writes anything.
// Single-dash arguments like -AppleLanguages are macOS defaults and stay allowed.
if args.contains("--help") || args.contains("-h") || args.contains("-help") {
    printHelp()
    exit(0)
}
if let unknown = args.dropFirst().first(where: { $0.hasPrefix("--") && !knownSwitches.contains($0) }) {
    FileHandle.standardError.write(Data((L("Unbekannter Schalter: %@", unknown) + "\n\n").utf8))
    printHelp()
    exit(2)
}

if let i = args.firstIndex(of: "--settings-shot"), i + 1 < args.count {
    let tab = args.firstIndex(of: "--tab").flatMap { Int(args[$0 + 1]) } ?? 0
    let height = args.firstIndex(of: "--height").flatMap { Double(args[$0 + 1]) } ?? 700
    let lang = args.firstIndex(of: "--lang").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    exit(SettingsShot.run(path: args[i + 1], tab: tab, allScreens: args.contains("--all-screens"),
                           lockedDemo: args.contains("--locked-demo"), objectsDemo: args.contains("--objects-demo"),
                           shipsDemo: args.contains("--ships-demo"), exoticsDemo: args.contains("--exotics-demo"),
                           height: CGFloat(height), lang: lang, welcome: args.contains("--welcome")))
}
if args.contains("--selftest") {
    exit(SelfTest.run())
}
if args.contains("--update-check") || args.contains("--update-install") {
    let install = args.contains("--update-install")
    Task { @MainActor in exit(await UpdateCLI.run(install: install)) }
    dispatchMain()
}
if args.contains("--snapshot") || args.contains("--diff") || args.contains("--export-ship") || args.contains("--import-check") {
    exit(Snapshot.run(args))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
