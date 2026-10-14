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

    /// Average the cover down to a single pixel, then push saturation up so that muted
    /// covers still produce a colour rather than a grey smudge.
    private static func accentColor(from image: NSImage, context: CIContext) -> NSColor {
        guard let tiff = image.tiffRepresentation,
              let ciImage = CIImage(data: tiff) else { return .systemPink }

        let extent = ciImage.extent
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ]), let output = filter.outputImage else { return .systemPink }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(output,
                       toBitmap: &bitmap,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        let base = NSColor(srgbRed: CGFloat(bitmap[0]) / 255,
                           green: CGFloat(bitmap[1]) / 255,
                           blue: CGFloat(bitmap[2]) / 255,
                           alpha: 1)

        guard let hsb = base.usingColorSpace(.sRGB) else { return base }
        return NSColor(hue: hsb.hueComponent,
                       saturation: min(hsb.saturationComponent * 1.6 + 0.15, 1),
                       brightness: max(min(hsb.brightnessComponent * 1.25, 0.95), 0.45),
                       alpha: 1)
    }
}
