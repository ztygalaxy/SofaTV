import AppKit
import SwiftUI

/// A short confirmation attached to the active app window, without taking focus
/// or intercepting clicks on the video and its controls.
@MainActor final class AppToast {
    static let shared = AppToast()
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?
    private weak var targetWindow: NSWindow?

    func show(_ message: String, in window: NSWindow? = nil) {
        let video = videoView(in: window)
        guard let parent = video?.window ?? window ?? NSApp.keyWindow ?? NSApp.mainWindow, parent.isVisible else { return }
        hide()
        targetWindow = window
        let width = min(400, max(180, (video?.bounds.width ?? parent.frame.width) - 48))
        let host = NSHostingView(rootView:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(message).font(.system(size: 13, weight: .medium)).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(width: width)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .preferredColorScheme(.dark)
        )
        let toast = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        toast.isReleasedWhenClosed = false
        toast.isOpaque = false; toast.backgroundColor = .clear
        toast.hasShadow = true; toast.ignoresMouseEvents = true; toast.hidesOnDeactivate = true
        toast.collectionBehavior = [.transient, .fullScreenAuxiliary]
        toast.contentView = host
        panel = toast
        reposition()
        toast.orderFront(nil)
        NSAccessibility.post(element: host, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        dismissal = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.hide()
        }
    }
    private func videoView(in window: NSWindow?) -> NSView? {
        [AppWindows.shared.playbackView, AppWindows.shared.videoRegion].compactMap { $0 }.first {
            $0.window?.isVisible == true && !$0.isHiddenOrHasHiddenAncestor && (window == nil || $0.window === window)
        }
    }
    func reposition() {
        guard let panel else { return }
        let video = videoView(in: targetWindow)
        guard let parent = video?.window ?? targetWindow ?? panel.parent ?? NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let rect = video.map { parent.convertToScreen($0.convert($0.bounds, to: nil)) }
            ?? parent.convertToScreen(parent.contentView?.bounds ?? .zero)
        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            panel.level = parent.level
            parent.addChildWindow(panel, ordered: .above)
        }
        let centerY = parent.frame.minY + parent.frame.height / 5
        panel.setFrameOrigin(NSPoint(x: rect.midX - panel.frame.width / 2, y: centerY - panel.frame.height / 2))
    }
    private func hide() {
        dismissal?.cancel(); dismissal = nil
        if let panel { panel.parent?.removeChildWindow(panel); panel.close() }
        panel = nil
        targetWindow = nil
    }
}

/// Includes the empty video region when no playback stage exists yet.
struct AppToastVideoRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {}
    final class Anchor: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { AppWindows.shared.videoRegion = self }
            AppToast.shared.reposition()
        }
        override func layout() { super.layout(); AppToast.shared.reposition() }
    }
}

/// Own independent windows until they close; opening one never updates the
/// playback view or enters an application-modal event loop.
@MainActor final class AppWindows {
    static let shared = AppWindows()
    private var windows: [String: AppWindowController] = [:]
    private(set) weak var playbackView: NSView?
    private var playbackIsFullscreen = false
    weak var videoRegion: NSView?

    func playbackWindowChanged(_ view: NSView, fullscreen: Bool = false) {
        if view.window != nil { playbackView = view }
        guard playbackView === view else { return }
        playbackIsFullscreen = fullscreen && view.window != nil
        for controller in windows.values { controller.attach(above: view.window, fullscreen: playbackIsFullscreen) }
        AppToast.shared.reposition()
    }

    func show<Content: View>(id: String, title: String, size: NSSize, titleVisible: Bool = false, content: Content) {
        if let controller = windows[id] {
            controller.attach(above: playbackView?.window, fullscreen: playbackIsFullscreen); controller.showWindow(nil); return
        }
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
        controller.attach(above: playbackView?.window, fullscreen: playbackIsFullscreen)
        if let parent = controller.window?.parent, let window = controller.window {
            window.setFrameOrigin(NSPoint(x: parent.frame.midX - window.frame.width / 2, y: parent.frame.midY - window.frame.height / 2))
        } else { controller.window?.center() }
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

    func attach(above playbackWindow: NSWindow?, fullscreen: Bool = false) {
        guard let window else { return }
        let parent = playbackWindow.flatMap { $0.isVisible && (fullscreen || $0.level > .normal) ? $0 : nil }
        // Child windows share their parent's level; .above determines their
        // ordering. Raising a child level can also raise the parent in AppKit.
        let level = parent?.level ?? .normal
        if window.level != level { window.level = level }
        if window.parent !== parent {
            window.parent?.removeChildWindow(window)
            window.collectionBehavior = [.fullScreenAuxiliary]
            parent?.addChildWindow(window, ordered: .above)
        }
    }

    @objc private func respond(_ sender: NSButton) {
        let result = NSApplication.ModalResponse(rawValue: sender.tag)
        let completion = onResponse
        onResponse = nil
        close()
        completion?(result)
    }

    func windowWillClose(_ notification: Notification) {
        if let window { window.parent?.removeChildWindow(window) }
        let completion = onClose
        onClose = nil
        onResponse = nil
        completion?()
    }
}
