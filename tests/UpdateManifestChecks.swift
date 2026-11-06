import Foundation

@main struct UpdateManifestChecks {
    static func main() throws {
        precondition(SemanticVersion("0.0.1")! < SemanticVersion("0.0.2")!)
        precondition(SemanticVersion("0.9.9")! < SemanticVersion("1.0.0")!)
        precondition(SemanticVersion("01.0.0") == nil)
        precondition(SemanticVersion("1.0") == nil)

        let hash = String(repeating: "a", count: 64)
        let valid = """
        {"schema":1,"version":"0.0.2","notes":"更舒服地看电视。","assets":{
          "arm64":{"name":"SofaTV-0.0.2-arm64.zip","sha256":"\(hash)"},
          "x86_64":{"name":"SofaTV-0.0.2-x86_64.zip","sha256":"\(hash)"}
        }}
        """.data(using: .utf8)!
        let update = try UpdateManifestValidator.decode(valid, architecture: "arm64")
        precondition(update.version.description == "0.0.2")
        precondition(update.asset.name == "SofaTV-0.0.2-arm64.zip")
        precondition(update.downloadURL.absoluteString.hasSuffix("/v0.0.2/SofaTV-0.0.2-arm64.zip"))
        precondition(update.releaseURL.absoluteString.hasSuffix("/tag/v0.0.2"))

        func mustReject(_ json: String, architecture: String = "arm64") {
            do {
                _ = try UpdateManifestValidator.decode(Data(json.utf8), architecture: architecture)
                preconditionFailure("Invalid update manifest was accepted")
            } catch {}
        }
        mustReject(String(data: valid, encoding: .utf8)!.replacingOccurrences(of: "\"schema\":1", with: "\"schema\":2"))
        mustReject(String(data: valid, encoding: .utf8)!.replacingOccurrences(of: "SofaTV-0.0.2-arm64.zip", with: "other.zip"))
        mustReject(String(data: valid, encoding: .utf8)!.replacingOccurrences(of: hash, with: "ABC"))
        mustReject(String(data: valid, encoding: .utf8)!, architecture: "riscv")
        print("Update manifest version, asset, checksum and fixed-URL checks passed")
    }
}
