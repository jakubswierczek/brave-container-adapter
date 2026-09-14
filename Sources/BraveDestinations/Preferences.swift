import Foundation

/// Reads only metadata. Errors deliberately omit the contents of browser files.
public struct PreferenceReader: Sendable {
    private let waitBeforeRetry: @Sendable () -> Void
    public init() { waitBeforeRetry = { Thread.sleep(forTimeInterval: 0.03) } }
    init(waitBeforeRetry: @escaping @Sendable () -> Void) { self.waitBeforeRetry = waitBeforeRetry }

    public func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        for attempt in 0..<3 {
            do {
                let before = try FileManager.default.attributesOfItem(atPath: url.path)
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode(type, from: data)
                let after = try FileManager.default.attributesOfItem(atPath: url.path)
                guard [.size, .modificationDate, .systemFileNumber].allSatisfy({ key in
                    String(describing: before[key]) == String(describing: after[key])
                }) else {
                    throw AdapterError("Metadata changed during reading.")
                }
                return decoded
            } catch {
                if attempt < 2 { waitBeforeRetry() }
            }
        }
        throw AdapterError("Cannot read valid \(url.lastPathComponent) metadata. It is missing, unreadable, malformed, or changing. Wait for Brave to save, then retry.")
    }
}

private struct LocalState: Decodable {
    struct ProfileSection: Decodable {
        struct Info: Decodable { let name: String }
        let info_cache: [String: Info]
    }
    struct BrowserSection: Decodable { let enabled_labs_experiments: [String]? }
    let profile: ProfileSection
    let browser: BrowserSection?
}

private struct Preferences: Decodable {
    struct Brave: Decodable {
        struct Containers: Decodable {
            let enabled: Bool?
            let list: [Container]?
            let used: [String: Container]?
        }
        let containers: Containers?
    }
    let brave: Brave?
}

public struct Discovery: Sendable {
    public let paths: BravePaths
    private let reader = PreferenceReader()
    public init(paths: BravePaths) { self.paths = paths }

    private var localStateURL: URL { URL(fileURLWithPath: paths.userData).appendingPathComponent("Local State") }

    public func profiles() throws -> [Profile] {
        let state = try reader.read(LocalState.self, at: localStateURL)
        return try state.profile.info_cache.map { directory, value in
            try Destination.validateProfileDirectory(directory)
            return Profile(directory: directory, displayName: value.name)
        }.sorted { $0.directory < $1.directory }
    }

    public func explicitlyDisabledFeature() throws -> Bool {
        let state = try reader.read(LocalState.self, at: localStateURL)
        return state.browser?.enabled_labs_experiments?.contains("containers@2") == true
    }

    public func containers(profileDirectory: String) throws -> ContainerSnapshot {
        try Destination.validateProfileDirectory(profileDirectory)
        let root = URL(fileURLWithPath: paths.userData)
        let profile = root.appendingPathComponent(profileDirectory).resolvingSymlinksInPath()
        guard profile.deletingLastPathComponent().path == root.path else {
            throw AdapterError("Profile directory resolves outside the selected user data directory.")
        }
        let prefs = try reader.read(Preferences.self, at: profile.appendingPathComponent("Preferences"))
        let value = prefs.brave?.containers
        let configured = value?.list
        let retained = value?.used ?? [:]
        for record in (configured ?? []) + Array(retained.values) {
            guard !record.id.isEmpty, !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !record.name.contains("\0") else { throw AdapterError("Container metadata has an invalid ID or name.") }
        }
        if let configured, Set(configured.map(\.id)).count != configured.count {
            throw AdapterError("Configured containers contain duplicate IDs; routing is unsafe.")
        }
        guard retained.allSatisfy({ $0.key == $0.value.id }) else {
            throw AdapterError("Retained container metadata has mismatched IDs.")
        }
        return ContainerSnapshot(enabled: value?.enabled == true, configured: configured, retained: retained)
    }

    public func resolve(_ destination: Destination) throws -> ResolvedDestination {
        guard destination.paths == paths else { throw AdapterError("Destination paths do not match discovery paths.") }
        guard let profile = try profiles().first(where: { $0.directory == destination.profileDirectory }) else {
            throw AdapterError("The configured Brave profile no longer exists in Local State. Run cbc list.")
        }
        guard try !explicitlyDisabledFeature() else {
            throw AdapterError("Containers is disabled in brave://flags. Enable it in Brave and relaunch Brave.")
        }
        let snapshot = try containers(profileDirectory: profile.directory)
        guard snapshot.enabled else {
            throw AdapterError("Containers is disabled or its enabled preference is not saved. Enable Containers in Brave Settings > Content, wait for preferences to save, then retry.")
        }
        let containerID: String
        switch destination.selection {
        case .temporary:
            try BraveInstallation(paths: paths).requireTemporaryContainers()
            return ResolvedDestination(destination: destination, profile: profile, container: .temporary)
        case .configured(let id): containerID = id
        }
        guard let configured = snapshot.configured else {
            throw AdapterError("Brave has not saved its container list. Add a container or edit and save one in Brave's UI, then wait for preferences to save. Built-in localized defaults are not inferred from retained records.")
        }
        guard let container = configured.first(where: { $0.id == containerID }) else {
            throw AdapterError("This container was deleted or is no longer configured. Retained records are not launch destinations. Run cbc list and regenerate the app for an existing container.")
        }
        // Brave compares UTF-8 bytes, not Swift's canonically equivalent String equality.
        guard configured.filter({ $0.name.utf8.elementsEqual(container.name.utf8) }).count == 1 else {
            throw AdapterError("Multiple configured containers have the same name. Rename one in Brave before opening links.")
        }
        return ResolvedDestination(destination: destination, profile: profile, container: .configured(container))
    }
}
