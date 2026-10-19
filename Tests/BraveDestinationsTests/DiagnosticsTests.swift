import AppPackaging
@testable import BraveDestinations
import Foundation
import Testing

@Test func diagnosticsDescribeConfiguredRecords() throws {
    let f = try Fixture()
    let report = Diagnostics.report(paths: f.paths)
    #expect(report.contains("Profile: Default"))
    #expect(report.contains("Profile: Profile 1"))
    #expect(report.contains("enabled: true"))
    #expect(report.contains("configured count: 2"))
    #expect(report.contains("list record shape: background_color: number, icon: number, id: string, name: string (count: 2)"))
}

@Test func diagnosticsExposeSchemaDriftWithoutValues() throws {
    let f = try Fixture()
    try f.editContainers { containers in
        var list = containers["list"] as! [[String: Any]]
        list[0]["icon"] = "synthetic_icon_DO_NOT_LOG"
        containers["list"] = list
        containers["private_string"] = "synthetic_private_value_DO_NOT_LOG"
    }
    let report = Diagnostics.report(paths: f.paths)
    #expect(report.contains("strict decode: typeMismatch"))
    #expect(report.contains("coding path: brave.containers.list[0].icon"))
    #expect(report.contains("expected type: Int"))
    #expect(report.contains("Discovery.containers error: Cannot read valid Preferences metadata."))
    #expect(report.contains("private_string: string (length:"))
    #expect(!report.contains("synthetic_icon_DO_NOT_LOG"))
    #expect(!report.contains("synthetic_private_value_DO_NOT_LOG"))
}

@Test func diagnosticsFindRenamedContainerKeys() throws {
    let f = try Fixture()
    let json: [String: Any] = ["brave": ["container_profiles_v9": ["private": "synthetic_private_value_DO_NOT_LOG"]]]
    try JSONSerialization.data(withJSONObject: json).write(to: f.preferenceURL)
    let report = Diagnostics.report(paths: f.paths)
    #expect(report.contains("brave.containers: absent"))
    #expect(report.contains("key: brave.container_profiles_v9: object"))
    #expect(!report.contains("synthetic_private_value_DO_NOT_LOG"))
}

@Test func diagnosticsHandleMalformedPreferences() throws {
    let f = try Fixture()
    try Data("{ synthetic_private_value_DO_NOT_LOG".utf8).write(to: f.preferenceURL)
    let report = Diagnostics.report(paths: f.paths)
    #expect(report.contains("JSON parses: false"))
    #expect(report.contains("strict decode: dataCorrupted"))
    #expect(!report.contains("synthetic_private_value_DO_NOT_LOG"))
}

@Test func diagnosticsHandleMissingLocations() throws {
    let f = try Fixture()
    let paths = BravePaths(application: f.root.appendingPathComponent("missing.app").path,
                           userData: f.root.appendingPathComponent("missing-data").path)
    let report = Diagnostics.report(paths: paths)
    #expect(report.contains("application exists: false"))
    #expect(report.contains("userData exists: false"))
    #expect(report.contains("Info.plist error:"))
    #expect(report.contains("BraveInstallation error:"))
    #expect(report.contains("explicitlyDisabledFeature error:"))
    #expect(report.contains("ready destinations: 0 (scan failed)"))
}

@Test func diagnosticsRedactHomeEverywhere() {
    let home = NSHomeDirectory()
    #expect(Diagnostics.redactHome(home + "/diagnostic-test") == "~/diagnostic-test")
    let report = Diagnostics.report(paths: BravePaths(application: home + "/cbc-missing.app", userData: home + "/cbc-missing-data"))
    #expect(report.contains("application: ~/cbc-missing.app"))
    #expect(!report.contains(home))
}

@Test func diagnosticsDecodeMissingAndNullFields() throws {
    let missing = Data(#"{"brave":{"containers":{"list":[{"id":"id","name":"Name","background_color":0}]}}}"#.utf8)
    #expect(Diagnostics.strictDecode(missing).contains("  strict decode: keyNotFound"))
    #expect(Diagnostics.strictDecode(missing).contains("  coding path: brave.containers.list[0].icon"))
    let null = Data(#"{"brave":{"containers":{"list":[{"id":"id","name":"Name","icon":null,"background_color":0}]}}}"#.utf8)
    #expect(Diagnostics.strictDecode(null).contains("  strict decode: valueNotFound"))
    #expect(Diagnostics.strictDecode(null).contains("  expected type: Int"))
}

@Test func diagnosticsBoundKeySearch() throws {
    let f = try Fixture()
    let brave = Dictionary(uniqueKeysWithValues: (0..<25).map { ("container_key_\($0)", "synthetic_private_value_DO_NOT_LOG") })
    try JSONSerialization.data(withJSONObject: ["brave": brave]).write(to: f.preferenceURL)
    let report = Diagnostics.report(paths: f.paths)
    #expect(report.contains("container key search: 20 hits"))
    #expect(!report.contains("synthetic_private_value_DO_NOT_LOG"))
    let nested: [String: Any] = ["brave": ["a": ["b": ["c": ["container_at_limit": true, "d": ["container_too_deep": true]]]]]]
    let lines = Diagnostics.preferenceShape(nested).joined(separator: "\n")
    #expect(lines.contains("brave.a.b.c.container_at_limit"))
    #expect(!lines.contains("container_too_deep"))
}

@Test func diagnosticsReportFlagAndDirectoryDisagreements() throws {
    let f = try Fixture()
    let root = URL(fileURLWithPath: f.paths.userData)
    let state: [String: Any] = ["profile": ["info_cache": ["Default": ["name": "Test"], "Profile 9": ["name": "Missing"]]],
                               "browser": ["enabled_labs_experiments": ["containers@2", "unrelated_private_flag", "CONTAINER-test@1"]]]
    try JSONSerialization.data(withJSONObject: state).write(to: root.appendingPathComponent("Local State"))
    let report = Diagnostics.report(paths: f.paths)
    #expect(report.contains("unlisted directory: Profile 1"))
    #expect(report.contains("info_cache entry without directory: Profile 9"))
    #expect(report.contains("flag: containers@2"))
    #expect(report.contains("flag: CONTAINER-test@1"))
    #expect(report.contains("explicitlyDisabledFeature: true"))
    #expect(!report.contains("unrelated_private_flag"))
}

@Test func sharedScanCollectsAllDestinationFailures() throws {
    let f = try Fixture()
    try makeDiagnosticBrowser(f)
    try f.editContainers { containers in
        var list = containers["list"] as! [[String: Any]]
        list[1]["name"] = list[0]["name"]
        containers["list"] = list
    }
    let scan = try f.discovery.scan()
    #expect(scan.destinations.count == 4)
    #expect(scan.problems.count == 2)
    #expect(scan.problems.allSatisfy { $0.contains("Multiple configured containers have the same name") })
    #expect(Diagnostics.report(paths: f.paths).contains("ready destinations: 4"))
}

@Test func sharedScanReportsDisabledAndUnsavedList() throws {
    let f = try Fixture()
    try makeDiagnosticBrowser(f)
    try f.editContainers { $0["enabled"] = false; $0.removeValue(forKey: "list") }
    let scan = try f.discovery.scan()
    #expect(scan.problems.count == 2)
    #expect(scan.destinations.count == 3)
}

@Test func diagnosticsRejectEscapingProfileSymlink() throws {
    let f = try Fixture()
    let profile = URL(fileURLWithPath: f.paths.userData).appendingPathComponent("Default")
    try FileManager.default.removeItem(at: profile)
    try FileManager.default.createSymbolicLink(at: profile, withDestinationURL: f.root)
    try Data("{ synthetic_private_value_DO_NOT_LOG".utf8).write(to: f.root.appendingPathComponent("Preferences"))
    let report = Diagnostics.report(paths: f.paths)
    #expect(report.contains("Preferences error: Profile directory resolves outside"))
    #expect(!report.contains("synthetic_private_value_DO_NOT_LOG"))
}

@Test func installedDiagnosticsIncludeBrokenManagedAppsAndSkipStaging() throws {
    let f = try Fixture()
    let directory = f.root.appendingPathComponent("apps")
    for name in ["Managed.app", ".cbc-staging.app", "Unrelated.app"] {
        let app = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CBCManagedBundle": name != "Unrelated.app"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
    }
    let installed = AppGenerator.installedApps(directories: [directory])
    #expect(installed.apps.map(\.lastPathComponent) == ["Managed.app"])
    let report = Diagnostics.report(paths: f.paths, installedApps: installed.apps)
    #expect(report.contains("Managed.app"))
    #expect(report.contains("read error: Cannot open the file for a safe read."))
    #expect(!report.contains(".cbc-staging.app"))
}

@Test func diagnosticsDescribeInstalledSelectionsAndPathMismatch() throws {
    let f = try Fixture()
    let app = f.root.appendingPathComponent("Synthetic.app")
    let resources = app.appendingPathComponent("Contents/Resources")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    for selection in [ContainerSelection.configured(id: "test-work"), .temporary] {
        let destination = try Destination(paths: f.paths, profileDirectory: "Default", selection: selection)
        let saved = DestinationConfiguration(destination: destination, displayName: "Synthetic app")
        try JSONEncoder().encode(saved).write(to: resources.appendingPathComponent("destination.json"))
        let info: [String: Any] = ["CBCManagedBundle": true, "CFBundleIdentifier": destination.bundleIdentifier]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let report = Diagnostics.report(paths: f.paths, installedApps: [app])
        #expect(report.contains("display name: Synthetic app"))
        #expect(report.contains("profile directory: Default"))
        #expect(report.contains("selection: " + (selection == .temporary ? "temporary" : "configured test-work")))
        #expect(report.contains("bundle id: " + destination.bundleIdentifier))
        #expect(report.contains("saved paths match: true"))
        let other = BravePaths(application: f.paths.application, userData: f.paths.userData + "-missing")
        #expect(Diagnostics.report(paths: other, installedApps: [app]).contains("saved paths match: false"))
    }
}

private func makeDiagnosticBrowser(_ f: Fixture) throws {
    let app = URL(fileURLWithPath: f.paths.application)
    try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: f.paths.executable)
    let info = ["CFBundleExecutable": "Brave Browser", "CFBundleShortVersionString": "153.1.95.101"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: app.appendingPathComponent("Contents/Info.plist"))
}
