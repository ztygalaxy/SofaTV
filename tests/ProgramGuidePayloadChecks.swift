import Foundation

@main struct ProgramGuidePayloadChecks {
    static func main() throws {
        let plain = Data(#"<tv><programme channel="cctv1" start="20261106100000 +0000" stop="20261106110000 +0000"><title>Test &amp; current</title></programme></tv>"#.utf8)
        let zipped = Data(base64Encoded: "H4sIAAAAAAAC/7MpKbOzKSjKTy9KzM1NVUjOSMzLS82xVUpOLikzVFIoLkksKrFVMjIwMjM0NDAzNAABBW0QCZLML0CSM0SSs7MpySzJSbULSS0uUVBLzC2wVkguLSpKzSux0YfI2OjDbQWyga4AAPmCW7iKAAAA")!
        let decodedPlain = try ProgramGuidePayload.xmlData(from: plain)
        let decodedGzip = try ProgramGuidePayload.xmlData(from: zipped)
        precondition(decodedPlain == plain && decodedGzip == plain)
        for input in [Data(zipped.dropLast(8)), Data([0x1f, 0x8b, 0, 1, 2, 3])] {
            do { _ = try ProgramGuidePayload.xmlData(from: input); preconditionFailure("Invalid gzip accepted") }
            catch ProgramGuidePayload.Failure.invalidCompression {}
        }
        do { _ = try ProgramGuidePayload.xmlData(from: zipped, limit: plain.count - 1); preconditionFailure("Expansion limit ignored") }
        catch ProgramGuidePayload.Failure.tooLarge {}
        do { _ = try ProgramGuidePayload.xmlData(from: Data(repeating: 0, count: ProgramGuidePayload.maximumDownloadBytes + 1)); preconditionFailure("Download limit ignored") }
        catch ProgramGuidePayload.Failure.tooLarge {}
        if CommandLine.arguments.count > 2 {
            let xml = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let gzip = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
            let decoded = try ProgramGuidePayload.xmlData(from: gzip)
            precondition(decoded == xml)
        }
        print("EPG plain XML, gzip, truncated input and bounded expansion checks passed")
    }
}
