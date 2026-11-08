import AppKit
import AVFoundation
import Testing
@testable import SofaTV

@MainActor @Suite("预解析省电与释放", .serialized)
struct WebMediaWarmupTests {
    private let page = URL(string: "https://example.invalid/channel")!
    private let media = ResolvedWebMedia(url: URL(string: "https://example.invalid/live.m3u8")!, cookies: [], cmgState: nil)

    @MainActor private final class WeakResolver {
        weak var value: FakeResolver?
        init(_ value: FakeResolver) { self.value = value }
    }
    @MainActor private final class Inputs {
        var state = WebMediaWarmupEnvironment.State()
        var created: [WeakResolver] = []
        var cancellations = 0
    }
    @MainActor private final class FakeResolver: WebMediaWarmupResolving {
        let warmupView = NSView()
        let inputs: Inputs
        var completion: ((ResolvedWebMedia) -> Void)?
        var failure: ((String) -> Void)?
        var requested: URL?
        init(_ inputs: Inputs) { self.inputs = inputs }
        func resolve(_ url: URL, completion: @escaping (ResolvedWebMedia) -> Void, failure: @escaping (String) -> Void) {
            requested = url; self.completion = completion; self.failure = failure
        }
        // Retain callbacks to simulate a result already queued before cancellation.
        func cancel() { inputs.cancellations += 1 }
    }
    @MainActor private final class Fixture {
        let inputs = Inputs()
        let notifications = NotificationCenter()
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        let warmup: WebMediaWarmup
        var live: [FakeResolver] { inputs.created.compactMap(\.value) }
        init() {
            let inputs = inputs
            warmup = WebMediaWarmup(environment: WebMediaWarmupEnvironment(notifications: notifications, state: { inputs.state }),
                                    makeResolver: {
                let resolver = FakeResolver(inputs)
                inputs.created.append(WeakResolver(resolver))
                return resolver
            })
        }
        func attach() { warmup.attach(to: host) }
        func post(_ name: Notification.Name) { notifications.post(name: name, object: nil) }
    }
    private func settle(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test func visibilityAndLowPowerControlOnlySpeculativeWork() {
        #expect(WebMediaWarmupEnvironment.State().allowsWarmup)
        #expect(!WebMediaWarmupEnvironment.State(isHidden: true).allowsWarmup)
        #expect(!WebMediaWarmupEnvironment.State(hasVisibleWindow: false).allowsWarmup)
        #expect(!WebMediaWarmupEnvironment.State(isLowPowerModeEnabled: true).allowsWarmup)
    }

    @Test func poolIsLazyAndCancellationReleasesBothResolverAndHostedView() {
        let f = Fixture()
        #expect(f.inputs.created.isEmpty)
        f.warmup.configure(pages: [page], prioritized: [])
        #expect(f.inputs.created.isEmpty, "A detached host must not start hidden webpages")
        weak var resolver: FakeResolver?
        weak var view: NSView?
        autoreleasepool {
            f.attach()
            #expect(f.live.count == 3 && f.host.subviews.count == 3)
            resolver = f.live.first; view = f.host.subviews.first
            f.warmup.cancel()
            #expect(f.warmup.resolvers.isEmpty && f.host.subviews.isEmpty)
        }
        #expect(resolver == nil && view == nil, "Dropping only the resolver array would leave the view retained by its host")
        #expect(f.inputs.cancellations == 3)
        f.warmup.configure(pages: [], prioritized: [])
        #expect(f.inputs.created.count == 3)
    }

    @Test func actualWebKitViewsAreReleasedWhenPlaybackStops() async throws {
        let warmup = WebMediaWarmup(environment: WebMediaWarmupEnvironment(state: { .init() }))
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        weak var resolver: WebMediaResolver?
        weak var view: NSView?
        autoreleasepool {
            warmup.attach(to: host)
            warmup.configure(pages: [URL(string: "about:blank")!], prioritized: [])
            resolver = warmup.resolvers.first as? WebMediaResolver
            view = resolver?.webView
            #expect(resolver != nil && view != nil)
            warmup.cancel()
        }
        try await settle { resolver == nil && view == nil }
        #expect(host.subviews.isEmpty)
    }

    @Test func hidingPausesAndUnhidingResumesWithoutAcceptingOldResults() async throws {
        let f = Fixture(); f.attach()
        defer { f.warmup.cancel() }
        f.warmup.configure(pages: [page], prioritized: [page])
        let old = try #require(f.live.first { $0.requested == page })
        f.inputs.state.isHidden = true
        f.post(NSApplication.didHideNotification)
        try await settle { f.warmup.resolvers.isEmpty }
        #expect(f.host.subviews.isEmpty)
        f.inputs.state.isHidden = false
        f.post(NSApplication.didUnhideNotification)
        try await settle { !f.warmup.resolvers.isEmpty }
        let current = try #require(f.live.last { $0.requested == page })
        #expect(current !== old && f.host.subviews.count == 3)
        let cancellations = f.inputs.cancellations
        old.completion?(media); old.failure?("过时的请求")
        #expect(f.warmup.cachedMedia(for: page) == nil)
        #expect(f.inputs.cancellations == cancellations)
        current.completion?(media)
        #expect(f.warmup.cachedMedia(for: page)?.url == media.url)
    }

    @Test func lowPowerNotificationsFromBackgroundQueuePauseAndResume() async throws {
        let f = Fixture(); f.attach()
        defer { f.warmup.cancel() }
        f.inputs.state.isLowPowerModeEnabled = true
        f.warmup.configure(pages: [page], prioritized: [])
        #expect(f.inputs.created.isEmpty, "A launch already in Low Power Mode must not create the pool")
        f.inputs.state.isLowPowerModeEnabled = false
        let notifications = f.notifications
        await Task.detached { notifications.post(name: .NSProcessInfoPowerStateDidChange, object: nil) }.value
        try await settle { !f.warmup.resolvers.isEmpty }
        f.inputs.state.isLowPowerModeEnabled = true
        await Task.detached { notifications.post(name: .NSProcessInfoPowerStateDidChange, object: nil) }.value
        try await settle { f.warmup.resolvers.isEmpty }
        #expect(f.host.subviews.isEmpty)
    }

    @Test func occlusionAndHostChangesDoNotLoseConfigurationOrReviveCancelledWork() async throws {
        let f = Fixture(); f.attach()
        defer { f.warmup.cancel() }
        f.warmup.configure(pages: [page], prioritized: [])
        f.inputs.state.hasVisibleWindow = false
        f.post(NSApplication.didChangeOcclusionStateNotification)
        try await settle { f.warmup.resolvers.isEmpty }
        f.inputs.state.hasVisibleWindow = true
        f.post(NSApplication.didChangeOcclusionStateNotification)
        try await settle { !f.warmup.resolvers.isEmpty }
        f.warmup.detach(from: f.host)
        #expect(f.warmup.resolvers.isEmpty && f.host.subviews.isEmpty)
        f.attach()
        #expect(!f.warmup.resolvers.isEmpty)
        f.warmup.cancel()
        let creations = f.inputs.created.count
        f.post(NSApplication.didUnhideNotification)
        // Await the actual observer callback even though the pool should stay empty.
        await Task.yield()
        #expect(f.warmup.resolvers.isEmpty && f.inputs.created.count == creations)
    }

    @Test func libraryDoesNotPrewarmUntilPlayingAndPowerChangesLeaveHandoffAlone() async throws {
        let f = Fixture()
        let name = "sofatv-warmup-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name); f.warmup.cancel() }
        let channel = Channel(name: "测试频道", group: "测试", url: URL(string: "webview://https://example.invalid/channel")!)
        defaults.set(try JSONEncoder().encode([ChannelList.legacy([channel])]), forKey: "channel-lists")
        let app = Library(defaults: defaults, recoveryMonitor: PlaybackRecoveryMonitor(observeSystemEvents: false, pollsAutomatically: false),
                          warmup: f.warmup)
        f.attach()
        app.favorite(channel)
        #expect(f.inputs.created.isEmpty, "Startup and favorite changes must not warm channels before playback")

        let item = AVPlayerItem(asset: AVMutableComposition())
        app.selected = channel; app.videoVisible = true; app.webVideo = true
        app.player.replaceCurrentItem(with: item)
        app.favorite(channel)
        #expect(!f.warmup.resolvers.isEmpty)
        f.inputs.state.isHidden = true
        f.post(NSApplication.didHideNotification)
        try await settle { f.warmup.resolvers.isEmpty }
        #expect(app.selected?.id == channel.id && app.videoVisible && app.webVideo)
        #expect(app.player.currentItem === item, "Pausing prewarm must not discard native preparation behind the webpage")
        app.stopPlayback()
        f.inputs.state.isHidden = false
        f.post(NSApplication.didUnhideNotification)
        app.favorite(channel)
        try app.parse("新频道,https://example.invalid/new.m3u8", as: .file(URL(fileURLWithPath: "/private/tmp/warmup-test.m3u")))
        await Task.yield()
        #expect(f.warmup.resolvers.isEmpty && f.host.subviews.isEmpty)
    }

    @Test func nativeFirstFrameStartsWarmupAfterTheAudioHandoff() async throws {
        let f = Fixture()
        let name = "sofatv-native-warmup-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        let channel = Channel(name: "原生频道", group: "测试", url: URL(string: "webview://https://example.invalid/channel")!)
        defaults.set(try JSONEncoder().encode([ChannelList.legacy([channel])]), forKey: "channel-lists")
        let app = Library(defaults: defaults, recoveryMonitor: PlaybackRecoveryMonitor(observeSystemEvents: false, pollsAutomatically: false),
                          warmup: f.warmup)
        defer { app.stopPlayback(); defaults.removePersistentDomain(forName: name) }
        f.attach()
        let item = AVPlayerItem(asset: AVMutableComposition())
        app.selected = channel; app.player.replaceCurrentItem(with: item)
        #expect(!app.videoVisible && f.warmup.resolvers.isEmpty)
        app.videoAppeared(item)
        try await settle { app.videoVisible && !f.warmup.resolvers.isEmpty }
        #expect(!app.webVideo && app.player.currentItem === item)
    }
}
