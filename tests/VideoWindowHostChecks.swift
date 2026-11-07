import AppKit
import AVKit

/// Exercise native window ownership without presenting windows on the desktop.
@MainActor private final class EmbeddedWindow: NSWindow {
    var hiddenCount = 0
    var raisedCount = 0
    var onRaise: (() -> Void)?
    override func orderOut(_ sender: Any?) { hiddenCount += 1 }
    override func makeKeyAndOrderFront(_ sender: Any?) { raisedCount += 1; onRaise?() }
}

@MainActor private final class DetachedWindow: VideoDetachedWindow {
    var closedCount = 0
    var onClose: (() -> Void)?
    override func makeKeyAndOrderFront(_ sender: Any?) {}
    override func close() { closedCount += 1; onClose?(); super.close() }
}

@main struct VideoWindowHostChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let main = EmbeddedWindow(contentRect: NSRect(x: 40, y: 40, width: 900, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
        main.isReleasedWhenClosed = false
        let content = NSView()
        let playerView = AVPlayerView()
        let player = AVPlayer()
        playerView.player = player
        playerView.controlsStyle = .none
        content.addSubview(playerView)
        let item = AVPlayerItem(asset: AVMutableComposition())
        player.replaceCurrentItem(with: item)
        var created: [DetachedWindow] = []
        var returnEvents: [String] = []
        main.onRaise = { returnEvents.append("raise") }
        let host = VideoWindowHost(content: content, activateApplication: { returnEvents.append("activate") }) { frame, mode in
            let window = DetachedWindow(frame: frame, presentation: mode)
            window.onClose = { returnEvents.append("close") }
            created.append(window)
            return window
        }
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 560)
        main.contentView = host
        host.layoutSubtreeIfNeeded()
        var modes: [VideoPresentation] = []
        host.onPresentationChange = { modes.append($0) }

        func checkPlaybackIdentity() {
            precondition(host.content === content && content.subviews.first === playerView)
            precondition(playerView.player === player && player.currentItem === item, "Window changes must preserve the player and playing item")
        }

        host.toggleMini(animated: false)
        let firstMini = host.detachedWindow!
        precondition(host.presentation == .mini && content.window === firstMini)
        precondition(firstMini.level == .floating && firstMini.isFloatingPanel && !firstMini.hidesOnDeactivate)
        precondition(firstMini.styleMask.contains(.nonactivatingPanel) && firstMini.styleMask.contains(.resizable))
        precondition(firstMini.isMovable && firstMini.contentAspectRatio == NSSize(width: 16, height: 9))
        precondition(firstMini.frame.size == NSSize(width: 400, height: 225))
        precondition(content.bounds.size == firstMini.frame.size)
        precondition(main.hiddenCount == 1)
        checkPlaybackIdentity()

        firstMini.setFrame(NSRect(x: 50, y: 50, width: 480, height: 270), display: false)
        content.layoutSubtreeIfNeeded()
        precondition(content.bounds.size == NSSize(width: 480, height: 270))

        host.toggleFullscreen(animated: false)
        precondition(host.presentation == .fullscreen && content.window === host.detachedWindow)
        precondition(host.detachedWindow !== firstMini && created[0].closedCount == 1)
        precondition(host.detachedWindow!.level.rawValue > NSWindow.Level.mainMenu.rawValue)
        checkPlaybackIdentity()

        host.toggleMini(animated: false)
        precondition(host.presentation == .mini && created[1].closedCount == 1)
        checkPlaybackIdentity()
        returnEvents.removeAll()
        host.toggleMini(animated: false)
        precondition(returnEvents == ["activate", "raise", "close"], "Restore and activate the main window before closing the nonactivating panel")
        precondition(host.presentation == .embedded && host.detachedWindow == nil && content.superview === host)
        precondition(content.frame == host.bounds)
        precondition(main.raisedCount == 1)
        checkPlaybackIdentity()

        for _ in 0..<10 {
            host.toggleMini(animated: false)
            host.toggleFullscreen(animated: false)
            host.restoreEmbedded(animated: false)
            checkPlaybackIdentity()
        }

        host.toggleMini(animated: false)
        let before = main.raisedCount
        returnEvents.removeAll()
        host.restoreEmbedded(animated: false, activateMain: false)
        precondition(returnEvents == ["close"], "Disposal must not activate the application")
        precondition(main.raisedCount == before && host.detachedWindow == nil, "Disposal must not reopen the main window")
        checkPlaybackIdentity()

        host.toggleMini(animated: false)
        precondition(!host.windowShouldClose(host.detachedWindow!))
        precondition(host.presentation == .embedded && content.superview === host)
        checkPlaybackIdentity()

        host.toggleFullscreen(animated: false)
        var browsersOpen = true
        host.onEscape = {
            if browsersOpen { browsersOpen = false; return true }
            return false
        }
        let fullscreen = host.detachedWindow!
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: fullscreen.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        precondition(fullscreen.performKeyEquivalent(with: escape))
        precondition(!browsersOpen && host.presentation == .fullscreen, "Escape must close browsers before leaving full screen")
        checkPlaybackIdentity()
        precondition(fullscreen.performKeyEquivalent(with: escape))
        for _ in 0..<100 {
            if host.presentation == .embedded { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(host.presentation == .embedded, "Escape with no browsers must restore the main window")
        host.onEscape = nil
        checkPlaybackIdentity()

        for screen in [NSRect(x: 0, y: 30, width: 1440, height: 850), NSRect(x: -1920, y: -200, width: 1920, height: 1080)] {
            let frame = VideoDetachedWindow.miniFrame(in: screen)
            precondition(screen.contains(frame) && frame.width == 400 && frame.height == 225)
        }
        precondition(modes.contains(.mini) && modes.contains(.fullscreen) && modes.last == .embedded)
        withExtendedLifetime((main, created)) {}
        print("Video windows passed: pinned panel, window round trips, playback identity, browser-first Escape, close/disposal, and display bounds")
    }
}
