import Foundation

struct ProgramGuideCacheEntry: Codable, Sendable {
    let fetchedAt: Date
    let guide: ProgramGuide
}

/// Downloading, XML parsing and cache IO stay off the UI thread.
actor ProgramGuideRepository {
    static let shared = ProgramGuideRepository()
    static let refreshInterval: TimeInterval = 4 * 60 * 60
    private static let sources = [
        URL(string: "https://github.com/TvWasm/autoEPG/releases/latest/download/epg.xml")!,
        URL(string: "http://epg.51zmt.top:8000/e.xml.gz")!
    ]
    private let cacheURL: URL
    private let session: URLSession
    private var memoryCache: ProgramGuideCacheEntry?
    private var inFlight: Task<ProgramGuideCacheEntry, Error>?

    init(cacheURL: URL? = nil) {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.cacheURL = cacheURL ?? directory.appendingPathComponent("SofaTV", isDirectory: true)
            .appendingPathComponent("program-guide-v1.json")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpMaximumConnectionsPerHost = 2
        self.session = URLSession(configuration: configuration)
    }

    func cachedGuide() -> ProgramGuideCacheEntry? {
        if let memoryCache { return memoryCache }
        guard let size = try? cacheURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 32 * 1_024 * 1_024,
              let data = try? Data(contentsOf: cacheURL, options: .mappedIfSafe),
              let entry = try? JSONDecoder().decode(ProgramGuideCacheEntry.self, from: data) else { return nil }
        memoryCache = entry
        return entry
    }

    /// Multiple windows share a single download rather than fetching once per row.
    func refresh() async throws -> ProgramGuideCacheEntry {
        if let inFlight { return try await inFlight.value }
        let task = Task { try await downloadGuide() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    private func downloadGuide() async throws -> ProgramGuideCacheEntry {
        var failure: Error = URLError(.cannotLoadFromNetwork)
        for source in Self.sources {
            do {
                try Task.checkCancellation()
                var request = URLRequest(url: source)
                request.setValue("SofaTV/0.0.1", forHTTPHeaderField: "User-Agent")
                let (file, response) = try await session.download(for: request)
                defer { try? FileManager.default.removeItem(at: file) }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= ProgramGuidePayload.maximumDownloadBytes else {
                    throw ProgramGuidePayload.Failure.tooLarge
                }
                let xml = try ProgramGuidePayload.xmlData(from: Data(contentsOf: file, options: .mappedIfSafe))
                let guide = try ProgramGuide.parse(xml)
                let now = Date()
                // A successfully parsed but expired feed must not replace usable data.
                guard guide.nextChange(after: now) != nil else { throw URLError(.resourceUnavailable) }
                let entry = ProgramGuideCacheEntry(fetchedAt: now, guide: guide)
                memoryCache = entry
                if let data = try? JSONEncoder().encode(entry) {
                    try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: cacheURL, options: .atomic)
                }
                return entry
            } catch is CancellationError { throw CancellationError() }
            catch { failure = error }
        }
        throw failure
    }
}
