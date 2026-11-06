import Foundation

/// Same SPS-boundary budget used by NativeWasmTv's HlsProxyServer.
/// Never reset halfway through an access unit.
struct CmgRecoveryPolicy {
    private(set) var vclSinceRestart = 0
    private(set) var boundaryRestarts = 0
    mutating func beginSegment() { vclSinceRestart = 0; boundaryRestarts = 0 }
    mutating func beforeNAL(_ type: UInt8) -> Bool {
        guard type == 7, vclSinceRestart >= 150 else { return false }
        vclSinceRestart = 0; boundaryRestarts += 1
        return true
    }
    mutating func afterNAL(_ type: UInt8) { if type == 1 || type == 5 { vclSinceRestart += 1 } }
}

/// LRU retention avoids repeatedly decoding a segment when AVPlayer retries a read.
struct CmgSegmentCache {
    private var entries: [URL: Data] = [:]
    private var order: [URL] = []
    private(set) var byteCount = 0
    let maxEntries: Int
    let maxBytes: Int
    init(maxEntries: Int = 8, maxBytes: Int = 32 * 1024 * 1024) { self.maxEntries = maxEntries; self.maxBytes = maxBytes }
    mutating func value(for key: URL) -> Data? {
        guard let data = entries[key] else { return nil }
        order.removeAll { $0 == key }; order.append(key)
        return data
    }
    mutating func insert(_ data: Data, for key: URL) {
        if let previous = entries.removeValue(forKey: key) { byteCount -= previous.count }
        order.removeAll { $0 == key }
        guard data.count <= maxBytes else { return }
        entries[key] = data; byteCount += data.count; order.append(key)
        while order.count > maxEntries || byteCount > maxBytes {
            let evicted = order.removeFirst()
            if let removed = entries.removeValue(forKey: evicted) { byteCount -= removed.count }
        }
    }
    mutating func removeAll() { entries.removeAll(); order.removeAll(); byteCount = 0 }
}
