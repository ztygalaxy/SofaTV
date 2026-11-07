import AppKit
import Foundation

@MainActor
final class UpdateChecker: NSObject {
    static let shared = UpdateChecker()

    private let automatic = AutomaticUpdateCheck()
    private var task: Task<Void, Never>?
    private var checkID: UUID?
    private var progressPanel: NSPanel?
    private var updateWindow: UpdateWindowController?

    func startAutomaticCheck(isWatching: @escaping () -> Bool) {
        automatic.start(isWatching: isWatching, fetch: { [weak self] in
            guard let self, let current = currentVersion,
                  let update = try await fetchUpdate(), update.version > current else { return nil }
            return update
        }, show: { [weak self] update in
            guard let self, let current = currentVersion else { return }
            showUpdate(update, current: current)
        })
    }

    func check() {
        automatic.cancel()
        if let window = updateWindow?.window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard task == nil else {
            progressPanel?.makeKeyAndOrderFront(nil)
            return
        }
        let id = UUID()
        checkID = id
        showProgress()
        task = Task { [weak self] in await self?.performCheck(id: id) }
    }

    @objc private func cancel() {
        task?.cancel()
        task = nil
        checkID = nil
        closeProgress()
    }

    private func fetchUpdate() async throws -> VerifiedUpdate? {
        var request = URLRequest(url: UpdateManifestValidator.manifestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SofaTV-Updater", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try UpdateManifestValidator.decode(data, architecture: architecture)
    }

    private func performCheck(id: UUID) async {
        do {
            let update = try await fetchUpdate()
            try Task.checkCancellation()
            guard let current = currentVersion else { throw UpdateManifestError.invalid }
            guard finishTask(id: id) else { return }
            if let update, update.version > current { showUpdate(update, current: current) }
            else { showMessage("已是最新版", detail: "当前版本：\(current)") }
        } catch {
            guard finishTask(id: id), !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            showMessage("检查更新失败", detail: userMessage(for: error))
        }
    }

    private var currentVersion: SemanticVersion? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return nil }
        return SemanticVersion(value)
    }

    private var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unsupported"
        #endif
    }

    @discardableResult private func finishTask(id: UUID) -> Bool {
        guard checkID == id else { return false }
        task = nil
        checkID = nil
        closeProgress()
        return true
    }

    private func showProgress() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "正在检查更新…"
        let progress = NSProgressIndicator(frame: NSRect(x: 20, y: 65, width: 340, height: 20))
        progress.style = .bar
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        panel.contentView?.addSubview(progress)
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancel.frame = NSRect(x: 260, y: 15, width: 100, height: 32)
        panel.contentView?.addSubview(cancel)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        progressPanel = panel
    }

    private func closeProgress() {
        progressPanel?.close()
        progressPanel = nil
    }

    private func showUpdate(_ update: VerifiedUpdate, current: SemanticVersion) {
        let controller = UpdateWindowController(update: update, current: current)
        controller.onClose = { [weak self] in self?.updateWindow = nil }
        updateWindow = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func showMessage(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "好")
        AppWindows.shared.present(alert)
    }

    private func userMessage(for error: Error) -> String {
        if let error = error as? UpdateManifestError { return error.localizedDescription }
        return "暂时无法连接更新服务，请检查网络后重试。"
    }
}
