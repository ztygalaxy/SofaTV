@preconcurrency import AVFoundation
@preconcurrency import Network
import Foundation

struct CmgSessionState: Sendable {
    let tag: String
    let location: String
    let timestamp: UInt64
    let nativeTrace: String
    let updates: String
    let base: UInt64
}

/// AVPlayer uses regular loopback HTTP for HLS; every upstream URL is an opaque registered route.
final class CmgAssetLoader: @unchecked Sendable {
    var onDiagnostic: (@Sendable (String) -> Void)?
    var onBelowRequestedResolution: (@Sendable (HlsResolution, HlsResolution) -> Void)?
    private let queue = DispatchQueue(label: "SofaTV.CmgAssetLoader")
    private let state: CmgSessionState?
    private let quality: Int
    private var highestH5eResolution: HlsResolution?
    private var runtime: CmgRuntime?
    private var h5eRuntime: H5eRuntime?
    private let session: URLSession
    private var cache = CmgSegmentCache()
    private struct Reply { let connection: NWConnection; let head: Bool }
    private var pending: [URL: [Reply]] = [:]
    private var downloads: [URL: URLSessionDataTask] = [:]
    private var segmentCount = 0
    private var rootURL: URL?
    private var routeOrder: [String] = []
    private var listener: NWListener?
    private var routes: [String: URL] = [:]
    private var baseURL: URL?
    private var cancelled = false
    init(state: CmgSessionState? = nil, cookies: [HTTPCookie], quality: Int = 0) {
        self.state = state
        self.quality = quality
        let config = URLSessionConfiguration.ephemeral
        let referer = state?.location ?? "https://tv.cctv.com/"
        let page = URLComponents(string: referer)
        let origin = "\(page?.scheme ?? "https")://\(page?.host ?? "tv.cctv.com")"
        config.httpAdditionalHeaders = ["Referer": referer, "Origin": origin, "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15"]
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        // Ephemeral configurations already provide an in-memory cookie jar. Keep
        // channel cookies there instead of opening a persistent group container.
        for cookie in cookies { config.httpCookieStorage?.setCookie(cookie) }
        session = URLSession(configuration: config)
    }
    deinit { listener?.cancel(); session.invalidateAndCancel() }
    func cancel() {
        queue.async { [self] in
            cancelled = true; listener?.cancel(); listener = nil; session.invalidateAndCancel()
            for task in downloads.values { task.cancel() }
            for replies in pending.values { for reply in replies { reply.connection.cancel() } }
            downloads.removeAll(); pending.removeAll(); cache.removeAll(); routes.removeAll(); routeOrder.removeAll()
        }
    }
    func start(_ url: URL, completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        queue.async { [self] in
            rootURL = url
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self, weak listener] status in
                    guard let self, !self.cancelled else { return }
                    switch status {
                    case .ready:
                        guard let port = listener?.port else { return }
                        self.baseURL = URL(string: "http://127.0.0.1:\(port.rawValue)")!
                        self.onDiagnostic?("本机直播通道已就绪")
                        completion(.success(self.register(url)))
                    case .failed(let error): completion(.failure(error))
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    guard let self else { connection.cancel(); return }
                    connection.start(queue: self.queue); self.receive(connection, accumulated: Data())
                }
                listener.start(queue: queue)
            } catch { completion(.failure(error)) }
        }
    }
    private func register(_ url: URL) -> URL {
        if let existing = routes.first(where: { $0.value == url }) { return baseURL!.appendingPathComponent(existing.key) }
        let path = UUID().uuidString + "." + (url.pathExtension.isEmpty ? "bin" : url.pathExtension)
        routes[path] = url; routeOrder.append(path)
        // Retain all playlist endpoints, but bound the rolling segment route map.
        while routeOrder.count > 512 {
            let expired = routeOrder.removeFirst()
            if let remote = routes[expired], remote != rootURL, remote.pathExtension.lowercased() != "m3u8", pending[remote] == nil { routes.removeValue(forKey: expired) }
        }
        return baseURL!.appendingPathComponent(path)
    }
    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            guard let self, !self.cancelled, error == nil else { connection.cancel(); return }
            let request = accumulated + (data ?? Data())
            guard request.count <= 16384 else { connection.cancel(); return }
            guard let text = String(data: request, encoding: .utf8), text.contains("\r\n\r\n") else {
                if complete { connection.cancel() } else { self.receive(connection, accumulated: request) }; return
            }
            let parts = text.components(separatedBy: "\r\n")[0].split(separator: " ")
            guard parts.count == 3, parts[0] == "GET" || parts[0] == "HEAD", let remote = self.routes[String(parts[1].dropFirst())] else { self.send(connection, status: "404 Not Found", data: Data(), type: "text/plain"); return }
            if let cached = self.cache.value(for: remote) { self.send(connection, data: cached, type: "video/mp2t", head: parts[0] == "HEAD"); return }
            let reply = Reply(connection: connection, head: parts[0] == "HEAD")
            if self.pending[remote] != nil { self.pending[remote]?.append(reply); return }
            self.pending[remote] = [reply]
            let started = ProcessInfo.processInfo.systemUptime
            let task = self.session.dataTask(with: remote) { [weak self] data, response, error in
                guard let self else { connection.cancel(); return }
                let downloaded = ProcessInfo.processInfo.systemUptime
                self.queue.async { [self] in
                    downloads.removeValue(forKey: remote)
                    guard !self.cancelled else { connection.cancel(); return }
                    do {
                        if let error { throw error }
                        guard let data, data.count <= 32 * 1024 * 1024, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw CmgError.message("视频分段下载失败") }
                        let result: Data; let type: String
                        if String(data: data.prefix(16), encoding: .utf8)?.hasPrefix("#EXTM3U") == true {
                            if state == nil {
                                let variants = HlsQualitySelection.variants(data, base: response?.url ?? remote)
                                if variants.count > 1 { selectH5eVariant(variants, master: remote); return }
                            }
                            result = try Self.rewrite(data, base: response?.url ?? remote, wrap: register)
                            type = "application/vnd.apple.mpegurl"
                        } else if data.first == 0x47 {
                            let decryptStarted = ProcessInfo.processInfo.systemUptime
                            if let state {
                                if runtime == nil {
                                    let crypto = try CmgRuntime()
                                    try crypto.configure(tag: state.tag, location: state.location, timestamp: state.timestamp, nativeTrace: state.nativeTrace, updates: state.updates, base: state.base)
                                    runtime = crypto
                                    onDiagnostic?("央视频解密会话已配置，启用分段和关键帧边界刷新")
                                }
                                guard let runtime else { throw CmgError.message("解密库未初始化") }
                                result = try runtime.transformSegment(data)
                            } else {
                                if h5eRuntime == nil {
                                    h5eRuntime = try H5eRuntime()
                                    onDiagnostic?("央视 H5E 原生解密已就绪")
                                }
                                guard let h5eRuntime else { throw H5eError.message("央视解密库未初始化") }
                                result = try h5eRuntime.transformSegment(data)
                            }
                            let decryptMs = Int((ProcessInfo.processInfo.systemUptime - decryptStarted) * 1000)
                            type = "video/mp2t"
                            segmentCount += 1
                            let downloadMs = Int((downloaded - started) * 1000)
                            let detail = runtime.map { " / \($0.lastVCLCount) 帧 / 边界刷新 \($0.lastBoundaryRestarts)" } ?? " / 央视 H5E"
                            onDiagnostic?("分段 \(segmentCount)：下载 \(downloadMs) 毫秒 / 解密 \(decryptMs) 毫秒" + detail)
                            cache.insert(result, for: remote)
                        } else { throw CmgError.message("当前视频分段格式暂不支持") }
                        replyAll(remote, data: result, type: type)
                    } catch {
                        onDiagnostic?("原生分段处理失败：" + error.localizedDescription)
                        replyAll(remote, status: "502 Bad Gateway", data: Data(error.localizedDescription.utf8), type: "text/plain")
                    }
                }
            }
            self.downloads[remote] = task; task.resume()
        }
    }
    private func selectH5eVariant(_ variants: [HlsVariant], master: URL) {
        highestH5eResolution = variants.compactMap(\.advertised).max { $0.pixels < $1.pixels }
        let ordered = HlsQualitySelection.ordered(variants, quality: quality)
        probeH5eVariants(ordered, available: [], fallback: ordered[0], master: master, deadline: Date().addingTimeInterval(10))
    }
    private func finishH5eSelection(_ probe: HlsVariantProbe, master: URL) {
        if quality == 0, let actual = probe.actual, let expected = highestH5eResolution,
           actual.pixels < expected.pixels, let onBelowRequestedResolution {
            onBelowRequestedResolution(actual, expected)
            replyAll(master, status: "503 Service Unavailable", data: Data(), type: "text/plain")
            return
        }
        let resolution = probe.actual?.description ?? probe.variant.advertised?.description ?? "未知"
        onDiagnostic?("央视清晰度已选择：\(resolution)")
        let playlist = "#EXTM3U\n" + probe.variant.info + "\n" + register(probe.variant.url).absoluteString + "\n"
        replyAll(master, data: Data(playlist.utf8), type: "application/vnd.apple.mpegurl")
    }
    private func probeH5eVariants(_ remaining: [HlsVariant], available: [HlsVariantProbe], fallback: HlsVariant, master: URL, deadline: Date) {
        guard !cancelled else { return }
        guard let variant = remaining.first, Date() < deadline else {
            finishH5eSelection(HlsQualitySelection.best(available, quality: quality) ?? HlsVariantProbe(variant: fallback, actual: nil), master: master)
            return
        }
        var request = URLRequest(url: variant.url); request.timeoutInterval = 3
        session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            self.queue.async { [self] in
                guard !cancelled else { return }
                guard let data, let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                      let text = String(data: data, encoding: .utf8),
                      let segment = text.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).first(where: { !$0.isEmpty && !$0.hasPrefix("#") }),
                      let segmentURL = URL(string: segment, relativeTo: response.url ?? variant.url)?.absoluteURL,
                      ["http", "https"].contains(segmentURL.scheme) else {
                    probeH5eVariants(Array(remaining.dropFirst()), available: available, fallback: fallback, master: master, deadline: deadline)
                    return
                }
                var sampleRequest = URLRequest(url: segmentURL); sampleRequest.timeoutInterval = 3
                sampleRequest.setValue("bytes=0-393215", forHTTPHeaderField: "Range")
                session.dataTask(with: sampleRequest) { [weak self] data, response, _ in
                    guard let self else { return }
                    self.queue.async { [self] in
                        guard !cancelled else { return }
                        let valid = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } == true
                        let actual = valid ? data.flatMap { HlsQualitySelection.resolution(in: $0) } : nil
                        let probe = HlsVariantProbe(variant: variant, actual: actual)
                        if probe.matchesAdvertised { finishH5eSelection(probe, master: master); return }
                        if let expected = variant.advertised, let actual {
                            onDiagnostic?("线路标注 \(expected.description)，实际 \(actual.description)，检查其他清晰度")
                        }
                        probeH5eVariants(Array(remaining.dropFirst()), available: available + [probe], fallback: fallback, master: master, deadline: deadline)
                    }
                }.resume()
            }
        }.resume()
    }
    private func replyAll(_ remote: URL, status: String = "200 OK", data: Data, type: String) {
        let replies = pending.removeValue(forKey: remote) ?? []
        for reply in replies { send(reply.connection, status: status, data: data, type: type, head: reply.head) }
    }
    private func send(_ connection: NWConnection, status: String = "200 OK", data: Data, type: String, head: Bool = false) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(data.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        connection.send(content: Data(header.utf8) + (head ? Data() : data), completion: .contentProcessed { _ in connection.cancel() })
    }
    static func wrapped(_ url: URL) -> URL {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        parts.scheme = url.scheme == "https" ? "sofatvhttps" : "sofatvhttp"
        return parts.url!
    }
    static func rewrite(_ data: Data, base: URL, wrap: (URL) -> URL = wrapped) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else { throw CmgError.message("无效的直播列表编码") }
        let expression = try NSRegularExpression(pattern: "URI=\"([^\"]+)\"")
        let lines = text.components(separatedBy: .newlines).map { line -> String in
            if line.hasPrefix("#") {
                var output = line
                for match in expression.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed() {
                    guard let range = Range(match.range(at: 1), in: line), let url = URL(string: String(line[range]), relativeTo: base)?.absoluteURL, ["http", "https"].contains(url.scheme) else { continue }
                    output.replaceSubrange(range, with: wrap(url).absoluteString)
                }
                return output
            }
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty, let url = URL(string: line, relativeTo: base)?.absoluteURL, ["http", "https"].contains(url.scheme) else { return line }
            return wrap(url).absoluteString
        }
        return Data(lines.joined(separator: "\n").utf8)
    }
}
