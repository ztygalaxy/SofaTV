import AppKit
import Combine

/// Publishes only changed current titles; playback and the rest of the library stay independent.
@MainActor final class ProgramGuideStore: NSObject, ObservableObject {
    @Published private(set) var titles: [String: String] = [:]
    private var channels: [Channel] = []
    private var guide: ProgramGuide?
    private var nextRefreshAt: Date?
    private var restoredCache = false
    private var guideExhausted = false
    private var loadTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var running = false
    private let wakeCenter = NSWorkspace.shared.notificationCenter

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: .NSSystemClockDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: .NSSystemTimeZoneDidChange, object: nil)
        wakeCenter.addObserver(self, selector: #selector(resume), name: NSWorkspace.didWakeNotification, object: nil)
    }
    deinit {
        loadTask?.cancel(); tickTask?.cancel()
        let notifications = wakeCenter
        NotificationCenter.default.removeObserver(self)
        notifications.removeObserver(self)
    }

    func setChannels(_ channels: [Channel]) {
        running = true
        self.channels = channels
        updateTitles()
        if !channels.isEmpty { refreshIfNeeded() }
        scheduleTick()
    }
    func stop() {
        running = false
        loadTask?.cancel(); loadTask = nil
        tickTask?.cancel(); tickTask = nil
    }
    @objc private func resume() {
        guard running else { return }
        updateTitles(); refreshIfNeeded(); scheduleTick()
    }
    private func updateTitles() {
        let now = Date()
        var current: [String: String] = [:]
        if let guide {
            if guide.nextChange(after: now) != nil { guideExhausted = false }
            else if !guideExhausted { guideExhausted = true; nextRefreshAt = now }
            for channel in channels {
                if let program = guide.currentProgram(channel: channel, at: now) {
                    current[channel.id] = program.subtitle()
                }
            }
        }
        if titles != current { titles = current }
    }
    private func refreshIfNeeded() {
        guard running, !channels.isEmpty, loadTask == nil,
              !restoredCache || nextRefreshAt == nil || nextRefreshAt! <= Date() else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            if !restoredCache {
                let cached = await ProgramGuideRepository.shared.cachedGuide()
                guard !Task.isCancelled else { return }
                restoredCache = true
                if let cached { install(cached) }
            }
            if nextRefreshAt == nil || nextRefreshAt! <= Date() {
                do {
                    let entry = try await ProgramGuideRepository.shared.refresh()
                    guard !Task.isCancelled else { return }
                    install(entry)
                } catch {
                    guard !Task.isCancelled else { return }
                    // Keep valid cached programmes, and retry quietly after a network failure.
                    nextRefreshAt = Date().addingTimeInterval(10 * 60)
                }
            }
            loadTask = nil
            updateTitles(); scheduleTick()
        }
    }
    private func install(_ entry: ProgramGuideCacheEntry) {
        guide = entry.guide
        guideExhausted = false
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: entry.fetchedAt))!
        nextRefreshAt = min(entry.fetchedAt.addingTimeInterval(ProgramGuideRepository.refreshInterval), midnight)
        if entry.fetchedAt > Date() || entry.guide.nextChange(after: Date()) == nil { nextRefreshAt = Date() }
        updateTitles(); scheduleTick()
    }
    private func scheduleTick() {
        tickTask?.cancel(); tickTask = nil
        guard running, !channels.isEmpty else { return }
        let now = Date()
        var deadline = now.addingTimeInterval(60)
        if let change = guide?.nextChange(after: now) { deadline = min(deadline, change) }
        if loadTask == nil, let nextRefreshAt { deadline = min(deadline, nextRefreshAt) }
        let delay = max(0.2, deadline.timeIntervalSince(now))
        tickTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, running, !Task.isCancelled else { return }
            updateTitles(); refreshIfNeeded(); scheduleTick()
        }
    }
}
