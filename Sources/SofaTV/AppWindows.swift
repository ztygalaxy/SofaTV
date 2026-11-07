import AppKit
import SwiftUI

/// Own independent windows until they close; opening one never updates the
/// playback view or enters an application-modal event loop.
@MainActor final class AppWindows {
    static let shared = AppWindows()
    private var windows: [String: AppWindowController] = [:]

    func show<Content: View>(id: String, title: String, size: NSSize, titleVisible: Bool = false, content: Content) {
        if let controller = windows[id] { controller.showWindow(nil); return }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = title
        window.titleVisibility = titleVisible ? .visible : .hidden
        window.titlebarAppearsTransparent = true
        let host = NSHostingView(rootView: content
            .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
            .preferredColorScheme(.dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity))
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        present(AppWindowController(window: window), id: id)
    }

    func close(id: String) { windows[id]?.close() }
    func resize(id: String, size: NSSize) { windows[id]?.window?.setContentSize(size) }

    func present(_ alert: NSAlert, onResponse: ((NSApplication.ModalResponse) -> Void)? = nil) {
        present(AppWindowController(alert: alert, onResponse: onResponse), id: UUID().uuidString)
    }

    func showMessage(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "好")
        present(alert)
    }

    private func present(_ controller: AppWindowController, id: String) {
        windows[id] = controller
        controller.onClose = { [weak self] in self?.windows.removeValue(forKey: id) }
        controller.window?.center()
        controller.showWindow(nil)
    }
}

@MainActor final class AppWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private var alert: NSAlert?
    private var onResponse: ((NSApplication.ModalResponse) -> Void)?

    override init(window: NSWindow?) {
        super.init(window: window)
        window?.isReleasedWhenClosed = false
        window?.delegate = self
    }

    convenience init(alert: NSAlert, onResponse: ((NSApplication.ModalResponse) -> Void)?) {
        alert.layout()
        self.init(window: alert.window)
        self.alert = alert
        self.onResponse = onResponse
        for (index, button) in alert.buttons.enumerated() {
            button.tag = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + index
            button.target = self
            button.action = #selector(respond(_:))
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func respond(_ sender: NSButton) {
        let result = NSApplication.ModalResponse(rawValue: sender.tag)
        let completion = onResponse
        onResponse = nil
        close()
        completion?(result)
    }

    func windowWillClose(_ notification: Notification) {
        let completion = onClose
        onClose = nil
        onResponse = nil
        completion?()
    }
}
