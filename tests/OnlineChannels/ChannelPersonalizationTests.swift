import AppKit
import SwiftUI
import Testing
@testable import SofaTV

private actor PersonalizationSource {
    var text: String
    var blocked = false
    var requests = 0
    private var waits: [CheckedContinuation<Void, Never>] = []
    init(_ text: String) { self.text = text }
    func configure(_ text: String, blocked: Bool = false) { self.text = text; self.blocked = blocked }
    func load(_ request: URLRequest) async -> (Data, HTTPURLResponse) {
        requests += 1
        let data = Data(text.utf8)
        if blocked { await withCheckedContinuation { waits.append($0) } }
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func release() { blocked = false; let pending = waits; waits = []; pending.forEach { $0.resume() } }
}

@MainActor private final class PersonalizationPreviewWindow: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor @Suite("频道个性化", .serialized)
struct ChannelPersonalizationTests {
    private let a = Channel(name: "新闻一台", group: "新闻", url: URL(string: "https://example.invalid/a.m3u8")!, epgID: "news-1")
    private let b = Channel(name: "新闻二台", group: "新闻", url: URL(string: "https://example.invalid/b.m3u8")!, epgID: "news-2")
    private let c = Channel(name: "体育频道", group: "体育", url: URL(string: "https://example.invalid/c.m3u8")!, epgID: "sports")
    private let url = URL(string: "https://example.invalid/channels.m3u")!

    private struct Preferences {
        let name = "SofaTV.PersonalizationTests." + UUID().uuidString
        let defaults: UserDefaults
        init() { defaults = UserDefaults(suiteName: name)! }
        func clean() { defaults.removePersistentDomain(forName: name) }
    }
    private func makeLibrary(_ preferences: Preferences, source: PersonalizationSource? = nil) throws -> Library {
        if preferences.defaults.data(forKey: "channel-lists") == nil {
            var list = ChannelList.online(url); list.channels = [a, b, c]
            preferences.defaults.set(try JSONEncoder().encode([list]), forKey: "channel-lists")
        }
        let repository = OnlineChannelRepository(loader: { request in
            if let source { return await source.load(request) }
            throw URLError(.notConnectedToInternet)
        })
        return Library(defaults: preferences.defaults, channelRepository: repository, warmsChannels: false,
            recoveryMonitor: PlaybackRecoveryMonitor(observeSystemEvents: false, pollsAutomatically: false))
    }
    private func settle(_ library: Library) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !library.updatingSourceIDs.isEmpty {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    private func playlist(_ channels: [Channel]) -> String {
        "#EXTM3U\n" + channels.map {
            "#EXTINF:-1 tvg-id=\"\($0.epgID ?? "")\" group-title=\"\($0.group)\",\($0.name)\n\($0.url.absoluteString)"
        }.joined(separator: "\n")
    }

    @Test func displayOverridesDoNotChangeSourceIdentity() {
        var preferences = ChannelPersonalization()
        preferences.customize(a, name: "我的新闻", group: "常看")
        let customized = preferences.applying(to: [a])[0]
        #expect(customized.name == a.name && customized.group == a.group && customized.identity == a.identity)
        #expect(customized.displayName == "我的新闻" && customized.displayGroup == "常看")
        #expect(customized.matches("我的") && customized.matches("新闻一台") && customized.matches("常看"))
        var updated = a; updated.url = URL(string: "https://example.invalid/new-a.m3u8")!
        updated.name = "上游的新名称"; updated.group = "上游的新分组"
        #expect(preferences.applying(to: [updated])[0].displayName == "我的新闻")
        #expect(updated.preferenceKey == a.preferenceKey)
        preferences.customize(a, name: a.name, group: a.group)
        #expect(preferences.applying(to: [a])[0] == a)
    }

    @Test func channelAndGroupOrderPersistAcrossRestart() throws {
        let preferences = Preferences(); defer { preferences.clean() }
        let app = try makeLibrary(preferences)
        app.customizeChannel(a, name: "我的新闻", group: "常看")
        app.moveChannel(c, by: -1); app.moveChannel(c, by: -1)
        let firstGroup = app.orderedGroups[0]
        app.moveGroup(firstGroup, by: 1)
        let groups = app.orderedGroups
        #expect(app.channels.map(\.identity) == [c.identity, a.identity, b.identity])
        #expect(app.channelLists[0].channels[0].name == a.name)
        let restarted = try makeLibrary(preferences)
        #expect(restarted.channels == app.channels && restarted.orderedGroups == groups)
        restarted.renameGroup("常看", to: "收藏节目")
        #expect(restarted.channels.first { $0.identity == a.identity }?.displayGroup == "收藏节目")
        restarted.resetChannelOrder()
        #expect(restarted.channels.map(\.identity) == [a.identity, b.identity, c.identity])
        #expect(restarted.channels[0].displayName == "我的新闻")
    }

    @Test func onlineUpdatesKeepNamesOrderFavoritesAndVolume() async throws {
        let preferences = Preferences(); defer { preferences.clean() }
        var updated = a; updated.url = URL(string: "https://example.invalid/replaced-a.m3u8")!
        let source = PersonalizationSource(playlist([updated, b, c]))
        let app = try makeLibrary(preferences, source: source)
        app.customizeChannel(a, name: "我的新闻", group: "常看")
        app.favorite(a); app.moveChannel(c, by: -1); app.moveChannel(c, by: -1)
        app.selected = app.channels.first { $0.identity == a.identity }
        app.setVolume(0.7)
        let playing = app.selected
        app.refreshOnlineChannels(); try await settle(app)
        let refreshed = try #require(app.channels.first { $0.identity == a.identity })
        #expect(refreshed.url == updated.url && refreshed.id == a.id && refreshed.displayName == "我的新闻" && refreshed.displayGroup == "常看")
        #expect(app.channels.first?.identity == c.identity)
        #expect(app.favorites.contains(refreshed.id))
        #expect(app.personalization.volumes[refreshed.preferenceKey] == 0.7)
        #expect(app.selected?.sources == playing?.sources, "Updating metadata must preserve the active playback snapshot")
        #expect(app.catalogSelectedChannel?.sources == updated.sources, "Guide navigation should still target the updated catalogue row")
        await source.configure(playlist([b, c])); app.refreshOnlineChannels(); try await settle(app)
        #expect(app.personalization.favoriteKeys.contains(a.preferenceKey))
        await source.configure(playlist([updated, b, c])); app.refreshOnlineChannels(); try await settle(app)
        #expect(app.favorites.contains(updated.id))
        #expect(app.channels.first { $0.identity == a.identity }?.displayName == "我的新闻")
    }

    @Test func deletingCustomGroupKeepsOtherMembersOfTheOriginalGroup() throws {
        let preferences = Preferences(); defer { preferences.clean() }
        let app = try makeLibrary(preferences)
        app.customizeChannel(a, name: a.name, group: "常看")
        app.deleteGroup("常看")
        #expect(app.channels.map(\.identity) == [b.identity, c.identity])
        #expect(app.channelLists[0].removedChannels?.contains(a.identity) == true)
    }

    @Test func addingAProviderIDMigratesExistingUserChoices() async throws {
        let preferences = Preferences(); defer { preferences.clean() }
        var anonymous = a; anonymous.epgID = nil
        var list = ChannelList.online(url); list.channels = [anonymous, b, c]
        preferences.defaults.set(try JSONEncoder().encode([list]), forKey: "channel-lists")
        let source = PersonalizationSource(playlist([a, b, c]))
        let app = try makeLibrary(preferences, source: source)
        app.customizeChannel(anonymous, name: "我的新闻", group: "常看")
        app.favorite(anonymous); app.moveChannel(anonymous, by: 1)
        app.selected = anonymous; app.setVolume(0.6)
        app.refreshOnlineChannels(); try await settle(app)
        let refreshed = try #require(app.channels.first { $0.preferenceKey == a.preferenceKey })
        #expect(refreshed.displayName == "我的新闻" && refreshed.displayGroup == "常看")
        #expect(app.favorites.contains(refreshed.id))
        #expect(app.personalization.volumes[a.preferenceKey] == 0.6)
        #expect(app.channels[1].preferenceKey == a.preferenceKey)
    }

    @Test func configurationBackupRestoresSourcesAndUserChoices() throws {
        let preferences = Preferences(); defer { preferences.clean() }
        let restoredPreferences = Preferences(); defer { restoredPreferences.clean() }
        let app = try makeLibrary(preferences)
        app.customizeChannel(a, name: "我的新闻", group: "常看")
        app.favorite(a); app.moveChannel(b, by: -1)
        let data = try app.configurationBackupData()
        let restored = try makeLibrary(restoredPreferences)
        try restored.restoreConfiguration(data)
        #expect(restored.channelLists == app.channelLists)
        #expect(restored.channels == app.channels && restored.favorites == app.favorites)
        let original = restored.channels
        #expect(throws: (any Error).self) { try restored.restoreConfiguration(Data("invalid backup".utf8)) }
        #expect(restored.channels == original, "Bad backups must not erase the existing library")
        let invalidVersion = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 999")
        #expect(throws: (any Error).self) { try restored.restoreConfiguration(Data(invalidVersion.utf8)) }
        #expect(restored.channels == original)
    }

    @Test func restoredConfigurationRejectsAnOldInFlightResponse() async throws {
        let preferences = Preferences(); defer { preferences.clean() }
        let source = PersonalizationSource(playlist([a]))
        await source.configure(playlist([a]), blocked: true)
        let app = try makeLibrary(preferences, source: source)
        app.refreshOnlineChannels()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await source.requests == 0 {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
        var replacement = ChannelList.online(url); replacement.channels = [c]
        let data = try JSONEncoder().encode(ChannelConfigurationBackup(sources: [replacement], personalization: ChannelPersonalization()))
        try app.restoreConfiguration(data)
        await source.release()
        try await Task.sleep(for: .milliseconds(30))
        #expect(app.channels.map(\.identity) == [c.identity])
    }

    @Test func previousChannelUsesUniqueHistoryAndRequiresADifferentChannel() throws {
        var preferences = ChannelPersonalization()
        let settings = Preferences(); defer { settings.clean() }
        preferences.record(a)
        settings.defaults.set(try JSONEncoder().encode(preferences), forKey: "channel-personalization-v1")
        let app = try makeLibrary(settings)
        #expect(app.previousChannel == nil, "Watching only one channel must leave Return disabled, including after stopping")
        app.selected = a
        #expect(app.previousChannel == nil)
        preferences.record(a); preferences.record(b); preferences.record(a)
        #expect(preferences.recent == [a.preferenceKey, b.preferenceKey])
        let backup = try JSONEncoder().encode(ChannelConfigurationBackup(sources: app.channelLists, personalization: preferences))
        try app.restoreConfiguration(backup)
        #expect(app.previousChannel?.preferenceKey == b.preferenceKey)
        app.selected = b
        #expect(app.previousChannel?.preferenceKey == a.preferenceKey)
        for index in 0..<30 {
            preferences.record(Channel(name: "频道\(index)", group: "测试", url: URL(string: "https://example.invalid/\(index)")!))
        }
        #expect(preferences.recent.count == 20)
        var changed = a; changed.url = URL(string: "https://example.invalid/new")!
        #expect(changed.preferenceKey == a.preferenceKey)
    }

    @Test func renderPreviews() async throws {
        guard let directory = ProcessInfo.processInfo.environment["SOFATV_PREVIEW_DIR"] else { return }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let preferences = Preferences(); defer { preferences.clean() }
        let app = try makeLibrary(preferences)
        app.customizeChannel(a, name: "我的新闻", group: "常看")
        app.favorite(a)
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let organizer = NSHostingView(rootView: ChannelOrganizer(library: app, onClose: {}).preferredColorScheme(.dark))
        organizer.sizingOptions = []
        try await capture(organizer, size: NSSize(width: 680, height: 540), to: folder.appendingPathComponent("organizer.png"))
        app.selected = a; app.videoVisible = true; app.setVolume(0.05)
        let stage = VideoStage.Stage(library: app)
        try await capture(stage, size: NSSize(width: 900, height: 506), to: folder.appendingPathComponent("controls.png")) {
            for view in playbackControlViews(in: stage) { view.isHidden = false }
        }
        app.stopPlayback()
    }
    private func capture(_ view: NSView, size: NSSize, to url: URL, prepare: () -> Void = {}) async throws {
        let window = PersonalizationPreviewWindow(contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; view.frame = NSRect(origin: .zero, size: size)
        window.contentView = view; window.orderBack(nil)
        for _ in 0..<15 { view.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(10)) }
        prepare()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        window.close(); withExtendedLifetime(window) {}
    }
}
