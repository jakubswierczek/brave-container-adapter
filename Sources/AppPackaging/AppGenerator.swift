import AppKit
import BraveDestinations
import Darwin
import Foundation

@MainActor
public enum AppGenerator {
    public static var installDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Choosy Brave Containers")
    }

    public static func generate(configuration: DestinationConfiguration, receiver: URL, directory: URL) throws -> URL {
        let fm = FileManager.default
        guard !configuration.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !configuration.displayName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw AdapterError("App label must be nonempty and contain no control characters.")
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
        let apps = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey])
            .filter { $0.pathExtension == "app" }
        let owned = apps.filter { app in
            guard let saved = try? DestinationConfiguration.read(from: app.appendingPathComponent("Contents/Resources/destination.json")),
                  saved.destination == configuration.destination,
                  let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
                  info["CBCManagedBundle"] as? Bool == true,
                  info["CFBundleIdentifier"] as? String == id else { return false }
            return true
        }
        guard owned.count <= 1 else { throw AdapterError("Multiple apps for this destination exist in the output directory. Remove the duplicate first.") }
        let name = configuration.displayName.unicodeScalars.map {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " —-()._")).contains($0) ? String($0) : "_"
        }.joined()
        let target = owned.first ?? directory.appendingPathComponent("\(name.prefix(100)) [\(id.suffix(12))].app")
        if fm.fileExists(atPath: target.path) {
            guard owned.contains(target), try target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw AdapterError("Refusing to overwrite an unrelated app or symbolic link.")
            }
        }
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
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1",
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
        try icon(configuration: configuration).write(to: resources.appendingPathComponent("Destination.icns"))
        try runTool("/usr/bin/codesign", ["--force", "--sign", "-", staging.path], failure: "Could not ad-hoc sign the app.")
        try runTool("/usr/bin/codesign", ["--verify", "--strict", staging.path], failure: "Generated app signature verification failed.")
        let exists = fm.fileExists(atPath: target.path)
        let flags = exists ? UInt32(RENAME_SWAP) : UInt32(RENAME_EXCL)
        guard renameatx_np(AT_FDCWD, staging.path, AT_FDCWD, target.path, flags) == 0 else {
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

    private static func icon(configuration: DestinationConfiguration) throws -> Data {
        var chunks = Data()
        for (size, type) in [(128, "ic07"), (256, "ic08"), (512, "ic09"), (1024, "ic10")] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw AdapterError("Could not render the app icon.") }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            let s = CGFloat(size)
            let seed = configuration.destination.bundleIdentifier.suffix(6)
            let hue = CGFloat(Int(seed, radix: 16) ?? 0) / CGFloat(0xffffff)
            NSColor(calibratedHue: hue, saturation: 0.7, brightness: 0.8, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: s * 0.08, y: s * 0.08, width: s * 0.84, height: s * 0.84),
                         xRadius: s * 0.18, yRadius: s * 0.18).fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: s * 0.42), .foregroundColor: NSColor.white]
            let mark = "B" as NSString
            let measured = mark.size(withAttributes: attributes)
            mark.draw(at: NSPoint(x: (s - measured.width) / 2, y: s * 0.38), withAttributes: attributes)
            let subtitle = String(configuration.displayName.replacingOccurrences(of: "Brave — ", with: "").prefix(3)).uppercased() as NSString
            let small: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: s * 0.13), .foregroundColor: NSColor.white]
            subtitle.draw(at: NSPoint(x: (s - subtitle.size(withAttributes: small).width) / 2, y: s * 0.22), withAttributes: small)
            NSGraphicsContext.restoreGraphicsState()
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw AdapterError("Could not encode the app icon.") }
            chunks.append(Data(type.utf8))
            chunks.append(bigEndian: UInt32(png.count + 8))
            chunks.append(png)
        }
        var result = Data("icns".utf8)
        result.append(bigEndian: UInt32(chunks.count + 8))
        result.append(chunks)
        return result
    }
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        var value = value.bigEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
