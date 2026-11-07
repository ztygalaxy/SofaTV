import AppKit
import AVKit
import Testing
@testable import SofaTV

@MainActor @Suite("播放自动恢复", .serialized)
struct PlaybackRecoveryTests {
    private func policy(sources: Int = 2) -> PlaybackRecoveryPolicy {
        var policy = PlaybackRecoveryPolicy()
        policy.begin(sourceCount: sources, index: 0, at: 0)
        policy.started(index: 0, at: 0)
        return policy
    }

    @Test func retriesThenChangesSourceAndStops() {
        var policy = policy()
        #expect(policy.failure() == .restart(index: 0, delay: 2))
        #expect(policy.failure() == nil, "Duplicate error notifications must not consume more attempts")
        policy.started(index: 0, at: 2)
        #expect(policy.failure() == .restart(index: 1, delay: 4))
        policy.started(index: 1, at: 6)
        #expect(policy.failure() == .restart(index: 1, delay: 8))
        policy.started(index: 1, at: 14)
        #expect(policy.failure() == .exhausted)
        #expect(policy.sample(position: nil, at: 100) == nil)
        #expect(policy.failure() == nil)
        #expect(policy.attempts == [0: 2, 1: 2])
    }

    @Test func onlySustainedLackOfProgressTriggersRecovery() {
        var policy = policy()
        policy.ready(at: 1)
        #expect(policy.sample(position: 10, at: 2) == nil)
        #expect(policy.sample(position: 10, at: 12) == nil)
        #expect(policy.sample(position: 11, at: 13) == nil, "Recovering buffers should keep their current source")
        #expect(policy.sample(position: 11, at: 24) == nil)
        #expect(policy.sample(position: 11, at: 25) == .restart(index: 0, delay: 2))
    }

    @Test func startupDeadlineRequiresAnActualRenderedFrame() {
        var policy = policy()
        #expect(policy.sample(position: 1, at: 1) == nil)
        #expect(policy.sample(position: 39, at: 39) == nil)
        #expect(policy.sample(position: 40, at: 40) == .restart(index: 0, delay: 2))
    }

    @Test func offlineWaitDoesNotUseUpRoutes() {
        var policy = policy()
        #expect(policy.networkChanged(available: false, at: 1) == nil)
        #expect(policy.failure() == .waitingForNetwork)
        for time in [15.0, 60, 120] { #expect(policy.sample(position: nil, at: time) == nil) }
        #expect(policy.attempts == [0: 1])
        #expect(policy.networkChanged(available: true, at: 121) == .restart(index: 0, delay: 0))
        #expect(policy.networkChanged(available: true, at: 122) == nil)
        policy.started(index: 0, at: 121)
        #expect(policy.attempts == [0: 1])
    }

    @Test func sleepDoesNotTriggerTimeoutAndWakeRefreshesTheSession() {
        var policy = policy()
        policy.suspend()
        #expect(policy.sample(position: nil, at: 10_000) == nil)
        #expect(policy.failure() == nil)
        #expect(policy.resume(at: 10_001) == .restart(index: 0, delay: 0))
        policy.stop()
        #expect(policy.resume(at: 20_000) == nil)
        #expect(policy.networkChanged(available: false, at: 20_001) == nil)
        #expect(policy.networkChanged(available: true, at: 20_002) == nil)
    }

    @Test func healthyPlaybackRenewsTheRetryBudget() {
        var policy = policy(sources: 1)
        _ = policy.failure()
        policy.started(index: 0, at: 2)
        policy.ready(at: 3)
        for time in stride(from: 3.0, through: 64, by: 1) {
            #expect(policy.sample(position: time, at: time) == nil)
        }
        #expect(policy.attempts == [0: 1])
        #expect(policy.failure() == .restart(index: 0, delay: 2))
    }

    @Test func newChannelAndStopCancelQueuedRestarts() async throws {
        var configuration = PlaybackRecoveryPolicy.Configuration()
        configuration.retryDelay = 0.03
        let monitor = PlaybackRecoveryMonitor(configuration: configuration, observeSystemEvents: false, pollsAutomatically: false)
        var restarts: [Int] = []
        monitor.onRestart = { index, _ in restarts.append(index) }
        monitor.begin(sourceCount: 2, index: 0); monitor.started(index: 0)
        monitor.failed("旧频道失败")
        monitor.begin(sourceCount: 2, index: 1); monitor.started(index: 1)
        try await Task.sleep(for: .milliseconds(60))
        #expect(restarts.isEmpty)
        monitor.failed("新频道失败")
        monitor.stop()
        monitor.resume(); monitor.networkChanged(available: false); monitor.networkChanged(available: true)
        try await Task.sleep(for: .milliseconds(60))
        #expect(restarts.isEmpty && !monitor.policy.active)
    }

    @Test func aLateFirstFrameCancelsTheQueuedReconnect() async throws {
        var configuration = PlaybackRecoveryPolicy.Configuration()
        configuration.retryDelay = 0.03
        let monitor = PlaybackRecoveryMonitor(configuration: configuration, observeSystemEvents: false, pollsAutomatically: false)
        var restarts = 0
        monitor.onRestart = { _, _ in restarts += 1 }
        monitor.begin(sourceCount: 1, index: 0); monitor.started(index: 0)
        monitor.failed("慢速起播")
        monitor.ready()
        try await Task.sleep(for: .milliseconds(60))
        #expect(restarts == 0, "Do not interrupt a source that became ready while waiting to reconnect")
        monitor.stop()
    }

    @Test func stopPlaybackClearsMediaAndPreventsAutomaticRestart() async throws {
        let suite = "SofaTV.StopTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var configuration = PlaybackRecoveryPolicy.Configuration()
        configuration.retryDelay = 0.03
        let monitor = PlaybackRecoveryMonitor(configuration: configuration, observeSystemEvents: false, pollsAutomatically: false)
        let library = Library(defaults: defaults, warmsChannels: false, recoveryMonitor: monitor)
        let channel = Channel(name: "测试频道", group: "测试", url: URL(string: "https://example.invalid/live.m3u8")!)
        library.selected = channel; library.videoVisible = true; library.webVideo = true
        let item = AVPlayerItem(asset: AVMutableComposition())
        library.player.replaceCurrentItem(with: item)
        var restoredMain: Bool?
        library.onStopPlayback = { restoredMain = $0 }
        monitor.begin(sourceCount: 1, index: 0); monitor.started(index: 0); monitor.failed("测试断流")
        library.stopPlayback()
        monitor.resume(); monitor.networkChanged(available: false); monitor.networkChanged(available: true)
        library.videoAppeared(item)
        try await Task.sleep(for: .milliseconds(60))
        #expect(restoredMain == true)
        #expect(library.selected == nil && library.player.currentItem == nil)
        #expect(!library.videoVisible && !library.webVideo && !monitor.policy.active)
        #expect(library.playbackStatus == "就绪")
        library.stopPlayback(restoreWindow: false)
        #expect(restoredMain == false)
    }

    @Test func powerControlStopsWithoutClosingTheMainWindow() {
        let suite = "SofaTV.PowerButtonTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = PlaybackRecoveryMonitor(observeSystemEvents: false, pollsAutomatically: false)
        let library = Library(defaults: defaults, warmsChannels: false, recoveryMonitor: monitor)
        library.selected = Channel(name: "测试", group: "测试", url: URL(string: "https://example.invalid/live")!)
        let stage = VideoStage.Stage(library: library)
        stage.frame = NSRect(x: 0, y: 0, width: 900, height: 560)
        stage.layoutSubtreeIfNeeded()
        #expect(stage.powerButton.toolTip == "停止播放")
        #expect(stage.powerButton.frame.size == NSSize(width: 32, height: 32))
        stage.powerButton.sendAction(stage.powerButton.action, to: stage.powerButton.target)
        #expect(library.selected == nil)
    }

    @Test func stoppedLibraryReleasesItsRecoveryMonitor() {
        let suite = "SofaTV.RecoveryLifetimeTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        weak var weakLibrary: Library?
        weak var weakMonitor: PlaybackRecoveryMonitor?
        do {
            let monitor = PlaybackRecoveryMonitor(observeSystemEvents: false, pollsAutomatically: false)
            let library = Library(defaults: defaults, warmsChannels: false, recoveryMonitor: monitor)
            weakLibrary = library; weakMonitor = monitor
            library.stopPlayback()
        }
        #expect(weakLibrary == nil && weakMonitor == nil)
    }
}
