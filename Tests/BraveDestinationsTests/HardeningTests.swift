import AppKit
@testable import AppPackaging
@testable import BraveDestinations
import Darwin
import Foundation
import Testing

@Test func queueRejectsOverflowWithoutLosingAcceptedBatches() throws {
    var queue = URLRequestQueue()
    for i in 0..<32 { try queue.enqueue(URLBatch(["https://example.com/\(i)"])) }
    #expect(throws: AdapterError.self) { try queue.enqueue(URLBatch(["https://example.com/rejected"])) }
    #expect(queue.count == 32)
    for i in 0..<32 { #expect(queue.next()?.urls.map(\.original) == ["https://example.com/\(i)"]) }
    #expect(queue.isEmpty && queue.byteCount == 0)
    try queue.enqueue(URLBatch(["https://example.com/new", "https://example.com/new"]))
    #expect(queue.next()?.urls.count == 2)
}

@Test func queueBoundsBytesAndRejectsInvalidBatchAtomically() throws {
    let large = "https://example.com/?x=" + String(repeating: "a", count: 60000)
    var queue = URLRequestQueue()
    for _ in 0..<8 { try queue.enqueue(URLBatch([large, large])) }
    #expect(throws: AdapterError.self) { try queue.enqueue(URLBatch([large, large])) }
    #expect(queue.count == 8)
    #expect(throws: AdapterError.self) { try queue.enqueue(URLBatch(["https://example.com/", "file:///private"])) }
    #expect(queue.count == 8)
    #expect(throws: AdapterError.self) { try URLBatch(Array(repeating: "https://example.com", count: 129)) }
    #expect(throws: AdapterError.self) { try URLBatch([large, large, large]) }
}

@Test func boundedReadsRejectOversizeSymlinksAndPipes() throws {
    let f = try Fixture()
    let file = f.root.appendingPathComponent("oversized")
    FileManager.default.createFile(atPath: file.path, contents: Data())
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: UInt64(FileReadLimit.metadata + 1))
    try handle.close()
    #expect(throws: AdapterError.self) { try BoundedFile.read(at: file, limit: FileReadLimit.metadata) }
    let link = f.root.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.preferenceURL)
    #expect(throws: AdapterError.self) { try BoundedFile.read(at: link, limit: FileReadLimit.metadata) }
    let pipe = f.root.appendingPathComponent("pipe")
    try #require(mkfifo(pipe.path, 0o600) == 0)
    #expect(throws: AdapterError.self) { try BoundedFile.read(at: pipe, limit: FileReadLimit.metadata) }
    #expect(try BoundedFile.read(at: f.preferenceURL, limit: FileReadLimit.metadata) == Data(contentsOf: f.preferenceURL))
}

@Test @MainActor func oversizedSavedIconAndConfigurationAreRejected() async throws {
    let f = try Fixture()
    let config = try DestinationConfiguration(destination: f.destination, displayName: "Test")
    let app = try await AppGenerator.generate(configuration: config, receiver: URL(fileURLWithPath: "/usr/bin/true"), directory: f.root.appendingPathComponent("Apps"))
    let resources = app.appendingPathComponent("Contents/Resources")
    try Data("{\"iconPreset\":\"custom\"}".utf8).write(to: resources.appendingPathComponent("appearance.json"))
    let handle = try FileHandle(forWritingTo: resources.appendingPathComponent("Destination.icns"))
    try handle.truncate(atOffset: UInt64(FileReadLimit.icon + 1)); try handle.close()
    #expect(throws: AdapterError.self) { try AppGenerator.savedIcon(at: app) }
    let configHandle = try FileHandle(forWritingTo: resources.appendingPathComponent("destination.json"))
    try configHandle.truncate(atOffset: UInt64(FileReadLimit.configuration + 1)); try configHandle.close()
    #expect(throws: AdapterError.self) { try AppGenerator.readManagedApp(app) }
}

@Test func ownerChecksCoverColdStaleUnknownAndDifferentInstallations() throws {
    let f = try Fixture()
    let lock = URL(fileURLWithPath: f.paths.userData).appendingPathComponent("SingletonLock")
    let probe = BrowserOwnershipProbe(host: "test-host", processExists: { $0 != 999 }, executable: { pid in
        pid == 123 ? URL(fileURLWithPath: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser") : nil
    })
    #expect(probe.inspect(userData: f.paths.userData) == .available)
    for (target, expected) in [("test-host-999", BrowserOwner.available), ("foreign-host-999", .unknown), ("test-host-0", .unknown), ("test-host-456", .unknown)] {
        try FileManager.default.createSymbolicLink(atPath: lock.path, withDestinationPath: target)
        #expect(probe.inspect(userData: f.paths.userData) == expected)
        try FileManager.default.removeItem(at: lock)
    }
    try FileManager.default.createSymbolicLink(atPath: lock.path, withDestinationPath: "test-host-123")
    let owner = probe.inspect(userData: f.paths.userData)
    let correct = URL(fileURLWithPath: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser")
    try owner.validate(executable: correct)
    #expect(throws: AdapterError.self) { try owner.validate(executable: f.paths.executable) }
    #expect(throws: AdapterError.self) { try BrowserOwner.unknown.validate(executable: correct) }
    #expect(owner.activationCandidate(executable: correct, launched: .available) == 123)
    #expect(owner.activationCandidate(executable: f.paths.executable, launched: .available) == nil)
    #expect(BrowserOwner.unknown.activationCandidate(executable: correct, launched: owner) == nil)
    #expect(BrowserOwner.available.activationCandidate(executable: correct, launched: owner) == 123)
}

@Test func toolsTimeOutAndCancelWithoutStoppingUnrelatedChildren() async throws {
    let sibling = Process()
    sibling.executableURL = URL(fileURLWithPath: "/bin/sleep")
    sibling.arguments = ["30"]
    try sibling.run()
    defer { sibling.terminate(); sibling.waitUntilExit() }
    let start = ContinuousClock.now
    await #expect(throws: AdapterError.self) {
        try await ToolRunner.run(ToolInvocation(executable: "/bin/sleep", arguments: ["30"], failure: "Test tool failed.", timeout: 0.1))
    }
    #expect(start.duration(to: .now) < .seconds(2))
    #expect(sibling.isRunning)
    let task = Task { try await ToolRunner.run(ToolInvocation(executable: "/bin/sleep", arguments: ["30"], failure: "Test tool failed.")) }
    try await Task.sleep(for: .milliseconds(50))
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(sibling.isRunning)
}

@Test func systemOwnershipProbeUsesChromiumHostnameAndResolvesLiveExecutable() throws {
    let f = try Fixture()
    var hostname = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
    try #require(gethostname(&hostname, hostname.count) == 0)
    let name = String(decoding: hostname.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    let lock = URL(fileURLWithPath: f.paths.userData).appendingPathComponent("SingletonLock")
    try FileManager.default.createSymbolicLink(atPath: lock.path, withDestinationPath: "\(name)-\(getpid())")
    let owner = BrowserOwnershipProbe().inspect(userData: f.paths.userData)
    guard case .running(let pid, let executable) = owner else {
        Issue.record("The system process and Chromium-format hostname must resolve"); return
    }
    #expect(pid == getpid())
    #expect(FileManager.default.isExecutableFile(atPath: executable.path))
}

@Test @MainActor func failedSigningPreservesOriginalAndReleasesDirectoryLock() async throws {
    let f = try Fixture()
    let directory = f.root.appendingPathComponent("Apps")
    let receiver = URL(fileURLWithPath: "/usr/bin/true")
    let original = try DestinationConfiguration(destination: f.destination, displayName: "Original")
    let app = try await AppGenerator.generate(configuration: original, receiver: receiver, directory: directory)
    let updated = DestinationConfiguration(destination: original.destination, displayName: "Updated")
    var services = GenerationServices()
    services.runTool = { _ in throw AdapterError("Injected tool failure") }
    await #expect(throws: AdapterError.self) {
        try await AppGenerator.generate(configuration: updated, receiver: receiver, directory: directory, rename: true, services: services)
    }
    #expect(try AppGenerator.readManagedApp(app) == original)
    #expect(try !FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".cbc-") && $0.hasSuffix(".app") })
    _ = try await AppGenerator.generate(configuration: updated, receiver: receiver, directory: directory, rename: true)
}

@Test @MainActor func failedSwapRestoresOldNameAndFailedRollbackRemainsRecoverable() async throws {
    for failRollback in [false, true] {
        let f = try Fixture()
        let directory = f.root.appendingPathComponent("Apps")
        let receiver = URL(fileURLWithPath: "/usr/bin/true")
        let original = try DestinationConfiguration(destination: f.destination, displayName: "Original")
        let old = try await AppGenerator.generate(configuration: original, receiver: receiver, directory: directory)
        let update = DestinationConfiguration(destination: original.destination, displayName: "Updated")
        var calls = 0
        var services = GenerationServices()
        let native = services.rename
        services.rename = { source, target, flags in
            calls += 1
            if calls == 2 || (calls == 3 && failRollback) { return -1 }
            return native(source, target, flags)
        }
        await #expect(throws: AdapterError.self) {
            try await AppGenerator.generate(configuration: update, receiver: receiver, directory: directory, rename: true, services: services)
        }
        let surviving = failRollback ? directory.appendingPathComponent("Updated.app") : old
        #expect(try AppGenerator.readManagedApp(surviving) == original)
        // A previous interrupted stage must not be mistaken for a second installed app.
        let orphan = directory.appendingPathComponent(".cbc-interrupted.app")
        try FileManager.default.copyItem(at: surviving, to: orphan)
        let recovered = try await AppGenerator.generate(configuration: update, receiver: receiver, directory: directory, rename: true)
        #expect(try AppGenerator.readManagedApp(recovered) == update)
        #expect(FileManager.default.fileExists(atPath: orphan.path))
    }
}
