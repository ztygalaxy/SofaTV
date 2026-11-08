import SwiftUI
import AVKit
import WebKit
import QuartzCore
import Combine

/// One live stage moves between the main window, full screen, and a pinned mini player.
/// Both playback engines keep their sessions during the move.
struct VideoStage: NSViewRepresentable {
    @ObservedObject var library: Library
    @ObservedObject var ui: UIState
    @ObservedObject var programGuide: ProgramGuideStore
    let guidePreview: ProgramGuidePreview
    let sidebarCollapsed: Bool
    let onToggleSidebar: (Bool) -> Void
    func makeNSView(context: Context) -> Host {
        let host = Host(library: library)
        host.stage.configureSidebar(collapsed: sidebarCollapsed, toggle: onToggleSidebar)
        host.stage.configureFullscreenChannelPicker(library: library, ui: ui, programGuide: programGuide, preview: guidePreview)
        return host
    }
    func updateNSView(_ host: Host, context: Context) {
        host.stage.configureSidebar(collapsed: sidebarCollapsed, toggle: onToggleSidebar)
        host.stage.configureFullscreenChannelPicker(library: library, ui: ui, programGuide: programGuide, preview: guidePreview)
    }
    static func dismantleNSView(_ host: Host, coordinator: ()) {
        host.restoreEmbedded(animated: false, activateMain: false)
        host.stage.clearGuidePreview()
        host.stage.observation = nil
    }

    final class Host: VideoWindowHost {
        let stage: Stage
        private let placeholder = NSHostingView(rootView: AnyView(EmptyView()))
        init(library: Library) {
            stage = Stage(library: library)
            super.init(content: stage)
            placeholder.rootView = AnyView(VStack(spacing: 12) {
                Image(systemName: "pin.fill").font(.system(size: 24)).foregroundStyle(.secondary)
                Text("正在置顶小窗播放").foregroundStyle(.secondary)
                Button("返回主窗口") { [weak self] in self?.restoreEmbedded() }
            })
            placeholder.autoresizingMask = [.width, .height]
            placeholder.frame = bounds
            placeholder.isHidden = true
            addSubview(placeholder, positioned: .below, relativeTo: stage)
            onPresentationChange = { [weak self] mode in
                guard let self else { return }
                self.placeholder.isHidden = mode != .mini
                self.stage.isVideoFullscreen = mode == .fullscreen
                self.stage.isMiniPlayer = mode == .mini
            }
            stage.onToggleFullscreen = { [weak self] in self?.toggleFullscreen() }
            stage.onToggleMiniPlayer = { [weak self] in self?.toggleMini() }
            library.onStopPlayback = { [weak self] activateMain in
                self?.restoreEmbedded(animated: false, activateMain: activateMain)
            }
            onEscape = { [weak self] in self?.stage.dismissFullscreenBrowsers() ?? false }
            stage.pointer.onDoubleClick = { [weak self] in
                guard let self else { return }
                if self.presentation == .mini { self.restoreEmbedded() }
                else { self.toggleFullscreen() }
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
    final class PointerSurface: NSView {
        var onDoubleClick: (() -> Void)?
        var onPointerActivity: (() -> Void)?
        var onPointerMoved: ((NSEvent) -> Void)?
        var onScroll: ((NSEvent) -> Void)?
        var isWindowDraggable = false
        var lastSidebarToggleTime: TimeInterval = 0
        var cursorExclusions: [NSRect] = [] {
            didSet { if oldValue != cursorExclusions { window?.invalidateCursorRects(for: self) } }
        }
        private var pointerTrackingArea: NSTrackingArea?
        override var acceptsFirstResponder: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                owner: self
            )
            addTrackingArea(area); pointerTrackingArea = area
        }
        override func resetCursorRects() {
            for rect in PlaybackCursorRegions.background(in: visibleRect, excluding: cursorExclusions) {
                addCursorRect(rect, cursor: .arrow)
            }
        }
        private func showPointer() {
            NSCursor.setHiddenUntilMouseMoves(false)
        }
        override func mouseEntered(with event: NSEvent) { showPointer(); onPointerActivity?(); onPointerMoved?(event) }
        override func mouseMoved(with event: NSEvent) { showPointer(); onPointerActivity?(); onPointerMoved?(event) }
        override func mouseDown(with event: NSEvent) {
            onPointerActivity?()
            if event.clickCount == 2, ProcessInfo.processInfo.systemUptime - lastSidebarToggleTime > NSEvent.doubleClickInterval {
                onDoubleClick?()
            } else if isWindowDraggable, event.clickCount == 1 {
                window?.performDrag(with: event)
            }
        }
        override func mouseUp(with event: NSEvent) {}
        override func mouseDragged(with event: NSEvent) { onPointerActivity?() }
        override func rightMouseDown(with event: NSEvent) {}
        override func rightMouseUp(with event: NSEvent) {}
        override func scrollWheel(with event: NSEvent) { onScroll?(event) }
        override func magnify(with event: NSEvent) {}
        override func menu(for event: NSEvent) -> NSMenu? { nil }
    }
    /// The gradient and its controls form one layer above the fullscreen browsers.
    /// Padding around controls shields the browser without blocking its header or other content.
    final class ControlsOverlay: NSView {
        var onPointerActivity: (() -> Void)?
        var onScroll: ((NSEvent) -> Void)?
        var blocksBackgroundInteraction = false
        private let top: Bool
        private var area: NSTrackingArea?
        private var cursorFrames: [NSRect] = []
        init(top: Bool = false) {
            self.top = top
            super.init(frame: .zero)
            wantsLayer = true
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard !isHiddenOrHasHiddenAncestor, let hit = super.hitTest(point) else { return nil }
            if hit !== self { return hit }
            return blocksBackgroundInteraction && containsControls(convert(point, from: superview)) ? self : nil
        }
        func containsControls(_ point: NSPoint) -> Bool {
            subviews.contains { !$0.isHiddenOrHasHiddenAncestor && $0.frame.insetBy(dx: -8, dy: -8).intersection(bounds).contains(point) }
        }
        override func resetCursorRects() {
            let controls = subviews.filter { !$0.isHiddenOrHasHiddenAncestor }.map(\.frame)
            for control in controls {
                for rect in PlaybackCursorRegions.background(in: control.insetBy(dx: -8, dy: -8).intersection(visibleRect), excluding: controls) {
                    addCursorRect(rect, cursor: .arrow)
                }
            }
        }
        func refreshCursorRects() {
            let frames = subviews.filter { !$0.isHiddenOrHasHiddenAncestor }.map(\.frame)
            guard frames != cursorFrames else { return }
            cursorFrames = frames
            window?.invalidateCursorRects(for: self)
        }
        override func draw(_ dirtyRect: NSRect) {
            NSGradient(starting: .black.withAlphaComponent(0.85), ending: .clear)?.draw(in: bounds, angle: top ? 270 : 90)
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let next = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self)
            addTrackingArea(next); area = next
        }
        override func mouseEntered(with event: NSEvent) { onPointerActivity?() }
        override func mouseMoved(with event: NSEvent) { onPointerActivity?() }
        override func mouseDown(with event: NSEvent) { onPointerActivity?() }
        override func mouseUp(with event: NSEvent) {}
        override func scrollWheel(with event: NSEvent) { onPointerActivity?(); onScroll?(event) }
    }
    /// Stays in the video-only window, allowing the channel browser to blur the
    /// picture beneath it without bringing the normal application window forward.
    final class FullscreenChannelDrawer: NSVisualEffectView {
        var onPointerMoved: ((NSEvent) -> Void)?
        var onPointerExited: ((NSEvent) -> Void)?
        private var pointerTrackingArea: NSTrackingArea?
        private var contentHost: NSHostingView<AnyView>?

        init() {
            super.init(frame: .zero)
            appearance = NSAppearance(named: .darkAqua)
            material = .underWindowBackground
            blendingMode = .withinWindow
            state = .active
            wantsLayer = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func setContent(_ view: AnyView) {
            guard contentHost == nil else { return }
            let host = NSHostingView<AnyView>(rootView: AnyView(view.preferredColorScheme(.dark)))
            host.translatesAutoresizingMaskIntoConstraints = false
            addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: leadingAnchor),
                host.trailingAnchor.constraint(equalTo: trailingAnchor),
                host.topAnchor.constraint(equalTo: topAnchor),
                host.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            contentHost = host
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                owner: self
            )
            addTrackingArea(area)
            pointerTrackingArea = area
        }

        override func mouseEntered(with event: NSEvent) { onPointerMoved?(event) }
        override func mouseMoved(with event: NSEvent) { onPointerMoved?(event) }
        override func mouseExited(with event: NSEvent) { onPointerExited?(event) }
    }
    final class Stage: NSView {
        let playerView = AVPlayerView()
        let pointer = PointerSurface()
        private let fullscreenDrawer = FullscreenChannelDrawer()
        private let sidebarButton = SidebarToggleButton()
        private let volumeControl = VideoVolumeControl()
        private let volumeBackdrop = ControlsOverlay()
        private let topBackdrop = ControlsOverlay(top: true)
        private let miniPlayerButton = VideoVolumeControl.SymbolButton()
        let powerButton = VideoVolumeControl.SymbolButton()
        let previousChannelButton = VideoVolumeControl.SymbolButton()
        private var volumeScroll = VideoVolumeScroll()
        private var lastDisplayedVolume: Float?
        private var lastDisplayedMute: Bool?
        private var displayedChannelID: String?
        private var sidebarCollapsed = false
        private var onToggleSidebar: ((Bool) -> Void)?
        private var sidebarTrackingArea: NSTrackingArea?
        private var controlsHideTimer: Timer?
        private var fullscreenDrawerHideTimer: Timer?
        private var pointerInVideo = false
        private var trackingSidebarButton = false
        private var trackingVolume = false
        private var trackingMiniPlayerButton = false
        private var trackingPowerButton = false
        private var trackingPreviousChannelButton = false
        private var sidebarControlAvailable = false
        private var volumeControlAvailable = false
        private var fullscreenDrawerVisible = false
        private var fullscreenBrowserSuppressed = false
        private var fullscreenBrowsersClosing = false {
            didSet { guidePreview?.acceptsHover = !fullscreenBrowsersClosing }
        }
        private var fullscreenPickerConfigured = false
        private weak var guidePreview: ProgramGuidePreview?
        private var guideHost: ProgramGuideOverlayHost?
        private var guideUpdates = Set<AnyCancellable>()
        private var trackingControls: Bool { trackingSidebarButton || trackingVolume || trackingMiniPlayerButton || trackingPowerButton || trackingPreviousChannelButton }
        var onToggleFullscreen: (() -> Void)?
        var onToggleMiniPlayer: (() -> Void)?
        var isMiniPlayer = false {
            didSet {
                pointer.isWindowDraggable = isMiniPlayer
                layer?.cornerRadius = isMiniPlayer ? 10 : 0
                layer?.masksToBounds = isMiniPlayer
                configureMiniPlayerButton()
                updateControlAvailability()
                updateGuidePresentation()
            }
        }
        var isVideoFullscreen = false {
            didSet {
                volumeControl.setFullscreen(isVideoFullscreen)
                volumeBackdrop.blocksBackgroundInteraction = isVideoFullscreen
                topBackdrop.blocksBackgroundInteraction = isVideoFullscreen
                if !isVideoFullscreen { setFullscreenDrawerVisible(false, animated: false) }
                fullscreenBrowserSuppressed = false
                fullscreenBrowsersClosing = false
                updateControlAvailability()
                updateGuidePresentation()
            }
        }
        let cover = NSView()
        let spinner = NSProgressIndicator()
        let label = NSTextField(labelWithString: "正在加载…")
        weak var library: Library?
        var observation: NSKeyValueObservation?
        private var libraryUpdates: AnyCancellable?
        private let pointerLocation: (NSWindow) -> NSPoint
        init(library: Library, pointerLocation: @escaping (NSWindow) -> NSPoint = { $0.mouseLocationOutsideOfEventStream }) {
            self.library = library
            self.pointerLocation = pointerLocation
            super.init(frame: .zero)
            wantsLayer = true
            let web = library.resolver.webView
            web.removeFromSuperview(); addSubview(web)
            playerView.controlsStyle = .none; playerView.showsFullScreenToggleButton = false
            playerView.allowsVideoFrameAnalysis = false
            playerView.player = library.player; playerView.wantsLayer = true; addSubview(playerView)
            cover.wantsLayer = true
            spinner.style = .spinning; spinner.controlSize = .large; spinner.startAnimation(nil)
            label.textColor = .secondaryLabelColor; label.alignment = .center
            cover.addSubview(spinner); cover.addSubview(label); addSubview(cover)
            addSubview(pointer)
            fullscreenDrawer.isHidden = true; addSubview(fullscreenDrawer)
            sidebarButton.target = self; sidebarButton.action = #selector(toggleSidebar)
            sidebarButton.isHidden = true; addSubview(sidebarButton)
            topBackdrop.isHidden = true; addSubview(topBackdrop)
            volumeBackdrop.isHidden = true; addSubview(volumeBackdrop)
            volumeControl.isHidden = true; volumeBackdrop.addSubview(volumeControl)
            miniPlayerButton.target = self; miniPlayerButton.action = #selector(toggleMiniPlayer)
            miniPlayerButton.isHidden = true; topBackdrop.addSubview(miniPlayerButton)
            powerButton.target = self; powerButton.action = #selector(stopPlayback)
            powerButton.toolTip = "停止播放"; powerButton.setAccessibilityLabel("停止播放")
            powerButton.setSymbol("power")
            powerButton.isHidden = true; topBackdrop.addSubview(powerButton)
            previousChannelButton.target = self; previousChannelButton.action = #selector(playPreviousChannel)
            if let url = Bundle.main.url(forResource: "fanhuishangyiceng", withExtension: "svg", subdirectory: "PlaybackControls"),
               let image = NSImage(contentsOf: url) {
                previousChannelButton.setImage(image)
            } else { previousChannelButton.setSymbol("arrow.uturn.backward") }
            previousChannelButton.isHidden = true; volumeBackdrop.addSubview(previousChannelButton)
            configureMiniPlayerButton()
            pointer.onPointerActivity = { [weak self] in self?.showOverlayControls() }
            pointer.onPointerMoved = { [weak self] event in self?.updateFullscreenDrawer(for: event) }
            pointer.onScroll = { [weak self] event in self?.adjustVolume(with: event) }
            for overlay in [volumeBackdrop, topBackdrop] {
                overlay.onPointerActivity = { [weak self] in self?.showOverlayControls() }
                overlay.onScroll = { [weak self] event in self?.adjustVolume(with: event) }
            }
            fullscreenDrawer.onPointerMoved = { [weak self] event in self?.updateFullscreenDrawer(for: event) }
            fullscreenDrawer.onPointerExited = { [weak self] event in self?.fullscreenDrawerDidExit(for: event) }
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
            miniPlayerButton.onPointerActivity = { [weak self] in self?.showOverlayControls() }
            miniPlayerButton.onScroll = { [weak self] event in self?.adjustVolume(with: event) }
            miniPlayerButton.onTrackingChanged = { [weak self] tracking in
                guard let self else { return }
                self.trackingMiniPlayerButton = tracking
                self.pointer.lastSidebarToggleTime = ProcessInfo.processInfo.systemUptime
                self.controlsTrackingChanged()
            }
            powerButton.onPointerActivity = { [weak self] in self?.showOverlayControls() }
            powerButton.onScroll = { [weak self] event in self?.adjustVolume(with: event) }
            powerButton.onTrackingChanged = { [weak self] tracking in
                guard let self else { return }
                self.trackingPowerButton = tracking
                self.pointer.lastSidebarToggleTime = ProcessInfo.processInfo.systemUptime
                self.controlsTrackingChanged()
            }
            previousChannelButton.onPointerActivity = { [weak self] in self?.showOverlayControls() }
            previousChannelButton.onScroll = { [weak self] event in self?.adjustVolume(with: event) }
            previousChannelButton.onTrackingChanged = { [weak self] tracking in
                guard let self else { return }
                self.trackingPreviousChannelButton = tracking
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
            // A detached stage stays live even while the main SwiftUI window is hidden.
            libraryUpdates = library.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self, weak library] in
                guard let self, let library else { return }
                self.update(library)
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        private func configureMiniPlayerButton() {
            let title = isMiniPlayer ? "返回主窗口" : "置顶迷你窗口"
            miniPlayerButton.toolTip = title
            miniPlayerButton.setAccessibilityLabel(title)
            miniPlayerButton.setSymbol(isMiniPlayer ? "pin.slash.fill" : "pin.fill", rotation: -45)
        }
        @objc private func toggleMiniPlayer() {
            pointer.lastSidebarToggleTime = ProcessInfo.processInfo.systemUptime
            onToggleMiniPlayer?()
        }
        @objc private func stopPlayback() { library?.stopPlayback() }
        @objc private func playPreviousChannel() {
            pointer.lastSidebarToggleTime = ProcessInfo.processInfo.systemUptime
            library?.playPreviousChannel()
        }
        func configureSidebar(collapsed: Bool, toggle: @escaping (Bool) -> Void) {
            sidebarCollapsed = collapsed; onToggleSidebar = toggle
            sidebarButton.setCollapsed(collapsed)
            updateControlAvailability()
            updateGuidePresentation()
        }
        func configureFullscreenChannelPicker(library: Library, ui: UIState, programGuide: ProgramGuideStore, preview: ProgramGuidePreview) {
            guideHost?.playingChannel = library.catalogSelectedChannel
            guard !fullscreenPickerConfigured else { return }
            fullscreenPickerConfigured = true
            guidePreview = preview
            fullscreenDrawer.setContent(AnyView(FullscreenChannelPicker(library: library, ui: ui, programGuide: programGuide, guidePreview: preview)))
            let guide = ProgramGuideOverlayHost(preview: preview, store: programGuide, presentation: .fullscreen,
                                                playingChannel: library.catalogSelectedChannel)
            guideHost = guide
            addSubview(guide, positioned: .below, relativeTo: topBackdrop)
            preview.$channel.receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.updateGuideInteraction()
            }.store(in: &guideUpdates)
            preview.$panelHovered.receive(on: DispatchQueue.main).sink { [weak self] inside in
                guard let self, self.isVideoFullscreen else { return }
                if inside { self.fullscreenDrawerHideTimer?.invalidate(); self.fullscreenDrawerHideTimer = nil }
                else if !self.fullscreenBrowserContainsCurrentPointer() { self.scheduleFullscreenDrawerHide() }
            }.store(in: &guideUpdates)
            updateGuidePresentation()
        }
        func clearGuidePreview() {
            guidePreview?.setPresentation(.embedded)
            guidePreview?.dismiss()
        }
        private func updateGuidePresentation() {
            guidePreview?.setPresentation(isMiniPlayer ? nil : isVideoFullscreen ? .fullscreen : sidebarCollapsed ? nil : .embedded)
            updateGuideInteraction()
        }
        private func updateGuideInteraction() {
            guideHost?.isHidden = !isVideoFullscreen
            guideHost?.isInteractive = isVideoFullscreen && guidePreview?.channel != nil
            updateCursorRegions()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateControlAvailability()
            if window == nil {
                miniPlayerButton.cancelTracking()
                powerButton.cancelTracking()
                previousChannelButton.cancelTracking()
                volumeScroll.reset(); hideOverlayControls(); setFullscreenDrawerVisible(false, animated: false)
            }
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
            return bounds.contains(convert(pointerLocation(window), from: nil))
        }
        private func fullscreenDrawerFrame(visible: Bool) -> NSRect {
            let width = min(max(320, bounds.width / 3), 460)
            return NSRect(x: visible ? 0 : -width - 12, y: 0, width: width, height: bounds.height)
        }
        private func layoutFullscreenDrawer() {
            let target = fullscreenDrawerFrame(visible: fullscreenDrawerVisible)
            // Keep an in-flight slide animation intact; only update the size.
            if fullscreenDrawer.frame.size != target.size || fullscreenDrawer.isHidden {
                fullscreenDrawer.frame = target
            }
        }
        private func updateFullscreenDrawer(for event: NSEvent) {
            guard isVideoFullscreen, !fullscreenBrowsersClosing else { return }
            let location = convert(event.locationInWindow, from: nil)
            if fullscreenBrowserSuppressed {
                if !fullscreenBrowserContains(location) { fullscreenBrowserSuppressed = false }
                return
            }
            if fullscreenBrowserContains(location) { setFullscreenDrawerVisible(true) }
            else { scheduleFullscreenDrawerHide() }
        }
        private func fullscreenDrawerDidExit(for event: NSEvent) {
            updateFullscreenDrawer(for: event)
        }
        private func fullscreenBrowserContains(_ point: NSPoint) -> Bool {
            !controlsContain(point) && bounds.contains(point) && (point.x <= bounds.width / 3 ||
                (guideHost?.isInteractive == true && guideHost?.frame.contains(point) == true))
        }
        private func fullscreenBrowserContainsCurrentPointer() -> Bool {
            guard let window else { return false }
            return fullscreenBrowserContains(convert(pointerLocation(window), from: nil))
        }
        func dismissFullscreenBrowsers() -> Bool {
            guard isVideoFullscreen else { return false }
            if fullscreenBrowsersClosing { return true }
            guard fullscreenDrawerVisible || guidePreview?.channel != nil else { return false }
            // Keep a stationary pointer from immediately reopening the dismissed sidebar.
            fullscreenBrowserSuppressed = true
            fullscreenBrowsersClosing = true
            fullscreenDrawerHideTimer?.invalidate(); fullscreenDrawerHideTimer = nil
            if guidePreview?.channel != nil {
                guidePreview?.dismiss { [weak self] in
                    guard let self, self.isVideoFullscreen else { return }
                    self.setFullscreenDrawerVisible(false)
                }
            } else {
                setFullscreenDrawerVisible(false)
            }
            return true
        }
        private func setFullscreenDrawerVisible(_ visible: Bool, animated: Bool = true) {
            fullscreenDrawerHideTimer?.invalidate(); fullscreenDrawerHideTimer = nil
            guard isVideoFullscreen || !visible else { return }
            guard fullscreenDrawerVisible != visible || (!visible && !fullscreenDrawer.isHidden) else {
                if !visible { fullscreenBrowsersClosing = false }
                return
            }
            fullscreenDrawerVisible = visible
            if !visible, isVideoFullscreen { guidePreview?.dismiss() }
            let target = fullscreenDrawerFrame(visible: visible)
            if visible { fullscreenDrawer.isHidden = false }
            let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !animated ? 0 : 0.24
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                fullscreenDrawer.animator().frame = target
            } completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, !self.fullscreenDrawerVisible else { return }
                    self.fullscreenDrawer.isHidden = true
                    self.fullscreenBrowsersClosing = false
                }
            }
        }
        private func scheduleFullscreenDrawerHide() {
            guard fullscreenDrawerVisible, !fullscreenBrowsersClosing, guidePreview?.panelHovered != true else { return }
            fullscreenDrawerHideTimer?.invalidate()
            let timer = Timer(timeInterval: 0.45, target: self, selector: #selector(hideFullscreenDrawer), userInfo: nil, repeats: false)
            RunLoop.main.add(timer, forMode: .common)
            fullscreenDrawerHideTimer = timer
        }
        @objc private func hideFullscreenDrawer() { setFullscreenDrawerVisible(false) }
        private func updateControlAvailability() {
            // Keep the expand affordance usable during buffering or a failed source.
            let sidebarAvailable = window != nil && !isVideoFullscreen && !isMiniPlayer && (library?.videoVisible == true || sidebarCollapsed)
            let volumeAvailable = window != nil && library?.selected != nil
            let becameAvailable = (sidebarAvailable && !sidebarControlAvailable) || (volumeAvailable && !volumeControlAvailable)
            sidebarControlAvailable = sidebarAvailable; volumeControlAvailable = volumeAvailable
            if !sidebarAvailable { sidebarButton.isHidden = true }
            if !volumeAvailable { setPlayerControlsVisible(false) }
            if !sidebarAvailable && !volumeAvailable { hideOverlayControls() }
            else if becameAvailable && containsCurrentPointer() { showOverlayControls() }
            updateCursorRegions()
        }
        private func showOverlayControls() {
            guard sidebarControlAvailable || volumeControlAvailable else { return }
            guard containsCurrentPointer() else {
                if !trackingControls { hideOverlayControls() }
                return
            }
            pointerInVideo = true
            sidebarButton.isHidden = !sidebarControlAvailable
            setPlayerControlsVisible(volumeControlAvailable)
            scheduleControlsHide()
        }
        private func showVolumeFeedback() {
            guard volumeControlAvailable else { return }
            setPlayerControlsVisible(true)
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
                let timer = Timer(timeInterval: 3, target: self, selector: #selector(hideIdleControls), userInfo: nil, repeats: false)
                RunLoop.main.add(timer, forMode: .common); controlsHideTimer = timer
            }
        }
        private func setPlayerControlsVisible(_ visible: Bool) {
            for view in [volumeControl, volumeBackdrop, miniPlayerButton, topBackdrop, powerButton, previousChannelButton]
                where view.isHidden == visible { view.isHidden = !visible }
            updateCursorRegions()
            volumeBackdrop.refreshCursorRects(); topBackdrop.refreshCursorRects()
        }
        @objc private func hideIdleControls() {
            controlsHideTimer = nil
            if trackingControls || pointerIsOverControls() { scheduleControlsHide(); return }
            hideOverlayControls()
        }
        private var cursorControls: [NSView] { [sidebarButton, volumeBackdrop, topBackdrop] }
        private func controlsContain(_ point: NSPoint) -> Bool {
            if !sidebarButton.isHiddenOrHasHiddenAncestor && sidebarButton.frame.contains(point) { return true }
            return [volumeBackdrop, topBackdrop].contains { !$0.isHiddenOrHasHiddenAncestor && $0.containsControls($0.convert(point, from: self)) }
        }
        private func pointerIsOverControls() -> Bool {
            guard let window else { return false }
            let point = convert(pointerLocation(window), from: nil)
            return controlsContain(point)
        }
        private func updateCursorRegions() {
            var obstacles = cursorControls + [fullscreenDrawer]
            if let guideHost, guidePreview?.channel != nil { obstacles.append(guideHost) }
            var exclusions = obstacles.filter { !$0.isHiddenOrHasHiddenAncestor }.map { pointer.convert($0.bounds, from: $0) }
            let resizeInset = !sidebarCollapsed && !isVideoFullscreen && !isMiniPlayer ? SidebarResizeHandle.hitExtension : 0
            sidebarButton.leadingResizeInset = resizeInset
            if resizeInset > 0 {
                exclusions.append(NSRect(x: pointer.bounds.minX, y: pointer.bounds.minY, width: resizeInset, height: pointer.bounds.height))
            }
            pointer.cursorExclusions = exclusions
        }
        @objc private func hideOverlayControls() {
            controlsHideTimer?.invalidate(); controlsHideTimer = nil
            sidebarButton.isHidden = true; setPlayerControlsVisible(false)
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
            sidebarCollapsed.toggle()
            sidebarButton.setCollapsed(sidebarCollapsed)
            updateGuidePresentation()
            onToggleSidebar?(sidebarCollapsed)
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
            let previousTitle = library.previousChannel.map { "返回上一观看频道 · \($0.displayName)" } ?? "返回上一观看频道"
            previousChannelButton.toolTip = previousTitle
            previousChannelButton.setAccessibilityLabel(previousTitle)
            previousChannelButton.isEnabled = library.previousChannel != nil
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
            layoutFullscreenDrawer()
            let guideX = fullscreenDrawerFrame(visible: true).maxX
            guideHost?.frame = NSRect(x: guideX, y: 0, width: min(340, max(0, bounds.width - guideX)), height: bounds.height)
            let controlInset: CGFloat = 16
            let cornerCenterInset = controlInset + VideoVolumeControl.trailingButtonCenterInset
            let buttonSide = VideoVolumeControl.buttonSide
            let fadeHeight = max(cornerCenterInset * 2, bounds.height * 0.1)
            volumeBackdrop.frame = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: fadeHeight)
            topBackdrop.frame = NSRect(x: bounds.minX, y: bounds.maxY - fadeHeight, width: bounds.width, height: fadeHeight)
            miniPlayerButton.frame = NSRect(x: topBackdrop.bounds.maxX - cornerCenterInset - buttonSide / 2, y: topBackdrop.bounds.maxY - cornerCenterInset - buttonSide / 2, width: buttonSide, height: buttonSide)
            powerButton.frame = NSRect(x: miniPlayerButton.frame.minX - buttonSide - 4, y: miniPlayerButton.frame.minY,
                                       width: buttonSide, height: buttonSide)
            previousChannelButton.frame = NSRect(x: cornerCenterInset - buttonSide / 2,
                                                y: volumeBackdrop.bounds.minY + cornerCenterInset - buttonSide / 2,
                                                width: buttonSide, height: buttonSide)
            let volumeSize = volumeControl.intrinsicContentSize
            let volumeWidth = min(volumeSize.width, max(0, bounds.maxX - controlInset - previousChannelButton.frame.maxX - 8))
            volumeControl.frame = NSRect(x: volumeBackdrop.bounds.maxX - volumeWidth - controlInset, y: volumeBackdrop.bounds.minY + cornerCenterInset - volumeSize.height / 2,
                                         width: volumeWidth, height: volumeSize.height)
            sidebarButton.frame = NSRect(x: 0, y: bounds.midY - 28, width: 28, height: 56)
            if pointerInVideo && !containsCurrentPointer() {
                pointerInVideo = false
                if !trackingControls { hideOverlayControls() }
            }
            spinner.frame = NSRect(x: bounds.midX - 16, y: bounds.midY + 4, width: 32, height: 32)
            label.frame = NSRect(x: 20, y: bounds.midY - 32, width: max(0, bounds.width - 40), height: 24)
            volumeBackdrop.refreshCursorRects(); topBackdrop.refreshCursorRects()
            updateCursorRegions()
        }
    }
}

/// A compact channel browser for the video-only full-screen window. It observes
/// the same state as the main sidebar, so programme updates and choices stay in sync.
private struct FullscreenChannelPicker: View {
    @ObservedObject var library: Library
    @ObservedObject var ui: UIState
    @ObservedObject var programGuide: ProgramGuideStore
    let guidePreview: ProgramGuidePreview
    private let contentScale: CGFloat = 1.3

    private struct Section: Identifiable {
        let name: String
        let channels: [Channel]
        var id: String { name }
    }

    private func sections() -> (channels: Int, values: [Section]) {
        var channelsByGroup: [String: [Channel]] = [:]
        var channelCount = 0
        for channel in library.channels {
            guard (!ui.favoritesOnly || library.favorites.contains(channel.id)),
                  channel.matches(ui.search) else { continue }
            channelCount += 1
            channelsByGroup[channel.displayGroup, default: []].append(channel)
        }
        return (channelCount, library.orderedGroups.filter { channelsByGroup[$0] != nil }.map { Section(name: $0, channels: channelsByGroup[$0] ?? []) })
    }

    private func groupHeader(_ group: String) -> some View {
        Button { ui.toggleGroup(group) } label: {
            HStack(spacing: 7 * contentScale) {
                Image(systemName: ui.collapsedGroups.contains(group) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10 * contentScale, weight: .semibold)).frame(width: 12 * contentScale)
                Text(group).font(.system(size: 13 * contentScale, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 4 * contentScale).padding(.trailing, 12 * contentScale).padding(.vertical, 9 * contentScale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group)
        .accessibilityValue(ui.collapsedGroups.contains(group) ? "已折叠" : "已展开")
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    var body: some View {
        let snapshot = sections()
        let pinnedGroups = snapshot.values.map {
            ChannelListGroup(name: $0.name, visibleChannelCount: ui.collapsedGroups.contains($0.name) ? 0 : $0.channels.count)
        }
        VStack(spacing: 0) {
            HStack(spacing: 10 * contentScale) {
                ChannelFilterTabs(favoritesOnly: $ui.favoritesOnly, contentScale: contentScale)
                    .frame(width: 130 * contentScale, height: 26 * contentScale)
                HStack(spacing: 5 * contentScale) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索", text: $ui.search)
                        .textFieldStyle(.plain).accessibilityLabel("搜索频道或分组")
                    if !ui.search.isEmpty {
                        Button { ui.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).help("清除搜索")
                    }
                }
                .font(.system(size: 13 * contentScale))
                .padding(.horizontal, 8 * contentScale).frame(height: 26 * contentScale)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6 * contentScale))
            }
            .padding(.horizontal, 14 * contentScale).padding(.top, 18 * contentScale).padding(.bottom, 10 * contentScale)

            List {
                ForEach(snapshot.values) { section in
                    groupHeader(section.name)
                    if !ui.collapsedGroups.contains(section.name) {
                        ForEach(section.channels) { channel in
                            ChannelRow(
                                channel: channel,
                                isFavorite: library.favorites.contains(channel.id),
                                isSelected: library.selected?.identity == channel.identity,
                                currentProgram: programGuide.titles[channel.id],
                                onPlay: { library.play(channel) },
                                onFavorite: { library.favorite(channel) },
                                onDeleteSource: { _ in },
                                onDelete: {},
                                allowsDeletion: false,
                                contentScale: contentScale
                            )
                            .equatable()
                            .onHover { guidePreview.hover(channel, in: .fullscreen, inside: $0) }
                            .onDisappear { guidePreview.hover(channel, in: .fullscreen, inside: false) }
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(ChannelRowHighlight(preview: guidePreview, channel: channel.identity,
                                                                  presentation: .fullscreen, selected: library.selected?.identity == channel.identity))
                            .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .background {
                ChannelListScrollStyle(
                    groups: pinnedGroups,
                    makeHeader: { AnyView(groupHeader($0)) },
                    pinnedHeaderBackground: .clear,
                    clipsContentBehindHeader: true
                )
            }
            .overlay {
                if library.channels.isEmpty {
                    SidebarEmptyView("暂无频道", systemImage: "tv")
                } else if snapshot.channels == 0 {
                    SidebarEmptyView(ui.favoritesOnly ? "暂无收藏频道" : "没有匹配的频道", systemImage: ui.favoritesOnly ? "star" : "magnifyingglass")
                }
            }

            .modifier(ChannelListFocus(preview: guidePreview, presentation: .fullscreen,
                                       favorites: library.favorites, search: $ui.search,
                                       favoritesOnly: $ui.favoritesOnly, collapsedGroups: $ui.collapsedGroups))

            HStack(spacing: 8 * contentScale) {
                AppLogoView(size: 16 * contentScale)
                Spacer(minLength: 6)
                Text("\(snapshot.channels) 个频道").fixedSize()
            }
            .font(.system(size: 11 * contentScale)).foregroundStyle(.secondary)
            .padding(.horizontal, 14 * contentScale).padding(.vertical, 10 * contentScale)
        }
        .background(Color.clear)
    }
}
