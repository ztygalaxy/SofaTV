import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// An XMLTV snapshot that can be cached without keeping the XML parser alive.
struct ProgramGuide: Codable, Sendable {
    struct CurrentProgram: Hashable, Identifiable, Sendable {
        let title: String
        let start: Date
        let end: Date
        var id: Self { self }

        func contains(_ date: Date) -> Bool { start <= date && date < end }

        func timeRange(timeZone: TimeZone = .current) -> String {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            func clock(_ date: Date) -> String {
                let time = calendar.dateComponents([.hour, .minute], from: date)
                return String(format: "%02d:%02d", time.hour!, time.minute!)
            }
            let nextDay = calendar.isDate(start, inSameDayAs: end) ? "" : "次日"
            return "\(clock(start))–\(nextDay)\(clock(end))"
        }
        func subtitle(timeZone: TimeZone = .current) -> String { "\(timeRange(timeZone: timeZone)) \(title)" }
    }

    struct Schedule: Equatable, Sendable {
        let programs: [CurrentProgram]

        struct Highlight: Equatable, Sendable {
            let program: CurrentProgram
            let isUpcoming: Bool

            func badge(isPlayingChannel: Bool) -> String {
                isUpcoming ? "即将播出" : (isPlayingChannel ? "当前节目" : "正在播出")
            }
            func subtitle(timeZone: TimeZone = .current) -> String {
                (isUpcoming ? "即将播出 · " : "") + program.subtitle(timeZone: timeZone)
            }
        }

        func programs(on day: Date, calendar: Calendar = .current) -> [CurrentProgram] {
            guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
            return programs.filter { $0.start < interval.end && $0.end > interval.start }
        }

        static func highlight(in programs: [CurrentProgram], at date: Date) -> Highlight? {
            if let current = programs.first(where: { $0.contains(date) }) {
                return Highlight(program: current, isUpcoming: false)
            }
            return programs.first(where: { $0.start > date }).map { Highlight(program: $0, isUpcoming: true) }
        }

        static func scrollTarget(in programs: [CurrentProgram], at date: Date) -> CurrentProgram? {
            highlight(in: programs, at: date)?.program ?? programs.last
        }
    }

    private struct Program: Codable, Hashable, Sendable {
        let start: Date
        let end: Date
        let title: String
    }

    private let programsByChannel: [String: [Program]]
    private let channelByAlias: [String: String]
    // Keep each source's IDs and aliases separate. Optional for pre-supplement cache compatibility.
    private let fallbackGuides: [ProgramGuide]?

    enum ParseError: LocalizedError {
        case invalidXML, emptyGuide
        var errorDescription: String? {
            switch self {
            case .invalidXML: "节目单不是有效的 XMLTV 文件。"
            case .emptyGuide: "节目单中没有有效节目。"
            }
        }
    }

    static func parse(_ data: Data) throws -> ProgramGuide {
        let reader = XMLReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), reader.validRoot else { throw ParseError.invalidXML }
        return try reader.snapshot()
    }

    func currentTitle(channel: Channel, at date: Date = Date()) -> String? {
        currentProgram(channel: channel, at: date)?.title
    }

    /// Earlier sources retain priority whenever they have a programme valid at the requested time.
    func supplementing(with fallback: ProgramGuide) -> ProgramGuide {
        ProgramGuide(programsByChannel: programsByChannel, channelByAlias: channelByAlias,
                     fallbackGuides: (fallbackGuides ?? []) + [fallback])
    }

    func currentProgram(channel: Channel, at date: Date = Date()) -> CurrentProgram? {
        if let current = localProgram(channel: channel, at: date) { return current }
        for fallback in fallbackGuides ?? [] {
            if let current = fallback.currentProgram(channel: channel, at: date) { return current }
        }
        return nil
    }

    /// Keep live programme matching strict. Only presentation falls forward to
    /// the next entry, using the same source-priority/clipping rules as the pane.
    func highlightedProgram(channel: Channel, at date: Date = Date(), calendar: Calendar = .current) -> Schedule.Highlight? {
        if let current = currentProgram(channel: channel, at: date) {
            return Schedule.Highlight(program: current, isUpcoming: false)
        }
        let today = schedule(channel: channel).programs(on: date, calendar: calendar)
        return Schedule.highlight(in: today, at: date)
    }

    /// Use the same source priority and overlap rules for the full schedule and current title.
    func schedule(channel: Channel) -> Schedule {
        let boundaries = programBoundaries(channel: channel).sorted()
        var programs: [CurrentProgram] = []
        var previous: CurrentProgram?
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            guard let program = currentProgram(channel: channel, at: start) else { previous = nil; continue }
            if previous == program, let last = programs.last, last.end == start {
                programs[programs.count - 1] = CurrentProgram(title: program.title, start: last.start, end: end)
            } else {
                programs.append(CurrentProgram(title: program.title, start: start, end: end))
            }
            previous = program
        }
        return Schedule(programs: programs)
    }

    private func programBoundaries(channel: Channel) -> Set<Date> {
        var result = Set<Date>()
        if let id = channelID(for: channel), let programs = programsByChannel[id] {
            for program in programs { result.insert(program.start); result.insert(program.end) }
        }
        for fallback in fallbackGuides ?? [] { result.formUnion(fallback.programBoundaries(channel: channel)) }
        return result
    }

    private func localProgram(channel: Channel, at date: Date) -> CurrentProgram? {
        guard let id = channelID(for: channel), let programs = programsByChannel[id] else { return nil }
        // Find the latest start first; overlapping entries still require a valid end.
        var lower = 0, upper = programs.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if programs[middle].start <= date { lower = middle + 1 } else { upper = middle }
        }
        var index = lower
        while index > 0 {
            index -= 1
            let program = programs[index]
            if date < program.end { return CurrentProgram(title: program.title, start: program.start, end: program.end) }
        }
        return nil
    }

    /// Include every source so a future primary programme can take over from its fallback on time.
    func nextChange(after date: Date) -> Date? {
        var next = fallbackGuides?.compactMap { $0.nextChange(after: date) }.min()
        for programs in programsByChannel.values {
            for program in programs {
                for boundary in [program.start, program.end] where boundary > date {
                    if next == nil || boundary < next! { next = boundary }
                }
            }
        }
        return next
    }

    private func channelID(for channel: Channel) -> String? {
        if let explicit = channel.epgID?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            if programsByChannel[explicit] != nil { return explicit }
            if let id = channelByAlias[Self.normalizedName(explicit)] { return id }
        }
        let name = channel.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if programsByChannel[name] != nil { return name }
        return channelByAlias[Self.normalizedName(name)]
    }

    private static func normalizedName(_ raw: String) -> String {
        var value = raw.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_Hans_CN")).uppercased()
        for (from, to) in [
            ("中央电视台", "CCTV"), ("央视", "CCTV"), ("中央", "CCTV"),
            ("中国教育电视台", "CETV"), ("福建东南卫视", "东南卫视"),
            ("上海东方卫视", "东方卫视"), ("上海卫视", "东方卫视"),
            ("CGTN阿拉伯语", "CGTN阿语"), ("CGTN西班牙语", "CGTN西语"),
            ("CGTN外语纪录", "CGTN纪录"), ("PLUS", "+"),
            ("超高清", ""), ("高清", ""), ("標清", ""), ("标清", ""),
            ("频道", ""), ("UHD", ""), ("FHD", ""), ("HD", ""), ("SD", "")
        ] { value = value.replacingOccurrences(of: from, with: to) }
        let result = String(value.filter { $0.isLetter || $0.isNumber || $0 == "+" })
        func region(_ suffix: String) -> String {
            if suffix == "E" || suffix.contains("欧") || suffix.contains("EU") { return "CCTV4欧洲" }
            if suffix == "A" || suffix.contains("美") || suffix.contains("AME") { return "CCTV4美洲" }
            return "CCTV4"
        }
        if result.hasPrefix("中文国际") || result.hasPrefix("国际亚洲") || result.hasPrefix("国际欧洲") || result.hasPrefix("国际美洲") {
            return region(result)
        }
        if result.hasPrefix("CCTV") {
            var suffix = String(result.dropFirst(4))
            // These are separate UHD channels, rather than CCTV-4 / CCTV-8 variants.
            if suffix.hasPrefix("4K") { return "CCTV4K" }
            if suffix.hasPrefix("8K") { return "CCTV8K" }
            if suffix.hasSuffix("4K") || suffix.hasSuffix("8K") { suffix = String(suffix.dropLast(2)) }
            let numbers = [("十七", 17), ("十六", 16), ("十五", 15), ("十四", 14), ("十三", 13), ("十二", 12), ("十一", 11), ("十", 10), ("九", 9), ("八", 8), ("七", 7), ("六", 6), ("五", 5), ("四", 4), ("三", 3), ("二", 2), ("一", 1)]
            if let number = numbers.first(where: { suffix.hasPrefix($0.0) }) {
                suffix = String(number.1) + suffix.dropFirst(number.0.count)
            }
            let digits = suffix.prefix(while: \.isNumber)
            if let number = Int(digits) {
                let remainder = String(suffix.dropFirst(digits.count))
                if number == 4 { return region(remainder) }
                if number == 5 && (remainder.hasPrefix("+") || remainder.contains("体育赛事")) { return "CCTV5+" }
                return "CCTV\(number)"
            }
            let names = [("体育赛事", "5+"), ("中文国际", "4"), ("国防军事", "7"), ("社会与法", "12"), ("奥林匹克", "16"), ("农业农村", "17"), ("综合", "1"), ("财经", "2"), ("综艺", "3"), ("体育", "5"), ("电影", "6"), ("电视剧", "8"), ("纪录", "9"), ("科教", "10"), ("戏曲", "11"), ("新闻", "13"), ("少儿", "14"), ("音乐", "15")]
            if suffix.hasPrefix("中文国际") { return region(suffix) }
            if let alias = names.first(where: { suffix.hasPrefix($0.0) }) { return "CCTV" + alias.1 }
        }
        if result.hasSuffix("卫视4K") || result.hasSuffix("卫视8K") { return String(result.dropLast(2)) }
        return result
    }

    private static func xmlDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = String(value.prefix(14))
        guard digits.utf8.count == 14, digits.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        let zone = value.dropFirst(14).trimmingCharacters(in: .whitespacesAndNewlines)
        let timeZone: TimeZone
        if zone.isEmpty { timeZone = .current }
        else if zone == "Z" { timeZone = TimeZone(secondsFromGMT: 0)! }
        else {
            let bytes = Array(zone.utf8)
            guard bytes.count == 5, bytes[0] == 43 || bytes[0] == 45,
                  bytes.dropFirst().allSatisfy({ (48...57).contains($0) }) else { return nil }
            let hours = Int(bytes[1] - 48) * 10 + Int(bytes[2] - 48)
            let minutes = Int(bytes[3] - 48) * 10 + Int(bytes[4] - 48)
            guard hours <= 23, minutes <= 59,
                  let parsed = TimeZone(secondsFromGMT: (hours * 3600 + minutes * 60) * (bytes[0] == 45 ? -1 : 1)) else { return nil }
            timeZone = parsed
        }
        let bytes = Array(digits.utf8)
        func number(_ offset: Int, _ count: Int) -> Int { bytes[offset..<(offset + count)].reduce(0) { $0 * 10 + Int($1 - 48) } }
        let year = number(0, 4), month = number(4, 2), day = number(6, 2)
        let hour = number(8, 2), minute = number(10, 2), second = number(12, 2)
        guard year > 0, (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 60 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(timeZone: timeZone, year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = calendar.date(from: components) else { return nil }
        let checked = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard checked.year == year, checked.month == month, checked.day == day,
              checked.hour == hour, checked.minute == minute, checked.second == second else { return nil }
        return date
    }

    private final class XMLReader: NSObject, XMLParserDelegate {
        private struct PendingProgram {
            let channel: String
            let start: Date
            let end: Date
            var title: String?
            var chineseTitle = false
        }
        private enum TextKind { case displayName, title }
        private var depth = 0
        private(set) var validRoot = false
        private var currentChannel: String?
        private var pendingProgram: PendingProgram?
        private var programs: [String: [Program]] = [:]
        private var displayAliases: [(String, String)] = []
        private var textKind: TextKind?
        private var textDepth = 0
        private var text = ""
        private var chineseText = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
            depth += 1
            if depth == 1 {
                validRoot = elementName == "tv"
                if !validRoot { parser.abortParsing() }
            } else if depth == 2 && elementName == "channel" {
                currentChannel = attributes["id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if depth == 2 && elementName == "programme" {
                pendingProgram = nil
                if let id = attributes["channel"]?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
                   let start = ProgramGuide.xmlDate(attributes["start"]), let end = ProgramGuide.xmlDate(attributes["stop"]), start < end {
                    pendingProgram = PendingProgram(channel: id, start: start, end: end)
                }
            } else if depth == 3 && ((elementName == "display-name" && currentChannel != nil) || (elementName == "title" && pendingProgram != nil)) {
                textKind = elementName == "display-name" ? .displayName : .title
                textDepth = depth; text = ""
                chineseText = (attributes["lang"] ?? "").lowercased().hasPrefix("zh")
            }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if textKind != nil { text += string }
        }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if textKind != nil, let value = String(data: CDATABlock, encoding: .utf8) { text += value }
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if depth == textDepth, let kind = textKind {
                let value = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                if !value.isEmpty {
                    switch kind {
                    case .displayName:
                        if let id = currentChannel, !id.isEmpty { displayAliases.append((ProgramGuide.normalizedName(value), id)) }
                    case .title:
                        if pendingProgram?.title == nil || (chineseText && pendingProgram?.chineseTitle == false) {
                            pendingProgram?.title = value; pendingProgram?.chineseTitle = chineseText
                        }
                    }
                }
                textKind = nil; text = ""
            }
            if depth == 2 && elementName == "programme" {
                if let pending = pendingProgram, let title = pending.title {
                    programs[pending.channel, default: []].append(Program(start: pending.start, end: pending.end, title: title))
                }
                pendingProgram = nil
            } else if depth == 2 && elementName == "channel" { currentChannel = nil }
            depth -= 1
        }
        func snapshot() throws -> ProgramGuide {
            guard !programs.isEmpty else { throw ParseError.emptyGuide }
            var sortedPrograms: [String: [Program]] = [:]
            var aliases: [String: String] = [:]
            for id in programs.keys.sorted() {
                sortedPrograms[id] = Set(programs[id]!).sorted {
                    if $0.start != $1.start { return $0.start < $1.start }
                    if $0.end != $1.end { return $0.end < $1.end }
                    return $0.title < $1.title
                }
                let alias = ProgramGuide.normalizedName(id)
                if !alias.isEmpty && aliases[alias] == nil { aliases[alias] = id }
            }
            // Display-name aliases take priority over unrelated opaque ID aliases.
            for (alias, id) in displayAliases where !alias.isEmpty && sortedPrograms[id] != nil { aliases[alias] = id }
            return ProgramGuide(programsByChannel: sortedPrograms, channelByAlias: aliases, fallbackGuides: nil)
        }
    }
}
