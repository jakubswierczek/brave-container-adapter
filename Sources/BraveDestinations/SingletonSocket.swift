import Darwin
import Foundation

/// Corroborates a changed hostname through Chromium's local singleton endpoint.
/// Opens an empty connection; never sends a browser command or modifies its files.
enum SingletonSocket {
    static func belongsTo(pid: Int32, userData: String) -> Bool {
        let root = URL(fileURLWithPath: userData)
        guard let endpoint = endpoint(root: root) else { return false }
        var info = stat()
        var volume = statfs()
        guard lstat(endpoint.path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK,
              info.st_uid == geteuid(), statfs(endpoint.path, &volume) == 0,
              volume.f_flags & UInt32(MNT_LOCAL) != 0 else { return false }

        var address = sockaddr_un()
        let bytes = Array(endpoint.path.utf8)
        guard !bytes.isEmpty, bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return false }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.offset(of: \.sun_path)! + bytes.count)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0,
              fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else { return false }
        let addressLength = socklen_t(address.sun_len)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, addressLength)
            }
        }
        if connected != 0 {
            guard errno == EINPROGRESS else { return false }
            var pending = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
            guard poll(&pending, 1, 100) == 1, pending.revents & Int16(POLLOUT) != 0 else { return false }
            var error: Int32 = 0
            var size = socklen_t(MemoryLayout.size(ofValue: error))
            guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else { return false }
        }
        var peer: Int32 = 0
        var size = socklen_t(MemoryLayout.size(ofValue: peer))
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &peer, &size) == 0,
              size == MemoryLayout.size(ofValue: peer), peer == pid else { return false }
        return self.endpoint(root: root) == endpoint
    }

    private struct Endpoint: Equatable {
        let path: String
        let cookie: String
    }

    private static func endpoint(root: URL) -> Endpoint? {
        let manager = FileManager.default
        guard let path = try? manager.destinationOfSymbolicLink(atPath: root.appendingPathComponent("SingletonSocket").path),
              path.hasPrefix("/"),
              let cookie = try? manager.destinationOfSymbolicLink(atPath: root.appendingPathComponent("SingletonCookie").path),
              !cookie.isEmpty,
              let remoteCookie = try? manager.destinationOfSymbolicLink(atPath:
                URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("SingletonCookie").path),
              cookie == remoteCookie else { return nil }
        return Endpoint(path: path, cookie: cookie)
    }
}
