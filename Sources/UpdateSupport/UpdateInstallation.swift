import CryptoKit
import Foundation
import Security

public enum UpdateInstallationError: LocalizedError {
    case checksum, archive, application, signature, location

    public var errorDescription: String? {
        switch self {
        case .checksum: "下载的更新包校验失败，请重新下载。"
        case .archive: "无法解压更新包，或更新包内容不正确。"
        case .application: "更新包中的应用与本次更新不匹配。"
        case .signature: "更新包中的应用签名验证失败。"
        case .location: "请先将沙发电视移到“应用程序”文件夹，再下载并安装更新。"
        }
    }
}

public struct UpdateInstallationRequest: Codable, Sendable {
    public let source: URL
    public let destination: URL
    public let version: String
    public let parentPID: Int32

    public init(source: URL, destination: URL, version: String, parentPID: Int32) {
        self.source = source
        self.destination = destination
        self.version = version
        self.parentPID = parentPID
    }
}

public enum UpdateInstallation {
    public static let bundleIdentifier = "local.sofatv.app"

    public static func verifyChecksum(of archive: URL, expected: String) throws {
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
        }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard hash == expected else { throw UpdateInstallationError.checksum }
    }

    public static func extract(archive: URL, into directory: URL, version: String) throws -> URL {
        // Reject paths outside the extraction directory before invoking ditto.
        let listing = try run("/usr/bin/zipinfo", ["-1", archive.path])
        let entries = listing.split(separator: "\n").map(String.init)
        guard !entries.isEmpty, entries.allSatisfy({ entry in
            !entry.hasPrefix("/") && !entry.split(separator: "/").contains("..")
        }) else { throw UpdateInstallationError.archive }
        // Release bundles contain regular files/directories, never symlinks.
        let attributes = try run("/usr/bin/zipinfo", ["-l", archive.path])
        guard !attributes.split(separator: "\n").contains(where: { $0.hasPrefix("l") }) else {
            throw UpdateInstallationError.archive
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        _ = try run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path])
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        guard names.contains("沙发电视.app"), names.allSatisfy({ ["沙发电视.app", "__MACOSX", ".DS_Store"].contains($0) }) else {
            throw UpdateInstallationError.archive
        }
        let application = directory.appendingPathComponent("沙发电视.app", isDirectory: true)
        try validateApplication(application, version: version)
        return application
    }

    public static func validateApplication(_ url: URL, version: String? = nil) throws {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: infoURL)
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == bundleIdentifier,
              info["CFBundleExecutable"] as? String == "SofaTV",
              version == nil || info["CFBundleShortVersionString"] as? String == version else {
            throw UpdateInstallationError.application
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures), nil) == errSecSuccess else {
            throw UpdateInstallationError.signature
        }
    }

    public static func validateDestination(_ destination: URL) throws {
        guard destination.pathExtension == "app",
              !destination.path.contains("/AppTranslocation/"),
              (try destination.resourceValues(forKeys: [.volumeIsReadOnlyKey])).volumeIsReadOnly != true else {
            throw UpdateInstallationError.location
        }
        try validateApplication(destination)
    }

    public static func replace(_ request: UpdateInstallationRequest, using manager: FileManager = .default) throws {
        try validateApplication(request.source, version: request.version)
        try validateDestination(request.destination)
        _ = try manager.replaceItemAt(request.destination, withItemAt: request.source)
    }

    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else { throw UpdateInstallationError.archive }
        return String(decoding: data, as: UTF8.self)
    }
}
