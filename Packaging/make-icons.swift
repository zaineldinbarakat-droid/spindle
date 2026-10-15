// Draws Spindle's and Sleeve's app icons and writes Packaging/<Name>.icns.
//
//   swift Packaging/make-icons.swift
//
// Each icon is a 3D emoji from Microsoft's Fluent Emoji (MIT, see Packaging/emoji/) on a
// macOS tile — an 824 pt continuous-corner squircle on a 1024 pt canvas. Apple's own
// emoji artwork can't be used in an app icon; Fluent's can.
import AppKit
import SwiftUI

let packaging = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

// MARK: - Shared pieces

/// The macOS tile: continuous corners, a soft drop shadow, a faint top highlight.
struct Tile<Content: View>: View {
    var colors: [Color]
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 185, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            content
            // Glassy sheen across the top half, the hallmark of emoji-style art.
            shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear],
                                      startPoint: .top, endPoint: .center))
            shape.strokeBorder(.white.opacity(0.18), lineWidth: 3)
        }
        .frame(width: 824, height: 824)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.35), radius: 22, y: 14)
        .frame(width: 1024, height: 1024)
    }
}

// MARK: - Emoji icons

struct Emoji: View {
    var file: String
    var size: CGFloat

    var body: some View {
        if let image = NSImage(contentsOf: packaging.appendingPathComponent("emoji/\(file)")) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.28), radius: 24, y: 16)
        }
    }
}

struct SpindleIcon: View {
    var body: some View {
        Tile(colors: [Color(red: 0.45, green: 0.28, blue: 0.16), Color(red: 0.20, green: 0.11, blue: 0.06)]) {
            Emoji(file: "optical_disk_3d.png", size: 560)
        }
    }
}

struct SleeveIcon: View {
    var body: some View {
        Tile(colors: [Color(red: 0.80, green: 0.76, blue: 1.00), Color(red: 0.45, green: 0.38, blue: 0.90)]) {
            Emoji(file: "eyes_3d.png", size: 580).offset(y: 6)
        }
    }
}

// MARK: - Rendering

@MainActor
func png<V: View>(_ view: V, size: Int) -> Data? {
    let renderer = ImageRenderer(content: view.frame(width: 1024, height: 1024))
    renderer.scale = CGFloat(size) / 1024
    guard let cg = renderer.cgImage else { return nil }
    return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
}

@MainActor
func makeIcon<V: View>(_ view: V, name: String) throws {
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let suffix = scale == 2 ? "@2x" : ""
            guard let data = png(view, size: base * scale) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: iconset.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
        }
    }
    if let preview = png(view, size: 512) {
        try preview.write(to: packaging.appendingPathComponent("\(name)-icon.png"))
    }
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", packaging.appendingPathComponent("\(name).icns").path]
    try iconutil.run()
    iconutil.waitUntilExit()
    print("\(name).icns:", iconutil.terminationStatus == 0 ? "ok" : "iconutil failed")
}

MainActor.assumeIsolated {
    do {
        try makeIcon(SpindleIcon(), name: "Spindle")
        try makeIcon(SleeveIcon(), name: "Sleeve")
    } catch {
        print("error:", error)
    }
}
