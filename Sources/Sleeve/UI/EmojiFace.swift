import AppKit
import CoreImage

extension SleeveSettings {
    /// The Emoji style's two faces, falling back sensibly when a box is left empty.
    var emojiFaceHidden: String { emojiHidden.isEmpty ? "👀" : emojiHidden }
    var emojiFaceShown: String { emojiShown.isEmpty ? emojiFaceHidden : emojiShown }

    /// Keeps only the last emoji typed or picked into a box (nothing else is an icon).
    static func lastEmoji(in text: String) -> String {
        guard let emoji = text.last(where: { character in
            let scalars = character.unicodeScalars
            return scalars.contains { $0.properties.isEmojiPresentation }
                || (scalars.count > 1 && scalars.first?.properties.isEmoji == true)
        }) else { return "" }
        return String(emoji)
    }
}

/// Emoji drawn as menu bar icons: the same 18 pt box and optical size as the symbol
/// icons, so switching styles doesn't change how the bar sits.
enum EmojiFace {
    private static let side: CGFloat = 18
    private static let context = CIContext()
    private static var cache: [String: NSImage] = [:]

    /// `quiet` is the "empty" face: grey and a touch faded, so it rests in the bar as
    /// calmly as the monochrome icons; the full face is the emoji in colour.
    static func image(_ emoji: String, quiet: Bool) -> NSImage {
        let key = "\(quiet ? "q" : "f")\(emoji)"
        if let cached = cache[key] { return cached }
        let points = NSSize(width: side, height: side)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side * 2), pixelsHigh: Int(side * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            return NSImage(size: points)
        }
        rep.size = points
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let text = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let size = text.size()
        text.draw(at: NSPoint(x: (side - size.width) / 2, y: (side - size.height) / 2 + 0.5))
        NSGraphicsContext.restoreGraphicsState()

        var result = NSImage(size: points)
        result.addRepresentation(rep)
        if quiet, let cg = rep.cgImage {
            let grey = CIImage(cgImage: cg)
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0,
                                                                kCIInputBrightnessKey: 0.08,
                                                                kCIInputContrastKey: 0.95])
                .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.8)])
            if let out = context.createCGImage(grey, from: grey.extent) {
                result = NSImage(cgImage: out, size: points)
            }
        }
        cache[key] = result
        return result
    }

    /// A small springy pop, the emoji's version of the symbols' bounce.
    static func bounce(_ view: NSView) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let w = view.bounds.width / 2, h = view.bounds.height / 2
        func scaled(_ s: CGFloat) -> NSValue {
            var m = CATransform3DMakeTranslation(w, h, 0)
            m = CATransform3DScale(m, s, s, 1)
            m = CATransform3DTranslate(m, -w, -h, 0)
            return NSValue(caTransform3D: m)
        }
        let pop = CAKeyframeAnimation(keyPath: "transform")
        pop.values = [scaled(1), scaled(1.2), scaled(0.95), scaled(1.03), scaled(1)]
        pop.keyTimes = [0, 0.3, 0.6, 0.82, 1]
        pop.duration = 0.38
        pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(pop, forKey: "bounce")
    }
}
