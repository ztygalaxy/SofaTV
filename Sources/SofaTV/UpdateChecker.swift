import AppKit
import Foundation

@MainActor
final class UpdateChecker: NSObject {
    static let shared = UpdateChecker()

    private var task: Task<Void, Never>?
    private var progressPanel: NSPanel?

    func check() {
        guard task == nil else {
            progressPanel?.makeKeyAndOrderFront(nil)
            return
        }
        showProgress()
        task = Task { [weak self] in await self?.performCheck() }
    }

    @objc private func cancel() {
        task?.cancel()
        task = nil
        closeProgress()
    }

    private func performCheck() async {
        do {
            var request = URLRequest(
                url: UpdateManifestValidator.manifestURL,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 30
            )
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("SofaTV-Updater", forHTTPHeaderField: "User-Agent")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            let session = URLSession(configuration: configuration)
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            // Private GitHub Releases return 404 to the app's anonymous
            // request even when the owner can open the asset in a browser.
            // Treat a missing manifest as no available newer release rather
            // than presenting a misleading error to the viewer.
            if response.statusCode == 404, let current = currentVersion {
                finishTask()
                showMessage("已是最新版", detail: "当前版本：\(current)")
                return
            }
            guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
            let update = try UpdateManifestValidator.decode(data, architecture: architecture)
            guard let current = currentVersion else { throw UpdateManifestError.invalid }
            finishTask()
            if update.version > current { showUpdate(update, current: current) }
            else { showMessage("已是最新版", detail: "当前版本：\(current)") }
        } catch is CancellationError {
            finishTask()
        } catch {
            finishTask()
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

    private func finishTask() {
        task = nil
        closeProgress()
    }

    private func showProgress() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
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
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "发现沙发电视新版本"
        alert.informativeText = "沙发电视 \(update.version) 已发布，你正在使用 \(current)。"
        if !update.notes.isEmpty { alert.accessoryView = releaseNotesView(update.notes) }
        alert.addButton(withTitle: "打开下载页")
        alert.addButton(withTitle: "稍后")
        AppWindows.shared.present(alert) { response in
            if response == .alertFirstButtonReturn { NSWorkspace.shared.open(update.releaseURL) }
        }
    }

    private func releaseNotesView(_ notes: String) -> NSView {
        let width: CGFloat = 500
        let height: CGFloat = 220
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height + 28))
        let heading = NSTextField(labelWithString: "更新说明：")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        heading.frame = NSRect(x: 0, y: height + 8, width: width, height: 20)
        container.addSubview(heading)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let text = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        text.isEditable = false
        text.isRichText = false
        text.font = .systemFont(ofSize: NSFont.systemFontSize)
        text.textColor = .textColor
        text.backgroundColor = .textBackgroundColor
        text.textContainerInset = NSSize(width: 8, height: 6)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.string = notes
        scroll.documentView = text
        container.addSubview(scroll)
        return container
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
        if let error = error as? URLError, error.code == .badServerResponse {
            return "暂时无法获取更新信息。首个 Release 发布前需要随安装包上传 update.json。"
        }
        return "暂时无法连接更新服务，请检查网络后重试。"
    }
}
