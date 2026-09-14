import Darwin
import Foundation

public enum FileReadLimit {
    public static let metadata = 16 * 1024 * 1024
    public static let configuration = 1024 * 1024
    public static let icon = 32 * 1024 * 1024
}

/// Rejects special files and checks the opened inode as well as its final pathname.
public enum BoundedFile {
    public static func read(at url: URL, limit: Int) throws -> Data {
        let fd = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw AdapterError("Cannot open the file for a safe read. Check permissions and symbolic links.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG else {
            throw AdapterError("Only regular files can be read.")
        }
        guard limit > 0, before.st_size >= 0, before.st_size <= limit else {
            throw AdapterError("File exceeds the safe read limit (\(limit / 1024) KiB).")
        }
        var data = Data()
        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: min(64 * 1024, limit - data.count + 1)) ?? Data()
            if chunk.isEmpty { break }
            guard chunk.count <= limit - data.count else {
                throw AdapterError("File grew beyond the safe read limit.")
            }
            data.append(chunk)
        }
        var after = stat()
        var named = stat()
        guard fstat(fd, &after) == 0, lstat(url.path, &named) == 0,
              unchanged(before, after), unchanged(before, named), data.count == before.st_size else {
            throw AdapterError("File changed during reading. Wait for it to save, then retry.")
        }
        return data
    }

    private static func unchanged(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size && a.st_mode == b.st_mode &&
        a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
        a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
}
