import AppKit
import AppPackaging
@testable import BraveDestinations
import Foundation
import Testing

final class Fixture {
    let root: URL
    let paths: BravePaths
    let discovery: Discovery

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("cbc-unit-\(UUID())")
        paths = BravePaths(application: root.appendingPathComponent("Brave Browser.app").path,
                           userData: root.appendingPathComponent("Data").path)
        discovery = Discovery(paths: paths)
        let resources = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
        for directory in ["Default", "Profile 1"] {
            let profile = URL(fileURLWithPath: paths.userData).appendingPathComponent(directory)
            try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: resources.appendingPathComponent("Preferences.json"),
                                            to: profile.appendingPathComponent("Preferences"))
        }
        try FileManager.default.copyItem(at: resources.appendingPathComponent("Local State.json"),
                                        to: URL(fileURLWithPath: paths.userData).appendingPathComponent("Local State"))
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    var preferenceURL: URL { URL(fileURLWithPath: paths.userData).appendingPathComponent("Default/Preferences") }
    var destination: Destination { get throws { try Destination(paths: paths, profileDirectory: "Default", containerID: "test-work") } }

    func editContainers(_ edit: (inout [String: Any]) -> Void) throws {
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: preferenceURL)) as! [String: Any]
        var brave = json["brave"] as! [String: Any]
        var containers = brave["containers"] as! [String: Any]
        edit(&containers)
        brave["containers"] = containers
        json["brave"] = brave
        try JSONSerialization.data(withJSONObject: json).write(to: preferenceURL, options: .atomic)
    }
}

@Test func profileDirectoryIsSeparateFromDisplayName() throws {
    let f = try Fixture()
    let profiles = try f.discovery.profiles()
    #expect(profiles.map(\.directory) == ["Default", "Profile 1"])
    #expect(profiles.last?.displayName == "Engineering")
    let d = try Destination(paths: f.paths, profileDirectory: "Profile 1", containerID: "test-work")
    #expect(try f.discovery.resolve(d).profile.directory == "Profile 1")
    #expect(throws: AdapterError.self) {
        try f.discovery.resolve(Destination(paths: f.paths, profileDirectory: "Engineering", containerID: "test-work"))
    }
}

@Test func configuredAndRetainedRecordsStaySeparate() throws {
    let f = try Fixture()
    let snapshot = try f.discovery.containers(profileDirectory: "Default")
    #expect(snapshot.configured?.count == 2)
    #expect(snapshot.retained.count == 2)
    #expect(try f.discovery.resolve(f.destination).container.name == "Work")
    #expect(throws: AdapterError.self) {
        try f.discovery.resolve(Destination(paths: f.paths, profileDirectory: "Default", containerID: "test-retained"))
    }
}

@Test func renameKeepsIdentityAndUsesFreshName() throws {
    let f = try Fixture()
    let d = try f.destination
    let originalID = d.bundleIdentifier
    #expect(try f.discovery.resolve(d).container.name == "Work")
    try f.editContainers { c in
        var list = c["list"] as! [[String: Any]]
        list[0]["name"] = "Praca 日本語"
        c["list"] = list
    }
    let resolved = try f.discovery.resolve(d)
    #expect(resolved.container.name == "Praca 日本語")
    #expect(d.bundleIdentifier == originalID)
    #expect(try LaunchRequest(resolved: resolved, urls: [WebURL("https://example.com")]).arguments.contains("--container=Praca 日本語"))
}

@Test func deletedContainerDoesNotUseStaleRetainedSnapshot() throws {
    let f = try Fixture()
    try f.editContainers { c in c["list"] = (c["list"] as! [[String: Any]]).filter { $0["id"] as? String != "test-work" } }
    #expect(throws: AdapterError.self) { try f.discovery.resolve(f.destination) }
}

@Test func duplicateNamesAreRejectedButRetainedNamesDoNotShadowConfiguredNames() throws {
    let f = try Fixture()
    try f.editContainers { c in
        var used = c["used"] as! [String: [String: Any]]
        used["test-retained"]?["name"] = "Work"
        c["used"] = used
    }
    // Brave searches configured list first. A retained-only name cannot shadow it.
    #expect(try f.discovery.resolve(f.destination).container.id == "test-work")
    try f.editContainers { c in
        var list = c["list"] as! [[String: Any]]
        list[1]["name"] = "Work"
        c["list"] = list
    }
    #expect(throws: AdapterError.self) { try f.discovery.resolve(f.destination) }
}

@Test func duplicateIDsAndBadRetainedKeysFailClosed() throws {
    let f = try Fixture()
    try f.editContainers { c in
        var list = c["list"] as! [[String: Any]]; list.append(list[0]); c["list"] = list
    }
    #expect(throws: AdapterError.self) { try f.discovery.containers(profileDirectory: "Default") }
    let g = try Fixture()
    try g.editContainers { c in
        var used = c["used"] as! [String: [String: Any]]
        used["test-work"]?["id"] = "wrong-key"; c["used"] = used
    }
    #expect(throws: AdapterError.self) { try g.discovery.containers(profileDirectory: "Default") }
}

@Test func missingDefaultsAreNotInventedFromUsedRecords() throws {
    let f = try Fixture()
    try f.editContainers { $0.removeValue(forKey: "list") }
    #expect(try f.discovery.containers(profileDirectory: "Default").configured == nil)
    #expect(throws: AdapterError.self) { try f.discovery.resolve(f.destination) }
}

@Test(arguments: ["false", "null", "missing"])
func disabledOrUnsavedEnabledPreferenceIsRejected(_ mode: String) throws {
    let f = try Fixture()
    try f.editContainers { c in
        if mode == "missing" { c.removeValue(forKey: "enabled") }
        else { c["enabled"] = mode == "false" ? false : NSNull() }
    }
    #expect(throws: AdapterError.self) { try f.discovery.resolve(f.destination) }
}

@Test(arguments: ["{", "[]", "null", "{\"brave\":42}", "{\"brave\":{\"containers\":{\"list\":{}}}}"])
func malformedPreferencesDoNotLeakContents(_ contents: String) throws {
    let f = try Fixture()
    try Data(contents.utf8).write(to: f.preferenceURL)
    do { _ = try f.discovery.containers(profileDirectory: "Default"); Issue.record("Expected malformed metadata error") }
    catch let error as AdapterError { #expect(error.message.hasPrefix("Cannot read valid Preferences metadata.")) }
}

@Test func incompleteContainerRecordIsRejected() throws {
    let f = try Fixture()
    try f.editContainers { $0["list"] = [["id": "test-work", "name": "Work"]] }
    #expect(throws: AdapterError.self) { try f.discovery.resolve(f.destination) }
}

@Test func missingFilesAndEmptyPreferencesAreHandled() throws {
    let f = try Fixture()
    try Data("{}".utf8).write(to: f.preferenceURL)
    #expect(try !f.discovery.containers(profileDirectory: "Default").enabled)
    try FileManager.default.removeItem(at: f.preferenceURL)
    #expect(throws: AdapterError.self) { try f.discovery.containers(profileDirectory: "Default") }
    try FileManager.default.removeItem(at: URL(fileURLWithPath: f.paths.userData).appendingPathComponent("Local State"))
    #expect(throws: AdapterError.self) { try f.discovery.profiles() }
}

@Test func malformedProfileMetadataAndDisabledFeatureAreRejected() throws {
    let f = try Fixture()
    let file = URL(fileURLWithPath: f.paths.userData).appendingPathComponent("Local State")
    try Data("{\"profile\":{\"info_cache\":{\"../elsewhere\":{\"name\":\"Invalid\"}}}}".utf8).write(to: file)
    #expect(throws: AdapterError.self) { try f.discovery.profiles() }
    try Data("{\"profile\":{\"info_cache\":{\"Default\":{\"name\":\"Test\"}}},\"browser\":{\"enabled_labs_experiments\":[\"containers@2\"]}}".utf8).write(to: file)
    #expect(throws: AdapterError.self) { try f.discovery.resolve(f.destination) }
}

@Test func pathTraversalAndEscapingProfileSymlinksAreRejected() throws {
    let f = try Fixture()
    #expect(throws: AdapterError.self) { try Destination(paths: f.paths, profileDirectory: "../bad", containerID: "id") }
    let profile = URL(fileURLWithPath: f.paths.userData).appendingPathComponent("Profile 1")
    try FileManager.default.removeItem(at: profile)
    try FileManager.default.createSymbolicLink(at: profile, withDestinationURL: f.root)
    #expect(throws: AdapterError.self) { try f.discovery.containers(profileDirectory: "Profile 1") }
}

@Test func everyDestinationDimensionChangesIdentity() throws {
    let f = try Fixture()
    let original = try f.destination.bundleIdentifier
    let variants = [
        try Destination(paths: f.paths, profileDirectory: "Profile 1", containerID: "test-work"),
        try Destination(paths: f.paths, profileDirectory: "Default", containerID: "test-personal"),
        try Destination(paths: BravePaths(application: f.paths.application + "2", userData: f.paths.userData), profileDirectory: "Default", containerID: "test-work"),
        try Destination(paths: BravePaths(application: f.paths.application, userData: f.paths.userData + "2"), profileDirectory: "Default", containerID: "test-work"),
    ]
    #expect(variants.allSatisfy { $0.bundleIdentifier != original })
    #expect(Set(variants.map(\.bundleIdentifier)).count == 4)
}

@Test func partialWriteIsRetriedUntilValidMetadataArrives() throws {
    let f = try Fixture()
    let file = f.preferenceURL
    struct Revision: Decodable { let revision: Int }
    try Data("{".utf8).write(to: file)
    let reader = PreferenceReader(waitBeforeRetry: {
        // Replace the partial file at the retry boundary without a timing race
        // against the test runner's cooperative thread pool.
        try! Data("{\"revision\":2}".utf8).write(to: file, options: .atomic)
    })
    let snapshot = try reader.read(Revision.self, at: file)
    #expect(snapshot.revision == 2)
}
