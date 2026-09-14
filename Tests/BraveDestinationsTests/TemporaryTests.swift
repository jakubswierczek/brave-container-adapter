import AppPackaging
@testable import BraveDestinations
import Foundation
import Testing

private extension Fixture {
    func installBrave(version: String = "153.1.95.101") throws {
        let contents = URL(fileURLWithPath: paths.application).appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: paths.executable.path) {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: paths.executable)
        }
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "Brave Browser", "CFBundleShortVersionString": version], format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
    }

    var temporary: Destination {
        get throws { try Destination(paths: paths, profileDirectory: "Default", selection: .temporary) }
    }
}

@Test func legacyConfigurationKeepsItsOriginalIdentityAndSchema() throws {
    let data = Data(#"{"formatVersion":1,"displayName":"Brave — Work","destination":{"paths":{"application":"/Applications/Synthetic Brave.app","userData":"/Library/CBC Synthetic Data"},"profileDirectory":"Default","containerID":"test-work"}}"#.utf8)
    let config = try JSONDecoder().decode(DestinationConfiguration.self, from: data)
    #expect(config.destination.selection == .configured(id: "test-work"))
    #expect(config.destination.bundleIdentifier == "app.choosy-brave-containers.destination.d5bc86cc5e88b7af3c73be7085b7e2a3958a14afdb5a0f34eec627347ff933159")
    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
    #expect(encoded["formatVersion"] as? Int == 1)
    let destination = encoded["destination"] as! [String: Any]
    #expect(destination["mode"] == nil)
    #expect(destination["containerID"] as? String == "test-work")
}

@Test func temporaryIdentityIsStableAndDistinctAcrossDestinationDimensions() throws {
    let f = try Fixture()
    let original = try f.temporary
    let variants = [
        try Destination(paths: f.paths, profileDirectory: "Profile 1", selection: .temporary),
        try Destination(paths: BravePaths(application: f.paths.application + "2", userData: f.paths.userData), profileDirectory: "Default", selection: .temporary),
        try Destination(paths: BravePaths(application: f.paths.application, userData: f.paths.userData + "2"), profileDirectory: "Default", selection: .temporary),
        try Destination(paths: f.paths, profileDirectory: "Default", containerID: "temporary"),
    ]
    #expect(variants.allSatisfy { $0.bundleIdentifier != original.bundleIdentifier })
    #expect(Set(variants.map(\.bundleIdentifier)).count == variants.count)
    let decoded = try JSONDecoder().decode(Destination.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
    #expect(decoded.bundleIdentifier == original.bundleIdentifier)
}

@Test func temporaryNeedsEnabledProfileButNoConfiguredContainerList() throws {
    let f = try Fixture()
    try f.installBrave()
    try f.editContainers { $0.removeValue(forKey: "list") }
    let resolved = try f.discovery.resolve(f.temporary)
    #expect(resolved.profile.directory == "Default")
    #expect(resolved.container.id == nil)
    #expect(resolved.displayName.hasPrefix("Brave — Temporary"))
    #expect(throws: AdapterError.self) { try f.discovery.resolve(f.destination) }
    try f.editContainers { $0["enabled"] = false }
    #expect(throws: AdapterError.self) { try f.discovery.resolve(f.temporary) }
}

@Test func temporaryDoesNotReuseNamedOrRetainedContainers() throws {
    let f = try Fixture()
    try f.installBrave()
    try f.editContainers { c in
        var list = c["list"] as! [[String: Any]]
        list[0]["name"] = "Temporary"
        list[1]["name"] = "Temporary"
        c["list"] = list
        var used = c["used"] as! [String: [String: Any]]
        used["t-existing"] = ["id": "t-existing", "name": "Temporary", "icon": 0, "background_color": 0]
        c["used"] = used
    }
    let urls = try ["https://example.com/a%2Fb?q=zażółć#x", "https://example.com/two", "https://example.com/two"].map(WebURL.init)
    for _ in 0..<2 {
        let request = try LaunchRequest(resolved: f.discovery.resolve(f.temporary), urls: urls)
        #expect(request.arguments == ["--user-data-dir=\(f.paths.userData)", "--profile-directory=Default", "--temporary-container", "--"] + urls.map(\.original))
        #expect(!request.arguments.contains(where: { $0.hasPrefix("--container=") }))
    }
}

@Test(arguments: ["150.1.92.140", "152.1.94.121", "153.1.95.100"])
func temporaryRejectsUnsupportedBraveWithoutBlockingConfiguredDestinations(_ version: String) throws {
    let f = try Fixture()
    try f.installBrave(version: version)
    #expect(try !BraveInstallation(paths: f.paths).supportsTemporaryContainers)
    #expect(try f.discovery.resolve(f.destination).container.name == "Work")
    #expect(throws: AdapterError.self) { try f.discovery.resolve(f.temporary) }
}

@Test(arguments: ["1.95.101", "153.1.95.101", "154.1.96.1"])
func temporaryAcceptsSupportedBraveVersionFormats(_ version: String) throws {
    let f = try Fixture()
    try f.installBrave(version: version)
    #expect(try BraveInstallation(paths: f.paths).supportsTemporaryContainers)
    #expect(try f.discovery.resolve(f.temporary).container.id == nil)
}

@Test func temporaryRechecksVersionAndProfileBeforeEachRequest() throws {
    let f = try Fixture()
    try f.installBrave()
    _ = try f.discovery.resolve(f.temporary)
    try f.installBrave(version: "150.1.92.140")
    #expect(throws: AdapterError.self) { try f.discovery.resolve(f.temporary) }
    try f.installBrave()
    let missing = try Destination(paths: f.paths, profileDirectory: "Missing", selection: .temporary)
    #expect(throws: AdapterError.self) { try f.discovery.resolve(missing) }
    let file = URL(fileURLWithPath: f.paths.userData).appendingPathComponent("Local State")
    var state = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
    state["browser"] = ["enabled_labs_experiments": ["containers@2"]]
    try JSONSerialization.data(withJSONObject: state).write(to: file)
    #expect(throws: AdapterError.self) { try f.discovery.resolve(f.temporary) }
}

@Test(arguments: ["{", "{}"])
func temporaryRejectsMalformedOrUnsavedPreferences(_ contents: String) throws {
    let f = try Fixture()
    try f.installBrave()
    try Data(contents.utf8).write(to: f.preferenceURL)
    #expect(throws: AdapterError.self) { try f.discovery.resolve(f.temporary) }
}

@Test @MainActor func temporaryBundleStoresModeWithoutEphemeralIDAndUpdatesInPlace() throws {
    let f = try Fixture()
    let config = try DestinationConfiguration(destination: f.temporary, displayName: "Brave — Temporary")
    let output = f.root.appendingPathComponent("Generated")
    let receiver = URL(fileURLWithPath: "/usr/bin/true")
    let app = try AppGenerator.generate(configuration: config, receiver: receiver, directory: output)
    let file = app.appendingPathComponent("Contents/Resources/destination.json")
    #expect(try DestinationConfiguration.read(from: file) == config)
    var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
    let destination = json["destination"] as! [String: Any]
    #expect(json["formatVersion"] as? Int == 2)
    #expect(destination["mode"] as? String == "temporary")
    #expect(destination["containerID"] == nil)
    #expect(try AppGenerator.generate(configuration: config, receiver: receiver, directory: output) == app)
    json["formatVersion"] = 1
    try JSONSerialization.data(withJSONObject: json).write(to: file)
    #expect(throws: AdapterError.self) { try DestinationConfiguration.read(from: file) }
}

@Test(arguments: ["unknown", "temporary"])
func conflictingOrUnknownDestinationModesFailClosed(_ mode: String) throws {
    let f = try Fixture()
    let config = try DestinationConfiguration(destination: f.destination, displayName: "Test")
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
    var destination = json["destination"] as! [String: Any]
    destination["mode"] = mode
    json["destination"] = destination
    let file = f.root.appendingPathComponent("destination.json")
    try JSONSerialization.data(withJSONObject: json).write(to: file)
    #expect(throws: AdapterError.self) { try DestinationConfiguration.read(from: file) }
}
