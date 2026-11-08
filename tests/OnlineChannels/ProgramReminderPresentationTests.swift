import AppKit
import SwiftUI
import Testing
@testable import SofaTV

@MainActor @Suite("提醒窗口与提示位置", .serialized)
struct ProgramReminderPresentationTests {
    private final class Notifications: ProgramReminderNotifications {
        var onWatch: ((String) -> Void)?
        var onIgnore: ((String) -> Void)?
        func configure() {}
        func requestAuthorization() async throws -> Bool { true }
        func pendingSignatures() async -> [String: String] { [:] }
        func schedule(_ reminder: ProgramReminder) async throws {}
        func remove(_ identifiers: [String], delivered: Bool) {}
    }
    @Test func toastCentersHorizontallyWithinVideoAtOneFifthWindowHeight() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let window = NSPanel(contentRect: NSRect(x: -10000, y: -10000, width: 1200, height: 700),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 700))
        let video = NSView(frame: NSRect(x: 300, y: 0, width: 900, height: 700))
        root.addSubview(video); window.contentView = root; window.orderBack(nil)
        defer {
            for child in window.childWindows ?? [] { window.removeChildWindow(child); child.close() }
            video.removeFromSuperview(); AppWindows.shared.playbackWindowChanged(video); window.close()
        }
        AppWindows.shared.playbackWindowChanged(video)
        AppToast.shared.show("测试节目 节目预约成功", in: window)
        let toast = try #require(window.childWindows?.first { $0.ignoresMouseEvents })
        func checkCenter() {
            let rect = window.convertToScreen(video.convert(video.bounds, to: nil))
            #expect(abs(toast.frame.midX - rect.midX) < 1)
            #expect(abs(toast.frame.midY - (window.frame.minY + window.frame.height / 5)) < 1)
        }
        checkCenter()
        #expect(toast.ignoresMouseEvents && !toast.isKeyWindow)
        video.frame = NSRect(x: 500, y: 0, width: 700, height: 700)
        AppToast.shared.reposition(); checkCenter()
    }

    @Test func reminderWindowStaysAboveFullscreenAndReturnsToNormalLevel() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let window = NSPanel(contentRect: NSRect(x: -10000, y: -10000, width: 1200, height: 700),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        let video = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 700))
        window.contentView = video; window.orderBack(nil)
        let domain = "sofatv-reminder-presentation-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        let store = ProgramReminderStore(defaults: defaults, notifications: Notifications())
        defer {
            AppWindows.shared.close(id: "program-reminders")
            window.contentView = nil; AppWindows.shared.playbackWindowChanged(video); window.close()
            defaults.removePersistentDomain(forName: domain)
        }
        AppWindows.shared.playbackWindowChanged(video)
        ProgramReminderWindow.show(store)
        let manager = try #require(window.childWindows?.first { $0.title == "节目预约" })
        #expect(manager.level >= window.level && manager.isVisible)
        #expect(manager.parent === window)
        #expect(manager.collectionBehavior.contains(.fullScreenAuxiliary))
        window.level = .normal
        AppWindows.shared.playbackWindowChanged(video, fullscreen: true)
        #expect(manager.parent === window && manager.level == .normal, "Normal-level fullscreen still keeps the manager above its video")
        AppWindows.shared.playbackWindowChanged(video)
        #expect(manager.parent == nil && manager.level == .normal)
    }

    @Test func reservationListKeepsThinOverlayWithoutLosingScrolling() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let domain = "sofatv-reservation-scroll-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        let store = ProgramReminderStore(defaults: defaults, notifications: Notifications())
        defer { defaults.removePersistentDomain(forName: domain) }
        let channel = Channel(name: "测试电视台", group: "测试", url: URL(string: "https://example.invalid/live")!)
        for index in 0..<10 {
            let start = Date().addingTimeInterval(Double(index + 1) * 3600)
            try await store.toggle(.init(title: "测试节目 \(index + 1)", start: start, end: start.addingTimeInterval(1800)), channel: channel)
        }
        let window = NSPanel(contentRect: NSRect(x: -10000, y: -10000, width: 520, height: 420),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: ProgramReminderList(store: store)
            .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.dark))
        host.sizingOptions = []; window.contentView = host; window.orderBack(nil)
        defer { window.close(); withExtendedLifetime(window) {} }
        for _ in 0..<20 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(10)) }
        func scroll(in view: NSView) -> NSScrollView? {
            if let view = view as? NSScrollView { return view }
            return view.subviews.lazy.compactMap { scroll(in: $0) }.first
        }
        let list = try #require(scroll(in: host))
        #expect(list.verticalScroller is ChannelListScroller && list.scrollerStyle == .overlay)
        let width = list.contentSize.width
        list.scrollerStyle = .legacy
        list.layoutSubtreeIfNeeded()
        #expect(list.scrollerStyle == .overlay && abs(list.contentSize.width - width) < 1,
                "Always-visible system scrollbars must not add a wide reserved track")
        #expect((list.documentView?.bounds.height ?? 0) > list.contentSize.height)
        list.contentView.scroll(to: NSPoint(x: 0, y: 60)); list.reflectScrolledClipView(list.contentView)
        #expect(list.contentView.bounds.minY > 0)
        if let file = ProcessInfo.processInfo.environment["SOFATV_RESERVATION_SCROLL_PREVIEW"] {
            list.flashScrollers()
            try await Task.sleep(for: .milliseconds(100))
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: file))
        }
    }
}
