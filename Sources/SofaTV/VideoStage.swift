import SwiftUI
import AVKit
import WebKit
import QuartzCore

/// One live stage is moved between its embedded host and a video-only window.
/// Both playback engines keep their sessions during the move.
struct VideoStage: NSViewRepresentable {
    @ObservedObject var library: Library
    let sidebarCollapsed: Bool
    let onToggleSidebar: () -> Void
    func makeNSView(context: Context) -> Host {
        let host = Host(library: library)
        host.stage.configureSidebar(collapsed: sidebarCollapsed, toggle: onToggleSidebar)
        return host
    }
    func updateNSView(_ host: Host, context: Context) {
        host.stage.configureSidebar(collapsed: sidebarCollapsed, toggle: onToggleSidebar)
        host.stage.update(library)
    }
    static func dismantleNSView(_ host: Host, coordinator: ()) { host.exitFullscreen(animated: false); host.stage.observation = nil }

    final class FullscreenWindow: NSWindow {
        var exit: (() -> Void)?
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { exit?() }
        }
    }
    final class Host: NSView {
        let stage: Stage
        private var fullscreenWindow: FullscreenWindow?
        private var transitioning = false
        private var transitionID = UUID()
        private var transitionDuration: TimeInterval { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.32 }
        init(library: Library) {
            stage = Stage(library: library)
            super.init(frame: .zero)
            stage.autoresizingMask = [.width, .height]; addSubview(stage)
            stage.onToggleFullscreen = { [weak self] in self?.toggleFullscreen() }
            stage.pointer.onDoubleClick = stage.onToggleFullscreen
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layout() { super.layout(); if fullscreenWindow == nil { stage.frame = bounds } }
        private func embeddedScreenFrame() -> NSRect? {
            window.map { $0.convertToScreen(convert(bounds, to: nil)) }
        }
        func toggleFullscreen() {
            guard !transitioning else { return }
            if fullscreenWindow != nil { exitFullscreen(); return }
            guard let screen = window?.screen ?? NSScreen.main, let initialFrame = embeddedScreenFrame() else { return }
            let videoWindow = FullscreenWindow(contentRect: initialFrame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
            videoWindow.isReleasedWhenClosed = false
            videoWindow.animationBehavior = .none
            videoWindow.backgroundColor = .black
            videoWindow.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
            videoWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            videoWindow.exit = { [weak self] in self?.exitFullscreen() }
            fullscreenWindow = videoWindow
            stage.isVideoFullscreen = true
            stage.removeFromSuperview()
            videoWindow.contentView = stage
            stage.frame = NSRect(origin: .zero, size: initialFrame.size)
            videoWindow.makeKeyAndOrderFront(nil)
            animate(videoWindow, to: screen.frame) { [weak self] in self?.stage.layoutSubtreeIfNeeded() }
        }
        private func animate(_ videoWindow: FullscreenWindow, to frame: NSRect, completion: @escaping @MainActor () -> Void) {
            transitioning = true
            transitionID = UUID()
            let token = transitionID
            NSAnimationContext.runAnimationGroup { context in
                context.duration = transitionDuration
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
        func exitFullscreen(animated: Bool = true) {
            guard let videoWindow = fullscreenWindow else { return }
            if !animated {
                transitionID = UUID(); transitioning = false
                restoreEmbeddedStage(videoWindow)
            } else if !transitioning, let target = embeddedScreenFrame() {
                animate(videoWindow, to: target) { [weak self, weak videoWindow] in
                    guard let self, let videoWindow else { return }
                    self.restoreEmbeddedStage(videoWindow)
                }
            }
        }
        private func restoreEmbeddedStage(_ videoWindow: FullscreenWindow) {
            guard fullscreenWindow === videoWindow else { return }
            stage.removeFromSuperview(); videoWindow.contentView = nil
            fullscreenWindow = nil
            addSubview(stage); stage.frame = bounds
            stage.isVideoFullscreen = false; stage.layoutSubtreeIfNeeded()
            videoWindow.close(); window?.makeKeyAndOrderFront(nil)
        }
    }
    final class PointerSurface: NSView {
        var onDoubleClick: (() -> Void)?
        var onPointerActivity: (() -> Void)?
        var onScroll: ((NSEvent) -> Void)?
        var lastSidebarToggleTime: TimeInterval = 0
        private var pointerTrackingArea: NSTrackingArea?
        override var acceptsFirstResponder: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate],
                owner: self
            )
            addTrackingArea(area); pointerTrackingArea = area
        }
        override func resetCursorRects() { addCursorRect(visibleRect, cursor: .arrow) }
        private func showPointer() {
            NSCursor.setHiddenUntilMouseMoves(false)
            NSCursor.arrow.set()
        }
        override func mouseEntered(with event: NSEvent) { showPointer(); onPointerActivity?() }
        override func mouseMoved(with event: NSEvent) { showPointer(); onPointerActivity?() }
        override func cursorUpdate(with event: NSEvent) { showPointer() }
        override func mouseDown(with event: NSEvent) {
            onPointerActivity?()
            if event.clickCount == 2, ProcessInfo.processInfo.systemUptime - lastSidebarToggleTime > NSEvent.doubleClickInterval { onDoubleClick?() }
        }
        override func mouseUp(with event: NSEvent) {}
        override func mouseDragged(with event: NSEvent) { onPointerActivity?() }
        override func rightMouseDown(with event: NSEvent) {}
        override func rightMouseUp(with event: NSEvent) {}
        override func scrollWheel(with event: NSEvent) { onScroll?(event) }
        override func magnify(with event: NSEvent) {}
        override func menu(for event: NSEvent) -> NSMenu? { nil }
    }
    /// Decorative only: clicks and wheel input pass through to the video surface.
    final class BottomFade: NSView {
        private let gradient = CAGradientLayer()
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            gradient.colors = [NSColor.black.withAlphaComponent(0.85).cgColor, NSColor.black.withAlphaComponent(0).cgColor]
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
            layer?.addSublayer(gradient)
        }
        convenience init() { self.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func layout() {
            super.layout()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            gradient.frame = bounds
            CATransaction.commit()
        }
    }
    final class Stage: NSView {
        let playerView = AVPlayerView()
        let pointer = PointerSurface()
        private let sidebarButton = SidebarToggleButton()
        private let volumeControl = VideoVolumeControl()
        private let volumeBackdrop = BottomFade()
        private var volumeScroll = VideoVolumeScroll()
        private var lastDisplayedVolume: Float?
        private var lastDisplayedMute: Bool?
        private var displayedChannelID: String?
        private var sidebarCollapsed = false
        private var onToggleSidebar: (() -> Void)?
        private var sidebarTrackingArea: NSTrackingArea?
        private var controlsHideTimer: Timer?
        private var pointerInVideo = false
        private var trackingSidebarButton = false
        private var trackingVolume = false
        private var sidebarControlAvailable = false
        private var volumeControlAvailable = false
        private var trackingControls: Bool { trackingSidebarButton || trackingVolume }
        var onToggleFullscreen: (() -> Void)?
        var isVideoFullscreen = false {
            didSet {
                volumeControl.setFullscreen(isVideoFullscreen)
                updateControlAvailability()
            }
        }
        let cover = NSView()
        let spinner = NSProgressIndicator()
        let label = NSTextField(labelWithString: "正在加载…")
        weak var library: Library?
        var observation: NSKeyValueObservation?
        init(library: Library) {
            self.library = library
            super.init(frame: .zero)
            wantsLayer = true
            let web = library.resolver.webView
            web.removeFromSuperview(); addSubview(web)
            playerView.controlsStyle = .none; playerView.showsFullScreenToggleButton = false
            playerView.player = library.player; playerView.wantsLayer = true; addSubview(playerView)
            cover.wantsLayer = true
            spinner.style = .spinning; spinner.controlSize = .large; spinner.startAnimation(nil)
            label.textColor = .secondaryLabelColor; label.alignment = .center
            cover.addSubview(spinner); cover.addSubview(label); addSubview(cover)
            volumeBackdrop.isHidden = true; addSubview(volumeBackdrop); addSubview(pointer)
            sidebarButton.target = self; sidebarButton.action = #selector(toggleSidebar)
            sidebarButton.isHidden = true; addSubview(sidebarButton)
            volumeControl.isHidden = true; addSubview(volumeControl)
            pointer.onPointerActivity = { [weak self] in self?.showOverlayControls() }
            pointer.onScroll = { [weak self] event in self?.adjustVolume(with: event) }
            sidebarButton.onPointerActivity = { [weak self] in self?.showOverlayControls() }
            sidebarButton.onTrackingChanged = { [weak self] tracking in
                guard let self else { return }
                self.trackingSidebarButton = tracking
                self.controlsTrackingChanged()
            }
            volumeControl.onPointerActivity = { [weak self] in self?.showOverlayControls() }
            volumeControl.onScroll = { [weak self] event in self?.adjustVolume(with: event) }
            volumeControl.onToggleFullscreen = { [weak self] in
                self?.showVolumeFeedback()
                self?.onToggleFullscreen?()
            }
            volumeControl.onToggleMute = { [weak self] in
                self?.volumeScroll.reset()
                self?.library?.toggleMute()
                self?.showVolumeFeedback()
            }
            volumeControl.onReload = { [weak self] in
                self?.volumeScroll.reset()
                self?.library?.reloadCurrentChannel()
            }
            volumeControl.onVolumeChanged = { [weak self] value in
                self?.volumeScroll.reset()
                self?.library?.setVolume(value)
                self?.showVolumeFeedback()
            }
            volumeControl.onTrackingChanged = { [weak self] tracking in
                guard let self else { return }
                self.trackingVolume = tracking
                // Keep clicks on playback controls separate from the video's double-click gesture.
                self.pointer.lastSidebarToggleTime = ProcessInfo.processInfo.systemUptime
                self.controlsTrackingChanged()
            }
            updateBackground()
            observation = playerView.observe(\.isReadyForDisplay, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self, weak view] in
                    guard let view, view.isReadyForDisplay else { return }
                    self?.library?.videoAppeared(view.player?.currentItem)
                }
            }
            update(library)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func configureSidebar(collapsed: Bool, toggle: @escaping () -> Void) {
            sidebarCollapsed = collapsed; onToggleSidebar = toggle
            sidebarButton.setCollapsed(collapsed)
            updateControlAvailability()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateControlAvailability()
            if window == nil { volumeScroll.reset(); hideOverlayControls() }
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let sidebarTrackingArea { removeTrackingArea(sidebarTrackingArea) }
            let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self)
            addTrackingArea(area); sidebarTrackingArea = area
        }
        override func mouseEntered(with event: NSEvent) { showOverlayControls() }
        override func mouseMoved(with event: NSEvent) { showOverlayControls() }
        override func mouseExited(with event: NSEvent) {
            if !containsCurrentPointer() {
                pointerInVideo = false; volumeScroll.reset()
                if !trackingControls { hideOverlayControls() }
            }
        }
        private func containsCurrentPointer() -> Bool {
            guard let window else { return false }
            return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
        private func updateControlAvailability() {
            // Keep the expand affordance usable during buffering or a failed source.
            let sidebarAvailable = window != nil && !isVideoFullscreen && (library?.videoVisible == true || sidebarCollapsed)
            let volumeAvailable = window != nil && library?.selected != nil
            let becameAvailable = (sidebarAvailable && !sidebarControlAvailable) || (volumeAvailable && !volumeControlAvailable)
            sidebarControlAvailable = sidebarAvailable; volumeControlAvailable = volumeAvailable
            if !sidebarAvailable { sidebarButton.isHidden = true }
            if !volumeAvailable { setVolumeControlVisible(false) }
            if !sidebarAvailable && !volumeAvailable { hideOverlayControls() }
            else if becameAvailable && containsCurrentPointer() { showOverlayControls() }
        }
        private func showOverlayControls() {
            guard sidebarControlAvailable || volumeControlAvailable else { return }
            guard containsCurrentPointer() else {
                if !trackingControls { hideOverlayControls() }
                return
            }
            pointerInVideo = true
            sidebarButton.isHidden = !sidebarControlAvailable
            setVolumeControlVisible(volumeControlAvailable)
            scheduleControlsHide()
        }
        private func showVolumeFeedback() {
            guard volumeControlAvailable else { return }
            setVolumeControlVisible(true)
            if containsCurrentPointer() {
                pointerInVideo = true; sidebarButton.isHidden = !sidebarControlAvailable
            }
            scheduleControlsHide()
        }
        private func controlsTrackingChanged() {
            if trackingControls { controlsHideTimer?.invalidate(); controlsHideTimer = nil }
            else { showOverlayControls() }
        }
        private func scheduleControlsHide() {
            guard !trackingControls else { return }
            if let timer = controlsHideTimer, timer.isValid { timer.fireDate = Date(timeIntervalSinceNow: 3) }
            else {
                let timer = Timer(timeInterval: 3, target: self, selector: #selector(hideOverlayControls), userInfo: nil, repeats: false)
                RunLoop.main.add(timer, forMode: .common); controlsHideTimer = timer
            }
        }
        private func setVolumeControlVisible(_ visible: Bool) {
            volumeControl.isHidden = !visible; volumeBackdrop.isHidden = !visible
        }
        @objc private func hideOverlayControls() {
            controlsHideTimer?.invalidate(); controlsHideTimer = nil
            sidebarButton.isHidden = true; setVolumeControlVisible(false)
        }
        override func scrollWheel(with event: NSEvent) { adjustVolume(with: event) }
        private func adjustVolume(with event: NSEvent) {
            // AppKit latches scroll gestures to the original view even after the cursor leaves it.
            guard containsCurrentPointer(), let library, library.selected != nil,
                  event.momentumPhase.isEmpty else { return }
            let adjustment = volumeScroll.adjustment(
                horizontal: Double(event.scrollingDeltaX), vertical: Double(event.scrollingDeltaY),
                precise: event.hasPreciseScrollingDeltas, inverted: event.isDirectionInvertedFromDevice,
                momentum: false, timestamp: event.timestamp
            )
            if let adjustment {
                library.setVolume(library.volume + adjustment)
                if library.volume == 0 || library.volume == 1 { volumeScroll.reset() }
            }
            if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) { showVolumeFeedback() }
        }
        @objc private func toggleSidebar() {
            window?.makeFirstResponder(nil)
            pointer.lastSidebarToggleTime = ProcessInfo.processInfo.systemUptime
            onToggleSidebar?()
            showOverlayControls()
        }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updateBackground()
        }
        private func updateBackground() {
            let color = NSColor.sofaBackground(for: effectiveAppearance).cgColor
            layer?.backgroundColor = color
            playerView.layer?.backgroundColor = color
            cover.layer?.backgroundColor = color
        }
        func update(_ library: Library) {
            let channelChanged = displayedChannelID != library.selected?.id
            let volumeChanged = lastDisplayedVolume != nil && (lastDisplayedVolume != library.volume || lastDisplayedMute != library.isMuted)
            displayedChannelID = library.selected?.id
            if channelChanged { volumeScroll.reset() }
            if lastDisplayedVolume != library.volume || lastDisplayedMute != library.isMuted {
                lastDisplayedVolume = library.volume; lastDisplayedMute = library.isMuted
                volumeControl.setVolume(library.volume, muted: library.isMuted)
            }
            let alpha: CGFloat = library.webVideo ? 0.001 : 1
            if playerView.alphaValue != alpha { playerView.alphaValue = alpha }
            let gravity: AVLayerVideoGravity = library.stretch ? .resize : .resizeAspect
            if playerView.videoGravity != gravity { playerView.videoGravity = gravity }
            cover.isHidden = library.videoVisible
            if label.stringValue != library.playbackStatus { label.stringValue = library.playbackStatus }
            updateControlAvailability()
            if volumeChanged && !channelChanged && containsCurrentPointer() { showVolumeFeedback() }
        }
        override func layout() {
            super.layout()
            // Volume feedback must not resize/reflow either playback engine.
            if let web = library?.resolver.webView, web.frame != bounds { web.frame = bounds }
            if playerView.frame != bounds { playerView.frame = bounds }
            cover.frame = bounds; pointer.frame = bounds
            let fadeHeight = bounds.height * 0.1
            volumeBackdrop.frame = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: fadeHeight)
            let volumeSize = volumeControl.intrinsicContentSize
            volumeControl.frame = NSRect(x: max(8, bounds.maxX - volumeSize.width - 16), y: max(0, (fadeHeight - volumeSize.height) / 2), width: min(volumeSize.width, max(0, bounds.width - 16)), height: volumeSize.height)
            sidebarButton.frame = NSRect(x: 0, y: bounds.midY - 28, width: 28, height: 56)
            if pointerInVideo && !containsCurrentPointer() {
                pointerInVideo = false
                if !trackingControls { hideOverlayControls() }
            }
            spinner.frame = NSRect(x: bounds.midX - 16, y: bounds.midY + 4, width: 32, height: 32)
            label.frame = NSRect(x: 20, y: bounds.midY - 32, width: max(0, bounds.width - 40), height: 24)
        }
    }
}
