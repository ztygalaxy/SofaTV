import Foundation

private actor GuideRepositoryFixture {
    private let cache: ProgramGuideCacheEntry?
    private var cacheReads = 0
    private var refreshes = 0
    private var pending: [CheckedContinuation<ProgramGuideCacheEntry, Error>] = []
    init(cache: ProgramGuideCacheEntry?) { self.cache = cache }
    func cachedGuide() -> ProgramGuideCacheEntry? { cacheReads += 1; return cache }
    func refresh() async throws -> ProgramGuideCacheEntry {
        refreshes += 1
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func counts() -> (Int, Int) { (cacheReads, refreshes) }
    func complete(_ entry: ProgramGuideCacheEntry) { precondition(!pending.isEmpty); pending.removeFirst().resume(returning: entry) }
    func fail() { precondition(!pending.isEmpty); pending.removeFirst().resume(throwing: URLError(.notConnectedToInternet)) }
}

@MainActor private final class GuideClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@main struct ProgramGuideStoreChecks {
    private static func check(_ condition: Bool, _ message: String = "Unexpected repository call count") { precondition(condition, message) }
    private static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private static func entry(_ xml: String, fetchedAt: Date) throws -> ProgramGuideCacheEntry {
        ProgramGuideCacheEntry(fetchedAt: fetchedAt, guide: try ProgramGuide.parse(Data(xml.utf8)))
    }
    @MainActor private static func waitFor(_ condition: @MainActor () async -> Bool) async {
        for _ in 0..<1_000 {
            if await condition() { return }
            await Task.yield()
        }
        preconditionFailure("Timed out waiting for the injected programme-guide operation")
    }
    @MainActor private static func makeStore(_ repository: GuideRepositoryFixture, clock: GuideClock) -> ProgramGuideStore {
        ProgramGuideStore(now: { clock.date }, cachedGuide: { await repository.cachedGuide() },
                          refreshGuide: { try await repository.refresh() }, observeSystemEvents: false)
    }
    @MainActor static func main() async throws {
        let start = date("2026-11-06T10:30:00Z")
        let clock = GuideClock(start)
        let first = Channel(name: "A", group: "测试", url: URL(string: "https://example.com/a")!)
        let second = Channel(name: "B", group: "测试", url: URL(string: "https://example.com/b")!)
        let cached = try entry("""
        <tv><programme channel="A" start="20261106100000 +0000" stop="20261106180000 +0000"><title>缓存A</title></programme>
        <programme channel="B" start="20261106100000 +0000" stop="20261106180000 +0000"><title>缓存B</title></programme></tv>
        """, fetchedAt: start) // A fresh disk cache must not suppress the startup network request.
        let fresh = try entry("""
        <tv><programme channel="A" start="20261106100000 +0000" stop="20261106104000 +0000"><title>第一档</title></programme>
        <programme channel="A" start="20261106104000 +0000" stop="20261106180000 +0000"><title>第二档</title></programme>
        <programme channel="B" start="20261106100000 +0000" stop="20261106180000 +0000"><title>新节目B</title></programme></tv>
        """, fetchedAt: start)
        let repository = GuideRepositoryFixture(cache: cached)
        let store = makeStore(repository, clock: clock)
        store.setChannels([])
        check(await repository.counts().1 == 0)
        store.setChannels([first])
        await waitFor { await repository.counts().1 == 1 }
        precondition(store.titles[first.id] == cached.guide.currentProgram(channel: first, at: clock.date)?.subtitle())
        precondition(store.nextRefreshAt == nil)
        for _ in 0..<5 { store.setChannels([first]); store.resume() }
        store.setChannels([])
        precondition(store.titles.isEmpty)
        store.stop()
        store.setChannels([second])
        precondition(store.titles[second.id] == cached.guide.currentProgram(channel: second, at: clock.date)?.subtitle())
        check(await repository.counts().1 == 1, "Stop/start must reuse the existing request")
        clock.date = start.addingTimeInterval(5)
        await repository.complete(fresh)
        let completedAt = clock.date
        await waitFor { store.nextRefreshAt != nil }
        precondition(store.nextRefreshAt == completedAt.addingTimeInterval(4 * 60 * 60))
        precondition(store.titles[second.id] == fresh.guide.currentProgram(channel: second, at: clock.date)?.subtitle())
        precondition(store.titles[first.id] == nil, "A completed load must use the latest channel selection")
        store.stop()
        clock.date = date("2026-11-06T10:35:00Z")
        store.resume()
        check(await repository.counts().1 == 1)
        store.setChannels([first, second])
        clock.date = date("2026-11-06T10:40:00Z")
        store.resume()
        precondition(store.titles[first.id] == fresh.guide.currentProgram(channel: first, at: clock.date)?.subtitle())
        precondition(store.titles[first.id]?.hasSuffix("第二档") == true)
        check(await repository.counts().1 == 1, "Programme boundaries must not trigger HTTP refreshes")
        clock.date = completedAt.addingTimeInterval(4 * 60 * 60 - 1)
        store.resume()
        check(await repository.counts().1 == 1)
        clock.date = completedAt.addingTimeInterval(4 * 60 * 60)
        store.resume()
        await waitFor { await repository.counts().1 == 2 }
        precondition(store.nextRefreshAt == nil)
        await repository.fail()
        await waitFor { store.nextRefreshAt != nil }
        precondition(store.nextRefreshAt == clock.date.addingTimeInterval(10 * 60))
        precondition(store.titles[first.id]?.hasSuffix("第二档") == true, "Failed refreshes must retain usable programmes")
        clock.date = clock.date.addingTimeInterval(10 * 60 - 1)
        store.resume()
        check(await repository.counts().1 == 2)
        clock.date = clock.date.addingTimeInterval(1)
        store.resume()
        await waitFor { await repository.counts().1 == 3 }
        await repository.complete(fresh)
        await waitFor { store.nextRefreshAt != nil }
        precondition(store.nextRefreshAt == clock.date.addingTimeInterval(4 * 60 * 60))
        check(await repository.counts().0 == 1, "The same store restores disk cache once")
        store.stop()

        // Midnight and exhausted data update labels without inventing extra refresh schedules.
        let midnightClock = GuideClock(date("2026-11-06T15:55:00Z"))
        let overnight = try entry("<tv><programme channel=\"A\" start=\"20261106150000 +0000\" stop=\"20261106160500 +0000\"><title>跨日节目</title></programme></tv>", fetchedAt: midnightClock.date)
        let midnightRepository = GuideRepositoryFixture(cache: nil)
        let midnightStore = makeStore(midnightRepository, clock: midnightClock)
        midnightStore.setChannels([first])
        await waitFor { await midnightRepository.counts().1 == 1 }
        await midnightRepository.complete(overnight)
        await waitFor { midnightStore.nextRefreshAt != nil }
        precondition(midnightStore.nextRefreshAt == date("2026-11-06T19:55:00Z"))
        midnightClock.date = date("2026-11-06T16:00:00Z")
        midnightStore.resume()
        precondition(midnightStore.titles[first.id]?.hasSuffix("跨日节目") == true)
        midnightClock.date = date("2026-11-06T16:05:00Z")
        midnightStore.resume()
        precondition(midnightStore.titles.isEmpty)
        check(await midnightRepository.counts().1 == 1, "Neither midnight nor exhausted data should retry early")
        midnightStore.stop()
        midnightClock.date = date("2026-11-06T20:00:00Z")
        midnightStore.resume()
        check(await midnightRepository.counts().1 == 1)
        midnightStore.setChannels([first]) // A reappearance after the deadline catches up once.
        await waitFor { await midnightRepository.counts().1 == 2 }
        for _ in 0..<5 { midnightStore.resume(); midnightStore.setChannels([first]) }
        check(await midnightRepository.counts().1 == 2)
        await midnightRepository.complete(overnight)
        await waitFor { midnightStore.nextRefreshAt != nil }
        precondition(midnightStore.nextRefreshAt == midnightClock.date.addingTimeInterval(4 * 60 * 60))
        midnightStore.stop()

        // Every newly created store fetches again, even with a just-written cache.
        let anotherRepository = GuideRepositoryFixture(cache: ProgramGuideCacheEntry(fetchedAt: clock.date, guide: fresh.guide))
        let anotherStore = makeStore(anotherRepository, clock: clock)
        anotherStore.setChannels([first])
        await waitFor { await anotherRepository.counts().1 == 1 }
        await anotherRepository.fail()
        await waitFor { anotherStore.nextRefreshAt != nil }
        precondition(anotherStore.nextRefreshAt == clock.date.addingTimeInterval(10 * 60))
        anotherStore.stop()
        // An in-flight operation must not keep a dismissed store alive or mutate a replacement.
        let releasedRepository = GuideRepositoryFixture(cache: cached)
        var releasedStore: ProgramGuideStore? = makeStore(releasedRepository, clock: clock)
        let storeWasReleased = { [weak releasedStore] in releasedStore == nil }
        releasedStore?.setChannels([first])
        await waitFor { await releasedRepository.counts().1 == 1 }
        releasedStore?.stop()
        releasedStore = nil
        precondition(storeWasReleased())
        await releasedRepository.complete(fresh)
        await Task.yield()
        print("EPG store checks passed: forced startup, cache-first display, four-hour schedule, failure retry, boundaries, midnight and stop/start reuse")
    }
}
