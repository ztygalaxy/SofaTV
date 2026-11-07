import Foundation

/// User choices are separate from remote catalogues. Keys use the provider's
/// channel ID when available, otherwise the original group/name, never the URL.
struct ChannelPersonalization: Codable, Equatable, Sendable {
    struct Override: Codable, Equatable, Sendable {
        var name: String?
        var group: String?
    }
    var overrides: [String: Override] = [:]
    var order: [String] = []
    var groupOrder: [String] = []
    var favoriteKeys: Set<String> = []
    var recent: [String] = []
    var volumes: [String: Float] = [:]
    var lines: [String: String] = [:]

    func applying(to channels: [Channel]) -> [Channel] {
        let positions = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return channels.enumerated().sorted {
            let left = positions[$0.element.preferenceKey] ?? Int.max
            let right = positions[$1.element.preferenceKey] ?? Int.max
            return left == right ? $0.offset < $1.offset : left < right
        }.map { _, channel in
            var channel = channel
            channel.customName = overrides[channel.preferenceKey]?.name
            channel.customGroup = overrides[channel.preferenceKey]?.group
            return channel
        }
    }
    func groups(in channels: [Channel]) -> [String] {
        let positions = Dictionary(groupOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return Set(channels.map(\.displayGroup)).sorted {
            let left = positions[$0] ?? Int.max, right = positions[$1] ?? Int.max
            return left == right ? $0.localizedStandardCompare($1) == .orderedAscending : left < right
        }
    }
    mutating func customize(_ channel: Channel, name: String, group: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = group.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = Override(name: name.isEmpty || name == channel.name ? nil : name,
                             group: group.isEmpty || group == channel.group ? nil : group)
        overrides[channel.preferenceKey] = value.name == nil && value.group == nil ? nil : value
    }
    mutating func record(_ channel: Channel) {
        recent.removeAll { $0 == channel.preferenceKey }
        recent.insert(channel.preferenceKey, at: 0)
        recent = Array(recent.prefix(20))
    }
    mutating func migrateKey(from old: String, to new: String) {
        guard old != new else { return }
        if let value = overrides.removeValue(forKey: old), overrides[new] == nil { overrides[new] = value }
        if let value = volumes.removeValue(forKey: old), volumes[new] == nil { volumes[new] = value }
        if let value = lines.removeValue(forKey: old), lines[new] == nil { lines[new] = value }
        if favoriteKeys.remove(old) != nil { favoriteKeys.insert(new) }
        func replacing(_ values: [String]) -> [String] {
            var seen: Set<String> = []
            return values.map { $0 == old ? new : $0 }.filter { seen.insert($0).inserted }
        }
        order = replacing(order); recent = replacing(recent)
    }
}

struct ChannelConfigurationBackup: Codable {
    let version: Int
    let sources: [ChannelList]
    let personalization: ChannelPersonalization

    init(sources: [ChannelList], personalization: ChannelPersonalization) {
        version = 1; self.sources = sources; self.personalization = personalization
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 32 * 1_024 * 1_024 else { throw BackupError.invalid }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version == 1, Set(value.sources.map(\.id)).count == value.sources.count,
              value.sources.allSatisfy({ list in
                  (list.kind != .online || list.remoteURL != nil) && list.channels.allSatisfy { channel in
                      channel.sources.allSatisfy { ["http", "https", "webview"].contains($0.scheme?.lowercased() ?? "") }
                  }
              }) else { throw BackupError.invalid }
        return value
    }
    enum BackupError: LocalizedError {
        case invalid
        var errorDescription: String? { "这不是受支持的沙发电视频道配置文件。" }
    }
}
