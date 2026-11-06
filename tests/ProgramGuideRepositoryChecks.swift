import Foundation

private actor PayloadStub {
    private var payloads: [URL: Data]
    private var failing: Set<URL> = []
    private var calls: [URL: Int] = [:]
    private let primary: URL
    init(primary: URL, payloads: [URL: Data]) { self.primary = primary; self.payloads = payloads }
    func load(_ url: URL) async throws -> Data {
        calls[url, default: 0] += 1
        // The faster backup must not acquire primary priority just because it finishes first.
        try await Task.sleep(for: url == primary ? .milliseconds(80) : .milliseconds(10))
        guard !failing.contains(url), let payload = payloads[url] else { throw URLError(.notConnectedToInternet) }
        return payload
    }
    func callCount(_ url: URL) -> Int { calls[url, default: 0] }
    func fail(_ sources: Set<URL>) { failing = sources }
    func replace(_ payloads: [URL: Data]) { self.payloads = payloads; failing = [] }
}

@main struct ProgramGuideRepositoryChecks {
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sofatv-epg-cache-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cacheURL = folder.appendingPathComponent("guide.json")
        let channel = Channel(name: "CCTV1", group: "央视", url: URL(string: "https://example.com/live")!)
        let at = ISO8601DateFormatter().date(from: "2026-11-06T10:30:00Z")!
        let xml = Data(#"<tv><programme channel="CCTV1" start="20261106100000 +0000" stop="20261106110000 +0000"><title>缓存节目</title></programme></tv>"#.utf8)
        let guide = try ProgramGuide.parse(xml)
        let entry = ProgramGuideCacheEntry(fetchedAt: at, guide: guide)
        try JSONEncoder().encode(entry).write(to: cacheURL, options: .atomic)
        let repository = ProgramGuideRepository(cacheURL: cacheURL)
        let cached = await repository.cachedGuide()
        precondition(cached?.fetchedAt == at)
        precondition(cached?.guide.currentTitle(channel: channel, at: at) == "缓存节目")
        precondition(cached?.guide.currentTitle(channel: channel, at: at.addingTimeInterval(3_600)) == nil)
        try Data("interrupted cache write".utf8).write(to: cacheURL)
        let inMemory = await repository.cachedGuide()
        precondition(inMemory?.guide.currentTitle(channel: channel, at: at) == "缓存节目")
        let corrupt = await ProgramGuideRepository(cacheURL: cacheURL).cachedGuide()
        precondition(corrupt == nil)
        let absent = await ProgramGuideRepository(cacheURL: folder.appendingPathComponent("absent.json")).cachedGuide()
        precondition(absent == nil)
        print("EPG disk cache restoration, corruption recovery and expired-title checks passed")
        try await checkFullRefresh(in: folder)

        if CommandLine.arguments.contains("--live") {
            let live = try await ProgramGuideRepository(cacheURL: folder.appendingPathComponent("live.json")).refresh()
            let playlist = try String(contentsOfFile: "Sources/SofaTV/Resources/builtin_channels.txt", encoding: .utf8)
            let channels = try ChannelCatalog.parse(playlist)
            let now = Date()
            let missing = channels.filter { live.guide.currentTitle(channel: $0, at: now) == nil }
            print("Live production downloader: \(channels.count - missing.count)/\(channels.count) current programmes, cache fetched at \(live.fetchedAt)")
            if !missing.isEmpty { print("Without current data: " + missing.map(\.name).joined(separator: ", ")) }
        }
    }

    private static func checkFullRefresh(in folder: URL) async throws {
        precondition(ProgramGuideRepository.refreshInterval == 4 * 60 * 60)
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss Z"
        func programme(_ id: String, _ title: String, start: Date, end: Date) -> String {
            "<programme channel=\"\(id)\" start=\"\(formatter.string(from: start))\" stop=\"\(formatter.string(from: end))\"><title>\(title)</title></programme>"
        }
        let start = now.addingTimeInterval(-600), end = now.addingTimeInterval(3600)
        let main = URL(string: "https://example.invalid/primary.xml")!
        let backup = URL(string: "https://example.invalid/backup.xml")!
        let cctv = Channel(name: "CCTV-1 综合", group: "央视", url: URL(string: "https://example.com/cctv1")!)
        let beijing = Channel(name: "北京卫视", group: "卫视", url: URL(string: "https://example.com/beijing")!)
        let primary = Data(("<tv>" + programme("CCTV1", "主源当前节目", start: start, end: end)
            + programme("北京卫视", "主源过期节目", start: start.addingTimeInterval(-3600), end: now.addingTimeInterval(-100)) + "</tv>").utf8)
        let secondary = Data(("<tv>" + programme("CCTV1", "备源一台节目", start: start, end: end)
            + programme("北京卫视", "备源北京节目", start: start, end: end) + "</tv>").utf8)
        let freshCacheURL = folder.appendingPathComponent("fresh.json")
        let old = try ProgramGuide.parse(Data(("<tv>" + programme("CCTV1", "刚缓存的旧内容", start: start, end: end) + "</tv>").utf8))
        try JSONEncoder().encode(ProgramGuideCacheEntry(fetchedAt: now, guide: old)).write(to: freshCacheURL)
        let stub = PayloadStub(primary: main, payloads: [main: primary, backup: secondary])
        let repository = ProgramGuideRepository(cacheURL: freshCacheURL, sources: [main, backup], payloadLoader: { try await stub.load($0) })
        let restored = await repository.cachedGuide()
        precondition(restored?.guide.currentTitle(channel: cctv, at: now) == "刚缓存的旧内容")
        async let firstRequest = repository.refresh()
        async let secondRequest = repository.refresh()
        let (first, second) = try await (firstRequest, secondRequest)
        precondition(first.fetchedAt == second.fetchedAt)
        let primaryCount = await stub.callCount(main), backupCount = await stub.callCount(backup)
        precondition(primaryCount == 1 && backupCount == 1)
        precondition(first.guide.currentTitle(channel: cctv, at: now) == "主源当前节目")
        precondition(first.guide.currentTitle(channel: beijing, at: now) == "备源北京节目")
        let disk = await ProgramGuideRepository(cacheURL: freshCacheURL).cachedGuide()
        precondition(disk?.guide.currentTitle(channel: beijing, at: now) == "备源北京节目")
        let latest = try await repository.refresh()
        let repeatedPrimary = await stub.callCount(main), repeatedBackup = await stub.callCount(backup)
        precondition(repeatedPrimary == 2 && repeatedBackup == 2)
        await stub.fail([main, backup])
        do { _ = try await repository.refresh(); preconditionFailure("All failed downloads should throw") } catch { }
        let retained = await repository.cachedGuide()
        precondition(retained?.fetchedAt == latest.fetchedAt)
        precondition(retained?.guide.currentTitle(channel: beijing, at: now) == "备源北京节目")
        let expired = Data(("<tv>" + programme("CCTV1", "过期", start: start.addingTimeInterval(-3600), end: now.addingTimeInterval(-100)) + "</tv>").utf8)
        await stub.replace([main: expired, backup: expired])
        do { _ = try await repository.refresh(); preconditionFailure("Expired sources should not overwrite cache") } catch { }
        let afterExpired = await repository.cachedGuide()
        precondition(afterExpired?.fetchedAt == latest.fetchedAt)
        let fallbackStub = PayloadStub(primary: main, payloads: [main: Data("<html>error</html>".utf8), backup: secondary])
        let fallbackOnly = try await ProgramGuideRepository(cacheURL: folder.appendingPathComponent("fallback.json"), sources: [main, backup], payloadLoader: { try await fallbackStub.load($0) }).refresh()
        precondition(fallbackOnly.guide.currentTitle(channel: cctv, at: now) == "备源一台节目")
        let partialStub = PayloadStub(primary: main, payloads: [main: primary])
        let partial = try await ProgramGuideRepository(cacheURL: folder.appendingPathComponent("partial.json"), sources: [main, backup], payloadLoader: { try await partialStub.load($0) }).refresh()
        precondition(partial.guide.currentTitle(channel: cctv, at: now) == "主源当前节目")
        print("EPG full source refresh, partial-primary supplementation, source priority, deduplication and failure retention checks passed")
    }
}
