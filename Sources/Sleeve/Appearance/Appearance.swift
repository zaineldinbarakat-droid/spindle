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

/// A colour at a position (0…1) along a gradient.
struct GradientStop: Codable, Equatable, Identifiable {
    var id = UUID()
    var color: RGBA
    var location: Double
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
    /// Any number of stops (two or more); empty means "use color1 → color2".
    var gradientStops: [GradientStop] = []
    /// Direction in degrees: 0 runs left → right, 90 top → bottom.
    var gradientAngle: Double = 0
    var shape: Shape = .full
    var cornerRadius: Double = 10
    /// Gap from the screen edge (and top) for the Rounded and Split shapes.
    var inset: Double = 4
    var shadow = false
    var shadowOpacity: Double = 0.35
    var border = false
    var borderColor = RGBA(r: 1, g: 1, b: 1, a: 0.25)
    var borderWidth: Double = 1

    /// The stops actually drawn, sorted, never fewer than two.
    var resolvedStops: [GradientStop] {
        let stops = gradientStops.count >= 2
            ? gradientStops
            : [GradientStop(color: color1, location: 0), GradientStop(color: color2, location: 1)]
        return stops.sorted { $0.location < $1.location }
    }

    var gradientPoints: (start: UnitPoint, end: UnitPoint) {
        let radians = gradientAngle * .pi / 180
        let dx = cos(radians) / 2, dy = sin(radians) / 2
        return (UnitPoint(x: 0.5 - dx, y: 0.5 - dy), UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }

    var linearGradient: LinearGradient {
        let points = gradientPoints
        return LinearGradient(stops: resolvedStops.map { .init(color: $0.color.color, location: $0.location) },
                              startPoint: points.start, endPoint: points.end)
    }

    /// Nothing to draw: the overlay window is skipped entirely.
    var isEmpty: Bool { fill == .none && !border && !shadow }

    var fillStyle: AnyShapeStyle {
        switch fill {
        case .none: return AnyShapeStyle(Color.clear)
        case .solid: return AnyShapeStyle(color1.color)
        case .gradient:
            return AnyShapeStyle(linearGradient)
        }
    }

    init(fill: Fill = .none,
         color1: RGBA = RGBA(r: 0.12, g: 0.12, b: 0.14, a: 0.85),
         color2: RGBA = RGBA(r: 0.30, g: 0.16, b: 0.40, a: 0.85),
         gradientStops: [GradientStop] = [],
         gradientAngle: Double = 0,
         shape: Shape = .full, cornerRadius: Double = 10, inset: Double = 4,
         shadow: Bool = false, shadowOpacity: Double = 0.35,
         border: Bool = false, borderColor: RGBA = RGBA(r: 1, g: 1, b: 1, a: 0.25), borderWidth: Double = 1) {
        self.fill = fill; self.color1 = color1; self.color2 = color2
        self.gradientStops = gradientStops; self.gradientAngle = gradientAngle
        self.shape = shape; self.cornerRadius = cornerRadius; self.inset = inset
        self.shadow = shadow; self.shadowOpacity = shadowOpacity
        self.border = border; self.borderColor = borderColor; self.borderWidth = borderWidth
    }

    /// Every key is optional, so a style saved by an older Sleeve still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MenuBarStyle()
        fill = try c.decodeIfPresent(Fill.self, forKey: .fill) ?? d.fill
        color1 = try c.decodeIfPresent(RGBA.self, forKey: .color1) ?? d.color1
        color2 = try c.decodeIfPresent(RGBA.self, forKey: .color2) ?? d.color2
        gradientStops = try c.decodeIfPresent([GradientStop].self, forKey: .gradientStops) ?? []
        gradientAngle = try c.decodeIfPresent(Double.self, forKey: .gradientAngle) ?? 0
        shape = try c.decodeIfPresent(Shape.self, forKey: .shape) ?? d.shape
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? d.cornerRadius
        inset = try c.decodeIfPresent(Double.self, forKey: .inset) ?? d.inset
        shadow = try c.decodeIfPresent(Bool.self, forKey: .shadow) ?? d.shadow
        shadowOpacity = try c.decodeIfPresent(Double.self, forKey: .shadowOpacity) ?? d.shadowOpacity
        border = try c.decodeIfPresent(Bool.self, forKey: .border) ?? d.border
        borderColor = try c.decodeIfPresent(RGBA.self, forKey: .borderColor) ?? d.borderColor
        borderWidth = try c.decodeIfPresent(Double.self, forKey: .borderWidth) ?? d.borderWidth
    }

    private static func stops(_ colors: [(Double, Double, Double)], alpha: Double = 0.8) -> [GradientStop] {
        colors.enumerated().map { index, rgb in
            GradientStop(color: RGBA(r: rgb.0, g: rgb.1, b: rgb.2, a: alpha),
                         location: Double(index) / Double(max(colors.count - 1, 1)))
        }
    }

    static let presets: [(String, MenuBarStyle)] = [
        ("Off", MenuBarStyle()),
        ("Midnight", MenuBarStyle(fill: .solid, color1: RGBA(r: 0.05, g: 0.05, b: 0.07, a: 0.92))),
        ("Sunset", MenuBarStyle(fill: .gradient, gradientStops: stops([(0.99, 0.70, 0.35), (0.95, 0.40, 0.40),
                                                                       (0.55, 0.25, 0.75)], alpha: 0.78))),
        ("Aurora", MenuBarStyle(fill: .gradient, gradientStops: stops([(0.20, 0.85, 0.65), (0.25, 0.55, 0.95),
                                                                       (0.60, 0.35, 0.95), (0.95, 0.40, 0.75)], alpha: 0.72))),
        ("Ice", MenuBarStyle(fill: .gradient, gradientStops: stops([(0.75, 0.92, 1.0), (0.45, 0.70, 0.98)], alpha: 0.6),
                             shape: .split, cornerRadius: 14, border: true)),
        ("Neon", MenuBarStyle(fill: .gradient, gradientStops: stops([(1.0, 0.20, 0.60), (0.55, 0.20, 1.0),
                                                                   (0.10, 0.80, 1.0)], alpha: 0.75),
                              shape: .rounded, shadow: true)),
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
