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

public struct Destination: Codable, Equatable, Sendable {
    public let paths: BravePaths
    public let profileDirectory: String
    public let containerID: String

    public init(paths: BravePaths, profileDirectory: String, containerID: String) throws {
        try Self.validateProfileDirectory(profileDirectory)
        guard !containerID.isEmpty, !containerID.contains("\0") else {
            throw AdapterError("Invalid container ID.")
        }
        self.paths = paths
        self.profileDirectory = profileDirectory
        self.containerID = containerID
    }

    public static func validateProfileDirectory(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
              !name.contains("\\"), !name.contains("\0") else {
            throw AdapterError("Invalid profile directory; use a directory key from list.")
        }
    }

    public var bundleIdentifier: String {
        // Length-prefixing avoids collisions between identities containing separators.
        let fields = [paths.application, paths.userData, profileDirectory, containerID]
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
        self.formatVersion = 1
        self.destination = destination
        self.displayName = displayName
    }

    public static func read(from url: URL) throws -> Self {
        do {
            let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
            guard value.formatVersion == 1 else { throw AdapterError("Unsupported app configuration version.") }
            try Destination.validateProfileDirectory(value.destination.profileDirectory)
            let d = value.destination
            guard !d.containerID.isEmpty,
                  d.paths.application.hasPrefix("/"), d.paths.userData.hasPrefix("/"),
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

public struct ResolvedDestination: Sendable {
    public let destination: Destination
    public let profile: Profile
    public let container: Container
    public var displayName: String {
        "Brave — \(container.name) (\(profile.displayName) · \(profile.directory))"
    }
}
