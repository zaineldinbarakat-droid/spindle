// Draws Spindle's and Sleeve's app icons and writes Packaging/<Name>.icns.
//
//   swift Packaging/make-icons.swift
//
// Drawn rather than borrowed: Apple's emoji artwork can't be used as an app icon, and
// open emoji sets need attribution. These follow the macOS icon grid — an 824 pt
// continuous-corner tile on a 1024 pt canvas — in a soft, emoji-like style.
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

struct Record: View {
    var size: CGFloat
    var label: [Color]

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(white: 0.18), Color(white: 0.04)],
                                         center: .center, startRadius: size * 0.1, endRadius: size * 0.5))
            // Grooves.
            ForEach(0..<9) { i in
                Circle()
                    .stroke(Color.white.opacity(i % 2 == 0 ? 0.07 : 0.035), lineWidth: size * 0.006)
                    .frame(width: size * (0.92 - CGFloat(i) * 0.055), height: size * (0.92 - CGFloat(i) * 0.055))
            }
            // Two-lobed sheen, the look of a glossy record under a lamp.
            Circle().fill(AngularGradient(gradient: Gradient(stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0.22), location: 0.12),
                .init(color: .white.opacity(0), location: 0.25),
                .init(color: .white.opacity(0), location: 0.5),
                .init(color: .white.opacity(0.16), location: 0.62),
                .init(color: .white.opacity(0), location: 0.75),
                .init(color: .white.opacity(0), location: 1)
            ]), center: .center))
            Circle().fill(LinearGradient(colors: label, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.36, height: size * 0.36)
                .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: size * 0.008))
            Circle().fill(Color(white: 0.1)).frame(width: size * 0.045, height: size * 0.045)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.45), radius: size * 0.04, y: size * 0.02)
    }
}

// MARK: - Spindle: a record on a walnut tile, tonearm resting on it

struct SpindleIcon: View {
    var body: some View {
        Tile(colors: [Color(red: 0.45, green: 0.28, blue: 0.16), Color(red: 0.20, green: 0.11, blue: 0.06)]) {
            ZStack {
                Record(size: 600, label: [Color(red: 1.0, green: 0.62, blue: 0.28),
                                          Color(red: 0.93, green: 0.30, blue: 0.38)])
                    .offset(x: -40, y: 30)
                Tonearm().offset(x: 185, y: -120)
            }
        }
    }
}

struct Tonearm: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Arm: from the pivot, angled down-left onto the record.
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.62)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 26, height: 420)
                .rotationEffect(.degrees(24), anchor: .top)
                .offset(x: -40, y: 40)
            // Headshell.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.22))
                .frame(width: 58, height: 80)
                .rotationEffect(.degrees(24))
                .offset(x: -205, y: 410)
            // Pivot.
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.95), Color(white: 0.55)],
                                     center: .topLeading, startRadius: 0, endRadius: 90))
                .frame(width: 110, height: 110)
                .overlay(Circle().fill(Color(white: 0.35)).frame(width: 34, height: 34))
        }
        .frame(width: 300, height: 520, alignment: .topTrailing)
        .shadow(color: .black.opacity(0.4), radius: 12, y: 8)
    }
}

// MARK: - Sleeve: a record sliding out of its sleeve

struct SleeveIcon: View {
    var body: some View {
        Tile(colors: [Color(red: 0.36, green: 0.62, blue: 0.98), Color(red: 0.42, green: 0.28, blue: 0.86)]) {
            ZStack {
                Record(size: 470, label: [Color(red: 0.55, green: 0.90, blue: 0.80),
                                          Color(red: 0.25, green: 0.60, blue: 0.95)])
                    .offset(x: 120, y: 0)
                // The sleeve: a cream card with a coral stripe and a thumb notch.
                ZStack {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.97, blue: 0.90),
                                                      Color(red: 0.95, green: 0.89, blue: 0.80)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.45),
                                                      Color(red: 0.98, green: 0.40, blue: 0.52)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: 96)
                        .offset(y: 120)
                    Circle()
                        .fill(Color(red: 1.0, green: 0.55, blue: 0.45))
                        .frame(width: 120, height: 120)
                        .offset(y: -60)
                    Circle()
                        .fill(Color(red: 1.0, green: 0.97, blue: 0.90))
                        .frame(width: 44, height: 44)
                        .offset(y: -60)
                }
                .frame(width: 440, height: 440)
                .shadow(color: .black.opacity(0.35), radius: 24, x: 10, y: 14)
                .offset(x: -110, y: 0)
            }
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
