import AppKit
import UpdateSupport

// The opaque OS token is transferred once; file operations remain on MainActor.
private struct ReplacementAuthorization: @unchecked Sendable {
    let value: NSWorkspace.Authorization
}

// The helper lives outside the application bundle while it replaces that bundle.
// The player exits only after the helper has validated the request and is ready.
@MainActor
final class Installer {
    private var parentExit: DispatchSourceProcess?
    private let request: UpdateInstallationRequest
    private let workspace: URL
    private var fileManager = FileManager.default

    init(requestURL: URL) throws {
        workspace = requestURL.deletingLastPathComponent()
        request = try JSONDecoder().decode(UpdateInstallationRequest.self, from: Data(contentsOf: requestURL))
    }

    func start() async throws {
        try UpdateInstallation.validateApplication(request.source, version: request.version)
        try UpdateInstallation.validateDestination(request.destination)
        let parent = request.destination.deletingLastPathComponent()
        if !fileManager.isWritableFile(atPath: parent.path) || !fileManager.isWritableFile(atPath: request.destination.path) {
            let authorization = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ReplacementAuthorization, Error>) in
                NSWorkspace.shared.requestAuthorization(to: .replaceFile) { authorization, error in
                    if let authorization {
                        continuation.resume(returning: ReplacementAuthorization(value: authorization))
                    } else {
                        continuation.resume(throwing: error ?? CocoaError(.userCancelled))
                    }
                }
            }
            fileManager = FileManager(authorization: authorization.value)
        }
        guard request.parentPID > 1, kill(request.parentPID, 0) == 0 else {
            throw UpdateInstallationError.application
        }
        let source = DispatchSource.makeProcessSource(identifier: request.parentPID, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in self?.install() }
        parentExit = source
        source.resume()
        FileHandle.standardOutput.write(Data("READY\n".utf8))
        try? FileHandle.standardOutput.close()
    }

    private func install() {
        parentExit?.cancel()
        parentExit = nil
        do {
            try UpdateInstallation.replace(request, using: fileManager)
            openApplication()
        } catch {
            showError(error)
            openApplication()
        }
    }

    private func openApplication() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: request.destination, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error { self.showError(error) }
                try? FileManager.default.removeItem(at: self.workspace)
                NSApp.terminate(nil)
            }
        }
    }

    private func showError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "安装更新失败"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
var installer: Installer?
Task { @MainActor in
    do {
        guard CommandLine.arguments.count == 2 else { throw UpdateInstallationError.application }
        installer = try Installer(requestURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        try await installer?.start()
    } catch {
        FileHandle.standardOutput.write(Data("ERROR:\(error.localizedDescription)\n".utf8))
        exit(1)
    }
}
application.run()
