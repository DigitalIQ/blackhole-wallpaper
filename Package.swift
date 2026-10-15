// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BlackHoleWallpaper",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "BlackHoleWallpaper",
            path: "Sources/BlackHoleWallpaper",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("ServiceManagement")]
        )
    ],
    swiftLanguageModes: [.v5]
)
