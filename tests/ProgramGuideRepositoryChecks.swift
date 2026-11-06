import Foundation

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

        if CommandLine.arguments.contains("--live") {
            let live = try await ProgramGuideRepository.shared.refresh()
            let playlist = try String(contentsOfFile: "Sources/SofaTV/Resources/builtin_channels.txt", encoding: .utf8)
            let channels = try ChannelCatalog.parse(playlist)
            let now = Date()
            let missing = channels.filter { live.guide.currentTitle(channel: $0, at: now) == nil }
            print("Live production downloader: \(channels.count - missing.count)/\(channels.count) current programmes, cache fetched at \(live.fetchedAt)")
            if !missing.isEmpty { print("Without current data: " + missing.map(\.name).joined(separator: ", ")) }
        }
    }
}
