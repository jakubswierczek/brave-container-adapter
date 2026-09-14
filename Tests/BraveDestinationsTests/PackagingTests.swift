import AppPackaging
@testable import BraveDestinations
import Foundation
import Testing

@Test @MainActor func standaloneBundleUpdatePreservesIdentityAndUnrelatedApps() async throws {
    let f = try Fixture()
    let directory = f.root.appendingPathComponent("Generated")
    let unrelated = directory.appendingPathComponent("Unrelated.app")
    try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
    let marker = unrelated.appendingPathComponent("keep.txt")
    try Data("keep".utf8).write(to: marker)
    let config = try DestinationConfiguration(destination: f.destination, displayName: "Brave — Work (Test)")
    let app = try await AppGenerator.generate(configuration: config, receiver: URL(fileURLWithPath: "/usr/bin/true"), directory: directory)
    let info = try #require(NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")))
    #expect(info["LSUIElement"] as? Bool == true)
    #expect(info["CFBundleIdentifier"] as? String == config.destination.bundleIdentifier)
    #expect((info["CFBundleURLTypes"] as? [[String: Any]])?.first?["CFBundleURLSchemes"] as? [String] == ["http", "https"])
    #expect(FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/ContainerReceiver").path))
    let icon = try Data(contentsOf: app.appendingPathComponent("Contents/Resources/Destination.icns"))
    #expect(String(data: icon.prefix(4), encoding: .utf8) == "icns")
    let renamed = DestinationConfiguration(destination: config.destination, displayName: "Brave — Renamed (Test)")
    let updated = try await AppGenerator.generate(configuration: renamed, receiver: URL(fileURLWithPath: "/usr/bin/true"), directory: directory)
    #expect(updated == app)
    #expect(try DestinationConfiguration.read(from: app.appendingPathComponent("Contents/Resources/destination.json")) == renamed)
    #expect(try String(contentsOf: marker, encoding: .utf8) == "keep")
    // A similarly named app without ownership metadata must not be overwritten.
    try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/Resources/destination.json"))
    await #expect(throws: AdapterError.self) {
        try await AppGenerator.generate(configuration: config, receiver: URL(fileURLWithPath: "/usr/bin/true"), directory: directory)
    }
}

@Test @MainActor func generationNeverWritesInsideBrowserData() async throws {
    let f = try Fixture()
    let config = try DestinationConfiguration(destination: f.destination, displayName: "Test")
    await #expect(throws: AdapterError.self) {
        try await AppGenerator.generate(configuration: config, receiver: URL(fileURLWithPath: "/usr/bin/true"),
                                  directory: URL(fileURLWithPath: f.paths.userData).appendingPathComponent("Apps"))
    }
}
