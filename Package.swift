// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Spindle",
    platforms: [.macOS(.v14)],
    targets: [
        // Shared with Sleeve (github.com/zaineldinbarakat-droid/sleeve): the sync
        // channel the two apps talk over, and the self-updater.
        .target(
            name: "SpindleSync",
            path: "Sources/SpindleSync",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Spindle",
            dependencies: ["SpindleSync"],
            path: "Sources/Spindle",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
