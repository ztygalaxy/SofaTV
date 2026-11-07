import Foundation

enum OnlineChannelSource {
    static let defaultURL = URL(string: "https://raw.githubusercontent.com/TvWasm/cjs/main/cmg.m3u")!

    // Keep existing source IDs and cached channels, but never add a source on launch.
    static func migrate(_ lists: [ChannelList]) -> [ChannelList] {
        lists.map { list in
            guard list.kind == .builtIn else { return list }
            var migrated = list
            migrated.kind = .online; migrated.name = "默认频道"; migrated.detail = defaultURL.absoluteString
            return migrated
        }
    }

    /// Only translate known playlist references. Never download or execute remote plugins.
    static func parse(_ text: String) throws -> [Channel] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\u{feff}")))
        guard !text.lowercased().hasPrefix("<") else { throw SourceError.invalidPlaylist }
        return try ChannelCatalog.parse(text).map { channel in
            let sources = try channel.sources.map(playableURL)
            var result = channel
            result.url = sources[0]
            var seen: Set<URL> = []
            let alternatives = Array(sources.filter { seen.insert($0).inserted }.dropFirst())
            result.alternatives = alternatives.isEmpty ? nil : alternatives
            return result
        }
    }

    private static func playableURL(_ url: URL) throws -> URL {
        guard url.pathExtension.lowercased() == "cjs" else { return url }
        guard url.scheme == "https", url.host?.lowercased() == "raw.githubusercontent.com",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = components.queryItems?.first(where: { $0.name == "id" })?.value, !id.isEmpty else {
            throw SourceError.unsupportedPlugin
        }
        switch url.path.lowercased() {
        case "/tvwasm/cjs/main/cmg.cjs":
            guard id.utf8.allSatisfy({ (48...57).contains($0) }) else { throw SourceError.unsupportedPlugin }
            return URL(string: "webview://https://yangshipin.cn/tv/home?pid=" + id)!
        case "/tvwasm/cjs/main/cctv.cjs":
            guard id.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) }) else {
                throw SourceError.unsupportedPlugin
            }
            return URL(string: "webview://https://tv.cctv.com/live/" + id + "/index.shtml")!
        default: throw SourceError.unsupportedPlugin
        }
    }

    enum SourceError: LocalizedError {
        case invalidPlaylist, unsupportedPlugin
        var errorDescription: String? {
            switch self {
            case .invalidPlaylist: "下载的内容不是有效的频道列表。"
            case .unsupportedPlugin: "频道列表包含尚不支持的插件地址，已保留原有频道。"
            }
        }
    }
}

struct OnlineChannelUpdate: Sendable {
    let channels: [Channel]?
    let checkedAt: Date
    let eTag: String?
    let lastModified: String?

    func applying(to list: ChannelList) -> ChannelList {
        var result = list
        if let channels {
            result.channels = list.applyingRemovals(to: channels)
            result.importedAt = checkedAt
        }
        result.lastCheckedAt = checkedAt
        result.eTag = eTag; result.lastModified = lastModified
        return result
    }
}

actor OnlineChannelRepository {
    static let shared = OnlineChannelRepository()
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let loader: Loader

    init(loader: Loader? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        self.loader = loader ?? { request in
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return (data, response)
        }
    }

    func refresh(_ list: ChannelList, force: Bool = false) async throws -> OnlineChannelUpdate {
        guard let url = list.remoteURL else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("SofaTV", forHTTPHeaderField: "User-Agent")
        if !force, list.lastCheckedAt != nil {
            request.setValue(list.eTag, forHTTPHeaderField: "If-None-Match")
            request.setValue(list.lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        let (data, response) = try await loader(request)
        let notModified = response.statusCode == 304
        guard response.statusCode == 200 || (notModified && !force && list.lastCheckedAt != nil) else {
            throw URLError(.badServerResponse)
        }
        let channels: [Channel]?
        if notModified { channels = nil }
        else {
            guard data.count <= 5 * 1_024 * 1_024, let text = String(data: data, encoding: .utf8) else {
                throw OnlineChannelSource.SourceError.invalidPlaylist
            }
            channels = try OnlineChannelSource.parse(text)
        }
        return OnlineChannelUpdate(channels: channels, checkedAt: Date(),
            eTag: response.value(forHTTPHeaderField: "ETag") ?? (notModified ? list.eTag : nil),
            lastModified: response.value(forHTTPHeaderField: "Last-Modified") ?? (notModified ? list.lastModified : nil))
    }
}
