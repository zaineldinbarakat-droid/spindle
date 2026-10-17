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
            exclude: ["README.md"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // macOS 27's menu bar visibility restriction (private framework, resolved
        // at runtime). Objective-C so a changed API raises a catchable exception.
        .target(
            name: "MenuBarVisibility",
            path: "Sources/MenuBarVisibility"
        ),
        .executableTarget(
            name: "Sleeve",
            dependencies: ["SpindleSync", "MenuBarVisibility"],
            path: "Sources/Sleeve",
            exclude: ["README.md"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("Carbon"), .linkedFramework("IOKit")]
        )
    ]
)
