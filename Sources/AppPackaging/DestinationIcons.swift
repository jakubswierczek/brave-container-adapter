import AppKit
import BraveDestinations
import ImageIO

public enum IconPreset: String, CaseIterable, Codable, Sendable {
    case monogram, work, personal, web, layers, temporary

    public var title: String { rawValue.capitalized }

    var letters: String? {
        switch self {
        case .monogram: nil
        case .work: "WK"
        case .personal: "ME"
        case .web: "WEB"
        case .layers: "LYR"
        case .temporary: "NEW"
        }
    }

    var hue: CGFloat? {
        switch self {
        case .monogram: nil
        case .work: 0.59
        case .personal: 0.91
        case .web: 0.46
        case .layers: 0.73
        case .temporary: 0.08
        }
    }
}

public enum AppIcon: Sendable {
    case generated(IconPreset)
    /// Normalized ICNS bytes. No source filename or image metadata is stored.
    case custom(Data)
}

@MainActor
public enum DestinationIcons {
    public static func importImage(at url: URL) throws -> AppIcon {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 32 * 1024 * 1024 else {
            throw AdapterError("Choose an image smaller than 32 MB.")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw AdapterError("Cannot read this image. Choose a PNG, JPEG, HEIC, TIFF, or ICNS file.")
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw AdapterError("The image has no readable frames.") }
        let indexes = (CGImageSourceGetType(source) as String?) == "com.apple.icns" ? Array(0..<count) : [0]
        let index = indexes.max(by: { dimensions(source, $0).width < dimensions(source, $1).width }) ?? 0
        let pixels = dimensions(source, index)
        guard pixels.width > 0, pixels.height > 0, pixels.width <= 16384, pixels.height <= 16384,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, index, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
              ] as CFDictionary) else { throw AdapterError("Cannot decode this image. Maximum dimensions are 16384 × 16384 pixels.") }
        let image = NSImage(cgImage: thumbnail, size: .zero)
        return .custom(try encode { rect in
            let scale = min(rect.width / image.size.width, rect.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: NSRect(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2,
                                 width: size.width, height: size.height))
        })
    }

    public static func data(for icon: AppIcon, configuration: DestinationConfiguration) throws -> Data {
        switch icon {
        case .custom(let data):
            guard data.count <= 32 * 1024 * 1024, data.starts(with: Data("icns".utf8)), NSImage(data: data) != nil else {
                throw AdapterError("The saved app icon cannot be read. Choose another icon.")
            }
            return data
        case .generated(let preset):
            return try encode { rect in
                let s = rect.width
                let seed = CGFloat(Int(configuration.destination.bundleIdentifier.suffix(6), radix: 16) ?? 0) / CGFloat(0xffffff)
                let hue = preset.hue ?? seed
                let tile = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.08, dy: s * 0.08),
                                        xRadius: s * 0.18, yRadius: s * 0.18)
                let start = NSColor(calibratedHue: hue, saturation: 0.60, brightness: 0.96, alpha: 1)
                let end = NSColor(calibratedHue: hue, saturation: 0.84, brightness: 0.64, alpha: 1)
                NSGradient(starting: start, ending: end)?.draw(in: tile, angle: -90)
                // SF Symbols are not licensed for application icons. Use letter tiles.
                let name = configuration.displayName.replacingOccurrences(of: "Brave — ", with: "")
                let mark = (preset.letters ?? String(name.prefix(2)).uppercased()) as NSString
                let fontSize = s * (mark.length > 2 ? 0.25 : 0.36)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .bold), .foregroundColor: NSColor.white,
                ]
                let size = mark.size(withAttributes: attrs)
                mark.draw(at: NSPoint(x: (s - size.width) / 2, y: (s - size.height) / 2), withAttributes: attrs)
            }
        }
    }

    private static func dimensions(_ source: CGImageSource, _ index: Int) -> (width: Int, height: Int) {
        let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        return (props?[kCGImagePropertyPixelWidth] as? Int ?? 0, props?[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    private static func encode(draw: (NSRect) -> Void) throws -> Data {
        var chunks = Data()
        for (size, type) in [(32, "icp5"), (64, "icp6"), (128, "ic07"), (256, "ic08"), (512, "ic09"), (1024, "ic10")] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw AdapterError("Could not render the app icon.") }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            draw(NSRect(x: 0, y: 0, width: size, height: size))
            NSGraphicsContext.restoreGraphicsState()
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw AdapterError("Could not encode the app icon.") }
            chunks.append(Data(type.utf8))
            chunks.append(bigEndian: UInt32(png.count + 8))
            chunks.append(png)
        }
        var result = Data("icns".utf8)
        result.append(bigEndian: UInt32(chunks.count + 8))
        result.append(chunks)
        return result
    }
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        var value = value.bigEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
