import SwiftUI

/// Resolves every webpage-backed channel in a bounded rolling queue. Signed media
/// URLs and CMG sessions are short-lived, so this is intentionally a refresh
/// service rather than a one-time, permanent cache.
@MainActor final class WebMediaWarmup {
    // Three hidden pages balance full-library coverage with source/server load.
    // They observe requests only; `WebMediaResolver` keeps their video paused.
    let resolvers = (0..<3).map { _ in WebMediaResolver(keepsVideoRunning: false) }

    private struct Entry {
        let media: ResolvedWebMedia
        let expiresAt: Date
    }
    private let lifetime: TimeInterval = 20
    private let deadline: Duration = .seconds(12)
    private let retryDelay: TimeInterval = 45
    private var entries: [URL: Entry] = [:]
    private var nextRetry: [URL: Date] = [:]
    private var pages: [URL] = []
    private var priorityPages: [URL] = []
    private var nextPageIndex = 0
    private var activePages: [URL?] = Array(repeating: nil, count: 3)
    private var deadlines: [Task<Void, Never>?] = Array(repeating: nil, count: 3)
    private var refreshTask: Task<Void, Never>?

    func cachedMedia(for page: URL) -> ResolvedWebMedia? {
        removeExpired()
        return entries[page]?.media
    }

    /// Replaces the rolling catalogue and moves likely viewing choices to the
    /// front of the next refresh cycle. Existing usable results are retained.
    func configure(pages requestedPages: [URL], prioritized prioritizedPages: [URL]) {
        let all = unique(requestedPages)
        let allowed = Set(all)
        pages = all
        priorityPages = unique(prioritizedPages.filter { allowed.contains($0) })
        nextPageIndex = min(nextPageIndex, max(0, pages.count - 1))
        entries = entries.filter { allowed.contains($0.key) && $0.value.expiresAt > Date() }
        nextRetry = nextRetry.filter { allowed.contains($0.key) && $0.value > Date() }
        for index in activePages.indices where activePages[index].map({ !allowed.contains($0) }) == true {
            finish(index, retryAfter: nil)
        }
        promotePriorityWork()
        schedule()
    }

    func cancel() {
        refreshTask?.cancel(); refreshTask = nil
        entries.removeAll(); nextRetry.removeAll(); pages.removeAll(); priorityPages.removeAll()
        for index in resolvers.indices {
            deadlines[index]?.cancel(); deadlines[index] = nil; activePages[index] = nil
            resolvers[index].cancel()
        }
    }

    private func schedule() {
        removeExpired()
        for index in resolvers.indices where activePages[index] == nil {
            guard let page = nextPageToWarm() else { break }
            start(page, on: index)
        }
        scheduleRefreshIfNeeded()
    }

    private func nextPageToWarm() -> URL? {
        let active = Set(activePages.compactMap { $0 })
        let now = Date()
        func ready(_ page: URL) -> Bool {
            !active.contains(page) && entries[page] == nil && (nextRetry[page] ?? .distantPast) <= now
        }
        for _ in priorityPages.indices {
            let page = priorityPages.removeFirst()
            priorityPages.append(page)
            if ready(page) { return page }
        }
        guard !pages.isEmpty else { return nil }
        for _ in pages.indices {
            let page = pages[nextPageIndex]
            nextPageIndex = (nextPageIndex + 1) % pages.count
            if ready(page) { return page }
        }
        return nil
    }

    private func start(_ page: URL, on index: Int) {
        refreshTask?.cancel(); refreshTask = nil
        activePages[index] = page
        resolvers[index].resolve(page, completion: { [weak self] media in
            guard let self, self.activePages[index] == page else { return }
            self.entries[page] = Entry(media: media, expiresAt: Date().addingTimeInterval(self.lifetime))
            // Yangshipin media needs the matching CMG capture. The resolver
            // emits once more when it becomes available; other sites are done
            // as soon as their first usable media URL is observed.
            if media.cmgState != nil || media.url.host?.hasSuffix("ysp.cctv.cn") != true {
                self.finish(index, retryAfter: nil)
            }
        }, failure: { [weak self] _ in
            self?.finish(index, retryAfter: Date().addingTimeInterval(self?.retryDelay ?? 45))
        })
        deadlines[index] = Task { [weak self] in
            do { try await Task.sleep(for: self?.deadline ?? .seconds(12)) } catch { return }
            guard !Task.isCancelled, self?.activePages[index] == page else { return }
            self?.finish(index, retryAfter: Date().addingTimeInterval(self?.retryDelay ?? 45))
        }
    }

    /// A channel switch should not wait behind an unrelated slow page already
    /// occupying every slot. Replace at most one low-priority warm-up request.
    private func promotePriorityWork() {
        guard activePages.allSatisfy({ $0 != nil }) else { return }
        let now = Date()
        guard priorityPages.contains(where: { entries[$0] == nil && (nextRetry[$0] ?? .distantPast) <= now && !activePages.contains($0) }),
              let index = activePages.indices.first(where: { activePages[$0].map({ !priorityPages.contains($0) }) == true }) else { return }
        finish(index, retryAfter: nil)
    }

    private func finish(_ index: Int, retryAfter: Date?) {
        guard let page = activePages[index] else { return }
        deadlines[index]?.cancel(); deadlines[index] = nil
        activePages[index] = nil
        if let retryAfter { nextRetry[page] = retryAfter }
        resolvers[index].cancel()
        schedule()
    }

    private func scheduleRefreshIfNeeded() {
        guard refreshTask == nil, activePages.allSatisfy({ $0 == nil }) else { return }
        let now = Date()
        let entryRefresh = entries.values.map(\.expiresAt).min()
        let retryRefresh = nextRetry.values.filter { $0 > now }.min()
        guard let next = [entryRefresh, retryRefresh].compactMap({ $0 }).min() else { return }
        let delay = max(1, Int(ceil(next.timeIntervalSince(now))))
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.refreshTask = nil
            self.schedule()
        }
    }

    private func removeExpired() {
        let now = Date()
        entries = entries.filter { $0.value.expiresAt > now }
        nextRetry = nextRetry.filter { $0.value > now }
    }

    private func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }
}

/// WKWebView runs page JavaScript reliably only while attached to a window.
/// The pool remains a one-pixel, transparent view and never receives input.
struct WarmupResolverHost: NSViewRepresentable {
    let warmup: WebMediaWarmup

    func makeNSView(context: Context) -> NSView {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        for webView in warmup.resolvers.map(\.webView) {
            webView.removeFromSuperview()
            webView.frame = host.bounds
            webView.alphaValue = 0.001
            host.addSubview(webView)
        }
        return host
    }

    func updateNSView(_ host: NSView, context: Context) {}
}
