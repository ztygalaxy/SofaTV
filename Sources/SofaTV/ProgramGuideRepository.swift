import Foundation

struct ProgramGuideCacheEntry: Codable, Sendable {
    let fetchedAt: Date
    let guide: ProgramGuide
}

/// Downloading, XML parsing and cache IO stay off the UI thread.
actor ProgramGuideRepository {
    static let shared = ProgramGuideRepository()
    static let refreshInterval: TimeInterval = 4 * 60 * 60
    private static let defaultSources = [
        URL(string: "https://github.com/TvWasm/autoEPG/releases/latest/download/epg.xml")!,
        URL(string: "http://epg.51zmt.top:8000/e.xml.gz")!
    ]
    typealias PayloadLoader = @Sendable (URL) async throws -> Data
    private struct SourceResult: Sendable {
        let index: Int
        let result: Result<ProgramGuide, Error>
    }
    private let sources: [URL]
    private let payloadLoader: PayloadLoader?
    private let cacheURL: URL
    private let session: URLSession
    private var memoryCache: ProgramGuideCacheEntry?
    private var inFlight: Task<ProgramGuideCacheEntry, Error>?

    init(cacheURL: URL? = nil, sources: [URL]? = nil, payloadLoader: PayloadLoader? = nil) {
        self.sources = sources ?? Self.defaultSources
        self.payloadLoader = payloadLoader
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.cacheURL = cacheURL ?? directory.appendingPathComponent("SofaTV", isDirectory: true)
            .appendingPathComponent("program-guide-v1.json")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.urlCache = nil
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
        // Fetch every complete source on each refresh; a partially valid primary must not block backup data.
        let results = await withTaskGroup(of: SourceResult.self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    do { return SourceResult(index: index, result: .success(try await self.fetchGuide(from: source))) }
                    catch { return SourceResult(index: index, result: .failure(error)) }
                }
            }
            var results: [SourceResult] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.index < $1.index }
        }
        try Task.checkCancellation()
        var combined: ProgramGuide?
        var failure: Error = URLError(.cannotLoadFromNetwork)
        for source in results {
            switch source.result {
            case .success(let guide):
                combined = combined.map { $0.supplementing(with: guide) } ?? guide
            case .failure(let error):
                if error is CancellationError { throw error }
                failure = error
            }
        }
        guard let guide = combined else { throw failure }
        let entry = ProgramGuideCacheEntry(fetchedAt: Date(), guide: guide)
        memoryCache = entry
        if let data = try? JSONEncoder().encode(entry) {
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: .atomic)
        }
        return entry
    }

    private func fetchGuide(from source: URL) async throws -> ProgramGuide {
        try Task.checkCancellation()
        let payload: Data
        if let payloadLoader { payload = try await payloadLoader(source) }
        else { payload = try await downloadPayload(from: source) }
        try Task.checkCancellation()
        guard !payload.isEmpty, payload.count <= ProgramGuidePayload.maximumDownloadBytes else {
            throw ProgramGuidePayload.Failure.tooLarge
        }
        let guide = try ProgramGuide.parse(ProgramGuidePayload.xmlData(from: payload))
        // Completely expired data must not replace a still-useful cached guide.
        guard guide.nextChange(after: Date()) != nil else { throw URLError(.resourceUnavailable) }
        return guide
    }

    private func downloadPayload(from source: URL) async throws -> Data {
        var request = URLRequest(url: source, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("SofaTV/0.0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (file, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= ProgramGuidePayload.maximumDownloadBytes else {
            throw ProgramGuidePayload.Failure.tooLarge
        }
        return try Data(contentsOf: file, options: .mappedIfSafe)
    }
}
