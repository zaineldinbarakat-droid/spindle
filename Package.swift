// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Spindle",
    platforms: [.macOS(.v14)],
    targets: [
        // The few types Spindle and Sleeve share to stay out of each other's way.
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
        ),
        .executableTarget(
            name: "Sleeve",
            dependencies: ["SpindleSync"],
            path: "Sources/Sleeve",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("Carbon"), .linkedFramework("IOKit")]
        )
    ]
)
