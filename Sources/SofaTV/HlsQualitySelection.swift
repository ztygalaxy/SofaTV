import Foundation
import CoreMedia

struct HlsResolution: Equatable, Sendable {
    let width: Int
    let height: Int
    var pixels: Int { width * height }
    var description: String { "\(width)×\(height)" }
}

struct HlsVariant: Sendable {
    let info: String
    let url: URL
    let bandwidth: Int
    let advertised: HlsResolution?
}

struct HlsVariantProbe: Sendable {
    let variant: HlsVariant
    let actual: HlsResolution?
    var matchesAdvertised: Bool {
        guard let expected = variant.advertised, let actual else { return false }
        return actual.width >= expected.width && actual.height >= expected.height
    }
}

enum HlsQualitySelection {
    static func variants(_ data: Data, base: URL) -> [HlsVariant] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var info: String?; var result: [HlsVariant] = []
        func number(_ pattern: String, in line: String) -> Int? {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range(at: 1), in: line) else { return nil }
            return Int(line[range])
        }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXT-X-STREAM-INF:") { info = line; continue }
            guard !line.isEmpty, !line.hasPrefix("#"), let attributes = info else { continue }
            info = nil
            guard let url = URL(string: line, relativeTo: base)?.absoluteURL, ["http", "https"].contains(url.scheme) else { continue }
            let width = number("RESOLUTION=(\\d+)x", in: attributes)
            let height = number("RESOLUTION=\\d+x(\\d+)", in: attributes)
            let resolution = width.flatMap { w in height.map { HlsResolution(width: w, height: $0) } }
            result.append(HlsVariant(info: attributes, url: url, bandwidth: number("(?:^|[:,])BANDWIDTH=(\\d+)", in: attributes) ?? 0, advertised: resolution))
        }
        return result.sorted {
            if $0.bandwidth != $1.bandwidth { return $0.bandwidth < $1.bandwidth }
            return ($0.advertised?.pixels ?? 0) < ($1.advertised?.pixels ?? 0)
        }
    }

    static func ordered(_ variants: [HlsVariant], quality: Int) -> [HlsVariant] {
        if quality == 2 { return variants }
        if quality == 0 { return Array(variants.reversed()) }
        let preferred = max(0, (variants.count - 1) / 2)
        return variants.indices.sorted {
            let a = abs($0 - preferred), b = abs($1 - preferred)
            return a == b ? $0 > $1 : a < b
        }.map { variants[$0] }
    }

    static func best(_ probes: [HlsVariantProbe], quality: Int) -> HlsVariantProbe? {
        let candidates = probes.contains(where: { $0.actual != nil }) ? probes.filter { $0.actual != nil } : probes
        let sorted = candidates.sorted { ($0.actual?.pixels ?? 0) < ($1.actual?.pixels ?? 0) }
        guard !sorted.isEmpty else { return nil }
        return sorted[quality == 2 ? 0 : quality == 1 ? (sorted.count - 1) / 2 : sorted.count - 1]
    }

    /// Read the SPS from bounded TS bytes; private H5E markers leave its geometry readable.
    static func resolution(in data: Data) -> HlsResolution? {
        let bytes = [UInt8](data.prefix(384 * 1024))
        var videoPID: Int?; var payload: [UInt8] = []
        for packet in stride(from: 0, to: bytes.count - bytes.count % 188, by: 188) {
            guard bytes[packet] == 0x47 else { return nil }
            let pid = Int(bytes[packet + 1] & 31) * 256 + Int(bytes[packet + 2])
            let control = bytes[packet + 3] >> 4 & 3
            guard control & 1 != 0 else { continue }
            var offset = packet + 4
            if control & 2 != 0 { offset += 1 + Int(bytes[packet + 4]) }
            guard offset < packet + 188 else { continue }
            if bytes[packet + 1] & 0x40 != 0, offset + 9 <= packet + 188,
               bytes[offset] == 0, bytes[offset + 1] == 0, bytes[offset + 2] == 1 {
                guard (0xe0...0xef).contains(bytes[offset + 3]) else { continue }
                videoPID = pid; offset += 9 + Int(bytes[offset + 8])
            }
            guard pid == videoPID, offset < packet + 188 else { continue }
            payload.append(contentsOf: bytes[offset..<(packet + 188)])
        }
        var starts: [(Int, Int)] = []; var i = 0
        while i + 3 < payload.count {
            if payload[i] == 0, payload[i + 1] == 0 {
                if payload[i + 2] == 1 { starts.append((i, 3)); i += 3; continue }
                if payload[i + 2] == 0, payload[i + 3] == 1 { starts.append((i, 4)); i += 4; continue }
            }
            i += 1
        }
        var sps: [UInt8]?; var pps: [UInt8]?
        for (index, start) in starts.enumerated() {
            let begin = start.0 + start.1
            let end = index + 1 < starts.count ? starts[index + 1].0 : payload.count
            guard begin < end else { continue }
            let type = payload[begin] & 31
            if type == 7, sps == nil { sps = Array(payload[begin..<end]); if sps!.count > 2 { sps![2] &= 0xfc } }
            if type == 8, pps == nil { pps = Array(payload[begin..<end]) }
            if sps != nil && pps != nil { break }
        }
        guard let sps, let pps else { return nil }
        var format: CMVideoFormatDescription?
        let status = sps.withUnsafeBufferPointer { s in pps.withUnsafeBufferPointer { p in
            let pointers = [s.baseAddress!, p.baseAddress!]; let sizes = [s.count, p.count]
            return pointers.withUnsafeBufferPointer { ptr in sizes.withUnsafeBufferPointer { size in
                CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: 2, parameterSetPointers: ptr.baseAddress!, parameterSetSizes: size.baseAddress!, nalUnitHeaderLength: 4, formatDescriptionOut: &format)
            }}
        }}
        guard status == noErr, let format else { return nil }
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        guard dimensions.width > 0, dimensions.height > 0 else { return nil }
        return HlsResolution(width: Int(dimensions.width), height: Int(dimensions.height))
    }
}
