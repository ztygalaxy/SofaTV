import Foundation
import Darwin

/// The C ABI serializes its shared WASM state and restarts it at each TS boundary.
final class H5eRuntime {
    private typealias Decode = @convention(c) (UnsafeMutablePointer<UInt8>?, Int32) -> Int32
    private let handle: UnsafeMutableRawPointer
    private let decode: Decode

    init(path: String? = nil) throws {
        let path = path ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libSofaTVH5e.dylib").path
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else { throw H5eError.message("央视原生解密库加载失败") }
        guard let symbol = dlsym(handle, "sofatv_h5e_decode") else {
            dlclose(handle); throw H5eError.message("央视原生解密库接口缺失")
        }
        self.handle = handle
        decode = unsafeBitCast(symbol, to: Decode.self)
    }
    deinit { dlclose(handle) }

    static func needsDecryption(_ url: URL) -> Bool {
        (url.host?.lowercased().contains("cctvwbcd") == true) || url.path.lowercased().contains("cdrmld")
    }

    func transformSegment(_ input: Data) throws -> Data {
        guard !input.isEmpty, input.count <= 32 * 1024 * 1024, input.count % 188 == 0 else {
            throw H5eError.message("央视视频分段不完整")
        }
        var lastResult: Int32 = -1
        for _ in 0..<2 {
            // A failed transform may have touched its buffer. Retry the original ciphertext.
            var output = input
            lastResult = output.withUnsafeMutableBytes { bytes in
                decode(bytes.bindMemory(to: UInt8.self).baseAddress, Int32(bytes.count))
            }
            if lastResult == input.count { return output }
        }
        throw H5eError.message("央视视频解密失败（\(lastResult)）")
    }
}

enum H5eError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
