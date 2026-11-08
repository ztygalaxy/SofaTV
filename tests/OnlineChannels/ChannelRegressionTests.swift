import Foundation
import Testing
@testable import SofaTV

private actor PendingChannelImports {
    private(set) var requests: [URLRequest] = []
    private var waiting: [Int: CheckedContinuation<(Data, HTTPURLResponse), Error>] = [:]
    func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let index = requests.count
        requests.append(request)
        return try await withCheckedThrowingContinuation { waiting[index] = $0 }
    }
    func complete(_ index: Int, name: String) {
        let body = "#EXTM3U\n#EXTINF:-1 group-title=\"测试\",\(name)\nhttps://example.invalid/\(index).m3u8\n"
        waiting.removeValue(forKey: index)!.resume(returning: (Data(body.utf8),
            HTTPURLResponse(url: requests[index].url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
    }
}

@MainActor @Suite("频道身份与导入回归", .serialized)
struct ChannelRegressionTests {
    private let sharedURL = URL(string: "https://example.invalid/shared.m3u8")!
    private let sourceURL = URL(string: "https://example.invalid/channels.m3u")!
    private struct Preferences {
        let name = "SofaTV.ChannelRegression." + UUID().uuidString
        let defaults: UserDefaults
        init() { defaults = UserDefaults(suiteName: name)! }
        func clean() { defaults.removePersistentDomain(forName: name) }
    }
    private func library(_ preferences: Preferences, imports: PendingChannelImports? = nil) -> Library {
        Library(defaults: preferences.defaults, channelRepository: OnlineChannelRepository(loader: { request in
            if let imports { return try await imports.load(request) }
            throw URLError(.notConnectedToInternet)
        }), warmsChannels: false, recoveryMonitor: PlaybackRecoveryMonitor(observeSystemEvents: false, pollsAutomatically: false))
    }
    private func waitFor(_ source: PendingChannelImports, count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await source.requests.count < count {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    private func restore(_ app: Library) throws -> ChannelList {
        var list = ChannelList.online(URL(string: "https://example.invalid/restored-list.m3u")!)
        list.channels = [Channel(name: "恢复的频道", group: "测试", url: sharedURL)]
        try app.restoreConfiguration(JSONEncoder().encode(ChannelConfigurationBackup(sources: [list], personalization: .init())))
        return list
    }

    @Test func channelIDsFollowCatalogueIdentityRatherThanMediaURLs() {
        let first = Channel(name: "频道一", group: "测试", url: sharedURL)
        let second = Channel(name: "频道二", group: "测试", url: sharedURL)
        #expect(first.id != second.id)
        var refreshed = first
        refreshed.url = URL(string: "https://example.invalid/new.m3u8")!
        refreshed.epgID = "provider-added-later"
        refreshed.customName = "我的频道"; refreshed.customGroup = "常看"
        #expect(refreshed.id == first.id)
        var anotherGroup = first; anotherGroup.group = "其他"
        #expect(anotherGroup.id != first.id)
        let restored = try? JSONDecoder().decode(Channel.self, from: JSONEncoder().encode(first))
        #expect(restored?.id == first.id)
    }

    @Test func sharedURLsKeepFavoritesVolumeAndDisplayPreferencesSeparate() throws {
        let preferences = Preferences(); defer { preferences.clean() }
        let app = library(preferences)
        try app.parse("""
        #EXTM3U
        #EXTINF:-1 group-title="测试",频道一
        https://example.invalid/shared.m3u8
        #EXTINF:-1 group-title="测试",频道二
        https://example.invalid/shared.m3u8
        """, as: .file(URL(fileURLWithPath: "/private/tmp/regression.m3u")))
        let first = app.channels[0], second = app.channels[1]
        #expect(Set(app.channels.map(\.id)).count == 2)
        app.favorite(first)
        #expect(app.favorites == [first.id] && !app.favorites.contains(second.id))
        app.customizeChannel(first, name: "我的新闻", group: "常看")
        app.selected = first; app.setVolume(0.7)
        app.selected = second; app.setVolume(0.2)
        #expect(app.personalization.volumes[first.preferenceKey] == 0.7)
        #expect(app.personalization.volumes[second.preferenceKey] == 0.2)
        let restarted = library(preferences)
        #expect(restarted.favorites == [first.id])
        #expect(restarted.channels.first { $0.id == second.id }?.displayName == second.name)
        app.stopPlayback()
    }

    @Test func legacyURLSettingsMigrateBeforeNewSharedURLChannelsAreAdded() throws {
        let preferences = Preferences(); defer { preferences.clean() }
        let old = Channel(name: "旧频道", group: "测试", url: sharedURL)
        preferences.defaults.set(try JSONEncoder().encode([ChannelList.legacy([old])]), forKey: "channel-lists")
        preferences.defaults.set([sharedURL.absoluteString], forKey: "favorites")
        preferences.defaults.set(0.65, forKey: "volume-" + sharedURL.absoluteString)
        preferences.defaults.set(sharedURL.absoluteString, forKey: "line-" + sharedURL.absoluteString)
        let app = library(preferences)
        #expect(app.favorites == [old.id])
        #expect(app.personalization.volumes[old.preferenceKey] == 0.65)
        #expect(app.personalization.lines[old.preferenceKey] == sharedURL.absoluteString)
        #expect(preferences.defaults.object(forKey: "volume-" + sharedURL.absoluteString) == nil)
        try app.parse("新频道,\(sharedURL.absoluteString)", as: .file(URL(fileURLWithPath: "/private/tmp/new-regression.m3u")))
        let added = try #require(app.channels.first { $0.name == "新频道" })
        let restarted = library(preferences)
        #expect(restarted.favorites == [old.id] && !restarted.favorites.contains(added.id))
        #expect(restarted.personalization.volumes[added.preferenceKey] == nil)
    }

    @Test func restoringConfigurationDiscardsAnEarlierManualImport() async throws {
        let preferences = Preferences(); defer { preferences.clean() }
        let source = PendingChannelImports(), app = library(preferences, imports: source)
        let importing = Task { await app.load(sourceURL.absoluteString, direct: false) }
        try await waitFor(source, count: 1)
        let replacement = try restore(app)
        #expect(!app.loading)
        await source.complete(0, name: "旧导入频道"); await importing.value
        #expect(app.channelLists == [replacement] && !app.loading)
    }

    @Test func staleImportCannotClearTheNewImportsLoadingState() async throws {
        let preferences = Preferences(); defer { preferences.clean() }
        let source = PendingChannelImports(), app = library(preferences, imports: source)
        let old = Task { await app.load(sourceURL.absoluteString, direct: false) }
        try await waitFor(source, count: 1)
        let replacement = try restore(app)
        let new = Task { await app.load(sourceURL.absoluteString, direct: false) }
        try await waitFor(source, count: 2)
        await source.complete(0, name: "旧导入频道"); await old.value
        #expect(app.loading && app.channelLists == [replacement])
        await source.complete(1, name: "新导入频道"); await new.value
        #expect(!app.loading && app.channels.contains { $0.name == "新导入频道" })
        #expect(!app.channels.contains { $0.name == "旧导入频道" })
    }

    @Test func deletingASourceDiscardsItsPendingManualRefresh() async throws {
        let preferences = Preferences(); defer { preferences.clean() }
        var list = ChannelList.online(sourceURL)
        list.channels = [Channel(name: "已有频道", group: "测试", url: sharedURL)]
        preferences.defaults.set(try JSONEncoder().encode([list]), forKey: "channel-lists")
        let source = PendingChannelImports(), app = library(preferences, imports: source)
        let importing = Task { await app.load(sourceURL.absoluteString, direct: false) }
        try await waitFor(source, count: 1)
        app.deleteList(list)
        await source.complete(0, name: "迟到频道"); await importing.value
        #expect(app.channelLists.isEmpty && app.channels.isEmpty && !app.loading)
    }

    @Test func theNewestManualImportWinsForTheSameSource() async throws {
        let preferences = Preferences(); defer { preferences.clean() }
        let source = PendingChannelImports(), app = library(preferences, imports: source)
        let old = Task { await app.load(sourceURL.absoluteString, direct: false) }
        try await waitFor(source, count: 1)
        let new = Task { await app.load(sourceURL.absoluteString, direct: false) }
        try await waitFor(source, count: 2)
        await source.complete(1, name: "新版本频道"); await new.value
        await source.complete(0, name: "旧版本频道"); await old.value
        #expect(app.channels.map(\.name) == ["新版本频道"] && !app.loading)
    }
}
