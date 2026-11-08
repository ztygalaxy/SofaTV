import AppKit
import Testing
@testable import SofaTV

@MainActor @Suite("视频返回上一观看频道", .serialized)
struct VideoPreviousChannelTests {
    @Test func buttonKeepsDisabledStateAndUsesTheSameHistoryActionAsTheMenu() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let name = "sofatv-previous-button-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        let app = Library(defaults: defaults, warmsChannels: false,
                          recoveryMonitor: PlaybackRecoveryMonitor(observeSystemEvents: false, pollsAutomatically: false))
        defer { app.stopPlayback(); defaults.removePersistentDomain(forName: name) }
        let a = Channel(name: "频道一", group: "测试", url: URL(string: "http://127.0.0.1:1/previous-one.m3u8")!)
        let b = Channel(name: "频道二", group: "测试", url: URL(string: "http://127.0.0.1:1/previous-two.m3u8")!)
        var preferences = ChannelPersonalization(); preferences.record(a)
        func restore() throws {
            try app.restoreConfiguration(JSONEncoder().encode(ChannelConfigurationBackup(sources: [.legacy([a, b])], personalization: preferences)))
        }
        try restore(); app.selected = a; app.videoVisible = true
        let stage = VideoStage.Stage(library: app)
        let window = NSPanel(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 506),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = stage; window.orderBack(nil)
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.close(); withExtendedLifetime(window) {} }
        let iconURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Assets/PlaybackControls/fanhuishangyiceng.svg")
        stage.previousChannelButton.setImage(try #require(NSImage(contentsOf: iconURL)))
        stage.frame = NSRect(x: 0, y: 0, width: 900, height: 506)
        stage.layoutSubtreeIfNeeded()
        for control in playbackControlViews(in: stage) { control.isHidden = false }
        #expect(!stage.previousChannelButton.isEnabled && app.previousChannel == nil)
        #expect(stage.previousChannelButton.toolTip == "返回上一观看频道")
        #expect(!stage.previousChannelButton.isHidden, "A single watched channel should disable the button, not remove it")
        stage.previousChannelButton.sendAction(stage.previousChannelButton.action, to: stage.previousChannelButton.target)
        #expect(app.selected?.id == a.id)
        try capture(stage, name: "disabled")

        preferences.record(b); try restore(); app.selected = b; app.videoVisible = true
        stage.update(app); stage.layoutSubtreeIfNeeded()
        #expect(stage.previousChannelButton.isEnabled == (app.previousChannel != nil))
        #expect(stage.previousChannelButton.toolTip == "返回上一观看频道 · 频道一")
        stage.previousChannelButton.sendAction(stage.previousChannelButton.action, to: stage.previousChannelButton.target)
        #expect(app.selected?.id == a.id)
        stage.update(app)
        #expect(app.previousChannel?.id == b.id && stage.previousChannelButton.isEnabled)
        app.videoVisible = true; stage.update(app)

        for (mode, size) in [("normal", NSSize(width: 900, height: 506)), ("mini", NSSize(width: 400, height: 225)),
                             ("fullscreen", NSSize(width: 1440, height: 810))] {
            stage.isMiniPlayer = mode == "mini"; stage.isVideoFullscreen = mode == "fullscreen"
            stage.frame = NSRect(origin: .zero, size: size); stage.layoutSubtreeIfNeeded()
            for control in playbackControlViews(in: stage) { control.isHidden = false }
            let volume = try #require(playbackControlViews(in: stage).first { $0 is VideoVolumeControl })
            #expect(stage.previousChannelButton.frame.maxX + 8 <= volume.frame.minX)
            #expect(stage.previousChannelButton.frame.midY == volume.frame.midY)
            try capture(stage, name: mode)
        }
    }
    private func capture(_ view: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SOFATV_CONTROL_PREVIEW_DIR"] else { return }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)
        try #require(image.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(name + ".png"))
    }
}

@MainActor func playbackControlViews(in root: NSView) -> [NSView] {
    root.subviews.flatMap { view in
        let current = view is VideoStage.ControlsOverlay || view is VideoVolumeControl || view is VideoVolumeControl.SymbolButton
        return (current ? [view] : []) + playbackControlViews(in: view)
    }
}
