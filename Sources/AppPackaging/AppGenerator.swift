import AppKit
import BraveDestinations
import Darwin
import Foundation

@MainActor
public enum AppGenerator {
    public static var installDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Brave Destinations")
    }

    public static func readManagedApp(_ app: URL) throws -> DestinationConfiguration {
        guard app.pathExtension.lowercased() == "app",
              try app.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              info["CBCManagedBundle"] as? Bool == true else {
            throw AdapterError("Choose a destination app created by this utility, not a browser or another application.")
        }
        let config = try DestinationConfiguration.read(from: app.appendingPathComponent("Contents/Resources/destination.json"))
        guard info["CFBundleIdentifier"] as? String == config.destination.bundleIdentifier else {
            throw AdapterError("This app's destination and bundle identity do not match.")
        }
        return config
    }

    public static func installedApp(for destination: Destination) throws -> URL? {
        let legacy = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Choosy Brave Containers")
        let matches = try [installDirectory, legacy].flatMap { try matchingApps(destination: destination, directory: $0) }
        guard matches.count <= 1 else { throw AdapterError("Multiple installed apps target this destination. Use Edit installed app to select one.") }
        return matches.first
    }

    public static func existingApp(for destination: Destination, directory: URL) throws -> URL? {
        let matches = try matchingApps(destination: destination, directory: directory)
        guard matches.count <= 1 else { throw AdapterError("Multiple apps target this destination in the selected folder.") }
        return matches.first
    }

    private static func matchingApps(destination: Destination, directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey])
            .filter { app in (try? readManagedApp(app).destination) == destination }
    }

    public static func savedIcon(at app: URL) throws -> AppIcon {
        _ = try readManagedApp(app)
        let resources = app.appendingPathComponent("Contents/Resources")
        if let data = try? Data(contentsOf: resources.appendingPathComponent("appearance.json")),
           let saved = try? JSONDecoder().decode([String: String].self, from: data),
           let raw = saved["iconPreset"], let preset = IconPreset(rawValue: raw) {
            return .generated(preset)
        }
        return .custom(try Data(contentsOf: resources.appendingPathComponent("Destination.icns")))
    }

    public static func generate(configuration: DestinationConfiguration, receiver: URL, directory: URL,
                                icon: AppIcon? = nil, rename: Bool = false) throws -> URL {
        let fm = FileManager.default
        guard !configuration.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !configuration.displayName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !configuration.displayName.contains("/"), !configuration.displayName.contains(":"),
              !configuration.displayName.hasPrefix("."), configuration.displayName.utf8.count <= 240 else {
            throw AdapterError("Use an app name up to 240 UTF-8 bytes, without /, :, control characters, or a leading dot.")
        }
        guard fm.isExecutableFile(atPath: receiver.path) else {
            throw AdapterError("ContainerReceiver is missing. Build both release executables or supply --receiver.")
        }
        let directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let data = configuration.destination.paths.userData
        guard directory.path != data, !directory.path.hasPrefix(data + "/") else {
            throw AdapterError("Apps cannot be generated inside Brave's user data directory.")
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let lock = Darwin.open(directory.appendingPathComponent(".cbc-install.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw AdapterError("Cannot lock the destination directory.") }
        defer { Darwin.close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw AdapterError("Another generation is running in this directory.") }
        let id = configuration.destination.bundleIdentifier
        let owned = try matchingApps(destination: configuration.destination, directory: directory)
        guard owned.count <= 1 else { throw AdapterError("Multiple apps for this destination exist in the output directory. Remove the duplicate first.") }
        let target = !rename && owned.first != nil ? owned[0] : directory.appendingPathComponent(configuration.displayName + ".app")
        if fm.fileExists(atPath: target.path) || (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            guard owned.contains(where: { BravePaths.canonical($0.path) == BravePaths.canonical(target.path) }), try target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw AdapterError("An app or link already uses this filename. Choose another app name; existing apps were preserved.")
            }
        }
        let selectedIcon = try icon ?? owned.first.map { try savedIcon(at: $0) } ?? .generated(.monogram)
        let iconData = try DestinationIcons.data(for: selectedIcon, configuration: configuration)
        guard NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty else {
            throw AdapterError("This destination receiver is running. Quit it in Activity Monitor, then repeat generation. Existing app was preserved.")
        }
        let staging = directory.appendingPathComponent(".cbc-\(UUID().uuidString).app")
        defer { try? fm.removeItem(at: staging) }
        let macOS = staging.appendingPathComponent("Contents/MacOS")
        let resources = staging.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try fm.copyItem(at: receiver, to: macOS.appendingPathComponent("ContainerReceiver"))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macOS.appendingPathComponent("ContainerReceiver").path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let configURL = resources.appendingPathComponent("destination.json")
        try encoder.encode(configuration).write(to: configURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        let info: [String: Any] = [
            "CFBundleIdentifier": id,
            "CFBundleName": configuration.displayName,
            "CFBundleDisplayName": configuration.displayName,
            "CFBundleExecutable": "ContainerReceiver",
            "CFBundlePackageType": "APPL",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleShortVersionString": "1.3.0",
            "CFBundleVersion": "6",
            "LSMinimumSystemVersion": "14.0",
            "LSUIElement": true,
            "NSHighResolutionCapable": true,
            "CFBundleIconFile": "Destination.icns",
            "CBCManagedBundle": true,
            "CFBundleURLTypes": [[
                "CFBundleURLName": id + ".web",
                "CFBundleTypeRole": "Viewer",
                "CFBundleURLSchemes": ["http", "https"],
            ]],
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: staging.appendingPathComponent("Contents/Info.plist"))
        try iconData.write(to: resources.appendingPathComponent("Destination.icns"))
        let preset: String
        switch selectedIcon {
        case .generated(let value): preset = value.rawValue
        case .custom: preset = "custom"
        }
        try encoder.encode(["iconPreset": preset]).write(to: resources.appendingPathComponent("appearance.json"))
        try runTool("/usr/bin/codesign", ["--force", "--sign", "-", staging.path], failure: "Could not ad-hoc sign the app.")
        try runTool("/usr/bin/codesign", ["--verify", "--strict", staging.path], failure: "Generated app signature verification failed.")
        let previous = owned.first
        let moving = previous.map { BravePaths.canonical($0.path) != BravePaths.canonical(target.path) } ?? false
        if moving, let previous {
            guard renameatx_np(AT_FDCWD, previous.path, AT_FDCWD, target.path, UInt32(RENAME_EXCL)) == 0 else {
                throw AdapterError("Could not rename the app. Check for a filename collision or missing permissions; existing app was preserved.")
            }
        }
        let flags = previous != nil ? UInt32(RENAME_SWAP) : UInt32(RENAME_EXCL)
        guard renameatx_np(AT_FDCWD, staging.path, AT_FDCWD, target.path, flags) == 0 else {
            if moving, let previous,
               renameatx_np(AT_FDCWD, target.path, AT_FDCWD, previous.path, UInt32(RENAME_EXCL)) != 0 {
                throw AdapterError("Update failed. The original app is intact under the requested new filename; inspect it in Finder before retrying.")
            }
            throw AdapterError("Could not atomically install the app. Existing apps were preserved.")
        }
        // On swap, staging now contains the old managed bundle and defer removes it.
        return URL(fileURLWithPath: BravePaths.canonical(target.path), isDirectory: true)
    }

    public static func register(_ app: URL) throws {
        try runTool("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                    ["-f", app.path], failure: "App was installed, but Launch Services registration failed. Open the app once in Finder.")
    }

    private static func runTool(_ executable: String, _ arguments: [String], failure: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() }
        catch { throw AdapterError(failure) }
        guard process.terminationStatus == 0 else { throw AdapterError(failure) }
    }

}
