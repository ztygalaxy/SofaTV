import AppKit
import Testing
@testable import SofaTV

@MainActor @Suite("全屏控件与浏览面板层级", .serialized)
struct FullscreenControlOverlayTests {
    @Test func controlsAndTheirBackgroundsStayAboveBothBrowsers() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let suite = "sofatv-fullscreen-controls-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let a = Channel(name: "频道一", group: "全屏交互测试", url: URL(string: "http://127.0.0.1:1/one.m3u8")!)
        let b = Channel(name: "频道二", group: "全屏交互测试", url: URL(string: "http://127.0.0.1:1/two.m3u8")!)
        var preferences = ChannelPersonalization()
        preferences.record(a); preferences.record(b); preferences.favoriteKeys = [a.preferenceKey, b.preferenceKey]
        defaults.set(try JSONEncoder().encode([ChannelList.legacy([a, b])]), forKey: "channel-lists")
        defaults.set(try JSONEncoder().encode(preferences), forKey: "channel-personalization-v1")
        let app = Library(defaults: defaults, warmsChannels: false,
                          recoveryMonitor: PlaybackRecoveryMonitor(observeSystemEvents: false, pollsAutomatically: false))
        defer { app.stopPlayback(); defaults.removePersistentDomain(forName: suite) }
        app.selected = b; app.videoVisible = true
        let window = NSPanel(contentRect: NSRect(x: -10000, y: -10000, width: 1200, height: 700),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.close(); withExtendedLifetime(window) {} }
        var location = NSPoint(x: 44, y: 44)
        let stage = VideoStage.Stage(library: app, pointerLocation: { _ in location })
        window.contentView = stage; stage.frame = NSRect(x: 0, y: 0, width: 1200, height: 700)
        let preview = ProgramGuidePreview()
        let guide = ProgramGuideStore(observeSystemEvents: false)
        stage.configureFullscreenChannelPicker(library: app, ui: UIState(), programGuide: guide, preview: preview)
        stage.isVideoFullscreen = true; stage.layout()
        func event(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func center(_ view: NSView) -> NSPoint {
            stage.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), from: view)
        }
        let bottom = try #require(stage.previousChannelButton.superview as? VideoStage.ControlsOverlay)
        let top = try #require(stage.powerButton.superview as? VideoStage.ControlsOverlay)
        #expect(bottom !== top && bottom.superview === stage && top.superview === stage)
        let drawer = try #require(stage.subviews.first { $0 is VideoStage.FullscreenChannelDrawer })

        // Moving onto Return must not summon the channel drawer.
        stage.pointer.mouseMoved(with: event(.mouseMoved, at: location))
        #expect(drawer.isHidden)
        #expect(stage.hitTest(center(stage.previousChannelButton)) === stage.previousChannelButton)
        location = NSPoint(x: 5, y: 350)
        stage.pointer.mouseMoved(with: event(.mouseMoved, at: location))
        try await Task.sleep(for: .milliseconds(280))
        #expect(!drawer.isHidden)
        preview.showPlayingChannel(b, in: .fullscreen)
        preview.hoverPanel(true, in: .fullscreen)
        try await Task.sleep(for: .milliseconds(280))
        stage.layout()
        let guidePane = try #require(stage.subviews.first { $0 is ProgramGuideOverlayHost })
        #expect(stage.hitTest(center(stage.previousChannelButton)) === stage.previousChannelButton)
        #expect(stage.hitTest(center(stage.powerButton)) === stage.powerButton)
        let menuFooter = NSPoint(x: 22, y: 44)
        #expect(stage.hitTest(menuFooter) === bottom, "The mask must intercept clicks over the channel rows beneath it")
        let guideFooter = NSPoint(x: guidePane.frame.midX, y: 30)
        let footerHit = try #require(stage.hitTest(guideFooter))
        #expect(footerHit === guidePane || footerHit.isDescendant(of: guidePane), "Uncovered footer controls must remain usable")
        let headerHit = try #require(stage.hitTest(NSPoint(x: 150, y: 660)))
        #expect(headerHit === drawer || headerHit.isDescendant(of: drawer), "The gradient must not block the channel filters")
        let guideMiddle = NSPoint(x: guidePane.frame.midX, y: 350)
        let guideHit = try #require(stage.hitTest(guideMiddle))
        #expect(guideHit === guidePane || guideHit.isDescendant(of: guidePane), "Uncovered programme content must remain usable")
        if let path = ProcessInfo.processInfo.environment["SOFATV_OVERLAY_PREVIEW"] {
            let bitmap = try #require(stage.bitmapImageRepForCachingDisplay(in: stage.bounds))
            stage.cacheDisplay(in: stage.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        }
        bottom.mouseDown(with: event(.leftMouseDown, at: menuFooter))
        bottom.mouseUp(with: event(.leftMouseUp, at: menuFooter))
        #expect(app.selected?.id == b.id)
        stage.frame.size.width = 900; stage.layout()
        let overlappingFooter = NSPoint(x: guidePane.frame.maxX - 20, y: 44)
        let overlapHit = try #require(stage.hitTest(overlappingFooter))
        #expect(overlapHit === bottom || overlapHit.isDescendant(of: bottom), "Playback controls must win when a narrow window puts them over programme content")
        location = center(stage.previousChannelButton)
        let target = try #require(stage.hitTest(location))
        target.mouseDown(with: event(.leftMouseDown, at: location))
        target.mouseUp(with: event(.leftMouseUp, at: location))
        #expect(app.selected?.id == a.id, "A visible browser must not steal Return's click")

        // Normal/mini window gradients leave blank areas available for video gestures.
        stage.isVideoFullscreen = false; stage.isMiniPlayer = true
        stage.layout()
        location = NSPoint(x: 100, y: 30)
        stage.mouseMoved(with: event(.mouseMoved, at: location))
        #expect(stage.hitTest(location) === stage.pointer)
    }
}
