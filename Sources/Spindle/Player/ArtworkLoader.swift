import AppKit
import CoreImage

/// Loads and caches cover art, and derives the accent colour the notch glows with.
actor ArtworkLoader {
    struct Result {
        var image: NSImage
        var accent: NSColor
    }

    private var cache: [String: Result] = [:]
    private var inFlight: Set<String> = []
    private let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

    func cached(_ key: String) -> Result? { cache[key] }

    /// `local` is evaluated only when there is no URL, so Apple Music's (relatively
    /// expensive) raw-data fetch never runs for providers that hand us a URL.
    func load(key: String, url: URL?, local: @Sendable () -> Data?) -> Result? {
        if let hit = cache[key] { return hit }
        guard !inFlight.contains(key) else { return nil }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        var data: Data?
        if let url {
            data = try? Data(contentsOf: url)
        }
        if data == nil {
            data = local()
        }
        guard let data, let image = NSImage(data: data) else { return nil }

        let result = Result(image: image, accent: Self.accentColor(from: image, context: ciContext))
        cache[key] = result
        if cache.count > 40 { cache.removeAll() }
        return result
    }

    /// The cover's dominant colour.
    ///
    /// Averaging every pixel (the old approach) turns any cover with two strong colours
    /// into the mud between them — a blue night sky over an orange desert came out dark
    /// red. Instead: shrink to 32×32, sort the colourful pixels into hue buckets, and
    /// take the bucket with the most colour in it. Near-black and near-white pixels
    /// don't vote; a cover with no colour at all falls back to its average, kept grey.
    private static func accentColor(from image: NSImage, context: CIContext) -> NSColor {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .systemPink
        }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let bitmap = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                     bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return .systemPink
        }
        bitmap.interpolationQuality = .medium
        bitmap.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        let bucketCount = 18
        var weight = [CGFloat](repeating: 0, count: bucketCount)
        var sums = [(r: CGFloat, g: CGFloat, b: CGFloat)](repeating: (0, 0, 0), count: bucketCount)
        var average: (r: CGFloat, g: CGFloat, b: CGFloat) = (0, 0, 0)

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = CGFloat(pixels[i]) / 255, g = CGFloat(pixels[i + 1]) / 255, b = CGFloat(pixels[i + 2]) / 255
            average.r += r; average.g += g; average.b += b
            let color = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
            let saturation = color.saturationComponent, brightness = color.brightnessComponent
            guard saturation > 0.22, brightness > 0.18 else { continue }
            let bucket = min(Int(color.hueComponent * CGFloat(bucketCount)), bucketCount - 1)
            // Vivid pixels count for more than washed-out ones of the same hue.
            let w = saturation * (0.4 + brightness)
            weight[bucket] += w
            sums[bucket].r += r * w; sums[bucket].g += g * w; sums[bucket].b += b * w
        }

        let count = CGFloat(side * side)
        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > count * 0.02 else {
            // Black-and-white or near-grey cover: a neutral accent, not an invented hue.
            let grey = (average.r + average.g + average.b) / (3 * count)
            return NSColor(white: max(min(grey * 1.3, 0.8), 0.45), alpha: 1)
        }

        let w = weight[best]
        let dominant = NSColor(srgbRed: sums[best].r / w, green: sums[best].g / w, blue: sums[best].b / w, alpha: 1)
        // Normalise so dark covers still glow and pale ones still read as a colour.
        return NSColor(hue: dominant.hueComponent,
                       saturation: min(max(dominant.saturationComponent * 1.15, 0.45), 0.95),
                       brightness: max(min(dominant.brightnessComponent * 1.2, 0.95), 0.55),
                       alpha: 1)
    }
}
