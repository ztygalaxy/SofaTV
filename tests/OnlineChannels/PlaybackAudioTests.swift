import AppKit
import AVFoundation
import Testing
@testable import SofaTV

@MainActor @Suite("换台与播放接替音量", .serialized)
struct PlaybackAudioTests {
    private final class VolumeEvents: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [(Float, Bool)] = []
        func record(_ player: AVPlayer) { lock.lock(); defer { lock.unlock() }; values.append((player.volume, player.isMuted)) }
        var audibleLevels: [Float] { lock.lock(); defer { lock.unlock() }; return values.filter { !$0.1 }.map(\.0) }
    }
    @MainActor private final class Fixture {
        let name = "sofatv-audio-test-" + UUID().uuidString
        let defaults: UserDefaults
        let app: Library
        init() {
            defaults = UserDefaults(suiteName: name)!
            app = Library(defaults: defaults, warmsChannels: false,
                          recoveryMonitor: PlaybackRecoveryMonitor(observeSystemEvents: false, pollsAutomatically: false))
        }
        func clean() { app.stopPlayback(); defaults.removePersistentDomain(forName: name) }
    }
    private var channel: Channel {
        Channel(name: "音量测试", group: "测试", url: URL(fileURLWithPath: "/private/tmp/sofatv-audio-test.m3u8"))
    }
    private func settle(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
    private func load(_ resolver: WebMediaResolver) async throws {
        resolver.webView.loadHTMLString("""
        <html><body><script>
        const video=document.createElement('video');
        video.volume=1;video.muted=false;document.body.append(video);
        window.initialAudio={volume:video.volume,muted:video.muted};
        window.__sofatvSelectedVideo=video;
        window.testReady=true;
        </script></body></html>
        """, baseURL: nil)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while (try? await resolver.webView.evaluateJavaScript("window.testReady===true")) as? Bool != true {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    private func audible(_ resolver: WebMediaResolver, _ value: Bool, volume: Float) async {
        await withCheckedContinuation { done in resolver.setAudible(value, volume: volume) { done.resume() } }
    }
    private func state(_ resolver: WebMediaResolver, script: String = "({volume:video.volume,muted:video.muted})") async throws -> [String: Any] {
        try #require(try await resolver.webView.evaluateJavaScript(script) as? [String: Any])
    }

    @Test func webpageIsSilentBeforeItsOwnScriptsRunAndCannotOverrideAppVolume() async throws {
        let resolver = WebMediaResolver(); defer { resolver.cancel() }
        try await load(resolver)
        let initial = try await state(resolver, script: "window.initialAudio")
        #expect((initial["volume"] as? Double) == 0 && (initial["muted"] as? Bool) == true)
        await audible(resolver, true, volume: 0.12)
        let controlled = try await state(resolver, script: "video.volume=1;video.muted=false;({volume:video.volume,muted:video.muted})")
        #expect(abs((controlled["volume"] as? Double ?? 1) - 0.12) < 0.00001)
        #expect((controlled["muted"] as? Bool) == false)
        await audible(resolver, false, volume: 0.12)
        let stopped = try await state(resolver, script: "video.volume=1;video.muted=false;({volume:video.volume,muted:video.muted})")
        #expect((stopped["volume"] as? Double) == 0 && (stopped["muted"] as? Bool) == true)
    }

    @Test func newlyCreatedMediaAndFramesStaySilentWhileTheSelectedVideoPlays() async throws {
        let resolver = WebMediaResolver(); defer { resolver.cancel() }
        try await load(resolver)
        await audible(resolver, true, volume: 0.08)
        let extra = try await state(resolver, script: """
        const audio=document.createElement('audio');audio.volume=1;audio.muted=false;document.body.append(audio);
        ({volume:audio.volume,muted:audio.muted})
        """)
        #expect((extra["volume"] as? Double) == 0 && (extra["muted"] as? Bool) == true)
        _ = try await resolver.webView.evaluateJavaScript("""
        const frame=document.createElement('iframe');
        frame.srcdoc='<body><script>const a=document.createElement("audio");a.volume=1;a.muted=false;document.body.append(a);window.audioState={volume:a.volume,muted:a.muted};</script>';
        document.body.append(frame);
        """)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        var frame: [String: Any]?
        while frame == nil {
            frame = (try? await resolver.webView.evaluateJavaScript("document.querySelector('iframe').contentWindow.audioState ?? null")) as? [String: Any]
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            if frame == nil { try await Task.sleep(for: .milliseconds(5)) }
        }
        #expect((frame?["volume"] as? Double) == 0 && (frame?["muted"] as? Bool) == true)
    }

    @Test func changingChannelMutesTheOldPlayerBeforeRestoringAHigherSavedLevel() {
        let f = Fixture(); defer { f.clean() }
        f.app.selected = channel; f.app.setVolume(0.05)
        f.app.player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
        f.app.player.isMuted = false
        let events = VolumeEvents()
        let observation = f.app.player.observe(\.volume, options: [.new]) { player, _ in events.record(player) }
        var next = channel; next.name = "高音量频道"
        f.defaults.set(0.9, forKey: "volume-" + next.id)
        f.app.play(next)
        #expect(f.app.volume == 0.9)
        #expect(events.audibleLevels.allSatisfy { $0 <= 0.05 }, "The old stream must never play at the next channel's louder level")
        #expect(f.app.player.isMuted)
        withExtendedLifetime(observation) {}
    }

    @Test func nativeHandoffUsesTheSameLevelAndDoesNotOverlapWebAudio() async throws {
        let f = Fixture(); defer { f.clean() }
        f.app.selected = channel; f.app.setVolume(0.12); f.app.webVideo = true
        let item = AVPlayerItem(asset: AVMutableComposition())
        f.app.player.replaceCurrentItem(with: item); f.app.player.isMuted = true
        try await load(f.app.resolver)
        await audible(f.app.resolver, true, volume: f.app.volume)
        let events = VolumeEvents()
        let observation = f.app.player.observe(\.volume, options: [.new]) { player, _ in events.record(player) }
        f.app.videoAppeared(item)
        try await settle { f.app.playbackStatus == "原生视频播放中" }
        let web = try await state(f.app.resolver)
        #expect((web["volume"] as? Double) == 0 && (web["muted"] as? Bool) == true)
        try await settle { abs(f.app.player.volume - 0.12) < 0.00001 }
        #expect(events.audibleLevels.allSatisfy { $0 <= 0.12001 })
        #expect(!f.app.webVideo && !f.app.player.isMuted)
        withExtendedLifetime(observation) {}
    }

    @Test func muteAndStopDuringTheFadeCannotBeUndoneByQueuedSteps() async throws {
        let f = Fixture(); defer { f.clean() }
        f.app.selected = channel; f.app.setVolume(0.2)
        let item = AVPlayerItem(asset: AVMutableComposition())
        f.app.player.replaceCurrentItem(with: item)
        f.app.videoAppeared(item)
        try await settle { f.app.playbackStatus == "原生视频播放中" }
        f.app.setVolume(0)
        try await Task.sleep(for: .milliseconds(180))
        #expect(f.app.player.volume == 0 && f.app.isMuted)
        f.app.stopPlayback()
        try await Task.sleep(for: .milliseconds(30))
        #expect(f.app.player.isMuted && f.app.player.volume == 0 && f.app.player.currentItem == nil)
    }
}
