import Foundation
import Testing
@testable import SofaTV

private actor SourceFixture {
    var requests: [URLRequest] = []
    var data: Data
    var status = 200
    var failing = false
    var blocked = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ text: String) { data = Data(text.utf8) }
    func configure(text: String? = nil, status: Int = 200, failing: Bool = false, blocked: Bool = false) {
        if let text { data = Data(text.utf8) }
        self.status = status; self.failing = failing; self.blocked = blocked
    }
    func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if blocked { await withCheckedContinuation { continuation = $0 } }
        if failing { throw URLError(.notConnectedToInternet) }
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["ETag": "\"version-1\"", "Last-Modified": "Fri, 06 Nov 2026 12:00:00 GMT"])!)
    }
    func release() { blocked = false; continuation?.resume(); continuation = nil }
}

@MainActor @Suite("在线频道更新", .serialized)
struct OnlineChannelTests {
    private static let playlist = """
    #EXTM3U
    #EXTINF:-1 tvg-id="CCTV1" group-title="央视频道",CCTV-1 综合
    https://raw.githubusercontent.com/TvWasm/cjs/main/cmg.cjs?id=600001859
    #EXTINF:-1 tvg-id="CCTV1" group-title="央视频道",CCTV-1 综合
    https://raw.githubusercontent.com/TvWasm/cjs/main/cctv.cjs?id=cctv1
    #EXTINF:-1 group-title="卫视频道",北京卫视
    https://raw.githubusercontent.com/TvWasm/cjs/main/cmg.cjs?id=600002309
    """

    private struct Preferences {
        let name = "SofaTV.OnlineChannelTests." + UUID().uuidString
        let defaults: UserDefaults
        init() { defaults = UserDefaults(suiteName: name)! }
        func clean() { defaults.removePersistentDomain(forName: name) }
    }
    private func library(_ preferences: Preferences, fixture: SourceFixture, hasImportedSource: Bool = true) throws -> Library {
        if hasImportedSource, preferences.defaults.data(forKey: "channel-lists") == nil {
            preferences.defaults.set(try JSONEncoder().encode([ChannelList.online(OnlineChannelSource.defaultURL)]), forKey: "channel-lists")
        }
        return Library(defaults: preferences.defaults, channelRepository: OnlineChannelRepository(loader: { try await fixture.load($0) }),
                warmsChannels: false)
    }
    private func settle(_ library: Library) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !library.updatingSourceIDs.isEmpty {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    private func waitForRequest(_ fixture: SourceFixture, count: Int = 1) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await fixture.requests.count < count {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func adaptsUpstreamAndRetainsProgrammeIDs() throws {
        let channels = try OnlineChannelSource.parse("\u{feff}" + Self.playlist)
        #expect(channels.count == 2)
        #expect(channels[0].epgID == "CCTV1")
        #expect(channels[0].sources.map(\.absoluteString) == [
            "webview://https://yangshipin.cn/tv/home?pid=600001859",
            "webview://https://tv.cctv.com/live/cctv1/index.shtml"
        ])
        #expect(throws: (any Error).self) { try OnlineChannelSource.parse("<html>Service unavailable</html>") }
        #expect(throws: (any Error).self) { try OnlineChannelSource.parse(Self.playlist.replacingOccurrences(of: "cmg.cjs", with: "unknown.cjs")) }
        #expect(throws: (any Error).self) { try OnlineChannelSource.parse(Self.playlist.replacingOccurrences(of: "id=600001859", with: "id=../evil")) }
        let txt = try OnlineChannelSource.parse("新闻,#genre#\n测试台,https://example.com/live.m3u8")
        #expect(txt[0].name == "测试台" && txt[0].group == "新闻")
    }

    @Test func firstLaunchStaysEmptyUntilUserImports() async throws {
        let preferences = Preferences(); defer { preferences.clean() }
        let fixture = SourceFixture(Self.playlist)
        let app = try library(preferences, fixture: fixture, hasImportedSource: false)
        #expect(app.channels.isEmpty && app.channelLists.isEmpty)
        app.startOnlineUpdates(); app.startOnlineUpdates()
        try await settle(app)
        #expect(await fixture.requests.isEmpty)
        #expect(app.channelLists.isEmpty)
        await app.load(OnlineChannelSource.defaultURL.absoluteString, direct: false)
        #expect(app.channels.count == 2)
        #expect(await fixture.requests.count == 1)
        #expect(app.channelLists[0].lastCheckedAt != nil)
        let restarted = try library(preferences, fixture: fixture)
        #expect(restarted.channels == app.channels)
        #expect(restarted.channelLists[0].eTag == "\"version-1\"")
        await fixture.configure(failing: true)
        restarted.startOnlineUpdates()
        try await settle(restarted)
        #expect(restarted.channels == app.channels)
        #expect(!restarted.sourceUpdateErrors.isEmpty)
    }

    @Test func conditionalRequestsAndManualRestore() async throws {
        let fixture = SourceFixture(Self.playlist)
        let repository = OnlineChannelRepository(loader: { try await fixture.load($0) })
        let list = ChannelList.online(OnlineChannelSource.defaultURL)
        let first = try await repository.refresh(list)
        let cached = first.applying(to: list)
        await fixture.configure(status: 304)
        let unchanged = try await repository.refresh(cached)
        #expect(unchanged.channels == nil)
        #expect(unchanged.applying(to: cached).channels == cached.channels)
        let request = await fixture.requests.last!
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"version-1\"")
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") != nil)
        await fixture.configure()
        _ = try await repository.refresh(cached, force: true)
        #expect(await fixture.requests.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func failedRefreshCanRetry() async throws {
        let preferences = Preferences(); defer { preferences.clean() }
        let fixture = SourceFixture(Self.playlist)
        await fixture.configure(failing: true)
        let app = try library(preferences, fixture: fixture)
        app.startOnlineUpdates(); try await settle(app)
        #expect(app.channels.isEmpty && app.channelLists[0].lastCheckedAt == nil)
        #expect(!app.sourceUpdateErrors.isEmpty)
        await fixture.configure()
        app.refreshOnlineChannels(); try await settle(app)
        #expect(app.channels.count == 2 && app.sourceUpdateErrors.isEmpty)
    }

    @Test func importedOnlineListsRefreshIndependently() async throws {
        let preferences = Preferences(); defer { preferences.clean() }
        let fixture = SourceFixture(Self.playlist)
        let ownURL = URL(string: "https://example.com/own.m3u")!
        let old = Channel(name: "自定义频道", group: "个人", url: URL(string: "https://example.com/old.m3u8")!)
        var own = ChannelList.online(ownURL); own.channels = [old]
        var file = ChannelList.file(URL(fileURLWithPath: "/private/tmp/own.m3u")); file.channels = [old]
        preferences.defaults.set(try JSONEncoder().encode([ChannelList.online(OnlineChannelSource.defaultURL), own, file]), forKey: "channel-lists")
        let repository = OnlineChannelRepository(loader: { request in
            if request.url == ownURL { throw URLError(.notConnectedToInternet) }
            return try await fixture.load(request)
        })
        let app = Library(defaults: preferences.defaults, channelRepository: repository, warmsChannels: false)
        app.startOnlineUpdates(); try await settle(app)
        #expect(app.channels.count == 3)
        #expect(app.channelLists.first { $0.id == own.id } == own)
        #expect(app.channelLists.first { $0.id == file.id } == file)
        #expect(app.sourceUpdateErrors.keys.contains(own.id))
        #expect(await fixture.requests.count == 1)
    }

    @Test func migrationRetainsPreferencesAndPlaybackSnapshot() async throws {
        let preferences = Preferences(); defer { preferences.clean() }
        let old = Channel(name: "CCTV-1 综合", group: "央视频道", url: URL(string: "https://example.com/old.m3u8")!, epgID: "CCTV1")
        let legacy = ChannelList(id: "builtin", name: "内置频道", detail: "随应用提供", kind: .builtIn, importedAt: Date(), channels: [old])
        // Exercise the old persisted shape, without any of the new optional fields.
        preferences.defaults.set(try JSONEncoder().encode([legacy]), forKey: "channel-lists")
        preferences.defaults.set([old.url.absoluteString], forKey: "favorites")
        preferences.defaults.set(0.65, forKey: "volume-" + old.url.absoluteString)
        preferences.defaults.set(old.url.absoluteString, forKey: "line-" + old.url.absoluteString)
        let fixture = SourceFixture(Self.playlist)
        let app = try library(preferences, fixture: fixture)
        #expect(app.channels == [old] && app.channelLists[0].kind == .online)
        app.selected = old; app.playbackStatus = "正在播放测试节目"
        app.startOnlineUpdates()
        try await settle(app)
        let refreshed = try #require(app.channels.first)
        #expect(app.favorites == [refreshed.id])
        #expect(preferences.defaults.float(forKey: "volume-" + refreshed.id) == 0.65)
        #expect(app.selected == old && app.sourceIndex == 0)
        #expect(app.playbackStatus == "正在播放测试节目")
        app.setVolume(0.8)
        #expect(preferences.defaults.float(forKey: "volume-" + refreshed.id) == 0.8)
        // An upstream removal also leaves the ongoing playback alone.
        await fixture.configure(text: "北京卫视,https://example.com/beijing.m3u8")
        app.refreshOnlineChannels()
        try await settle(app)
        #expect(app.channels.count == 1 && app.selected == old)
    }

    @Test func refreshReplacesOldLinesAndKeepsUserRemovals() async throws {
        let preferences = Preferences(); defer { preferences.clean() }
        let fixture = SourceFixture(Self.playlist)
        let app = try library(preferences, fixture: fixture)
        app.startOnlineUpdates(); try await settle(app)
        let cctv = app.channels[0], beijing = app.channels[1]
        let sourceID = try #require(app.channelLists.first?.id)
        app.deleteSource(cctv.url, from: cctv, fromList: sourceID)
        app.deleteChannel(beijing, fromList: sourceID)
        app.refreshOnlineChannels(); try await settle(app)
        #expect(app.channels.count == 1 && app.channels[0].sources == [cctv.sources[1]])
        let restarted = try library(preferences, fixture: fixture)
        restarted.startOnlineUpdates(); try await settle(restarted)
        #expect(restarted.channels == app.channels)
        restarted.refreshOnlineChannels(listID: sourceID, restoreRemoved: true)
        try await settle(restarted)
        #expect(restarted.channels.count == 2 && restarted.channels[0].sources.count == 2)
        restarted.deleteGroup("卫视频道")
        restarted.refreshOnlineChannels(); try await settle(restarted)
        #expect(restarted.channels.map(\.name) == ["CCTV-1 综合"])
        await fixture.configure(text: "#EXTM3U\n#EXTINF:-1 group-title=\"央视频道\",CCTV-1 综合\nhttps://example.com/new.m3u8")
        restarted.refreshOnlineChannels(); try await settle(restarted)
        #expect(restarted.channels[0].sources.map(\.absoluteString) == ["https://example.com/new.m3u8"])
    }

    @Test func failedRefreshDoesNotReplaceGoodData() async throws {
        let preferences = Preferences(); defer { preferences.clean() }
        let fixture = SourceFixture(Self.playlist)
        let app = try library(preferences, fixture: fixture)
        app.startOnlineUpdates(); try await settle(app)
        let saved = app.channelLists
        for (text, status) in [("", 200), ("<html>Error</html>", 200), (Self.playlist, 500),
                               (Self.playlist.replacingOccurrences(of: "cmg.cjs", with: "new.cjs"), 200)] {
            await fixture.configure(text: text, status: status)
            app.refreshOnlineChannels(); try await settle(app)
            #expect(app.channelLists == saved)
            #expect(!app.sourceUpdateErrors.isEmpty)
        }
    }

    @Test func deletionDuringDownloadDoesNotRecreateSource() async throws {
        let preferences = Preferences(); defer { preferences.clean() }
        let fixture = SourceFixture(Self.playlist)
        await fixture.configure(blocked: true)
        let app = try library(preferences, fixture: fixture)
        app.startOnlineUpdates(); try await waitForRequest(fixture)
        app.deleteList(app.channelLists[0])
        await fixture.release(); try await settle(app)
        #expect(app.channelLists.isEmpty && app.channels.isEmpty)
        let restarted = try library(preferences, fixture: fixture)
        #expect(restarted.channelLists.isEmpty)
        restarted.startOnlineUpdates(); try await settle(restarted)
        #expect(restarted.channelLists.isEmpty)
        #expect(await fixture.requests.count == 1)
        await restarted.load(OnlineChannelSource.defaultURL.absoluteString, direct: false)
        #expect(restarted.channels.count == 2)
    }

    @Test func removalDuringDownloadIsAppliedToNewData() async throws {
        let preferences = Preferences(); defer { preferences.clean() }
        let fixture = SourceFixture(Self.playlist)
        let app = try library(preferences, fixture: fixture)
        app.startOnlineUpdates(); try await settle(app)
        await fixture.configure(blocked: true)
        app.refreshOnlineChannels()
        try await waitForRequest(fixture, count: 2)
        app.deleteGroup("卫视频道")
        await fixture.release(); try await settle(app)
        #expect(app.channels.map(\.name) == ["CCTV-1 综合"])
    }

    @Test func liveDefaultSource() async throws {
        guard ProcessInfo.processInfo.environment["SOFATV_TEST_LIVE_SOURCE"] == "1" else { return }
        let result = try await OnlineChannelRepository().refresh(.online(OnlineChannelSource.defaultURL))
        let channels = try #require(result.channels)
        #expect(channels.count > 20)
        #expect(channels.allSatisfy { $0.sources.allSatisfy { $0.pathExtension != "cjs" } })
        #expect(channels.contains { $0.name == "CCTV-1 综合" && $0.sources.count > 1 })
        print("Live default source: \(channels.count) channels, \(channels.reduce(0) { $0 + $1.sources.count }) playback routes")
    }
}
