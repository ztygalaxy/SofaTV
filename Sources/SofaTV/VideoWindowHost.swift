import AppKit
import QuartzCore

enum VideoPresentation: Equatable, Sendable { case embedded, fullscreen, mini }

/// Moves one live view between windows. It never creates or reconfigures a player.
class VideoWindowHost: NSView, NSWindowDelegate {
    let content: NSView
    private(set) var presentation: VideoPresentation = .embedded
    private(set) var detachedWindow: VideoDetachedWindow?
    var onPresentationChange: ((VideoPresentation) -> Void)?
    var onEscape: (() -> Bool)?
    private let activateApplication: () -> Void
    private let makeWindow: (NSRect, VideoPresentation) -> VideoDetachedWindow
    private var transitioning = false
    private var transitionID = UUID()
    private var presentationOptionsBeforeFullscreen: NSApplication.PresentationOptions?

    init(content: NSView, activateApplication: @escaping () -> Void = { NSApplication.shared.activate() }, makeWindow: @escaping (NSRect, VideoPresentation) -> VideoDetachedWindow = { VideoDetachedWindow(frame: $0, presentation: $1) }) {
        self.content = content
        self.activateApplication = activateApplication
        self.makeWindow = makeWindow
        super.init(frame: .zero)
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        if presentation == .embedded { content.frame = bounds }
    }

    func toggleFullscreen(animated: Bool = true) {
        if presentation == .fullscreen { restoreEmbedded(animated: animated) }
        else { present(.fullscreen, animated: animated) }
    }

    func toggleMini(animated: Bool = true) {
        if presentation == .mini { restoreEmbedded(animated: animated) }
        else { present(.mini, animated: animated) }
    }

    private final func embeddedScreenFrame() -> NSRect? {
        window.map { $0.convertToScreen(convert(bounds, to: nil)) }
    }

    private final func present(_ target: VideoPresentation, animated: Bool) {
        guard !transitioning,
              let screen = detachedWindow?.screen ?? window?.screen ?? NSScreen.main,
              let initial = detachedWindow?.frame ?? embeddedScreenFrame() else { return }
        let previous = detachedWindow
        configureSystemPresentation(for: target)
        let videoWindow = makeWindow(initial, target)
        videoWindow.delegate = self
        videoWindow.onExit = { [weak self] in
            guard let self else { return }
            if self.onEscape?() != true { self.restoreEmbedded() }
        }
        detachedWindow = videoWindow
        content.removeFromSuperview()
        previous?.contentView = nil
        videoWindow.contentView = content
        videoWindow.setFrame(initial, display: false)
        presentation = target
        onPresentationChange?(target)
        previous?.delegate = nil
        previous?.close()
        if target == .mini { window?.orderOut(nil) }
        videoWindow.makeKeyAndOrderFront(nil)
        let frame = target == .fullscreen ? screen.frame : VideoDetachedWindow.miniFrame(in: screen.visibleFrame)
        animate(videoWindow, to: frame, animated: animated) { [weak self] in self?.content.layoutSubtreeIfNeeded() }
    }

    func restoreEmbedded(animated: Bool = true, activateMain: Bool = true) {
        guard let videoWindow = detachedWindow else { return }
        if !animated || embeddedScreenFrame() == nil {
            transitionID = UUID(); transitioning = false
            finishRestore(videoWindow, activateMain: activateMain)
        } else if !transitioning, let frame = embeddedScreenFrame() {
            animate(videoWindow, to: frame, animated: true) { [weak self, weak videoWindow] in
                guard let self, let videoWindow else { return }
                self.finishRestore(videoWindow, activateMain: activateMain)
            }
        }
    }

    private final func finishRestore(_ videoWindow: VideoDetachedWindow, activateMain: Bool) {
        guard detachedWindow === videoWindow else { return }
        content.removeFromSuperview()
        videoWindow.contentView = nil
        detachedWindow = nil
        presentation = .embedded
        configureSystemPresentation(for: .embedded)
        addSubview(content)
        content.frame = bounds
        onPresentationChange?(.embedded)
        content.layoutSubtreeIfNeeded()
        if activateMain {
            activateApplication()
            window?.makeKeyAndOrderFront(nil)
        }
        videoWindow.delegate = nil
        videoWindow.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        restoreEmbedded(animated: false)
        return false
    }

    private func configureSystemPresentation(for presentation: VideoPresentation) {
        if presentation == .fullscreen {
            if presentationOptionsBeforeFullscreen == nil { presentationOptionsBeforeFullscreen = NSApp.presentationOptions }
            var options = NSApp.presentationOptions
            options.subtract([.hideDock, .hideMenuBar])
            options.formUnion([.autoHideDock, .autoHideMenuBar])
            NSApp.presentationOptions = options
        } else if let previous = presentationOptionsBeforeFullscreen {
            NSApp.presentationOptions = previous
            presentationOptionsBeforeFullscreen = nil
        }
    }

    private final func animate(_ videoWindow: VideoDetachedWindow, to frame: NSRect, animated: Bool, completion: @escaping @MainActor @Sendable () -> Void) {
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            videoWindow.setFrame(frame, display: true)
            completion()
            return
        }
        transitioning = true
        transitionID = UUID()
        let token = transitionID
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            videoWindow.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.transitionID == token else { return }
                self.transitioning = false
                completion()
            }
        }
    }
}

class VideoDetachedWindow: NSPanel {
    var onExit: (() -> Void)?

    init(frame: NSRect, presentation: VideoPresentation) {
        let mini = presentation == .mini
        super.init(contentRect: frame, styleMask: mini ? [.borderless, .resizable, .nonactivatingPanel] : [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        animationBehavior = .none
        backgroundColor = mini ? .clear : .black
        isOpaque = !mini
        hasShadow = mini
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isFloatingPanel = mini
        // Fullscreen uses the system's menu/Dock presentation options. Raising
        // the video above the menu bar can cover system notification banners.
        level = mini ? .floating : .normal
        becomesKeyOnlyIfNeeded = mini
        isMovable = mini
        isMovableByWindowBackground = mini
        if mini {
            title = "沙发电视 · 置顶小窗"
            contentAspectRatio = NSSize(width: 16, height: 9)
            contentMinSize = NSSize(width: 368, height: 207)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { onExit?(); return true }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onExit?() }
        else { super.keyDown(with: event) }
    }

    static func miniFrame(in visibleFrame: NSRect) -> NSRect {
        let width = min(400, visibleFrame.width - 40, (visibleFrame.height - 40) * 16 / 9)
        return NSRect(x: visibleFrame.maxX - width - 20, y: visibleFrame.minY + 20, width: width, height: width * 9 / 16)
    }
}
