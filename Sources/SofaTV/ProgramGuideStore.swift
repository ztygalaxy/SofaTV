import AppKit
import Combine

/// Publishes current or upcoming programmes independently of playback and channel loading.
@MainActor final class ProgramGuideStore: NSObject, ObservableObject {
    struct ProgramMatch: Identifiable {
        struct ID: Hashable {
            let channel: Channel.Identity
            let program: ProgramGuide.CurrentProgram
        }

        let channel: Channel
        let program: ProgramGuide.CurrentProgram
        var id: ID { ID(channel: channel.identity, program: program) }
    }

    struct SearchResults {
        var live: [ProgramMatch] = []
        var upcoming: [ProgramMatch] = []
        var count: Int { live.count + upcoming.count }
        var isEmpty: Bool { live.isEmpty && upcoming.isEmpty }
    }

    @Published private(set) var titles: [String: String] = [:]
    @Published private(set) var scheduleRevision = 0
    // A boundary can change search results even when the sidebar's titles are identical.
    @Published private var nextProgramChange: Date?
    var currentDate: Date { now() }
    private(set) var nextRefreshAt: Date?
    private var channels: [Channel] = []
    private var guide: ProgramGuide?
    private var schedules: [Channel: ProgramGuide.Schedule] = [:]
    private var restoredCache = false
    private var loadTask: Task<Void, Never>?
    private var loadID: UUID?
    private var tickTask: Task<Void, Never>?
    private var running = false
    let reminders: ProgramReminderStore?
    private let now: @MainActor () -> Date
    private let cachedGuide: @Sendable () async -> ProgramGuideCacheEntry?
    private let refreshGuide: @Sendable () async throws -> ProgramGuideCacheEntry
    private let wakeCenter: NotificationCenter?

    init(now: @escaping @MainActor () -> Date = { Date() },
         cachedGuide: @escaping @Sendable () async -> ProgramGuideCacheEntry? = { await ProgramGuideStore.readSharedCache() },
         refreshGuide: @escaping @Sendable () async throws -> ProgramGuideCacheEntry = { try await ProgramGuideRepository.shared.refresh() },
         observeSystemEvents: Bool = true, reminders: ProgramReminderStore? = nil) {
        self.now = now; self.cachedGuide = cachedGuide; self.refreshGuide = refreshGuide
        self.reminders = reminders
        wakeCenter = observeSystemEvents ? NSWorkspace.shared.notificationCenter : nil
        super.init()
        if observeSystemEvents {
            NotificationCenter.default.addObserver(self, selector: #selector(resume), name: NSApplication.didBecomeActiveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(resume), name: .NSSystemClockDidChange, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(resume), name: .NSSystemTimeZoneDidChange, object: nil)
            wakeCenter?.addObserver(self, selector: #selector(resume), name: NSWorkspace.didWakeNotification, object: nil)
        }
    }
    private nonisolated static func readSharedCache() async -> ProgramGuideCacheEntry? {
        await ProgramGuideRepository.shared.cachedGuide()
    }
    deinit {
        loadTask?.cancel(); tickTask?.cancel()
        let notifications = wakeCenter
        NotificationCenter.default.removeObserver(self)
        notifications?.removeObserver(self)
    }

    func setChannels(_ channels: [Channel]) {
        running = true
        self.channels = channels
        schedules.removeAll()
        updateTitles()
        refreshIfNeeded()
        scheduleTick()
        synchronizeReminders()
    }
    func stop() {
        running = false
        // Keep an existing shared refresh in flight so an immediate reappearance reuses it.
        tickTask?.cancel(); tickTask = nil
    }
    @objc func resume() {
        guard running else { return }
        updateTitles(); refreshIfNeeded(); scheduleTick()
        reminders?.refresh()
    }
    private func synchronizeReminders() {
        reminders?.reconcile(channels: channels, programs: { schedule(for: $0).programs })
    }
    func schedule(for channel: Channel) -> ProgramGuide.Schedule {
        guard let guide else { return ProgramGuide.Schedule(programs: []) }
        if let cached = schedules[channel] { return cached }
        let schedule = guide.schedule(channel: channel)
        schedules[channel] = schedule
        return schedule
    }
    func search(_ text: String, channels: [Channel], at date: Date) -> SearchResults {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, guide != nil else { return SearchResults() }
        var results = SearchResults()
        for channel in channels {
            for program in schedule(for: channel).programs
                where program.end > date && program.title.localizedCaseInsensitiveContains(query) {
                let match = ProgramMatch(channel: channel, program: program)
                if program.contains(date) { results.live.append(match) }
                else { results.upcoming.append(match) }
            }
        }
        results.live.sort { $0.program.start < $1.program.start }
        results.upcoming.sort { $0.program.start < $1.program.start }
        return results
    }
    private func updateTitles() {
        let at = now()
        var current: [String: String] = [:]
        if let guide {
            for channel in channels {
                if let highlight = guide.highlightedProgram(channel: channel, at: at) {
                    current[channel.id] = highlight.subtitle()
                }
            }
        }
        if titles != current { titles = current }
    }
    private func refreshIfNeeded() {
        guard running, !channels.isEmpty, loadTask == nil,
              nextRefreshAt == nil || nextRefreshAt! <= now() else { return }
        let token = UUID()
        loadID = token
        nextRefreshAt = nil
        let shouldRestore = !restoredCache
        restoredCache = true
        let readCache = cachedGuide, download = refreshGuide
        loadTask = Task { [weak self] in
            if shouldRestore {
                let cached = await readCache()
                guard !Task.isCancelled, self?.restore(cached, for: token) == true else { return }
            }
            // A cache never satisfies this initial refresh, even if it was fetched moments ago.
            guard !Task.isCancelled else { return }
            do {
                let entry = try await download()
                guard !Task.isCancelled else { return }
                self?.finish(entry, for: token)
            } catch {
                guard !Task.isCancelled else { return }
                self?.finish(nil, for: token)
            }
        }
    }
    private func restore(_ entry: ProgramGuideCacheEntry?, for token: UUID) -> Bool {
        guard loadID == token else { return false }
        if let entry { install(entry.guide) }
        if running { updateTitles(); scheduleTick() }
        return true
    }
    private func finish(_ entry: ProgramGuideCacheEntry?, for token: UUID) {
        guard loadID == token else { return }
        if let entry { install(entry.guide) }
        // Successful snapshots refresh every four hours; network failures keep a short retry cooldown.
        let interval = entry == nil ? 10 * 60 : ProgramGuideRepository.refreshInterval
        nextRefreshAt = now().addingTimeInterval(interval)
        loadID = nil; loadTask = nil
        if running { updateTitles(); scheduleTick() }
    }
    private func install(_ guide: ProgramGuide) {
        self.guide = guide
        schedules.removeAll()
        scheduleRevision += 1
        synchronizeReminders()
    }
    private func scheduleTick() {
        tickTask?.cancel(); tickTask = nil
        guard running, !channels.isEmpty else { return }
        let at = now()
        var deadline = at.addingTimeInterval(60)
        let change = guide?.nextChange(after: at)
        if nextProgramChange != change { nextProgramChange = change }
        if let change { deadline = min(deadline, change) }
        if loadTask == nil, let nextRefreshAt { deadline = min(deadline, nextRefreshAt) }
        let delay = max(0.2, deadline.timeIntervalSince(at))
        tickTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.resume()
        }
    }
}
