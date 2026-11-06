import Foundation
import VideoToolbox
import CoreImage
import ImageIO

final class FrameProbe: @unchecked Sendable {
    let lock = NSLock()
    var frames = 0
    var errors: [OSStatus] = []
    var first: CVPixelBuffer?
    func receive(_ status: OSStatus, _ image: CVImageBuffer?) {
        lock.lock(); defer { lock.unlock() }
        if status != 0 { errors.append(status) }
        if let image { frames += 1; if first == nil { first = image } }
    }
}

@main struct H5eFrameProbe {
    static func check(_ directory: URL, runtime: H5eRuntime) throws {
        var nals: [[UInt8]] = []
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix("-encrypted.ts") }.sorted { $0.path < $1.path }
        for file in files {
            let encrypted = try Data(contentsOf: file)
            let clear = try runtime.transformSegment(encrypted)
            precondition(clear.count == encrypted.count && clear != encrypted)
            _ = try CmgTransportStream.transform(clear) { nals.append($0); return $0 }
        }
        guard let sps = nals.first(where: { $0.first.map { $0 & 31 == 7 } == true }),
              let pps = nals.first(where: { $0.first.map { $0 & 31 == 8 } == true }) else { fatalError("Missing parameter sets") }
        var format: CMVideoFormatDescription?
        let status = sps.withUnsafeBufferPointer { s in pps.withUnsafeBufferPointer { p in
            let pointers = [s.baseAddress!, p.baseAddress!]
            let sizes = [s.count, p.count]
            return pointers.withUnsafeBufferPointer { ptr in sizes.withUnsafeBufferPointer { sz in
                CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: 2, parameterSetPointers: ptr.baseAddress!, parameterSetSizes: sz.baseAddress!, nalUnitHeaderLength: 4, formatDescriptionOut: &format)
            }}
        }}
        precondition(status == noErr && format != nil, "Invalid H264 configuration \(status)")
        let probe = FrameProbe()
        var callback = VTDecompressionOutputCallbackRecord(decompressionOutputCallback: { context, _, status, _, image, _, _ in
            if let context { Unmanaged<FrameProbe>.fromOpaque(context).takeUnretainedValue().receive(status, image) }
        }, decompressionOutputRefCon: Unmanaged.passUnretained(probe).toOpaque())
        var session: VTDecompressionSession?
        let create = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: format!, decoderSpecification: nil, imageBufferAttributes: [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA] as CFDictionary, outputCallback: &callback, decompressionSessionOut: &session)
        precondition(create == noErr && session != nil, "Cannot create decoder \(create)")
        defer { VTDecompressionSessionInvalidate(session!) }
        let hasAUD = nals.contains { $0.first.map { $0 & 31 == 9 } == true }
        var units: [[[UInt8]]] = []; var unit: [[UInt8]] = []; var vcl = false
        for nal in nals {
            guard let first = nal.first else { continue }
            let type = first & 31
            if (type == 9 || (!hasAUD && (type == 1 || type == 5))) && vcl {
                units.append(unit); unit = []; vcl = false
            }
            if [1,5,6].contains(type) { unit.append(nal) }
            if type == 1 || type == 5 { vcl = true }
        }
        if vcl { units.append(unit) }
        var started = false; var sent = 0
        for unit in units {
            if unit.contains(where: { $0[0] & 31 == 5 }) { started = true }
            if !started { continue }
            var bytes = Data()
            for nal in unit {
                var length = UInt32(nal.count).bigEndian
                withUnsafeBytes(of: &length) { bytes.append(contentsOf: $0) }
                bytes.append(contentsOf: nal)
            }
            var block: CMBlockBuffer?
            precondition(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes.count, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: bytes.count, flags: 0, blockBufferOut: &block) == noErr)
            precondition(bytes.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: bytes.count) } == noErr)
            var size = bytes.count
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 25), presentationTimeStamp: CMTime(value: Int64(sent), timescale: 25), decodeTimeStamp: .invalid)
            var sample: CMSampleBuffer?
            precondition(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr)
            let result = VTDecompressionSessionDecodeFrame(session!, sampleBuffer: sample!, flags: [._EnableAsynchronousDecompression], frameRefcon: nil, infoFlagsOut: nil)
            if result != noErr { probe.receive(result, nil) }
            sent += 1
        }
        VTDecompressionSessionFinishDelayedFrames(session!)
        VTDecompressionSessionWaitForAsynchronousFrames(session!)
        let dimensions = CMVideoFormatDescriptionGetDimensions(format!)
        print("\(directory.lastPathComponent): submitted=\(sent), decoded=\(probe.frames), errors=\(probe.errors), size=\(dimensions.width)x\(dimensions.height)")
        precondition(probe.frames >= 20 && probe.errors.isEmpty, "Real decoded-frame check failed")
        if CommandLine.arguments.contains("--save-frames"), let first = probe.first, let cg = CIContext().createCGImage(CIImage(cvPixelBuffer: first), from: CGRect(x: 0,y: 0,width: Int(dimensions.width),height: Int(dimensions.height))),
           let output = CGImageDestinationCreateWithURL(directory.appendingPathComponent("decoded-frame.png") as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(output,cg,nil); precondition(CGImageDestinationFinalize(output))
        }
    }
    static func main() throws {
        guard CommandLine.arguments.count >= 3 else { fatalError("Usage: h5e-check fixtures-directory native-library-path [--save-frames]") }
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
        let library = CommandLine.arguments[2]
        let runtime = try H5eRuntime(path: library)
        precondition(H5eRuntime.needsDecryption(URL(string: "https://ldncctvwbcd.example/live.m3u8")!))
        precondition(H5eRuntime.needsDecryption(URL(string: "https://example.com/cdrmldcctv1/index.m3u8")!))
        precondition(!H5eRuntime.needsDecryption(URL(string: "https://example.com/live.m3u8?label=cctvwbcd")!))
        do { _ = try runtime.transformSegment(Data(repeating: 0, count: 188)); fatalError("Invalid TS accepted") }
        catch {}
        // Exercise CMG and H5E in one process, matching a switch from satellite to CCTV.
        let cmgPath = URL(fileURLWithPath: library).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("cmg/libSofaTVCmg.dylib").path
        let cmg = try CmgNativeLibrary(path: cmgPath)
        precondition(cmg.initialize(tag: "h5e-coexistence-check", location: "https://www.yangshipin.cn/"))
        for name in ["CCTV-1","CCTV-2","CCTV-3"] {
            try check(fixtures.appendingPathComponent(name), runtime: runtime)
        }
        precondition(cmg.initialize(tag: "cmg-after-h5e-check", location: "https://www.yangshipin.cn/"))
        let sample = try Data(contentsOf: fixtures.appendingPathComponent("CCTV-1/00-encrypted.ts"))
        let first = try runtime.transformSegment(sample)
        for _ in 0..<12 { let repeated = try runtime.transformSegment(sample); precondition(repeated == first) }
        print("H5E/CMG coexistence, malformed TS and repeated-segment checks passed")
    }
}
