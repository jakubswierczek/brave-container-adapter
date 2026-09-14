import Foundation

public struct URLBatch: Sendable {
    public static let maximumURLBytes = 64 * 1024
    public static let maximumURLs = 128
    public static let maximumBytes = 128 * 1024
    public let urls: [WebURL]
    public let byteCount: Int

    public init(_ strings: [String]) throws {
        guard !strings.isEmpty, strings.count <= Self.maximumURLs else {
            throw AdapterError("Send between 1 and 128 URLs per request. This request was rejected.")
        }
        var bytes = 0
        for string in strings {
            guard string.utf8.count <= Self.maximumURLBytes else {
                throw AdapterError("A URL exceeds the 64 KiB limit. This request was rejected; URL contents are omitted.")
            }
            bytes += string.utf8.count + 1
            guard bytes <= Self.maximumBytes else {
                throw AdapterError("The URL batch exceeds 128 KiB. Send smaller batches; this request was rejected.")
            }
        }
        urls = try strings.map(WebURL.init)
        byteCount = bytes
    }
}

/// FIFO backpressure: reject a new batch atomically; never evict an accepted one.
public struct URLRequestQueue: Sendable {
    public static let maximumBatches = 32
    public static let maximumBytes = 1024 * 1024
    private var pending: [URLBatch] = []
    public private(set) var byteCount = 0
    public var isEmpty: Bool { pending.isEmpty }
    public var count: Int { pending.count }
    public init() {}

    public mutating func enqueue(_ batch: URLBatch) throws {
        guard pending.count < Self.maximumBatches, batch.byteCount <= Self.maximumBytes - byteCount else {
            throw AdapterError("Too many pending links. This new request was rejected; earlier accepted requests remain queued. Retry after closing the error alert.")
        }
        pending.append(batch)
        byteCount += batch.byteCount
    }

    public mutating func next() -> URLBatch? {
        guard !pending.isEmpty else { return nil }
        let next = pending.removeFirst()
        byteCount -= next.byteCount
        return next
    }
}
