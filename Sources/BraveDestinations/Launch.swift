import AppKit
import Foundation

public struct BraveInstallation: Sendable {
    public let paths: BravePaths
    public let version: String
    public let supportsTemporaryContainers: Bool

    public init(paths: BravePaths) throws {
        let plistURL = URL(fileURLWithPath: paths.application).appendingPathComponent("Contents/Info.plist")
        guard let data = try? BoundedFile.read(at: plistURL, limit: FileReadLimit.configuration),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["CFBundleExecutable"] as? String == "Brave Browser",
              let version = plist["CFBundleShortVersionString"] as? String,
              FileManager.default.isExecutableFile(atPath: paths.executable.path) else {
            throw AdapterError("Brave installation is missing or invalid. Use --brave with a Brave .app bundle.")
        }
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        let parts = components.compactMap { Int($0) }
        // macOS bundle version includes the Chromium major: 150.1.92.140.
        let braveVersion = parts.count == 4 ? Array(parts.dropFirst()) : parts
        guard parts.count == components.count, parts.allSatisfy({ $0 >= 0 }), braveVersion.count == 3,
              !braveVersion.lexicographicallyPrecedes([1, 92, 140]) else {
            throw AdapterError("Brave is older than the inspected 1.92.140 build. Container routing is not supported by this adapter for this version.")
        }
        self.paths = paths
        self.version = version
        supportsTemporaryContainers = !braveVersion.lexicographicallyPrecedes([1, 95, 101])
    }

    public func requireTemporaryContainers() throws {
        guard supportsTemporaryContainers else {
            throw AdapterError("Temporary destinations require Brave 1.95.101 or later. Update Brave before using this app; nothing was opened.")
        }
    }
}

public struct WebURL: Equatable, Sendable {
    public let original: String
    public init(_ raw: String) throws {
        let forbiddenCharacters = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard !raw.isEmpty,
              raw.utf8.count <= URLBatch.maximumURLBytes,
              !raw.unicodeScalars.contains(where: { forbiddenCharacters.contains($0) }),
              let parsed = URLComponents(string: raw),
              ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""),
              let host = parsed.host, !host.isEmpty, parsed.url != nil else {
            throw AdapterError("Only valid absolute HTTP and HTTPS URLs are accepted. URL contents are omitted.")
        }
        let bytes = Array(raw.utf8)
        func hex(_ byte: UInt8) -> Bool { (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte) }
        for i in bytes.indices where bytes[i] == 37 {
            guard i + 2 < bytes.count, hex(bytes[i + 1]), hex(bytes[i + 2]) else {
                throw AdapterError("URL contains an invalid percent escape. URL contents are omitted.")
            }
        }
        original = raw
    }
}

public struct LaunchRequest: Sendable {
    public let executable: URL
    public let arguments: [String]
    public let userData: String

    public init(resolved: ResolvedDestination, urls: [WebURL]) throws {
        guard !urls.isEmpty else { throw AdapterError("No URLs were supplied.") }
        executable = resolved.destination.paths.executable
        userData = resolved.destination.paths.userData
        arguments = [
            "--user-data-dir=\(userData)",
            "--profile-directory=\(resolved.profile.directory)",
            resolved.container.launchArgument,
            "--",
        ] + urls.map(\.original)
        guard arguments.reduce(0, { $0 + $1.utf8.count + 1 }) < 128 * 1024 else {
            throw AdapterError("The URL batch exceeds the safe launch size. Send smaller batches; nothing was opened.")
        }
    }
}

public enum BraveLauncher {
    @MainActor private static var activationTask: Task<Void, Never>?
    /// Successful process creation is not proof that Brave used the container.
    /// A cold browser process remains alive; never wait for it on the UI thread.
    @MainActor
    @discardableResult
    public static func launch(_ request: LaunchRequest,
                              onFailure: @escaping @Sendable (AdapterError) -> Void = { _ in }) throws -> Process {
        let probe = BrowserOwnershipProbe()
        try probe.inspect(userData: request.userData).validate(executable: request.executable)
        let process = Process()
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { process in
            if process.terminationStatus != 0 {
                onFailure(AdapterError("Brave exited with status \(process.terminationStatus). Run cbc doctor; browser output is suppressed to protect URL contents."))
            }
        }
        do { try process.run() }
        catch { throw AdapterError("Could not start Brave. Check installation permissions and run cbc doctor. URL contents are omitted.") }
        activationTask?.cancel()
        activationTask = Task { @MainActor in
            for delay in [200, 400, 800, 1600, 2000, 2000, 2000] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                let owner = probe.inspect(userData: request.userData)
                if let pid = owner.activationCandidate(executable: request.executable, launched: probe.process(process.processIdentifier)),
                   let app = NSRunningApplication(processIdentifier: pid),
                   app.executableURL?.resolvingSymlinksInPath() == request.executable.resolvingSymlinksInPath() {
                    app.activate(options: [])
                    if app.isActive { return }
                }
            }
            onFailure(AdapterError("Brave was started, but its foreground window could not be confirmed. Check its profile and container badge before retrying the link."))
        }
        return process
    }

}
