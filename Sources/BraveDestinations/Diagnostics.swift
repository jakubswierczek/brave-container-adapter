import CoreFoundation
import Darwin
import Foundation

public enum Diagnostics {
    public static func report(paths: BravePaths, installedApps: [URL] = [], installedAppIssues: [String] = []) -> String {
        let discovery = Discovery(paths: paths)
        var sections = [[
            "Brave Container Adapter diagnostics",
            "adapter: \(ReleaseVersion.version) (\(ReleaseVersion.build))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "CPU: \(architecture())",
            "timestamp: \(ISO8601DateFormatter().string(from: Date()))",
        ]]
        sections.append(installation(paths))
        let root = URL(fileURLWithPath: paths.userData)
        var stateLines = ["Local State:"] + fileStatus(root.appendingPathComponent("Local State"))
        var entries: [String: Any] = [:]
        if let data = read(root.appendingPathComponent("Local State"), lines: &stateLines),
           let value = parse(data, lines: &stateLines) {
            let json = value as? [String: Any] ?? [:]
            let cache = (json["profile"] as? [String: Any])?["info_cache"]
            stateLines.append("  profile.info_cache: " + (cache.map(describe) ?? "absent"))
            entries = cache as? [String: Any] ?? [:]
            for key in entries.keys.sorted() {
                let name = (entries[key] as? [String: Any])?["name"] as? String
                stateLines.append("  profile: \(key)  \(name ?? "(name absent or invalid)")")
            }
            let flags = (json["browser"] as? [String: Any])?["enabled_labs_experiments"] as? [Any] ?? []
            let containerFlags = flags.compactMap { $0 as? String }.filter { $0.localizedCaseInsensitiveContains("container") }
            stateLines.append("  container flags: \(containerFlags.count)")
            stateLines += containerFlags.map { "  flag: \($0)" }
        }
        do { stateLines.append("  explicitlyDisabledFeature: \(try discovery.explicitlyDisabledFeature())") }
        catch { stateLines.append("  explicitlyDisabledFeature error: \(safeError(error))") }
        do {
            let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
                .filter { isProfileDirectory($0.lastPathComponent) && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .map(\.lastPathComponent)
            let unlisted = Set(directories).subtracting(entries.keys).sorted()
            stateLines.append("  directories absent from info_cache: \(unlisted.count)")
            stateLines += unlisted.map { "  unlisted directory: \($0)" }
        } catch { stateLines.append("  directory enumeration error: Could not list userData directories.") }
        for key in entries.keys.sorted() {
            do {
                let profile = try profileURL(key, root: root)
                var isDirectory: ObjCBool = false
                if !FileManager.default.fileExists(atPath: profile.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
                    stateLines.append("  info_cache entry without directory: \(key)")
                }
            } catch { stateLines.append("  profile directory error: \(key): \(safeError(error))") }
        }
        sections.append(stateLines)
        for directory in entries.keys.sorted() {
            sections.append(profile(directory, root: root, discovery: discovery))
        }
        var ownerLines = ["Singleton owner:"]
        switch BrowserOwnershipProbe().inspect(userData: paths.userData) {
        case .available: ownerLines.append("  state: available"); ownerLines.append("  matches executable: not applicable")
        case .unknown: ownerLines.append("  state: unknown"); ownerLines.append("  matches executable: unknown")
        case .running(let pid, let executable):
            ownerLines += ["  state: running", "  pid: \(pid)", "  executable: \(executable.path)",
                           "  matches executable: \(executable.resolvingSymlinksInPath() == paths.executable.resolvingSymlinksInPath())"]
        }
        sections.append(ownerLines)
        sections.append(apps(installedApps, paths: paths) + installedAppIssues.map { "  enumeration error: \($0)" })
        var summary = ["Discovery summary:"]
        do {
            let scan = try discovery.scan()
            summary += scan.problems.map { "  problem: \($0)" }
            summary.append("  ready destinations: \(scan.destinations.count)")
        } catch {
            summary += ["  error: \(safeError(error))", "  ready destinations: 0 (scan failed)"]
        }
        sections.append(summary)
        sections.append(["This report lists profile and container names, flag names and ~-relative paths. It contains no URLs, cookies, history or other preference values. Review names before sharing."])
        return sections.map { $0.map(safeLine).joined(separator: "\n") }.joined(separator: "\n\n") + "\n"
    }

    static func redactHome(_ text: String, home: String = NSHomeDirectory()) -> String {
        text.replacingOccurrences(of: NSRegularExpression.escapedPattern(for: home) + #"(?=/|$|[\s.,:)])"#,
                                  with: "~", options: .regularExpression)
    }

    private static func safeLine(_ text: String) -> String {
        redactHome(text).unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? "\\u{\(String($0.value, radix: 16))}" : String($0)
        }.joined()
    }

    private static func safeError(_ error: Error) -> String {
        (error as? AdapterError)?.message ?? "Read failed; contents and system error details omitted."
    }

    private static func architecture() -> String {
        var value = utsname()
        guard uname(&value) == 0 else { return "unknown" }
        return withUnsafeBytes(of: &value.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static func location(_ path: String, key: String) -> [String] {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return ["  \(key): \(path)", "  \(key) exists: \(exists)", "  \(key) is directory: \(isDirectory.boolValue)"]
    }

    private static func installation(_ paths: BravePaths) -> [String] {
        var lines = ["Paths:"] + location(paths.application, key: "application") + location(paths.userData, key: "userData")
        let plist = URL(fileURLWithPath: paths.application).appendingPathComponent("Contents/Info.plist")
        do {
            let data = try BoundedFile.read(at: plist, limit: FileReadLimit.configuration)
            if let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                lines += ["  Info.plist readable: true", "  CFBundleExecutable: \(info["CFBundleExecutable"] as? String ?? "absent or invalid")",
                          "  CFBundleShortVersionString: \(info["CFBundleShortVersionString"] as? String ?? "absent or invalid")"]
            } else { lines.append("  Info.plist error: Expected a dictionary.") }
        } catch { lines.append("  Info.plist error: \(safeError(error))") }
        lines.append("  executable present: \(FileManager.default.isExecutableFile(atPath: paths.executable.path))")
        do {
            let installation = try BraveInstallation(paths: paths)
            lines += ["  BraveInstallation version: \(installation.version)",
                      "  supportsTemporaryContainers: \(installation.supportsTemporaryContainers)"]
        } catch { lines.append("  BraveInstallation error: \(safeError(error))") }
        return lines
    }

    private static func fileStatus(_ url: URL) -> [String] {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            return ["  exists: \(errno == ENOENT ? "false" : "unknown")", "  regular file: unknown", "  byte size: unknown"]
        }
        return ["  exists: true", "  regular file: \(info.st_mode & S_IFMT == S_IFREG)", "  byte size: \(info.st_size)"]
    }

    private static func read(_ url: URL, lines: inout [String]) -> Data? {
        do { return try BoundedFile.read(at: url, limit: FileReadLimit.metadata) }
        catch { lines.append("  read error: \(safeError(error))"); return nil }
    }

    private static func parse(_ data: Data, lines: inout [String]) -> Any? {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            lines.append("  JSON parses: true (\(jsonType(json)))")
            return json
        } catch { lines.append("  JSON parses: false"); return nil }
    }

    private static func isProfileDirectory(_ name: String) -> Bool {
        if name == "Default" { return true }
        guard name.hasPrefix("Profile ") else { return false }
        let suffix = name.dropFirst("Profile ".count)
        return !suffix.isEmpty && suffix.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func profileURL(_ directory: String, root: URL) throws -> URL {
        try Destination.validateProfileDirectory(directory)
        let url = root.appendingPathComponent(directory).resolvingSymlinksInPath()
        guard url.deletingLastPathComponent().path == root.path else {
            throw AdapterError("Profile directory resolves outside the selected user data directory.")
        }
        return url
    }

    private static func profile(_ directory: String, root: URL, discovery: Discovery) -> [String] {
        var lines = ["Profile: \(directory)"]
        do {
            let url = try profileURL(directory, root: root).appendingPathComponent("Preferences")
            lines.append("  Preferences: \(url.path)")
            lines += fileStatus(url)
            if let data = read(url, lines: &lines) {
                if let json = parse(data, lines: &lines) { lines += preferenceShape(json) }
                lines += strictDecode(data)
            }
        } catch { lines.append("  Preferences error: \(safeError(error))") }
        do {
            let snapshot = try discovery.containers(profileDirectory: directory)
            lines += ["  enabled: \(snapshot.enabled)", "  configured count: \(snapshot.configured.map { String($0.count) } ?? "unavailable")",
                      "  retained count: \(snapshot.retained.count)"]
            lines += (snapshot.configured ?? []).map { "  configured: \($0.id)  \($0.name)" }
        } catch { lines.append("  Discovery.containers error: \(safeError(error))") }
        return lines
    }

    static func jsonType(_ value: Any) -> String {
        switch value {
        case is NSNull: return "null"
        case is String: return "string"
        case let number as NSNumber: return CFGetTypeID(number) == CFBooleanGetTypeID() ? "bool" : "number"
        case is [Any]: return "array"
        case is [String: Any]: return "object"
        default: return "unknown"
        }
    }

    private static func describe(_ value: Any) -> String {
        let type = jsonType(value)
        switch type {
        case "string": return "string (length: \((value as! String).count))"
        case "bool": return "bool (value: \((value as! NSNumber).boolValue))"
        case "number": return "number (value: \(value))"
        case "array": return "array (count: \((value as! [Any]).count))"
        case "object": return "object (count: \((value as! [String: Any]).count))"
        default: return type
        }
    }

    static func preferenceShape(_ json: Any) -> [String] {
        let root = json as? [String: Any] ?? [:]
        var lines = ["  brave: " + (root["brave"].map(jsonType) ?? "absent")]
        let brave = root["brave"] as? [String: Any] ?? [:]
        lines.append("  brave.containers: " + (brave["containers"].map(jsonType) ?? "absent"))
        if let containers = brave["containers"] as? [String: Any] {
            for key in containers.keys.sorted() { lines.append("  \(key): \(describe(containers[key]!))") }
            for key in ["list", "used"] {
                let records: [Any]
                if key == "list" { records = containers[key] as? [Any] ?? [] }
                else { records = (containers[key] as? [String: Any]).map { Array($0.values) } ?? [] }
                let shapes = Dictionary(grouping: records) { record in
                    (record as? [String: Any]).map { object in
                        object.keys.sorted().map { "\($0): \(jsonType(object[$0]!))" }.joined(separator: ", ")
                    } ?? jsonType(record)
                }
                for shape in shapes.keys.sorted() { lines.append("  \(key) record shape: \(shape) (count: \(shapes[shape]!.count))") }
            }
        }
        var hits: [String] = []
        searchKeys(brave, path: "brave", depth: 0, hits: &hits)
        lines.append("  container key search: \(hits.count) hits (depth <= 4, max 20)")
        lines += hits.map { "  key: \($0)" }
        return lines
    }

    private static func searchKeys(_ value: Any, path: String, depth: Int, hits: inout [String]) {
        guard depth < 4, hits.count < 20 else { return }
        if let object = value as? [String: Any] {
            for key in object.keys.sorted() {
                guard hits.count < 20 else { return }
                let next = path + "." + key
                if key.localizedCaseInsensitiveContains("container") { hits.append(next + ": " + jsonType(object[key]!)) }
                searchKeys(object[key]!, path: next, depth: depth + 1, hits: &hits)
            }
        } else if let array = value as? [Any] {
            for (index, item) in array.enumerated() {
                guard hits.count < 20 else { return }
                searchKeys(item, path: "\(path)[\(index)]", depth: depth + 1, hits: &hits)
            }
        }
    }

    static func strictDecode(_ data: Data) -> [String] {
        do { _ = try JSONDecoder().decode(Preferences.self, from: data); return ["  strict decode: succeeded"] }
        catch let error as DecodingError {
            let kind: String
            let context: DecodingError.Context
            var expected: String?
            switch error {
            case .typeMismatch(let type, let value): kind = "typeMismatch"; context = value; expected = String(describing: type)
            case .valueNotFound(let type, let value): kind = "valueNotFound"; context = value; expected = String(describing: type)
            case .keyNotFound(let key, let value):
                return ["  strict decode: keyNotFound", "  coding path: \(codingPath(value.codingPath + [key]))"]
            case .dataCorrupted(let value): kind = "dataCorrupted"; context = value
            @unknown default: return ["  strict decode: unknown DecodingError"]
            }
            return ["  strict decode: \(kind)", "  coding path: \(codingPath(context.codingPath))"] +
                (expected.map { ["  expected type: \($0)"] } ?? [])
        } catch { return ["  strict decode: failed (details omitted)"] }
    }

    private static func codingPath(_ keys: [any CodingKey]) -> String {
        let path = keys.reduce("") { path, key in
            if let index = key.intValue, key.stringValue == "Index \(index)" { return path + "[\(index)]" }
            return path + (path.isEmpty ? "" : ".") + key.stringValue
        }
        return path.isEmpty ? "<root>" : path
    }

    private static func apps(_ urls: [URL], paths: BravePaths) -> [String] {
        var lines = ["Installed destination apps:", "  count: \(urls.count)"]
        for app in urls.sorted(by: { $0.path < $1.path }) {
            lines.append("  app: \(app.path)")
            do {
                let saved = try DestinationConfiguration.read(from: app.appendingPathComponent("Contents/Resources/destination.json"))
                let data = try BoundedFile.read(at: app.appendingPathComponent("Contents/Info.plist"), limit: FileReadLimit.configuration)
                guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      info["CBCManagedBundle"] as? Bool == true,
                      info["CFBundleIdentifier"] as? String == saved.destination.bundleIdentifier else {
                    throw AdapterError("App ownership or bundle identity does not match its configuration.")
                }
                let selection: String
                switch saved.destination.selection {
                case .temporary: selection = "temporary"
                case .configured(let id): selection = "configured \(id)"
                }
                lines += ["  display name: \(saved.displayName)", "  profile directory: \(saved.destination.profileDirectory)",
                          "  selection: \(selection)", "  bundle id: \(saved.destination.bundleIdentifier)",
                          "  saved paths match: \(saved.destination.paths == paths)"]
            } catch { lines.append("  read error: \(safeError(error))") }
        }
        return lines
    }
}
