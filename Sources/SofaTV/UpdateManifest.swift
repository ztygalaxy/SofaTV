import Foundation

struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let strings = parts.map(String.init)
        guard strings.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(strings[0]), let minor = Int(strings[1]), let patch = Int(strings[2]),
              strings == [String(major), String(minor), String(patch)] else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct UpdateAsset: Decodable, Sendable {
    let name: String
    let sha256: String
}

struct UpdateManifest: Decodable {
    let schema: Int
    let version: String
    let notes: String?
    let assets: [String: UpdateAsset]
}

struct VerifiedUpdate: Sendable {
    let version: SemanticVersion
    let notes: String
    let asset: UpdateAsset
    let downloadURL: URL
    let releaseURL: URL
}

enum UpdateManifestError: LocalizedError {
    case tooLarge
    case invalid
    case unavailable

    var errorDescription: String? {
        switch self {
        case .tooLarge: "更新信息文件过大。"
        case .invalid: "更新信息格式无效。"
        case .unavailable: "没有适用于这台 Mac 的更新包。"
        }
    }
}

enum UpdateManifestValidator {
    static let maximumSize = 1_048_576
    static let manifestURL = URL(string: "https://github.com/ztygalaxy/SofaTV/releases/latest/download/update.json")!

    static func decode(_ data: Data, architecture: String) throws -> VerifiedUpdate {
        guard data.count <= maximumSize else { throw UpdateManifestError.tooLarge }
        guard ["arm64", "x86_64"].contains(architecture),
              let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: data),
              manifest.schema == 1,
              let version = SemanticVersion(manifest.version),
              version.description == manifest.version else { throw UpdateManifestError.invalid }
        let expectedName = "SofaTV-\(version)-\(architecture).zip"
        guard let asset = manifest.assets[architecture],
              asset.name == expectedName,
              isSHA256(asset.sha256) else { throw UpdateManifestError.unavailable }
        let root = "https://github.com/ztygalaxy/SofaTV/releases"
        guard let downloadURL = URL(string: "\(root)/download/v\(version)/\(expectedName)"),
              let releaseURL = URL(string: "\(root)/tag/v\(version)") else { throw UpdateManifestError.invalid }
        return VerifiedUpdate(
            version: version,
            notes: manifest.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            asset: asset,
            downloadURL: downloadURL,
            releaseURL: releaseURL
        )
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (97...102).contains($0.value)
        }
    }
}
