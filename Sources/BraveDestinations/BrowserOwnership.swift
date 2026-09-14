import Darwin
import Foundation

public enum BrowserOwner: Equatable, Sendable {
    case available
    case running(pid: Int32, executable: URL)
    case unknown

    public func validate(executable: URL) throws {
        switch self {
        case .available: return
        case .unknown:
            throw AdapterError("Cannot establish which process owns this user data directory. Wait for Brave to finish starting or closing, then run cbc doctor. Nothing was launched.")
        case .running(_, let owner):
            guard owner.resolvingSymlinksInPath() == executable.resolvingSymlinksInPath() else {
                throw AdapterError("This user data directory is open in a different browser installation. Close that instance before using this destination.")
            }
        }
    }

    public func activationCandidate(executable: URL, launched: BrowserOwner) -> Int32? {
        guard (try? validate(executable: executable)) != nil else { return nil }
        if case .running(let pid, _) = self { return pid }
        guard case .running(let pid, let actual) = launched,
              actual.resolvingSymlinksInPath() == executable.resolvingSymlinksInPath() else { return nil }
        return pid
    }
}

public struct BrowserOwnershipProbe: Sendable {
    private let host: String
    private let processExists: @Sendable (Int32) -> Bool
    private let executable: @Sendable (Int32) -> URL?

    public init() {
        // Chromium writes the POSIX hostname, which can differ from Foundation's DNS name.
        var name = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
        host = gethostname(&name, name.count) == 0
            ? String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            : ""
        processExists = { pid in Darwin.kill(pid, 0) == 0 || errno == EPERM }
        executable = { pid in
            var buffer = [CChar](repeating: 0, count: 4096)
            let count = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
            guard count > 0 else { return nil }
            let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self))
        }
    }

    init(host: String, processExists: @escaping @Sendable (Int32) -> Bool,
         executable: @escaping @Sendable (Int32) -> URL?) {
        self.host = host
        self.processExists = processExists
        self.executable = executable
    }

    public func process(_ pid: Int32) -> BrowserOwner {
        guard pid > 0 else { return .unknown }
        guard processExists(pid) else { return .available }
        guard let path = executable(pid) else { return .unknown }
        return .running(pid: pid, executable: path)
    }

    public func inspect(userData: String) -> BrowserOwner {
        let lock = URL(fileURLWithPath: userData).appendingPathComponent("SingletonLock").path
        var info = stat()
        guard lstat(lock, &info) == 0 else { return errno == ENOENT ? .available : .unknown }
        guard !host.isEmpty, info.st_mode & S_IFMT == S_IFLNK,
              let target = try? FileManager.default.destinationOfSymbolicLink(atPath: lock),
              let separator = target.lastIndex(of: "-"), String(target[..<separator]) == host,
              let pid = Int32(target[target.index(after: separator)...]), pid > 0 else { return .unknown }
        return process(pid)
    }
}
