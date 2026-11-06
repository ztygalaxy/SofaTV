import Foundation
final class FakeCmgAPI: CmgNativeAPI {
    var restarts = 0
    var initializedTags: [String] = []
    var fallbackTags: [UInt32] = []
    var decoded = 0
    func initialize(tag: String, location: String) -> Bool { restarts += 1; initializedTags.append(tag); return true }
    func clock(_ time: UInt64) {}
    func update() -> UInt32 { 0 }
    func setUpdateTag(_ tag: UInt32) { fallbackTags.append(tag) }
    func decode(_ data: inout [UInt8]) -> Int { decoded += 1; return data.count }
}
@main struct CmgChecks {
    static func transport(_ nals: [[UInt8]]) -> Data {
        var pes: [UInt8] = [0,0,1,0xe0,0,0,0x80,0,0]
        for nal in nals { pes += [0,0,0,1]; pes += nal }
        var data = Data(); var cursor = 0; var cc: UInt8 = 0
        while cursor < pes.count {
            let count = min(184, pes.count - cursor)
            var packet = [UInt8](repeating: 0xff, count: 188)
            packet[0] = 0x47; packet[1] = cursor == 0 ? 0x41 : 0x01; packet[2] = 0
            packet[3] = (count == 184 ? 0x10 : 0x30) | cc
            let offset = 188 - count
            if count < 184 { packet[4] = UInt8(183 - count); if count < 183 { packet[5] = 0 } }
            packet.replaceSubrange(offset..<188, with: pes[cursor..<(cursor+count)])
            data.append(contentsOf: packet); cursor += count; cc = (cc + 1) & 15
        }
        return data
    }
    static func longPlaybackChecks() throws {
        let api = FakeCmgAPI(); let runtime = CmgRuntime(api: api)
        try runtime.configure(tag: "session-A", location: "https://example.com", timestamp: 1, nativeTrace: "", updates: "0,12;1,34", base: 1)
        let sps: [UInt8] = [0x67,0x64,0x01,0x1f]
        let frames = Array(repeating: [UInt8]([0x65,0xaa,0xbb]), count: 160)
        let tail = Array(repeating: [UInt8]([0x41,0xcc,0xdd]), count: 10)
        let source = transport([sps] + frames + [sps] + tail)
        for _ in 0..<30 {
            let output = try runtime.transformSegment(source)
            precondition(output.count == source.count)
            precondition(runtime.lastVCLCount == 170 && runtime.lastBoundaryRestarts == 1)
        }
        precondition(api.restarts == 60, "each segment and SPS budget must independently reset runtime")
        precondition(api.fallbackTags.allSatisfy { $0 == 34 }, "refresh must retain captured stable update tag")
        let other = CmgRuntime(api: api)
        try other.configure(tag: "session-B", location: "https://example.com", timestamp: 1, nativeTrace: "", updates: "", base: 1)
        _ = try other.transformSegment(transport([sps, [0x65,0xaa]]))
        _ = try runtime.transformSegment(transport([sps, [0x65,0xaa]]))
        precondition(Array(api.initializedTags.suffix(2)) == ["session-B", "session-A"], "out-of-order old reads must restore their own session")
        var policy = CmgRecoveryPolicy(); policy.beginSegment()
        for _ in 0..<150 { precondition(!policy.beforeNAL(5)); policy.afterNAL(5) }
        precondition(!policy.beforeNAL(5), "must not reset in the middle of an access unit")
        precondition(policy.beforeNAL(7)); precondition(!policy.beforeNAL(7))
        var cache = CmgSegmentCache(maxEntries: 3, maxBytes: 10)
        let keys = (0..<4).map { URL(string: "https://example.com/\($0).ts")! }
        for key in keys.prefix(3) { cache.insert(Data([1,2,3]), for: key) }
        precondition(cache.value(for: keys[0]) != nil)
        cache.insert(Data([4,5,6]), for: keys[3])
        precondition(cache.value(for: keys[0]) != nil && cache.value(for: keys[1]) == nil && cache.byteCount == 9)
        cache.insert(Data(repeating: 1, count: 11), for: keys[3])
        precondition(cache.byteCount <= 10)
        print("Long-play recovery: 5,100 VCLs, SPS-only refresh, per-segment/session isolation and LRU bounds passed")
    }
    static func main() throws {
        let text = "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"key?id=1\"\n../video.ts?token=a%2Bb\n"
        let rewritten = String(data: try CmgAssetLoader.rewrite(Data(text.utf8), base: URL(string: "https://example.com/live/list.m3u8")!), encoding: .utf8)!
        precondition(rewritten.contains("sofatvhttps://example.com/live/key?id=1"))
        precondition(rewritten.contains("sofatvhttps://example.com/video.ts?token=a%2Bb"))
        var packet = [UInt8](repeating: 0xff, count: 188)
        packet[0] = 0x47; packet[1] = 0x41; packet[2] = 0; packet[3] = 0x10
        let pes: [UInt8] = [0,0,1,0xe0,0,0,0x80,0,0,0,0,0,1,0x67,0x64,0,0x1f]
        packet.replaceSubrange(4..<(4+pes.count), with: pes)
        var count = 0
        let output = try CmgTransportStream.transform(Data(packet)) { bytes in count += 1; return bytes }
        precondition(output == Data(packet) && count == 1)
        do { _ = try CmgTransportStream.transform(Data(packet.dropLast())) { $0 }; fatalError("truncation accepted") } catch {}
        let shrunk = try CmgTransportStream.transform(Data(packet)) { Array($0.dropLast()) }
        precondition(shrunk.count == packet.count)
        precondition(shrunk[3] & 0x30 == 0x30 && shrunk[4] == 0)
        do { _ = try CmgTransportStream.transform(Data(packet)) { $0 + [0] }; fatalError("unsafe growth accepted") } catch {}
        try longPlaybackChecks()
        print("CMG playlist, PES preservation and invalid-input checks passed")
    }
}
