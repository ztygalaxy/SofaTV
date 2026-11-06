import Foundation
import Darwin

protocol CmgNativeAPI: AnyObject {
    func initialize(tag: String, location: String) -> Bool
    func clock(_ time: UInt64)
    func update() -> UInt32
    func setUpdateTag(_ tag: UInt32)
    func decode(_ data: inout [UInt8]) -> Int
}

/// JNI-free ABI over the unchanged upstream generated WASM implementation.
final class CmgNativeLibrary: CmgNativeAPI {
    typealias Initialize = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UInt32) -> Int32
    typealias Decode = @convention(c) (UnsafeMutablePointer<UInt8>?, Int32, Int32, Int32) -> Int32
    typealias Update = @convention(c) () -> UInt32
    typealias Clock = @convention(c) (UInt64) -> Void
    typealias SetTag = @convention(c) (UInt32) -> Void
    private let handle: UnsafeMutableRawPointer
    private let initializeFn: Initialize
    private let decodeFn: Decode
    private let updateFn: Update
    private let clockFn: Clock
    private let setTagFn: SetTag
    init(path: String? = nil) throws {
        let path = path ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libSofaTVCmg.dylib").path
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else { throw CmgError.message("央视频解密库加载失败") }
        func symbol<T>(_ name: String, _: T.Type) throws -> T {
            guard let pointer = dlsym(handle, name) else { throw CmgError.message("央视频解密库接口缺失") }
            return unsafeBitCast(pointer, to: T.self)
        }
        do {
            initializeFn = try symbol("sofatv_cmg_initialize", Initialize.self)
            decodeFn = try symbol("sofatv_cmg_decode", Decode.self)
            updateFn = try symbol("sofatv_cmg_update", Update.self)
            clockFn = try symbol("sofatv_cmg_clock", Clock.self)
            setTagFn = try symbol("sofatv_cmg_set_update_tag", SetTag.self)
        } catch { dlclose(handle); throw error }
        self.handle = handle
    }
    deinit { dlclose(handle) }
    func initialize(tag: String, location: String) -> Bool { tag.withCString { t in location.withCString { initializeFn(t, $0, 0) != 0 } } }
    func clock(_ time: UInt64) { clockFn(time) }
    func update() -> UInt32 { updateFn() }
    func setUpdateTag(_ tag: UInt32) { setTagFn(tag) }
    func decode(_ data: inout [UInt8]) -> Int { data.withUnsafeMutableBufferPointer { Int(decodeFn($0.baseAddress, Int32($0.count), 1, 1)) } }
}

final class CmgRuntime {
    // The C module has process-global state. Own it for an entire segment so a
    // completed download from the previous channel cannot modify a new session.
    private static let executionLock = NSLock()
    private let api: any CmgNativeAPI
    private var tag = ""
    private var location = ""
    private var initialUpdateTag: UInt32 = 0
    private var stableUpdateTag: UInt32 = 0
    private var encrypted = false
    private var policy = CmgRecoveryPolicy()
    private(set) var lastBoundaryRestarts = 0
    private(set) var lastVCLCount = 0
    init(api: any CmgNativeAPI) { self.api = api }
    convenience init() throws { self.init(api: try CmgNativeLibrary()) }
    func configure(tag: String, location: String, timestamp: UInt64, nativeTrace: String, updates: String, base: UInt64) throws {
        guard !tag.isEmpty else { throw CmgError.message("央视频会话标识为空") }
        self.tag = tag; self.location = location
        let captured = updates.split(separator: ";").compactMap { line -> UInt32? in
            guard let value = line.split(separator: ",").last, let number = Int64(value) else { return nil }
            return UInt32(truncatingIfNeeded: number)
        }
        initialUpdateTag = captured.first ?? 0; stableUpdateTag = captured.last ?? 0
    }
    private func restart() throws {
        api.clock(UInt64(Date().timeIntervalSince1970 * 1000))
        guard api.initialize(tag: tag, location: location) else { throw CmgError.message("央视频解密会话初始化失败") }
        encrypted = false
    }
    func transformSegment(_ data: Data) throws -> Data {
        Self.executionLock.lock(); defer { Self.executionLock.unlock() }
        guard !tag.isEmpty else { throw CmgError.message("央视频解密会话尚未配置") }
        // Upstream restarts on every TS segment and again at an SPS after 150 VCLs.
        // This also makes a retried/out-of-order HTTP read independent of prior reads.
        policy.beginSegment(); lastBoundaryRestarts = 0; lastVCLCount = 0
        try restart()
        let output = try CmgTransportStream.transform(data, nal: transformNAL)
        lastBoundaryRestarts = policy.boundaryRestarts
        return output
    }
    private func transformNAL(_ input: [UInt8]) throws -> [UInt8] {
        guard !input.isEmpty, input.count <= Int(Int32.max) else { return input }
        let type = input[0] & 31
        if policy.beforeNAL(type) { try restart() }
        defer { policy.afterNAL(type) }
        if type == 1 || type == 5 { lastVCLCount += 1 }
        if type == 7, input.count > 2 { encrypted = encrypted || [1, 2].contains(input[2] & 3) }
        guard type == 7 || (encrypted && [1, 5].contains(type)) else { return input }
        api.clock(UInt64(Date().timeIntervalSince1970 * 1000))
        if api.update() == 0 {
            let captured = stableUpdateTag != 0 ? stableUpdateTag : initialUpdateTag
            if captured != 0 { api.setUpdateTag(captured) }
        }
        var bytes = input
        let count = api.decode(&bytes)
        // The upstream SPS path advances state but preserves the original SPS bytes.
        if type == 7 { bytes = input; if bytes.count > 2 { bytes[2] &= 0xfc }; return bytes }
        guard count >= 0, count <= input.count else { throw CmgError.message("央视频视频数据解密失败") }
        return Array(bytes.prefix(count))
    }
}
enum CmgError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

/// Reassembles each complete video PES payload and preserves audio, PSI and PCR packets.
enum CmgTransportStream {
    static func transform(_ data: Data, nal: ([UInt8]) throws -> [UInt8]) throws -> Data {
        var bytes = Array(data)
        guard !bytes.isEmpty, bytes.count % 188 == 0 else { throw CmgError.message("视频分段不是完整的 MPEG-TS 数据") }
        var payloadCapacity = 0; var payload: [UInt8] = []; var videoPID: Int?
        var slots: [(packet: Int, offset: Int)] = []
        var header: [UInt8] = []
        var expectedPayload: Int?
        func flush() throws {
            guard !payload.isEmpty else { payloadCapacity = 0; slots = []; header = []; expectedPayload = nil; return }
            if let expectedPayload { payload = Array(payload.prefix(expectedPayload)) }
            var starts: [(Int, Int)] = []; var i = 0
            while i + 3 < payload.count {
                if payload[i] == 0 && payload[i+1] == 0 {
                    if payload[i+2] == 1 { starts.append((i, 3)); i += 3; continue }
                    if payload[i+2] == 0 && payload[i+3] == 1 { starts.append((i, 4)); i += 4; continue }
                }
                i += 1
            }
            var output: [UInt8] = []
            if let first = starts.first { output += payload.prefix(first.0) }
            for (index, start) in starts.enumerated() {
                let end = index + 1 < starts.count ? starts[index + 1].0 : payload.count
                output += payload[start.0..<(start.0 + start.1)]
                output += try nal(Array(payload[(start.0 + start.1)..<end]))
            }
            if starts.isEmpty { output = payload }
            guard output.count <= payloadCapacity else { throw CmgError.message("解密后的 PES 超出原始容量") }
            if header.count >= 9, header[4] != 0 || header[5] != 0 {
                let length = output.count + header.count - 6
                guard length <= 65535 else { throw CmgError.message("PES 长度超出协议范围") }
                header[4] = UInt8(length >> 8); header[5] = UInt8(length & 255)
            }
            let combined = header + output
            var cursor = 0
            for slot in slots {
                let end = slot.packet + 188
                let capacity = end - slot.offset
                let count = min(capacity, combined.count - cursor)
                if count == capacity {
                    bytes.replaceSubrange(slot.offset..<end, with: combined[cursor..<(cursor+count)])
                } else {
                    let oldControl = (bytes[slot.packet+3] >> 4) & 3
                    var adaptation: [UInt8] = []
                    if oldControl & 2 != 0 {
                        let length = Int(bytes[slot.packet+4])
                        if length > 0, slot.packet+5+length <= end { adaptation = Array(bytes[(slot.packet+5)..<(slot.packet+5+length)]) }
                    }
                    // Preserve PCR/OPCR and discontinuity flags while growing adaptation stuffing.
                    for index in (slot.packet+4)..<end { bytes[index] = 0xff }
                    let adaptationLength = 183 - count
                    guard adaptation.count <= adaptationLength else { throw CmgError.message("视频包适配字段容量不足") }
                    bytes[slot.packet+3] = (bytes[slot.packet+3] & 0xcf) | (count == 0 ? 0x20 : 0x30)
                    bytes[slot.packet+4] = UInt8(adaptationLength)
                    if adaptationLength > 0 {
                        bytes[slot.packet+5] = 0
                        if !adaptation.isEmpty { bytes.replaceSubrange((slot.packet+5)..<(slot.packet+5+adaptation.count), with: adaptation) }
                    }
                    if count == 0 { bytes[slot.packet+1] &= 0xbf }
                    else { bytes.replaceSubrange((end-count)..<end, with: combined[cursor..<(cursor+count)]) }
                }
                cursor += count
            }
            guard cursor == combined.count else { throw CmgError.message("视频 PES 重封装不完整") }
            payloadCapacity = 0; payload = []; slots = []; header = []; expectedPayload = nil
        }
        for packet in stride(from: 0, to: bytes.count, by: 188) {
            guard bytes[packet] == 0x47 else { throw CmgError.message("视频分段同步标记损坏") }
            let pid = Int(bytes[packet+1] & 31) << 8 | Int(bytes[packet+2])
            let control = (bytes[packet+3] >> 4) & 3
            guard control & 1 != 0 else { continue }
            var offset = packet + 4
            if control & 2 != 0 { offset += 1 + Int(bytes[offset]) }
            guard offset < packet + 188 else { continue }
            let start = bytes[packet+1] & 64 != 0
            if start, offset + 9 <= packet + 188, bytes[offset] == 0, bytes[offset+1] == 0, bytes[offset+2] == 1, (0xe0...0xef).contains(bytes[offset+3]) {
                if videoPID == nil { videoPID = pid }
                guard pid == videoPID else { continue }
                try flush()
                let length = 9 + Int(bytes[offset+8])
                guard offset + length <= packet + 188 else { throw CmgError.message("跨包 PES 头暂不支持") }
                header = Array(bytes[offset..<(offset+length)])
                let pesLength = Int(header[4]) << 8 | Int(header[5])
                expectedPayload = pesLength == 0 ? nil : max(0, pesLength - (length - 6))
                slots.append((packet, offset))
                offset += length
            } else if start, pid == videoPID { try flush(); continue }
            guard pid == videoPID, offset < packet + 188 else { continue }
            if slots.last?.packet != packet { slots.append((packet, offset)) }
            payloadCapacity += packet + 188 - offset; payload += bytes[offset..<(packet+188)]
        }
        try flush()
        guard let videoPID else { throw CmgError.message("视频分段没有找到 H.264 PES") }
        var counter: Int?
        for packet in stride(from: 0, to: bytes.count, by: 188) {
            let pid = Int(bytes[packet+1] & 31) << 8 | Int(bytes[packet+2])
            guard pid == videoPID else { continue }
            let payload = bytes[packet+3] & 0x10 != 0
            let next = counter.map { payload ? ($0 + 1) & 15 : $0 } ?? Int(bytes[packet+3] & 15)
            bytes[packet+3] = (bytes[packet+3] & 0xf0) | UInt8(next); counter = next
        }
        return Data(bytes)
    }
}
