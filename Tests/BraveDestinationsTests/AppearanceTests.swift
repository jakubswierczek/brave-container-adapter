import AppKit
import AppPackaging
@testable import BraveDestinations
import ImageIO
import Testing

@Test @MainActor func explicitRenameRemovesLegacySuffixWithoutChangingRouting() throws {
    let f = try Fixture()
    let directory = f.root.appendingPathComponent("Apps")
    let receiver = URL(fileURLWithPath: "/usr/bin/true")
    let config = try DestinationConfiguration(destination: f.destination, displayName: "Brave — Work (Test · Default)")
    let original = try AppGenerator.generate(configuration: config, receiver: receiver, directory: directory)
    let legacy = directory.appendingPathComponent("Brave — Work (Test _ Default) [123456789abc].app")
    try FileManager.default.moveItem(at: original, to: legacy)
    let before = try LaunchRequest(resolved: f.discovery.resolve(config.destination), urls: [WebURL("https://example.com/?x=1#two")])
    let renamed = DestinationConfiguration(destination: config.destination, displayName: "Brave — Work")
    let updated = try AppGenerator.generate(configuration: renamed, receiver: receiver, directory: directory, rename: true)
    #expect(updated.lastPathComponent == "Brave — Work.app")
    #expect(!FileManager.default.fileExists(atPath: legacy.path))
    let saved = try AppGenerator.readManagedApp(updated)
    #expect(saved == renamed)
    #expect(saved.destination.bundleIdentifier == config.destination.bundleIdentifier)
    let after = try LaunchRequest(resolved: f.discovery.resolve(saved.destination), urls: [WebURL("https://example.com/?x=1#two")])
    #expect(before.arguments == after.arguments)
    #expect(try AppGenerator.generate(configuration: renamed, receiver: receiver, directory: directory, rename: true) == updated)
}

@Test @MainActor func renameCollisionPreservesBothAppsAndOriginalIcon() throws {
    let f = try Fixture()
    let directory = f.root.appendingPathComponent("Apps")
    let receiver = URL(fileURLWithPath: "/usr/bin/true")
    let config = try DestinationConfiguration(destination: f.destination, displayName: "Original")
    let app = try AppGenerator.generate(configuration: config, receiver: receiver, directory: directory, icon: .generated(.work))
    let originalIcon = try Data(contentsOf: app.appendingPathComponent("Contents/Resources/Destination.icns"))
    let other = directory.appendingPathComponent("Occupied.app")
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    try Data("unrelated".utf8).write(to: other.appendingPathComponent("keep"))
    #expect(throws: AdapterError.self) {
        try AppGenerator.generate(configuration: DestinationConfiguration(destination: config.destination, displayName: "Occupied"),
                                  receiver: receiver, directory: directory, icon: .generated(.personal), rename: true)
    }
    #expect(try AppGenerator.readManagedApp(app) == config)
    #expect(try Data(contentsOf: app.appendingPathComponent("Contents/Resources/Destination.icns")) == originalIcon)
    #expect(try String(contentsOf: other.appendingPathComponent("keep"), encoding: .utf8) == "unrelated")
}

@Test @MainActor func importedIconIsStandaloneAndSurvivesNameOnlyUpdate() throws {
    let f = try Fixture()
    let source = f.root.appendingPathComponent("private-image-name.png")
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 32,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let bytes = try #require(bitmap.bitmapData)
    for y in 0..<32 {
        for x in 0..<64 {
            let offset = y * bitmap.bytesPerRow + x * 4
            bytes[offset] = x < 32 ? 255 : 0
            bytes[offset + 1] = 0
            bytes[offset + 2] = x < 32 ? 0 : 255
            bytes[offset + 3] = 255
        }
    }
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: source)
    let imported = try DestinationIcons.importImage(at: source)
    try FileManager.default.removeItem(at: source)
    let config = try DestinationConfiguration(destination: f.destination, displayName: "Custom")
    let data = try DestinationIcons.data(for: imported, configuration: config)
    let imageSource = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
    let pixels = NSBitmapImageRep(cgImage: image)
    #expect(try #require(pixels.colorAt(x: pixels.pixelsWide / 2, y: 0)).alphaComponent == 0)
    let left = try #require(pixels.colorAt(x: pixels.pixelsWide / 4, y: pixels.pixelsHigh / 2))
    let right = try #require(pixels.colorAt(x: pixels.pixelsWide * 3 / 4, y: pixels.pixelsHigh / 2))
    #expect(left.redComponent > 0.9)
    #expect(right.blueComponent > 0.9)
    let directory = f.root.appendingPathComponent("Apps")
    let receiver = URL(fileURLWithPath: "/usr/bin/true")
    let app = try AppGenerator.generate(configuration: config, receiver: receiver, directory: directory, icon: imported)
    let renamed = DestinationConfiguration(destination: config.destination, displayName: "Renamed")
    let updated = try AppGenerator.generate(configuration: renamed, receiver: receiver, directory: directory, rename: true)
    #expect(try Data(contentsOf: updated.appendingPathComponent("Contents/Resources/Destination.icns")) == data)
    #expect(!FileManager.default.fileExists(atPath: app.path))
    let appearance = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: updated.appendingPathComponent("Contents/Resources/appearance.json")))
    #expect(appearance == ["iconPreset": "custom"])
}

@Test @MainActor func generatedPresetsAreDistinctAndRestoreTheirSelection() throws {
    let f = try Fixture()
    let config = try DestinationConfiguration(destination: f.destination, displayName: "Test")
    var outputs = Set<Data>()
    for preset in IconPreset.allCases {
        let data = try DestinationIcons.data(for: .generated(preset), configuration: config)
        #expect(NSImage(data: data) != nil)
        outputs.insert(data)
    }
    #expect(outputs.count == IconPreset.allCases.count)
    let app = try AppGenerator.generate(configuration: config, receiver: URL(fileURLWithPath: "/usr/bin/true"),
                                       directory: f.root.appendingPathComponent("Apps"), icon: .generated(.layers))
    guard case .generated(.layers) = try AppGenerator.savedIcon(at: app) else {
        Issue.record("Generated icon choice was not restored"); return
    }
}

@Test @MainActor func invalidImageAndUnsafeNamesLeaveExistingAppIntact() throws {
    let f = try Fixture()
    let bad = f.root.appendingPathComponent("bad.png")
    try Data("not an image".utf8).write(to: bad)
    #expect(throws: AdapterError.self) { try DestinationIcons.importImage(at: bad) }
    let config = try DestinationConfiguration(destination: f.destination, displayName: "Original")
    let directory = f.root.appendingPathComponent("Apps")
    let receiver = URL(fileURLWithPath: "/usr/bin/true")
    let app = try AppGenerator.generate(configuration: config, receiver: receiver, directory: directory)
    for name in ["../escape", ".hidden", "bad:name", "", "bad\nname", String(repeating: "é", count: 121)] {
        #expect(throws: AdapterError.self) {
            try AppGenerator.generate(configuration: DestinationConfiguration(destination: config.destination, displayName: name),
                                      receiver: receiver, directory: directory, rename: true)
        }
    }
    #expect(try AppGenerator.readManagedApp(app) == config)
}

@Test @MainActor func editorRejectsUnrelatedAppsAndSymlinks() throws {
    let f = try Fixture()
    let config = try DestinationConfiguration(destination: f.destination, displayName: "Original")
    let directory = f.root.appendingPathComponent("Apps")
    let app = try AppGenerator.generate(configuration: config, receiver: URL(fileURLWithPath: "/usr/bin/true"), directory: directory)
    let link = directory.appendingPathComponent("Link.app")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: app)
    #expect(throws: AdapterError.self) { try AppGenerator.readManagedApp(link) }
    try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/Resources/destination.json"))
    #expect(throws: AdapterError.self) { try AppGenerator.readManagedApp(app) }
}
