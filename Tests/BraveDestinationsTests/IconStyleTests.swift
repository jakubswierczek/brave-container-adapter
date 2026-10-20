import AppKit
import AppPackaging
@testable import BraveDestinations
import ImageIO
import Testing

@MainActor private func rectangularIcon(in root: URL, height: Int = 60) throws -> AppIcon {
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let bytes = try #require(bitmap.bitmapData)
    for y in 0..<height {
        for x in 0..<120 {
            let offset = y * bitmap.bytesPerRow + x * 4
            bytes[offset] = 255
            bytes[offset + 1] = 0
            bytes[offset + 2] = 0
            bytes[offset + 3] = 255
        }
    }
    let url = root.appendingPathComponent("logo.png")
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    let icon = try DestinationIcons.importImage(at: url)
    try FileManager.default.removeItem(at: url)
    return icon
}

@Test(arguments: [60, 240]) @MainActor func macOSIconFillsTileAndPreservesTransparentCornersAtEverySize(height: Int) throws {
    let f = try Fixture()
    guard case .custom(let original, _) = try rectangularIcon(in: f.root, height: height) else { return }
    let config = try DestinationConfiguration(destination: f.destination, displayName: "Logo")
    let data = try DestinationIcons.data(for: .custom(original, style: .macOS), configuration: config)
    #expect(data != original)
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    #expect(CGImageSourceGetCount(source) == 6)
    for index in 0..<CGImageSourceGetCount(source) {
        let image = try #require(CGImageSourceCreateImageAtIndex(source, index, nil))
        let size = image.width
        let context = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        let bitmap = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
        #expect(size == bitmap.pixelsHigh)
        #expect(try #require(bitmap.colorAt(x: 0, y: 0)).alphaComponent == 0)
        let tile = try #require(bitmap.colorAt(x: size / 2, y: size / 5)).usingColorSpace(.deviceRGB)
        #expect(try #require(tile).redComponent > 0.9)
        #expect(try #require(tile).greenComponent < 0.1)
        #expect(try #require(tile).alphaComponent > 0.99)
        var xs: [Int] = [], ys: [Int] = []
        for y in 0..<size {
            for x in 0..<size {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if color.redComponent > 0.8 && color.greenComponent < 0.2 && color.alphaComponent > 0.9 {
                    xs.append(x); ys.append(y)
                }
            }
        }
        let width = try #require(xs.max()) - #require(xs.min()) + 1
        let height = try #require(ys.max()) - #require(ys.min()) + 1
        #expect(abs(width - height) <= 2)
        #expect(abs((try #require(xs.min()) + #require(xs.max())) - (size - 1)) <= 2)
        #expect(abs((try #require(ys.min()) + #require(ys.max())) - (size - 1)) <= 2)
    }
}

@Test @MainActor func styledIconRoundtripRetainsUntreatedImageAndDoesNotCompound() async throws {
    let f = try Fixture()
    guard case .custom(let original, _) = try rectangularIcon(in: f.root) else { return }
    let config = try DestinationConfiguration(destination: f.destination, displayName: "Styled")
    let directory = f.root.appendingPathComponent("Apps")
    let receiver = URL(fileURLWithPath: "/usr/bin/true")
    let app = try await AppGenerator.generate(configuration: config, receiver: receiver, directory: directory,
                                            icon: .custom(original, style: .macOS))
    let resources = app.appendingPathComponent("Contents/Resources")
    let rendered = try Data(contentsOf: resources.appendingPathComponent("Destination.icns"))
    for _ in 0..<2 {
        guard case .custom(let restored, let style) = try AppGenerator.savedIcon(at: app) else {
            Issue.record("Custom image was not restored"); return
        }
        #expect(restored == original)
        #expect(style == .macOS)
        _ = try await AppGenerator.generate(configuration: config, receiver: receiver, directory: directory)
        #expect(try Data(contentsOf: resources.appendingPathComponent("Destination.icns")) == rendered)
    }
    _ = try await AppGenerator.generate(configuration: config, receiver: receiver, directory: directory, icon: .custom(original))
    #expect(try Data(contentsOf: resources.appendingPathComponent("Destination.icns")) == original)
    #expect(!FileManager.default.fileExists(atPath: resources.appendingPathComponent("CustomOriginal.icns").path))
    // Legacy appearance dictionaries and apps without appearance metadata retain their exact bytes.
    for hasMetadata in [true, false] {
        if !hasMetadata { try FileManager.default.removeItem(at: resources.appendingPathComponent("appearance.json")) }
        guard case .custom(let restored, .original) = try AppGenerator.savedIcon(at: app) else {
            Issue.record("Legacy icon was not restored as Original"); return
        }
        #expect(restored == original)
    }
}

@Test @MainActor func styledIconRejectsMissingOriginalAndUnknownStyle() async throws {
    let f = try Fixture()
    guard case .custom(let original, _) = try rectangularIcon(in: f.root) else { return }
    let config = try DestinationConfiguration(destination: f.destination, displayName: "Styled")
    let app = try await AppGenerator.generate(configuration: config, receiver: URL(fileURLWithPath: "/usr/bin/true"),
        directory: f.root.appendingPathComponent("Apps"), icon: .custom(original, style: .macOS))
    let resources = app.appendingPathComponent("Contents/Resources")
    try FileManager.default.removeItem(at: resources.appendingPathComponent("CustomOriginal.icns"))
    #expect(throws: (any Error).self) { try AppGenerator.savedIcon(at: app) }
    try JSONEncoder().encode(["iconPreset": "custom", "iconStyle": "unknown"])
        .write(to: resources.appendingPathComponent("appearance.json"))
    #expect(throws: AdapterError.self) { try AppGenerator.savedIcon(at: app) }
}

@Test @MainActor func squareArtworkFillsTileAndCornerClippingIsOptional() throws {
    let f = try Fixture()
    guard case .custom(let original, _) = try rectangularIcon(in: f.root, height: 120) else { return }
    let config = try DestinationConfiguration(destination: f.destination, displayName: "Square")
    for style in CustomIconStyle.allCases {
        let data = try DestinationIcons.data(for: .custom(original, style: style), configuration: config)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let bitmap = NSBitmapImageRep(cgImage: image)
        let s = bitmap.pixelsWide
        let corner = try #require(bitmap.colorAt(x: s * 12 / 100, y: s * 12 / 100))
        #expect(style == .original ? corner.alphaComponent > 0.99 : corner.alphaComponent < 0.3)
        let edge = try #require(bitmap.colorAt(x: s / 8, y: s / 2))
        #expect(edge.redComponent > 0.9)
        #expect(edge.greenComponent < 0.1)
        #expect(edge.alphaComponent > 0.99)
    }
}
