import CryptoKit
import Foundation
import UpdateSupport

struct UpdateInstallationTests {
    private func run(_ executable: String, _ arguments: [String], directory: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        check(process.terminationStatus == 0)
    }

    func fixture(in directory: URL, version: String) throws -> URL {
        let app = directory.appendingPathComponent("沙发电视.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": UpdateInstallation.bundleIdentifier, "CFBundleExecutable": "SofaTV",
                    "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: contents.appendingPathComponent("MacOS/SofaTV"))
        try Data(version.utf8).write(to: contents.appendingPathComponent("Resources/version.txt"))
        try run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        return app
    }

    func testExtractsVerifiesAndReplacesSignedApplication() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SofaTV.InstallTests.\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try fixture(in: root.appendingPathComponent("installed"), version: "0.0.3")
        let original = try fixture(in: root.appendingPathComponent("new"), version: "0.0.4")
        let new = original.deletingLastPathComponent().appendingPathComponent("SofaTV-0.0.4-arm64.app")
        try FileManager.default.moveItem(at: original, to: new)
        let archive = root.appendingPathComponent("SofaTV-0.0.4-arm64.zip")
        try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", new.path, archive.path])
        let hash = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
        try UpdateInstallation.verifyChecksum(of: archive, expected: hash)
        expectThrows(try UpdateInstallation.verifyChecksum(of: archive, expected: String(repeating: "0", count: 64)))
        let extracted = try UpdateInstallation.extract(archive: archive, into: root.appendingPathComponent("extracted"), version: "0.0.4")
        expectThrows(try UpdateInstallation.validateApplication(extracted, version: "0.0.5"))
        let request = UpdateInstallationRequest(source: extracted, destination: old, version: "0.0.4", parentPID: 123)
        let decoded = try JSONDecoder().decode(UpdateInstallationRequest.self, from: JSONEncoder().encode(request))
        check(decoded.source == request.source && decoded.destination == request.destination)
        try UpdateInstallation.replace(request)
        try UpdateInstallation.validateApplication(old, version: "0.0.4")
        check(!FileManager.default.fileExists(atPath: extracted.path))
        check(String(decoding: try Data(contentsOf: old.appendingPathComponent("Contents/Resources/version.txt")), as: UTF8.self) == "0.0.4")
    }

    func testTamperedApplicationCannotReplaceExistingVersion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SofaTV.InstallTests.\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try fixture(in: root.appendingPathComponent("installed"), version: "0.0.3")
        let new = try fixture(in: root.appendingPathComponent("new"), version: "0.0.4")
        try Data("tampered".utf8).write(to: new.appendingPathComponent("Contents/Resources/version.txt"))
        let request = UpdateInstallationRequest(source: new, destination: old, version: "0.0.4", parentPID: 123)
        expectThrows(try UpdateInstallation.replace(request))
        try UpdateInstallation.validateApplication(old, version: "0.0.3")
    }

    func testRejectsUnexpectedArchivePathsAndSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SofaTV.InstallTests.\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("unexpected".utf8).write(to: root.appendingPathComponent("outside.txt"))
        let archive = root.appendingPathComponent("unexpected.zip")
        try run("/usr/bin/zip", ["-q", archive.path, "outside.txt"], directory: root)
        expectThrows(try UpdateInstallation.extract(archive: archive, into: root.appendingPathComponent("unexpected"), version: "0.0.4"))
        let app = try fixture(in: root.appendingPathComponent("new"), version: "0.0.4")
        try FileManager.default.createSymbolicLink(at: app.appendingPathComponent("Contents/Resources/link"), withDestinationURL: root)
        let linked = root.appendingPathComponent("symlink.zip")
        try run("/usr/bin/zip", ["-q", "-r", "-y", linked.path, "沙发电视.app"], directory: app.deletingLastPathComponent())
        expectThrows(try UpdateInstallation.extract(archive: linked, into: root.appendingPathComponent("linked"), version: "0.0.4"))
    }
}
