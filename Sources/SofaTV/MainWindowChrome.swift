import SwiftUI
import AppKit

/// Retain standard window buttons over the sidebar without reserving a title/toolbar strip.
struct MainWindowChrome: NSViewRepresentable {
    @MainActor static weak var mainWindow: NSWindow?
    let title: String
    let onClose: () -> Void
    func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView()
        view.onClose = onClose
        return view
    }
    func updateNSView(_ view: ChromeView, context: Context) {
        view.windowTitle = title
        view.onClose = onClose
        view.configureWindow()
    }
    final class ChromeView: NSView {
        private static let framePreferenceKey = "mainWindowFrame"
        var windowTitle = "沙发电视"
        var onClose: (() -> Void)?
        private weak var configuredWindow: NSWindow?
        deinit { NotificationCenter.default.removeObserver(self) }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configureWindow() }
        func configureWindow() {
            guard let window else { return }
            let firstBinding = configuredWindow !== window
            MainWindowChrome.mainWindow = window
            configureFramePersistence(for: window)
            if window.title != windowTitle { window.title = windowTitle }
            // Unrelated view updates should not make AppKit rebuild the window chrome.
            guard firstBinding else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
            window.toolbar = nil
        }
        private func configureFramePersistence(for window: NSWindow) {
            guard configuredWindow !== window else { return }
            NotificationCenter.default.removeObserver(self)
            configuredWindow = window
            if let value = UserDefaults.standard.string(forKey: Self.framePreferenceKey) {
                let savedFrame = NSRectFromString(value)
                if savedFrame.width >= 900, savedFrame.height >= 560 {
                    DispatchQueue.main.async { [weak self, weak window] in
                        guard let self, let window, self.configuredWindow === window else { return }
                        let screen = NSScreen.screens.first(where: { $0.frame.intersects(savedFrame) }) ?? window.screen
                        let restoredFrame = screen.map { window.constrainFrameRect(savedFrame, to: $0) } ?? savedFrame
                        window.setFrame(restoredFrame, display: true)
                        self.observeFrameChanges(of: window)
                    }
                    return
                }
            }
            observeFrameChanges(of: window)
        }
        private func observeFrameChanges(of window: NSWindow) {
            NotificationCenter.default.addObserver(self, selector: #selector(storeWindowFrame(_:)), name: NSWindow.didMoveNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(storeWindowFrame(_:)), name: NSWindow.didResizeNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(storeWindowFrame(_:)), name: NSWindow.willCloseNotification, object: window)
        }
        @objc private func storeWindowFrame(_ notification: Notification) {
            guard let window = notification.object as? NSWindow, window === configuredWindow else { return }
            UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.framePreferenceKey)
            if notification.name == NSWindow.willCloseNotification {
                if MainWindowChrome.mainWindow === window { MainWindowChrome.mainWindow = nil }
                onClose?()
            }
        }
    }
}
