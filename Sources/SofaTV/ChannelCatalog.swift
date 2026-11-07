import Foundation

struct Channel: Identifiable, Codable, Hashable, Sendable {
    struct Identity: Hashable, Codable, Sendable {
        let name: String
        let group: String
        init(_ channel: Channel) { name = channel.name; group = channel.group }
    }
    var id: String { url.absoluteString }
    var identity: Identity { Identity(self) }
    var alternatives: [URL]? = nil
    var sources: [URL] { [url] + (alternatives ?? []) }
    var name: String
    var group: String
    var url: URL
    var epgID: String? = nil
    // Display overrides never change the source identity used by EPG and imports.
    var customName: String? = nil
    var customGroup: String? = nil
    var displayName: String { customName ?? name }
    var displayGroup: String { customGroup ?? group }
    var preferenceKey: String {
        if let id = epgID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty { return "epg:" + id }
        return "name:\(group.utf8.count):\(group)\(name.utf8.count):\(name)"
    }
    func matches(_ query: String) -> Bool {
        query.isEmpty || [name, group, displayName, displayGroup].contains { $0.localizedCaseInsensitiveContains(query) }
    }

    func removing(_ source: URL) -> Channel? {
        let remaining = sources.filter { $0 != source }
        guard let first = remaining.first else { return nil }
        return Channel(
            alternatives: remaining.count > 1 ? Array(remaining.dropFirst()) : nil,
            name: name,
            group: group,
            url: first,
            epgID: epgID
        )
    }
}

struct ChannelList: Identifiable, Codable, Hashable, Sendable {
    // builtIn remains decodable for migration from earlier versions.
    enum Kind: String, Codable, Sendable { case builtIn, file, online, legacy }
    struct RemovedSource: Codable, Hashable, Sendable {
        let channel: Channel.Identity
        let url: URL
    }
    let id: String
    var name: String
    var detail: String
    var kind: Kind
    var importedAt: Date
    var channels: [Channel]
    var lastCheckedAt: Date? = nil
    var eTag: String? = nil
    var lastModified: String? = nil
    var removedChannels: Set<Channel.Identity>? = nil
    var removedGroups: Set<String>? = nil
    var removedSources: Set<RemovedSource>? = nil

    var remoteURL: URL? {
        guard kind == .online, let url = URL(string: detail),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }
    var hasRemovals: Bool {
        removedChannels?.isEmpty == false || removedGroups?.isEmpty == false || removedSources?.isEmpty == false
    }
    func applyingRemovals(to channels: [Channel]) -> [Channel] {
        channels.compactMap { channel in
            guard removedChannels?.contains(channel.identity) != true,
                  removedGroups?.contains(channel.group) != true else { return nil }
            return channel.sources.reduce(Optional(channel)) { remaining, url in
                removedSources?.contains(RemovedSource(channel: channel.identity, url: url)) == true
                    ? remaining?.removing(url) : remaining
            }
        }
    }
    static func file(_ url: URL) -> ChannelList {
        ChannelList(id: "file:" + url.standardizedFileURL.path, name: url.deletingPathExtension().lastPathComponent, detail: url.lastPathComponent, kind: .file, importedAt: Date(), channels: [])
    }
    static func online(_ url: URL) -> ChannelList {
        ChannelList(id: "online:" + url.absoluteString, name: url.host ?? "在线频道列表", detail: url.absoluteString, kind: .online, importedAt: Date(), channels: [])
    }
    static func legacy(_ channels: [Channel]) -> ChannelList {
        ChannelList(id: "legacy", name: "现有频道", detail: "升级前保存的频道", kind: .legacy, importedAt: Date(), channels: channels)
    }
}

enum ChannelCatalog {
    private typealias ChannelKey = Channel.Identity

    static func parse(_ text: String) throws -> [Channel] {
        var result: [Channel] = []; var name = ""; var group = "未分组"; var epgID: String?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXTINF:") {
                name = line.components(separatedBy: ",").dropFirst().joined(separator: ",")
                if let value = attribute("group-title", in: line) { group = value }
                epgID = attribute("tvg-id", in: line)
            } else if !line.isEmpty && !line.hasPrefix("#") {
                let parts = line.components(separatedBy: ",")
                if parts.count > 1 && parts[1] == "#genre#" { group = parts[0]; epgID = nil; continue }
                let address = parts.count > 1 ? parts.dropFirst().joined(separator: ",") : line
                if let url = URL(string: address), ["http", "https", "webview"].contains(url.scheme?.lowercased() ?? "") {
                    result.append(Channel(name: parts.count > 1 ? parts[0] : (name.isEmpty ? url.lastPathComponent : name), group: group, url: url, epgID: epgID)); name = ""
                }
                epgID = nil
            }
        }
        result = merge(result, into: [])
        guard !result.isEmpty else { throw NSError(domain: "SofaTV", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有找到可播放的 HTTP/HTTPS 频道，请导入 M3U 或 TXT 列表。直接播放地址请使用“打开直播”。"]) }
        return result
    }

    private static func attribute(_ name: String, in line: String) -> String? {
        let pattern = #"(?:^|\s)"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s,]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        for index in 1...3 {
            if let range = Range(match.range(at: index), in: line) {
                let value = line[range].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    static func merge(_ lists: [ChannelList]) -> [Channel] {
        var merged: [Channel] = []
        var positions: [ChannelKey: Int] = [:]
        var knownSources: [ChannelKey: Set<URL>] = [:]
        for list in lists {
            append(list.channels, to: &merged, positions: &positions, knownSources: &knownSources)
        }
        return merged
    }

    static func merge(_ incoming: [Channel], into existing: [Channel]) -> [Channel] {
        var merged = existing
        var positions: [ChannelKey: Int] = [:]
        var knownSources: [ChannelKey: Set<URL>] = [:]
        for (index, channel) in merged.enumerated() {
            let key = ChannelKey(channel)
            // Older saved libraries can contain duplicates. Keep their existing
            // order and use the first one, matching the previous behaviour.
            guard positions[key] == nil else { continue }
            positions[key] = index
            knownSources[key] = Set(channel.sources)
        }
        append(incoming, to: &merged, positions: &positions, knownSources: &knownSources)
        return merged
    }

    /// Merges by name and group in linear time. This path runs for every import,
    /// so repeatedly searching `merged` here made large channel lists stall the UI.
    private static func append(_ incoming: [Channel], to merged: inout [Channel], positions: inout [ChannelKey: Int], knownSources: inout [ChannelKey: Set<URL>]) {
        for channel in incoming {
            let key = ChannelKey(channel)
            if let index = positions[key] {
                if merged[index].epgID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    merged[index].epgID = channel.epgID
                }
                var sources = knownSources[key] ?? Set(merged[index].sources)
                let additions = channel.sources.filter { sources.insert($0).inserted }
                knownSources[key] = sources
                if !additions.isEmpty { merged[index].alternatives = (merged[index].alternatives ?? []) + additions }
            } else {
                positions[key] = merged.count
                knownSources[key] = Set(channel.sources)
                merged.append(channel)
            }
        }
    }

    static func deletingChannel(_ channel: Channel, from lists: [ChannelList], inList listID: String? = nil) -> [ChannelList] {
        lists.map { list in
            guard listID == nil || list.id == listID else { return list }
            var list = list
            if list.remoteURL != nil { list.removedChannels = (list.removedChannels ?? []).union([channel.identity]) }
            list.channels.removeAll { $0.name == channel.name && $0.group == channel.group }
            return list
        }
    }

    static func deletingSource(_ source: URL, from channel: Channel, in lists: [ChannelList], inList listID: String? = nil) -> [ChannelList] {
        lists.map { list in
            guard listID == nil || list.id == listID else { return list }
            var list = list
            if list.remoteURL != nil {
                list.removedSources = (list.removedSources ?? []).union([.init(channel: channel.identity, url: source)])
            }
            list.channels = list.channels.compactMap { candidate in
                guard candidate.name == channel.name, candidate.group == channel.group else { return candidate }
                return candidate.removing(source)
            }
            return list
        }
    }

    static func deletingGroup(_ group: String, from lists: [ChannelList]) -> [ChannelList] {
        lists.map { list in
            var list = list
            if list.remoteURL != nil { list.removedGroups = (list.removedGroups ?? []).union([group]) }
            list.channels.removeAll { $0.group == group }; return list
        }
    }
}
