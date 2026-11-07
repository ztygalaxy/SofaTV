import Foundation
import UpdateSupport

struct UpdateHelperTests {
    func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SofaTV.HelperTests.\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try UpdateInstallationTests().fixture(in: root.appendingPathComponent("new"), version: "0.0.4")
        let destination = try UpdateInstallationTests().fixture(in: root.appendingPathComponent("installed"), version: "0.0.3")
        for version in ["0.0.5", "0.0.4"] {
            let request = UpdateInstallationRequest(source: source, destination: destination, version: version,
                                                    parentPID: ProcessInfo.processInfo.processIdentifier)
            let url = root.appendingPathComponent("install.json")
            try JSONEncoder().encode(request).write(to: url)
            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
            helper.arguments = [url.path]
            let pipe = Pipe()
            helper.standardOutput = pipe
            helper.standardError = FileHandle.nullDevice
            try helper.run()
            let response = await Task.detached { String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) }.value
            if version == "0.0.4" {
                check(response == "READY\n")
                check(helper.isRunning)
                // A prepared helper must wait while its parent is still alive.
                try await Task.sleep(for: .milliseconds(100))
                try UpdateInstallation.validateApplication(destination, version: "0.0.3")
                helper.terminate()
            } else {
                check(response.hasPrefix("ERROR:"))
            }
            helper.waitUntilExit()
        }
    }
}
