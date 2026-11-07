import Foundation

@main struct ProgramGuideScheduleChecks {
    private static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    static func main() throws {
        let primary = try ProgramGuide.parse(Data("""
        <tv><channel id="p"><display-name>北京卫视</display-name></channel>
        <programme channel="p" start="20261107110000 +0800" stop="20261107120000 +0800"><title>主源节目</title></programme>
        <programme channel="p" start="20261107120000 +0800" stop="20261107130000 +0800"><title>主源节目</title></programme>
        <programme channel="p" start="20261107233000 +0800" stop="20261108003000 +0800"><title>跨日节目</title></programme></tv>
        """.utf8))
        let backup = try ProgramGuide.parse(Data("""
        <tv><channel id="b"><display-name>北京卫视高清</display-name></channel>
        <programme channel="b" start="20261107100000 +0800" stop="20261107140000 +0800"><title>补充节目</title></programme></tv>
        """.utf8))
        let guide = primary.supplementing(with: backup)
        let channel = Channel(name: "北京卫视 HD", group: "测试", url: URL(string: "https://example.com/live")!)
        let schedule = guide.schedule(channel: channel)
        precondition(schedule.programs.map(\.title) == ["补充节目", "主源节目", "主源节目", "补充节目", "跨日节目"])
        precondition(Set(schedule.programs.map(\.id)).count == schedule.programs.count)
        precondition(schedule.programs[0].end == date("2026-11-07T03:00:00Z"))
        precondition(schedule.programs[3].start == date("2026-11-07T05:00:00Z"))
        for offset in stride(from: 0, to: 30 * 60, by: 5) {
            let at = date("2026-11-07T02:00:00Z").addingTimeInterval(Double(offset) * 60)
            precondition(schedule.programs.first { $0.contains(at) }?.title == guide.currentTitle(channel: channel, at: at))
        }
        let now = date("2026-11-07T03:30:00Z")
        precondition(ProgramGuide.Schedule.scrollTarget(in: schedule.programs, at: now) == schedule.programs[1])
        precondition(ProgramGuide.Schedule.scrollTarget(in: schedule.programs, at: date("2026-11-07T12:00:00Z")) == schedule.programs.last)
        precondition(ProgramGuide.Schedule.scrollTarget(in: [], at: now) == nil)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        precondition(schedule.programs(on: today, calendar: calendar).count == 5)
        precondition(schedule.programs(on: tomorrow, calendar: calendar).map(\.title) == ["跨日节目"])
        precondition(schedule.programs.last!.timeRange(timeZone: calendar.timeZone) == "23:30–次日00:30")
        precondition(schedule.programs[1].contains(schedule.programs[1].start))
        precondition(!schedule.programs[1].contains(schedule.programs[1].end))
        let restored = try JSONDecoder().decode(ProgramGuide.self, from: JSONEncoder().encode(guide))
        precondition(restored.schedule(channel: channel) == schedule)
        let unknown = Channel(name: "未匹配", group: "测试", url: channel.url)
        precondition(guide.schedule(channel: unknown).programs.isEmpty)

        // The day interval must follow the calendar across a 25-hour DST day.
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let dst = ProgramGuide.Schedule(programs: [ProgramGuide.CurrentProgram(title: "长节目", start: date("2026-11-01T07:00:00Z"), end: date("2026-11-02T08:00:00Z"))])
        let dstDay = date("2026-11-01T07:00:00Z")
        precondition(dst.programs(on: dstDay, calendar: calendar).count == 1)
        precondition(dst.programs(on: date("2026-11-02T08:00:00Z"), calendar: calendar).isEmpty)
        print("Full schedule passed: source priority, gaps, overlap clipping, aliases, current positioning, overnight/DST dates, and cache compatibility")
    }
}
