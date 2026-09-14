import CryptoKit
import Foundation

public struct AdapterError: Error, LocalizedError, Sendable, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct BravePaths: Codable, Equatable, Sendable {
    public let application: String
    public let userData: String

    public init(application: String, userData: String) {
        self.application = Self.canonical(application)
        self.userData = Self.canonical(userData)
    }

    public static var standard: Self {
        Self(application: "/Applications/Brave Browser.app",
             userData: NSHomeDirectory() + "/Library/Application Support/BraveSoftware/Brave-Browser")
    }

    public static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL.resolvingSymlinksInPath().path
    }

    public var executable: URL {
        URL(fileURLWithPath: application).appendingPathComponent("Contents/MacOS/Brave Browser")
    }
}

public enum ContainerSelection: Equatable, Sendable {
    case configured(id: String)
    case temporary
}

public struct Destination: Codable, Equatable, Sendable {
    public let paths: BravePaths
    public let profileDirectory: String
    public let selection: ContainerSelection

    public init(paths: BravePaths, profileDirectory: String, containerID: String) throws {
        try self.init(paths: paths, profileDirectory: profileDirectory, selection: .configured(id: containerID))
    }

    public init(paths: BravePaths, profileDirectory: String, selection: ContainerSelection) throws {
        try Self.validateProfileDirectory(profileDirectory)
        if case .configured(let id) = selection {
            guard !id.isEmpty, !id.contains("\0") else { throw AdapterError("Invalid container ID.") }
        }
        self.paths = paths
        self.profileDirectory = profileDirectory
        self.selection = selection
    }

    public var isTemporary: Bool { selection == .temporary }

    private enum CodingKeys: String, CodingKey { case paths, profileDirectory, containerID, mode }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let selection: ContainerSelection
        switch try values.decodeIfPresent(String.self, forKey: .mode) {
        case nil:
            selection = .configured(id: try values.decode(String.self, forKey: .containerID))
        case "temporary":
            guard !values.contains(.containerID) else { throw AdapterError("Temporary destinations must not contain a container ID.") }
            selection = .temporary
        default:
            throw AdapterError("Unknown destination mode. Update the adapter or regenerate this app.")
        }
        try self.init(paths: values.decode(BravePaths.self, forKey: .paths),
                      profileDirectory: values.decode(String.self, forKey: .profileDirectory), selection: selection)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(paths, forKey: .paths)
        try values.encode(profileDirectory, forKey: .profileDirectory)
        switch selection {
        case .configured(let id): try values.encode(id, forKey: .containerID)
        case .temporary: try values.encode("temporary", forKey: .mode)
        }
    }

    public static func validateProfileDirectory(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
              !name.contains("\\"), !name.contains("\0") else {
            throw AdapterError("Invalid profile directory; use a directory key from list.")
        }
    }

    public var bundleIdentifier: String {
        // Length-prefixing avoids collisions between identities containing separators.
        let suffix: [String]
        switch selection {
        case .configured(let id): suffix = [id] // Preserve existing destination identities.
        case .temporary: suffix = ["temporary", "fresh"] // Separate from every four-field configured identity.
        }
        let fields = [paths.application, paths.userData, profileDirectory] + suffix
        let identity = fields.map { "\($0.utf8.count):\($0)" }.joined()
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return "app.choosy-brave-containers.destination.d" + hash
    }
}

public struct DestinationConfiguration: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let destination: Destination
    public let displayName: String

    public init(destination: Destination, displayName: String) {
        self.formatVersion = destination.isTemporary ? 2 : 1
        self.destination = destination
        self.displayName = displayName
    }

    public static func read(from url: URL) throws -> Self {
        do {
            let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
            guard [1, 2].contains(value.formatVersion),
                  value.formatVersion != 1 || !value.destination.isTemporary else {
                throw AdapterError("Unsupported app configuration version.")
            }
            try Destination.validateProfileDirectory(value.destination.profileDirectory)
            let d = value.destination
            guard d.paths.application.hasPrefix("/"), d.paths.userData.hasPrefix("/"),
                  d.paths == BravePaths(application: d.paths.application, userData: d.paths.userData) else {
                throw AdapterError("App configuration contains invalid destination paths or ID. Regenerate this app.")
            }
            return value
        } catch let error as AdapterError { throw error }
        catch { throw AdapterError("Cannot read destination.json. Reinstall this destination app.") }
    }
}

public struct Profile: Equatable, Sendable {
    public let directory: String
    public let displayName: String
}

public struct Container: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let icon: Int
    public let backgroundColor: Int32
    enum CodingKeys: String, CodingKey { case id, name, icon; case backgroundColor = "background_color" }
}

public struct ContainerSnapshot: Sendable {
    public let enabled: Bool
    /// Nil means Brave's localized built-in defaults have not been serialized.
    public let configured: [Container]?
    public let retained: [String: Container]
}

public enum ResolvedContainer: Sendable {
    case configured(Container)
    case temporary

    public var name: String {
        switch self {
        case .configured(let container): container.name
        case .temporary: "Temporary"
        }
    }

    public var id: String? {
        switch self {
        case .configured(let container): container.id
        case .temporary: nil
        }
    }

    public var launchArgument: String {
        switch self {
        case .configured(let container): "--container=\(container.name)"
        case .temporary: "--temporary-container"
        }
    }
}

public struct ResolvedDestination: Sendable {
    public let destination: Destination
    public let profile: Profile
    public let container: ResolvedContainer
    public var displayName: String {
        "Brave — \(container.name) (\(profile.displayName) · \(profile.directory))"
    }
}
