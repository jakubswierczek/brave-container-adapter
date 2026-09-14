@testable import BraveDestinations
import Foundation
import Testing

@Test(arguments: [
    "https://example.com/a%2Fb?token=a%2Bb&x=1#part%20two",
    "https://例え.テスト/日本語?q=zażółć#fragment",
    "HTTP://example.com:8080/path?a=1&a=2#x",
    "https://example.com/?literal=$(touch%20/tmp/not-executed)&quote=';#`echo`",
])
func originalURLTextReachesArgumentArrayUnchanged(_ raw: String) throws {
    let f = try Fixture()
    let request = try LaunchRequest(resolved: f.discovery.resolve(f.destination), urls: [WebURL(raw)])
    #expect(request.arguments.last == raw)
    #expect(request.arguments[request.arguments.count - 2] == "--")
}

@Test(arguments: ["file:///tmp/x", "javascript:alert(1)", "brave://settings", "mailto:test@example.com", "--container=Other", "https://", "https://example.com/%ZZ", "https://example.com/%1", "https://example.com/a b", "https://example.com/\nsecret", "/relative", ""])
func unsupportedAndMalformedURLsAreRejected(_ raw: String) {
    #expect(throws: AdapterError.self) { try WebURL(raw) }
}

@Test func batchPreservesOrderDuplicatesAndAllRoutingArguments() throws {
    let f = try Fixture()
    let d = try Destination(paths: f.paths, profileDirectory: "Profile 1", containerID: "test-work")
    let urls = try ["https://example.com/one", "https://example.com/two", "https://example.com/one"].map(WebURL.init)
    let request = try LaunchRequest(resolved: f.discovery.resolve(d), urls: urls)
    #expect(request.executable == f.paths.executable)
    #expect(request.arguments == ["--user-data-dir=\(f.paths.userData)", "--profile-directory=Profile 1", "--container=Work", "--"] + urls.map(\.original))
}

@Test func shellMetacharactersInContainerNameRemainOneArgument() throws {
    let f = try Fixture()
    let name = "Work; $(touch never) ' \""
    try f.editContainers { c in
        var list = c["list"] as! [[String: Any]]; list[0]["name"] = name; c["list"] = list
    }
    let request = try LaunchRequest(resolved: f.discovery.resolve(f.destination), urls: [WebURL("https://example.com")])
    #expect(request.arguments[2] == "--container=" + name)
    #expect(request.arguments.count == 5)
}

@Test func emptyAndOversizedBatchesFailBeforeLaunch() throws {
    let f = try Fixture()
    let resolved = try f.discovery.resolve(f.destination)
    #expect(throws: AdapterError.self) { try LaunchRequest(resolved: resolved, urls: []) }
    #expect(throws: AdapterError.self) { try WebURL("https://example.com/?q=" + String(repeating: "x", count: 131072)) }
    let url = try WebURL("https://example.com/?q=" + String(repeating: "x", count: 60000))
    #expect(throws: AdapterError.self) { try LaunchRequest(resolved: resolved, urls: [url, url, url]) }
}

@Test @MainActor func launchFailureDoesNotIncludeIncomingURL() throws {
    let f = try Fixture()
    let request = try LaunchRequest(resolved: f.discovery.resolve(f.destination), urls: [WebURL("https://example.com/?private=DO_NOT_LOG")])
    do { try BraveLauncher.launch(request); Issue.record("Missing executable should fail") }
    catch let error as AdapterError { #expect(!error.message.contains("DO_NOT_LOG")); #expect(!error.message.contains("example.com")) }
}

@Test(arguments: ["149.1.91.100", "150.1.92.139", "150.bad.1.92.140", "150..1.92.140", "garbage"])
func olderAndMalformedInstallationVersionsAreRejected(_ version: String) throws {
    let f = try Fixture()
    let app = URL(fileURLWithPath: f.paths.application)
    try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: f.paths.executable)
    let info = ["CFBundleExecutable": "Brave Browser", "CFBundleShortVersionString": version]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: app.appendingPathComponent("Contents/Info.plist"))
    #expect(throws: AdapterError.self) { try BraveInstallation(paths: f.paths) }
}
