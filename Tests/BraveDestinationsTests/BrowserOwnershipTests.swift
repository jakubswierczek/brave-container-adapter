@testable import BraveDestinations
import Darwin
import Foundation
import Testing

@Test func hostnameChangeWithLocalSocketKeepsOwner() throws {
    let f = try Fixture()
    let socket = try OwnershipSocketFixture(userData: f.paths.userData)
    defer { socket.close() }
    let executable = f.paths.executable
    let probe = BrowserOwnershipProbe(host: "new-host", processExists: { $0 == getpid() },
                                      executable: { _ in executable })
    let owner = probe.inspect(userData: f.paths.userData)
    #expect(owner == .running(pid: getpid(), executable: f.paths.executable))
    try owner.validate(executable: f.paths.executable)
    #expect(throws: AdapterError.self) { try owner.validate(executable: URL(fileURLWithPath: "/other/Brave Browser")) }
    #expect(owner.activationCandidate(executable: f.paths.executable, launched: .available) == getpid())
}

@Test(arguments: ["missing-cookie", "different-cookie", "missing-socket", "regular-file", "closed-socket", "wrong-pid"])
func hostnameChangeWithoutMatchingEndpointIsRejected(failure: String) throws {
    let f = try Fixture()
    let socket = try OwnershipSocketFixture(userData: f.paths.userData)
    defer { socket.close() }
    let root = URL(fileURLWithPath: f.paths.userData)
    switch failure {
    case "missing-cookie":
        try FileManager.default.removeItem(at: root.appendingPathComponent("SingletonCookie"))
    case "different-cookie":
        let cookie = socket.directory.appendingPathComponent("SingletonCookie")
        try FileManager.default.removeItem(at: cookie)
        try FileManager.default.createSymbolicLink(atPath: cookie.path, withDestinationPath: "other-cookie")
    case "missing-socket":
        try FileManager.default.removeItem(at: root.appendingPathComponent("SingletonSocket"))
    case "regular-file":
        try FileManager.default.removeItem(at: socket.path)
        try Data().write(to: socket.path)
    case "closed-socket": socket.closeDescriptor()
    case "wrong-pid":
        let lock = root.appendingPathComponent("SingletonLock")
        try FileManager.default.removeItem(at: lock)
        try FileManager.default.createSymbolicLink(atPath: lock.path, withDestinationPath: "old-host-1")
    default: Issue.record("Unknown fixture failure")
    }
    let executable = f.paths.executable
    let probe = BrowserOwnershipProbe(host: "new-host", processExists: { _ in true }, executable: { _ in executable })
    let owner = probe.inspect(userData: f.paths.userData)
    #expect(owner == .hostnameMismatch)
    #expect(throws: AdapterError.self) { try owner.validate(executable: executable) }
    #expect(owner.activationCandidate(executable: executable, launched: .running(pid: getpid(), executable: executable)) == nil)
}

@Test func hostnameRecoveryRejectsLockChangesDuringVerification() throws {
    let f = try Fixture()
    let lock = URL(fileURLWithPath: f.paths.userData).appendingPathComponent("SingletonLock")
    try FileManager.default.createSymbolicLink(atPath: lock.path, withDestinationPath: "old-host-123")
    let executable = f.paths.executable
    let probe = BrowserOwnershipProbe(host: "new-host", processExists: { _ in true }, executable: { _ in executable },
        socketOwner: { _, _ in
            try? FileManager.default.removeItem(at: lock)
            try? FileManager.default.createSymbolicLink(atPath: lock.path, withDestinationPath: "old-host-456")
            return true
        })
    #expect(probe.inspect(userData: f.paths.userData) == .hostnameMismatch)
}

@Test func hostnameRecoveryVerifiesAnotherProcessUsingSystemProbe() async throws {
    let f = try Fixture()
    let socket = try OwnershipSocketFixture(userData: f.paths.userData)
    defer { socket.close() }
    socket.closeDescriptor()
    try FileManager.default.removeItem(at: socket.path)
    let listener = Process()
    listener.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
    listener.arguments = ["-l", "-k", "-U", socket.path.path]
    listener.standardInput = FileHandle.nullDevice
    listener.standardOutput = FileHandle.nullDevice
    listener.standardError = FileHandle.nullDevice
    try listener.run()
    defer {
        if listener.isRunning { listener.terminate() }
        listener.waitUntilExit()
    }
    let lock = URL(fileURLWithPath: f.paths.userData).appendingPathComponent("SingletonLock")
    try FileManager.default.removeItem(at: lock)
    try FileManager.default.createSymbolicLink(atPath: lock.path, withDestinationPath: "old-host-\(listener.processIdentifier)")
    let probe = BrowserOwnershipProbe()
    var owner = BrowserOwner.unknown
    for _ in 0..<100 {
        owner = probe.inspect(userData: f.paths.userData)
        if case .running = owner { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(owner == .running(pid: listener.processIdentifier, executable: listener.executableURL!))
    #expect(throws: AdapterError.self) { try owner.validate(executable: f.paths.executable) }
}

@Test(arguments: ["-123", "old/host-123", "old host-123", "old-host-+123", "old-host-0", "old-host-2147483648"])
func malformedLocksNeverUseSocketRecovery(target: String) throws {
    let f = try Fixture()
    let lock = URL(fileURLWithPath: f.paths.userData).appendingPathComponent("SingletonLock")
    try FileManager.default.createSymbolicLink(atPath: lock.path, withDestinationPath: target)
    let executable = f.paths.executable
    let probe = BrowserOwnershipProbe(host: "new-host", processExists: { _ in true }, executable: { _ in executable },
        socketOwner: { _, _ in Issue.record("Malformed lock must not probe a socket"); return true })
    #expect(probe.inspect(userData: f.paths.userData) == .unknown)
}

@Test func foreignDeadOwnerNeverBecomesAvailable() throws {
    let f = try Fixture()
    let lock = URL(fileURLWithPath: f.paths.userData).appendingPathComponent("SingletonLock")
    try FileManager.default.createSymbolicLink(atPath: lock.path, withDestinationPath: "old-host-123")
    let probe = BrowserOwnershipProbe(host: "new-host", processExists: { _ in false }, executable: { _ in nil },
        socketOwner: { _, _ in Issue.record("Dead owner must not probe a socket"); return true })
    #expect(probe.inspect(userData: f.paths.userData) == .hostnameMismatch)
}

@Test func hostnameMismatchDiagnosticsExplainRecoveryWithoutLeakingHostname() throws {
    let f = try Fixture()
    let lock = URL(fileURLWithPath: f.paths.userData).appendingPathComponent("SingletonLock")
    try FileManager.default.createSymbolicLink(atPath: lock.path, withDestinationPath: "private-host-DO-NOT-LOG-\(getpid())")
    let report = Diagnostics.report(paths: f.paths)
    #expect(report.contains("state: hostname mismatch"))
    #expect(report.contains("local socket owner could not be verified"))
    #expect(report.contains("Quit Brave completely with Command-Q"))
    #expect(!report.contains("private-host-DO-NOT-LOG"))
    do {
        try BrowserOwner.hostnameMismatch.validate(executable: f.paths.executable)
        Issue.record("Unverified owner must be rejected")
    } catch let error as AdapterError {
        #expect(error.message.contains("different computer hostname"))
        #expect(error.message.contains("Nothing was launched"))
        #expect(!error.message.contains("finish starting"))
    }
}

private final class OwnershipSocketFixture {
    let directory: URL
    let path: URL
    private var descriptor: Int32

    init(userData: String) throws {
        directory = URL(fileURLWithPath: "/private/tmp/cbc-owner-\(UUID())")
        path = directory.appendingPathComponent("SingletonSocket")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(descriptor >= 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.path.utf8) + [0]
        try #require(bytes.count <= MemoryLayout.size(ofValue: address.sun_path))
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        try #require(bound == 0)
        try #require(listen(descriptor, 1) == 0)
        let root = URL(fileURLWithPath: userData)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("SingletonLock").path,
                                                   withDestinationPath: "old-host-\(getpid())")
        // Chromium's singleton cookie is a symlink token, not browser cookie data.
        for parent in [root, directory] {
            try FileManager.default.createSymbolicLink(atPath: parent.appendingPathComponent("SingletonCookie").path,
                                                       withDestinationPath: "synthetic-cookie")
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("SingletonSocket"), withDestinationURL: path)
    }

    func close() {
        closeDescriptor()
        try? FileManager.default.removeItem(at: directory)
    }

    func closeDescriptor() {
        if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
    }
}
