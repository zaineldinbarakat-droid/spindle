import AppKit
import SwiftUI

struct RGBA: Codable, Equatable {
    var r: Double, g: Double, b: Double, a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(r: ns.redComponent, g: ns.greenComponent, b: ns.blueComponent, a: ns.alphaComponent)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

/// One complete look for the menu bar.
struct MenuBarStyle: Codable, Equatable {
    enum Fill: String, Codable, CaseIterable, Identifiable {
        case none, solid, gradient
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum Shape: String, Codable, CaseIterable, Identifiable {
        /// Edge to edge, like the system bar.
        case full
        /// One floating rounded bar, inset from the screen edges.
        case rounded
        /// Two capsules: one under the app menus, one under the status icons.
        case split
        var id: String { rawValue }
        var title: String {
            switch self {
            case .full: return "Full Width"
            case .rounded: return "Rounded"
            case .split: return "Split"
            }
        }
    }

    var fill: Fill = .none
    var color1 = RGBA(r: 0.12, g: 0.12, b: 0.14, a: 0.85)
    var color2 = RGBA(r: 0.30, g: 0.16, b: 0.40, a: 0.85)
    var shape: Shape = .full
    var cornerRadius: Double = 10
    /// Gap from the screen edge (and top) for the Rounded and Split shapes.
    var inset: Double = 4
    var shadow = false
    var shadowOpacity: Double = 0.35
    var border = false
    var borderColor = RGBA(r: 1, g: 1, b: 1, a: 0.25)
    var borderWidth: Double = 1

    /// Nothing to draw: the overlay window is skipped entirely.
    var isEmpty: Bool { fill == .none && !border && !shadow }

    var fillStyle: AnyShapeStyle {
        switch fill {
        case .none: return AnyShapeStyle(Color.clear)
        case .solid: return AnyShapeStyle(color1.color)
        case .gradient:
            return AnyShapeStyle(LinearGradient(colors: [color1.color, color2.color],
                                                startPoint: .leading, endPoint: .trailing))
        }
    }

    static let presets: [(String, MenuBarStyle)] = [
        ("Off", MenuBarStyle()),
        ("Midnight", MenuBarStyle(fill: .solid, color1: RGBA(r: 0.05, g: 0.05, b: 0.07, a: 0.92))),
        ("Sunset", MenuBarStyle(fill: .gradient,
                                color1: RGBA(r: 0.95, g: 0.45, b: 0.30, a: 0.75),
                                color2: RGBA(r: 0.55, g: 0.25, b: 0.75, a: 0.75))),
        ("Walnut", MenuBarStyle(fill: .gradient,
                                color1: RGBA(r: 0.36, g: 0.22, b: 0.13, a: 0.9),
                                color2: RGBA(r: 0.17, g: 0.10, b: 0.06, a: 0.9),
                                shape: .rounded, shadow: true)),
        ("Floating Capsules", MenuBarStyle(fill: .solid, color1: RGBA(r: 0.1, g: 0.1, b: 0.12, a: 0.8),
                                           shape: .split, cornerRadius: 14, shadow: true,
                                           border: true))
    ]
}

/// Which style applies when: a base look, an optional dark-mode look, and optional
/// per-display overrides (keyed by the display's name).
struct AppearanceProfiles: Codable, Equatable {
    var light = MenuBarStyle()
    var dark = MenuBarStyle()
    var separateDarkStyle = false
    var displayOverrides: [String: MenuBarStyle] = [:]

    func style(for screen: NSScreen, isDark: Bool) -> MenuBarStyle {
        if let override = displayOverrides[screen.localizedName] { return override }
        return (separateDarkStyle && isDark) ? dark : light
    }
}

enum SystemAppearance {
    static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
