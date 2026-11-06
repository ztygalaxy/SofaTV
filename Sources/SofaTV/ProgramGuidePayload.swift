import Foundation
import zlib

enum ProgramGuidePayload {
    static let maximumDownloadBytes = 8 * 1_024 * 1_024
    static let maximumXMLBytes = 64 * 1_024 * 1_024

    enum Failure: Error {
        case tooLarge, invalidCompression
    }

    /// A .gz URL may return plain XML after HTTP decompression; inspect the bytes.
    static func xmlData(from data: Data, limit: Int = maximumXMLBytes) throws -> Data {
        guard data.count <= maximumDownloadBytes else { throw Failure.tooLarge }
        guard data.starts(with: [0x1f, 0x8b]) else {
            guard data.count <= limit else { throw Failure.tooLarge }
            return data
        }
        var stream = z_stream()
        guard inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw Failure.invalidCompression
        }
        defer { inflateEnd(&stream) }
        return try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            var result = Data()
            var buffer = [UInt8](repeating: 0, count: 32_768)
            while true {
                let (status, written) = buffer.withUnsafeMutableBytes { output -> (Int32, Int) in
                    stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(output.count)
                    let status = inflate(&stream, Z_NO_FLUSH)
                    return (status, output.count - Int(stream.avail_out))
                }
                guard result.count + written <= limit else { throw Failure.tooLarge }
                result.append(contentsOf: buffer.prefix(written))
                if status == Z_STREAM_END { return result }
                guard status == Z_OK, written > 0 || stream.avail_in > 0 else { throw Failure.invalidCompression }
            }
        }
    }
}
