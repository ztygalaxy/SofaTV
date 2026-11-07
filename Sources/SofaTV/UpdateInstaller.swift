import AppKit
import UpdateSupport

@MainActor
enum UpdateInstaller {
    static func launch(source: URL, version: String, workspace: URL) async throws {
        let destination = Bundle.main.bundleURL.resolvingSymlinksInPath()
        try UpdateInstallation.validateDestination(destination)
        let helper = workspace.appendingPathComponent("SofaTVUpdater")
        try FileManager.default.copyItem(at: destination.appendingPathComponent("Contents/Helpers/SofaTVUpdater"), to: helper)
        let request = UpdateInstallationRequest(source: source, destination: destination, version: version, parentPID: ProcessInfo.processInfo.processIdentifier)
        let requestURL = workspace.appendingPathComponent("install.json")
        try JSONEncoder().encode(request).write(to: requestURL, options: .atomic)
        let process = Process()
        process.executableURL = helper
        process.arguments = [requestURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let response = await Task.detached {
            String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        }.value
        guard response == "READY\n" else {
            throw NSError(domain: "SofaTV.Update", code: 1, userInfo: [NSLocalizedDescriptionKey:
                response.hasPrefix("ERROR:") ? String(response.dropFirst(6)).trimmingCharacters(in: .newlines) : "更新安装程序未能启动，请重试。"])
        }
        NSApp.terminate(nil)
    }
}
