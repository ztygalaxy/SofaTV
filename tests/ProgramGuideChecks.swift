import Foundation

@main struct ProgramGuideChecks {
    private static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private static func channel(_ name: String, epgID: String? = nil) -> Channel {
        Channel(name: name, group: "测试", url: URL(string: "https://example.com/live")!, epgID: epgID)
    }
    private static func parse(_ xml: String) throws -> ProgramGuide { try ProgramGuide.parse(Data(xml.utf8)) }
    private static func rejects(_ xml: String) {
        do { _ = try parse(xml); preconditionFailure("Accepted an invalid or empty guide") }
        catch { }
    }

    private static func checkSupplementalGuides() throws {
        let primary = try parse("""
        <tv>
          <channel id="primary-beijing"><display-name>北京卫视</display-name></channel>
          <channel id="primary-hubei"><display-name>湖北卫视</display-name></channel>
          <programme channel="primary-beijing" start="20261106230000 +0800" stop="20261107000000 +0800"><title>北京昨日节目</title></programme>
          <programme channel="primary-hubei" start="20261106233030 +0800" stop="20261107004200 +0800"><title>湖北主源跨日节目</title></programme>
        </tv>
        """)
        let fallback = try parse("""
        <tv>
          <channel id="backup-beijing"><display-name>北京卫视高清</display-name></channel>
          <channel id="backup-hubei"><display-name>湖北卫视</display-name></channel>
          <channel id="backup-guangdong"><display-name>广东卫视</display-name></channel>
          <programme channel="backup-beijing" start="20261107000000 +0800" stop="20261107004000 +0800"><title>北京备用新日节目</title></programme>
          <programme channel="backup-hubei" start="20261107000000 +0800" stop="20261107010000 +0800"><title>湖北备用节目</title></programme>
          <programme channel="backup-guangdong" start="20261106234500 +0800" stop="20261107003500 +0800"><title>广东备用节目</title></programme>
        </tv>
        """)
        let combined = primary.supplementing(with: fallback)
        let midnight = date("2026-11-06T16:00:00Z")
        let afterMidnight = date("2026-11-06T16:25:00Z")
        precondition(combined.currentTitle(channel: channel("北京卫视"), at: midnight.addingTimeInterval(-1)) == "北京昨日节目")
        precondition(combined.currentTitle(channel: channel("北京卫视"), at: midnight) == "北京备用新日节目")
        precondition(combined.currentTitle(channel: channel("北京卫视"), at: afterMidnight) == "北京备用新日节目")
        precondition(combined.currentTitle(channel: channel("湖北卫视"), at: afterMidnight) == "湖北主源跨日节目")
        precondition(combined.currentTitle(channel: channel("广东卫视"), at: afterMidnight) == "广东备用节目")
        precondition(combined.currentTitle(channel: channel("湖北卫视"), at: date("2026-11-06T16:42:00Z")) == "湖北备用节目")
        precondition(combined.currentTitle(channel: channel("北京卫视"), at: date("2026-11-06T16:40:00Z")) == nil)
        precondition(combined.nextChange(after: afterMidnight) == date("2026-11-06T16:35:00Z"))
        precondition(combined.nextChange(after: date("2026-11-06T17:00:00Z")) == nil)

        let futurePrimary = try parse("""
        <tv><channel id="beijing"><display-name>北京卫视</display-name></channel>
          <programme channel="beijing" start="20261107003000 +0800" stop="20261107010000 +0800"><title>北京主源恢复</title></programme>
        </tv>
        """)
        let longFallback = try parse("""
        <tv><channel id="backup"><display-name>北京卫视</display-name></channel>
          <programme channel="backup" start="20261107000000 +0800" stop="20261107020000 +0800"><title>北京长时备用</title></programme>
        </tv>
        """)
        let futureCombined = futurePrimary.supplementing(with: longFallback)
        precondition(futureCombined.currentTitle(channel: channel("北京卫视"), at: afterMidnight) == "北京长时备用")
        precondition(futureCombined.nextChange(after: afterMidnight) == date("2026-11-06T16:30:00Z"))
        precondition(futureCombined.currentTitle(channel: channel("北京卫视"), at: date("2026-11-06T16:30:00Z")) == "北京主源恢复")
        precondition(futureCombined.nextChange(after: date("2026-11-06T16:30:00Z")) == date("2026-11-06T17:00:00Z"))
        precondition(futureCombined.currentTitle(channel: channel("北京卫视"), at: date("2026-11-06T17:00:00Z")) == "北京长时备用")

        // Identical opaque IDs can mean different channels in different feeds.
        let collisionPrimary = try parse("""
        <tv><channel id="shared"><display-name>北京卫视</display-name></channel>
          <programme channel="shared" start="20261106230000 +0800" stop="20261107000000 +0800"><title>北京过期主源</title></programme>
        </tv>
        """)
        let collisionFallback = try parse("""
        <tv>
          <channel id="shared"><display-name>江苏卫视</display-name></channel>
          <channel id="other"><display-name>北京卫视</display-name></channel>
          <programme channel="shared" start="20261107000000 +0800" stop="20261107010000 +0800"><title>江苏备用</title></programme>
          <programme channel="other" start="20261107000000 +0800" stop="20261107010000 +0800"><title>北京备用</title></programme>
        </tv>
        """)
        let collisionCombined = collisionPrimary.supplementing(with: collisionFallback)
        precondition(collisionCombined.currentTitle(channel: channel("北京卫视"), at: afterMidnight) == "北京备用")
        precondition(collisionCombined.currentTitle(channel: channel("江苏卫视"), at: afterMidnight) == "江苏备用")
        precondition(collisionPrimary.currentTitle(channel: channel("江苏卫视"), at: midnight.addingTimeInterval(-1)) == nil)

        let europeFallback = try parse("""
        <tv><channel id="eu"><display-name>CCTV4欧洲</display-name></channel>
          <programme channel="eu" start="20261107000000 +0800" stop="20261107010000 +0800"><title>欧洲备用</title></programme>
        </tv>
        """)
        let regions = primary.supplementing(with: europeFallback)
        precondition(regions.currentTitle(channel: channel("CCTV-4 中文国际（欧）"), at: afterMidnight) == "欧洲备用")
        precondition(regions.currentTitle(channel: channel("未知台", epgID: "CCTV4E"), at: afterMidnight) == "欧洲备用")
        for name in ["CCTV4", "CCTV4美洲", "CCTV4K", "CCTV8K"] {
            precondition(regions.currentTitle(channel: channel(name), at: afterMidnight) == nil)
        }

        let third = try parse("""
        <tv><channel id="beijing"><display-name>北京卫视</display-name></channel>
          <programme channel="beijing" start="20261107000000 +0800" stop="20261107030000 +0800"><title>第三来源</title></programme>
        </tv>
        """)
        let layered = primary.supplementing(with: fallback).supplementing(with: third)
        precondition(layered.currentTitle(channel: channel("北京卫视"), at: afterMidnight) == "北京备用新日节目")
        precondition(layered.currentTitle(channel: channel("北京卫视"), at: date("2026-11-06T16:40:00Z")) == "第三来源")
        let nested = primary.supplementing(with: fallback.supplementing(with: third))
        precondition(nested.currentTitle(channel: channel("北京卫视"), at: date("2026-11-06T16:40:00Z")) == "第三来源")

        let restored = try JSONDecoder().decode(ProgramGuide.self, from: JSONEncoder().encode(layered))
        precondition(restored.currentProgram(channel: channel("北京卫视"), at: afterMidnight) == layered.currentProgram(channel: channel("北京卫视"), at: afterMidnight))
        precondition(restored.currentTitle(channel: channel("湖北卫视"), at: afterMidnight) == "湖北主源跨日节目")
        precondition(restored.currentTitle(channel: channel("北京卫视"), at: date("2026-11-06T16:40:00Z")) == "第三来源")
        precondition(restored.nextChange(after: afterMidnight) == layered.nextChange(after: afterMidnight))
        let legacy: [String: Any] = [
            "programsByChannel": ["legacy": [["start": midnight.timeIntervalSinceReferenceDate, "end": afterMidnight.timeIntervalSinceReferenceDate, "title": "旧缓存节目"]]],
            "channelByAlias": ["LEGACY": "legacy"]
        ]
        let oldGuide = try JSONDecoder().decode(ProgramGuide.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(oldGuide.currentTitle(channel: channel("legacy"), at: midnight) == "旧缓存节目")
        precondition(oldGuide.supplementing(with: fallback).currentTitle(channel: channel("北京卫视"), at: afterMidnight) == "北京备用新日节目")
    }

    static func main() throws {
        let now = date("2026-11-06T10:30:00Z")
        let channels = [
            ("opaque-cn1", "CCTV-1 综合 HD", "综合节目"),
            ("CCTV1", "自定义节目台", "精确 ID 节目"),
            ("asia", "CCTV4中文国际亚洲", "亚洲节目"),
            ("europe", "CCTV4欧洲", "欧洲节目"),
            ("america", "CCTV4美洲", "美洲节目"),
            ("uhd4", "CCTV4K", "四K节目"),
            ("uhd8", "CCTV8K", "八K节目"),
            ("olympics", "CCTV16", "奥运节目"),
            ("sportsplus", "CCTV5+", "体育赛事节目"),
            ("beijing", "北京卫视 高清", "北京节目"),
            ("southeast", "东南卫视", "东南节目"),
            ("education", "中国教育电视台1", "教育节目")
        ]
        let xml = "<tv>" + channels.map { id, name, _ in
            "<channel id=\"\(id)\"><display-name>\(name)</display-name></channel>"
        }.joined() + channels.map { id, _, title in
            "<programme channel=\"\(id)\" start=\"20261106180000 +0800\" stop=\"20261106190000 +0800\"><title>\(title)</title></programme>"
        }.joined() + "</tv>"
        let guide = try parse(xml)
        precondition(guide.currentTitle(channel: channel("中央1"), at: now) == "综合节目")
        precondition(guide.currentTitle(channel: channel("央视一套"), at: now) == "综合节目")
        precondition(guide.currentTitle(channel: channel("中央1", epgID: " CCTV1 "), at: now) == "精确 ID 节目")
        precondition(guide.currentTitle(channel: channel("未知频道", epgID: "opaque-cn1"), at: now) == "综合节目")
        precondition(guide.currentTitle(channel: channel("中央1", epgID: "不存在的ID"), at: now) == "综合节目")
        precondition(guide.currentTitle(channel: channel("CCTV-4 中文国际（亚）"), at: now) == "亚洲节目")
        precondition(guide.currentTitle(channel: channel("CCTV-4 中文国际（欧）"), at: now) == "欧洲节目")
        precondition(guide.currentTitle(channel: channel("CCTV-4 中文国际（美）"), at: now) == "美洲节目")
        precondition(guide.currentTitle(channel: channel("CCTV4 EUO"), at: now) == "欧洲节目")
        precondition(guide.currentTitle(channel: channel("未知台", epgID: "CCTV4E"), at: now) == "欧洲节目")
        precondition(guide.currentTitle(channel: channel("未知台", epgID: "CCTV4A"), at: now) == "美洲节目")
        precondition(guide.currentTitle(channel: channel("中文国际美洲"), at: now) == "美洲节目")
        precondition(guide.currentTitle(channel: channel("CCTV4K 超高清"), at: now) == "四K节目")
        precondition(guide.currentTitle(channel: channel("CCTV8K"), at: now) == "八K节目")
        precondition(guide.currentTitle(channel: channel("CCTV16（4K）"), at: now) == "奥运节目")
        precondition(guide.currentTitle(channel: channel("CCTV-5+ 体育赛事"), at: now) == "体育赛事节目")
        precondition(guide.currentTitle(channel: channel("北京卫视 HD"), at: now) == "北京节目")
        precondition(guide.currentTitle(channel: channel("福建东南卫视"), at: now) == "东南节目")
        precondition(guide.currentTitle(channel: channel("中国教育电视台1频道"), at: now) == "教育节目")
        precondition(guide.currentTitle(channel: channel("未知频道"), at: now) == nil)
        precondition(guide.currentTitle(channel: channel("中央1"), at: date("2026-11-06T10:00:00Z")) == "综合节目")
        precondition(guide.currentTitle(channel: channel("中央1"), at: date("2026-11-06T11:00:00Z")) == nil)
        precondition(guide.currentTitle(channel: channel("中央1"), at: date("2026-11-06T09:59:59Z")) == nil)
        precondition(guide.nextChange(after: now) == date("2026-11-06T11:00:00Z"))
        precondition(guide.nextChange(after: date("2026-11-06T11:00:00Z")) == nil)

        let timeGuide = try parse("""
        <tv>
          <programme channel="east" start="20261106000000+0800" stop="20261106003000+0800"><title>午夜节目</title></programme>
          <programme channel="utc" start="20261105160000 +0000" stop="20261105163000 +0000"><title>UTC节目</title></programme>
          <programme channel="west" start="20261105110000 -0500" stop="20261105113000 -0500"><title>西部节目</title></programme>
          <programme channel="zulu" start="20261105160000Z" stop="20261105163000Z"><title>Z节目</title></programme>
        </tv>
        """)
        let midnight = date("2026-11-05T16:00:00Z")
        precondition(timeGuide.currentTitle(channel: channel("east"), at: midnight) == "午夜节目")
        precondition(timeGuide.currentTitle(channel: channel("utc"), at: midnight) == "UTC节目")
        precondition(timeGuide.currentTitle(channel: channel("west"), at: midnight) == "西部节目")
        precondition(timeGuide.currentTitle(channel: channel("zulu"), at: midnight) == "Z节目")
        precondition(timeGuide.currentTitle(channel: channel("east"), at: date("2026-11-05T16:30:00Z")) == nil)
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = .current
        let localDate = localCalendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 18, minute: 30))!
        let localGuide = try parse("<tv><programme channel=\"local\" start=\"20261106180000\" stop=\"20261106190000\"><title>本地时区</title></programme></tv>")
        precondition(localGuide.currentTitle(channel: channel("local"), at: localDate) == "本地时区")

        let titleGuide = try parse("""
        <tv><programme channel="title" start="20261106100000 +0000" stop="20261106110000 +0000">
          <title lang="en">English title</title><title lang="zh"> 新闻
          联播 &amp; 访谈 </title><title lang="en">Another title</title>
        </programme><programme channel="title" start="20261106110000 +0000" stop="20261106120000 +0000"><title><![CDATA[下一档节目]]></title></programme></tv>
        """)
        precondition(titleGuide.currentTitle(channel: channel("title"), at: now) == "新闻 联播 & 访谈")
        precondition(titleGuide.currentTitle(channel: channel("title"), at: date("2026-11-06T11:00:00Z")) == "下一档节目")
        precondition(titleGuide.nextChange(after: date("2026-11-06T09:00:00Z")) == date("2026-11-06T10:00:00Z"))
        let regionOnly = try parse("<tv><channel id=\"eu\"><display-name>CCTV4欧洲</display-name></channel><programme channel=\"eu\" start=\"20261106100000 +0000\" stop=\"20261106110000 +0000\"><title>欧洲</title></programme></tv>")
        for name in ["CCTV4", "CCTV4美洲", "CCTV4K", "CCTV8K"] { precondition(regionOnly.currentTitle(channel: channel(name), at: now) == nil) }
        for invalid in ["", "<tv/>", "<html><title>错误页</title></html>", "<tv><programme", "<tv><channel id=\"empty\"/></tv>"] { rejects(invalid) }
        for (start, stop) in [("20260230100000 +0000", "20260230110000 +0000"), ("20261106100000 +2460", "20261106110000 +2460"), ("20261106110000 +0000", "20261106100000 +0000"), ("20261106100000junk", "20261106110000junk")] {
            rejects("<tv><programme channel=\"bad\" start=\"\(start)\" stop=\"\(stop)\"><title>错误</title></programme></tv>")
        }
        let cached = try JSONDecoder().decode(ProgramGuide.self, from: JSONEncoder().encode(guide))
        precondition(cached.currentTitle(channel: channel("中央1"), at: now) == "综合节目")
        precondition(cached.nextChange(after: now) == guide.nextChange(after: now))

        let displayGuide = try parse("""
        <tv>
          <programme channel="display" start="20261106120000 +0000" stop="20261106124500 +0000"><title>新闻联播</title></programme>
          <programme channel="display" start="20261106124500 +0000" stop="20261106130000 +0000"><title>新闻联播</title></programme>
          <programme channel="overnight" start="20261231153000 +0000" stop="20261231163000 +0000"><title>跨年节目</title></programme>
          <programme channel="month" start="20261130153000 +0000" stop="20261130163000 +0000"><title>月末节目</title></programme>
          <programme channel="padding" start="20261106010200 +0000" stop="20261106030900 +0000"><title>零补齐</title></programme>
        </tv>
        """)
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        let utc = TimeZone(secondsFromGMT: 0)!
        let displayChannel = channel("display")
        precondition(displayGuide.currentProgram(channel: displayChannel, at: date("2026-11-06T11:59:59Z")) == nil)
        let firstBroadcast = displayGuide.currentProgram(channel: displayChannel, at: date("2026-11-06T12:00:00Z"))!
        precondition(firstBroadcast.title == "新闻联播")
        precondition(firstBroadcast.start == date("2026-11-06T12:00:00Z"))
        precondition(firstBroadcast.end == date("2026-11-06T12:45:00Z"))
        precondition(firstBroadcast.subtitle(timeZone: shanghai) == "20:00–20:45 新闻联播")
        precondition(firstBroadcast.subtitle(timeZone: utc) == "12:00–12:45 新闻联播")
        precondition(firstBroadcast.subtitle() == firstBroadcast.subtitle(timeZone: .current))
        precondition(displayGuide.currentProgram(channel: displayChannel, at: date("2026-11-06T12:44:59Z")) == firstBroadcast)
        let nextBroadcast = displayGuide.currentProgram(channel: displayChannel, at: date("2026-11-06T12:45:00Z"))!
        precondition(firstBroadcast.title == nextBroadcast.title && firstBroadcast != nextBroadcast)
        precondition(nextBroadcast.subtitle(timeZone: shanghai) == "20:45–21:00 新闻联播")
        precondition(displayGuide.currentProgram(channel: displayChannel, at: date("2026-11-06T13:00:00Z")) == nil)
        precondition(displayGuide.currentProgram(channel: channel("unknown"), at: now) == nil)
        let yearEnd = displayGuide.currentProgram(channel: channel("overnight"), at: date("2026-12-31T16:00:00Z"))!
        precondition(yearEnd.subtitle(timeZone: shanghai) == "23:30–次日00:30 跨年节目")
        precondition(yearEnd.subtitle(timeZone: utc) == "15:30–16:30 跨年节目")
        let monthEnd = displayGuide.currentProgram(channel: channel("month"), at: date("2026-11-30T16:00:00Z"))!
        precondition(monthEnd.subtitle(timeZone: shanghai) == "23:30–次日00:30 月末节目")
        let padded = displayGuide.currentProgram(channel: channel("padding"), at: date("2026-11-06T02:00:00Z"))!
        precondition(padded.subtitle(timeZone: utc) == "01:02–03:09 零补齐")
        let oldCache: [String: Any] = [
            "programsByChannel": ["legacy": [["start": firstBroadcast.start.timeIntervalSinceReferenceDate, "end": firstBroadcast.end.timeIntervalSinceReferenceDate, "title": firstBroadcast.title]]],
            "channelByAlias": ["LEGACY": "legacy"]
        ]
        let oldSnapshot = try JSONDecoder().decode(ProgramGuide.self, from: JSONSerialization.data(withJSONObject: oldCache))
        precondition(oldSnapshot.currentProgram(channel: channel("legacy"), at: firstBroadcast.start) == firstBroadcast)
        precondition(oldSnapshot.currentTitle(channel: channel("legacy"), at: firstBroadcast.start) == firstBroadcast.title)
        let restoredDisplay = try JSONDecoder().decode(ProgramGuide.self, from: JSONEncoder().encode(displayGuide))
        precondition(restoredDisplay.currentProgram(channel: displayChannel, at: firstBroadcast.start) == firstBroadcast)

        let playlist = """
        #EXTM3U
        #EXTINF:-1 tvg-id="opaque-cn1" group-title="央视",中央1
        https://example.com/one.m3u8
        #EXTINF:-1 group-title="卫视",北京卫视
        https://example.com/beijing.m3u8
        #EXTINF:-1 tvg-id='europe' group-title='央视',欧洲台
        https://example.com/europe.m3u8
        #EXTINF:-1 tvg-id=uhd4 group-title=央视,四K台
        https://example.com/4k.m3u8
        """
        let parsedChannels = try ChannelCatalog.parse(playlist)
        precondition(parsedChannels.map(\.epgID) == ["opaque-cn1", nil, "europe", "uhd4"])
        precondition(parsedChannels.map(\.group) == ["央视", "卫视", "央视", "央视"])
        let legacy = try JSONDecoder().decode(Channel.self, from: Data(#"{"name":"旧频道","group":"直播","url":"https://example.com/old"}"#.utf8))
        precondition(legacy.epgID == nil)
        var identified = parsedChannels[0]
        identified.alternatives = [URL(string: "https://example.com/backup.m3u8")!]
        precondition(identified.removing(identified.url)?.epgID == "opaque-cn1")
        let restoredChannel = try JSONDecoder().decode(Channel.self, from: JSONEncoder().encode(identified))
        precondition(restoredChannel.epgID == "opaque-cn1")
        var withoutID = identified; withoutID.epgID = nil
        precondition(ChannelCatalog.merge([identified], into: [withoutID])[0].epgID == "opaque-cn1")
        var conflicting = identified; conflicting.epgID = "another-id"
        precondition(ChannelCatalog.merge([conflicting], into: [identified])[0].epgID == "opaque-cn1")
        try checkSupplementalGuides()
        print("Program guide parsing, matching, time boundaries, fallback priority, caching and M3U compatibility passed")

        if CommandLine.arguments.count > 1 {
            let liveGuide = try ProgramGuide.parse(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            let builtinText = try String(contentsOfFile: "Sources/SofaTV/Resources/builtin_channels.txt", encoding: .utf8)
            let builtins = try ChannelCatalog.parse(builtinText)
            let checkedAt = Date()
            let missing = builtins.filter { liveGuide.currentTitle(channel: $0, at: checkedAt) == nil }.map(\.name)
            print("Real XMLTV sample: \(builtins.count - missing.count)/\(builtins.count) built-in channels have a current programme at \(checkedAt)")
            if !missing.isEmpty { print("Without current programme: \(missing.joined(separator: ", "))") }
            for name in ["CCTV-4 中文国际（亚）", "CCTV-4 中文国际（欧）", "CCTV-4 中文国际（美）", "CCTV4K", "CCTV8K"] {
                print("\(name): \(liveGuide.currentTitle(channel: channel(name), at: checkedAt) ?? "无节目")")
            }
        }
    }
}
