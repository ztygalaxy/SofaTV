import Foundation
import Testing
@testable import SofaTV

@MainActor @Suite("节目单当前与即将播出", .serialized)
struct ProgramGuidePresentationTests {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    private func gapGuide() throws -> ProgramGuide {
        try ProgramGuide.parse(Data("""
        <tv><channel id="gx"><display-name>广西卫视</display-name></channel>
        <programme channel="gx" start="20261108084000 +0800" stop="20261108104000 +0800"><title>独立大队</title></programme>
        <programme channel="gx" start="20261108105000 +0800" stop="20261108121000 +0800"><title>渡江侦察记</title></programme>
        <programme channel="gx" start="20261109100000 +0800" stop="20261109120000 +0800"><title>明天节目</title></programme></tv>
        """.utf8))
    }

    @Test func gapHighlightsTheNextEntryWithoutInventingALiveProgramme() throws {
        let guide = try gapGuide()
        let channel = Channel(name: "广西卫视", group: "卫视", url: URL(string: "https://example.invalid/gx")!)
        let now = date("2026-11-08T02:45:00Z")
        #expect(guide.currentProgram(channel: channel, at: now) == nil)
        let highlight = try #require(guide.highlightedProgram(channel: channel, at: now, calendar: calendar))
        #expect(highlight.program.title == "渡江侦察记" && highlight.isUpcoming)
        #expect(highlight.badge(isPlayingChannel: true) == "即将播出")
        #expect(highlight.badge(isPlayingChannel: false) == "即将播出")
        #expect(highlight.subtitle(timeZone: calendar.timeZone) == "即将播出 · 10:50–12:10 渡江侦察记")
        let today = guide.schedule(channel: channel).programs(on: now, calendar: calendar)
        #expect(ProgramGuide.Schedule.scrollTarget(in: today, at: now) == highlight.program)
        #expect(ProgramGuide.Schedule.highlight(in: today, at: now) == highlight)
        let started = try #require(guide.highlightedProgram(channel: channel, at: date("2026-11-08T02:50:00Z"), calendar: calendar))
        #expect(!started.isUpcoming && started.program == highlight.program)
        #expect(started.badge(isPlayingChannel: true) == "当前节目")
        #expect(started.badge(isPlayingChannel: false) == "正在播出")
        #expect(guide.highlightedProgram(channel: channel, at: date("2026-11-08T04:10:00Z"), calendar: calendar) == nil,
            "Tomorrow's programme must not appear as upcoming in today's pane")
        #expect(guide.highlightedProgram(channel: channel, at: date("2026-11-08T00:00:00Z"), calendar: calendar)?.isUpcoming == true)
    }

    @Test func aValidFallbackStaysCurrentInsteadOfHighlightingAFuturePrimaryEntry() throws {
        let fallback = try ProgramGuide.parse(Data("""
        <tv><programme channel="广西卫视" start="20261108104000 +0800" stop="20261108110000 +0800"><title>补充排期</title></programme></tv>
        """.utf8))
        let guide = try gapGuide().supplementing(with: fallback)
        let channel = Channel(name: "广西卫视", group: "卫视", url: URL(string: "https://example.invalid/gx")!)
        let now = date("2026-11-08T02:45:00Z")
        let highlight = try #require(guide.highlightedProgram(channel: channel, at: now, calendar: calendar))
        #expect(highlight.program.title == "补充排期" && !highlight.isUpcoming)
        #expect(ProgramGuide.Schedule.highlight(in: guide.schedule(channel: channel).programs, at: now)?.isUpcoming == false)
    }

    @Test func sharedURLChannelsPublishSeparateTitlesAndUpcomingBecomesCurrentOnTime() async throws {
        var now = date("2026-11-08T02:45:00Z")
        let first = Channel(name: "频道一", group: "测试", url: URL(string: "https://example.invalid/shared")!, epgID: "one")
        let second = Channel(name: "频道二", group: "测试", url: first.url, epgID: "two")
        let guide = try ProgramGuide.parse(Data("""
        <tv><programme channel="one" start="20261108100000 +0800" stop="20261108120000 +0800"><title>频道一直播</title></programme>
        <programme channel="two" start="20261108105000 +0800" stop="20261108121000 +0800"><title>频道二下一档</title></programme></tv>
        """.utf8))
        let entry = ProgramGuideCacheEntry(fetchedAt: now, guide: guide)
        let store = ProgramGuideStore(now: { now }, cachedGuide: { entry }, refreshGuide: { entry }, observeSystemEvents: false)
        defer { store.stop() }
        store.setChannels([first, second])
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while store.nextRefreshAt == nil {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.titles.count == 2)
        #expect(store.titles[first.id]?.hasSuffix("频道一直播") == true)
        #expect(store.titles[second.id]?.hasPrefix("即将播出 · ") == true)
        now = date("2026-11-08T02:50:00Z"); store.resume()
        #expect(store.titles[second.id]?.hasSuffix("频道二下一档") == true)
        #expect(store.titles[second.id]?.hasPrefix("即将播出") == false)
    }
}
