import Foundation
import Combine

/// Reminders are persisted intentions. One serial worker reconciles them with
/// the notification center, including cancellations that arrive during an add.
@MainActor final class ProgramReminderStore: ObservableObject {
    static let shared: ProgramReminderStore = ProgramReminderStore(defaults: .standard, notifications: SystemProgramReminderNotifications(),
                                                                  now: { Date() })
    @Published private(set) var reminders: [ProgramReminder]
    @Published private(set) var busyKeys: Set<String> = []
    @Published private(set) var deliveryErrors: [UUID: String] = [:]
    var onWatch: ((ProgramReminder) -> Bool)?
    var onActivate: (() -> Void)?
    private var pendingWatch: ProgramReminder?
    private let defaults: UserDefaults
    private let notifications: any ProgramReminderNotifications
    private let now: () -> Date
    private var catalogue: [Channel]?
    private var syncTask: Task<Void, Never>?
    private var needsSync = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var authorizationTask: Task<Bool, Error>?
    private var expiryTask: Task<Void, Never>?
    private static let preference = "program-reminders-v1"

    init(defaults: UserDefaults = .standard, notifications: any ProgramReminderNotifications = SystemProgramReminderNotifications(),
         now: @escaping () -> Date = { Date() }) {
        self.defaults = defaults; self.notifications = notifications; self.now = now
        reminders = defaults.data(forKey: Self.preference).flatMap { try? JSONDecoder().decode([ProgramReminder].self, from: $0) } ?? []
        var seen: Set<UUID> = []
        reminders = reminders.filter { $0.end > $0.start && seen.insert($0.id).inserted }
        notifications.onWatch = { [weak self] in self?.requestWatch(notificationID: $0) }
        notifications.onIgnore = { [weak self] in self?.ignore(notificationID: $0) }
    }
    deinit { expiryTask?.cancel() }
    var currentDate: Date { now() }
    func start() { notifications.configure(); refresh(); consumePendingWatch() }
    func reminder(for program: ProgramGuide.CurrentProgram, channel: Channel) -> ProgramReminder? {
        reminders.first { $0.matches(program, channel: channel) }
    }
    func isBusy(_ program: ProgramGuide.CurrentProgram, channel: Channel) -> Bool { busyKeys.contains(key(program, channel: channel)) }
    private func key(_ program: ProgramGuide.CurrentProgram, channel: Channel) -> String {
        channel.preferenceKey + "|" + String(program.start.timeIntervalSince1970) + "|" + program.title
    }
    func toggle(_ program: ProgramGuide.CurrentProgram, channel: Channel) async throws {
        if let existing = reminder(for: program, channel: channel) { remove(existing.id); return }
        let key = key(program, channel: channel)
        guard !busyKeys.contains(key) else { return }
        guard program.start > now() else { throw ProgramReminderError.alreadyStarted }
        busyKeys.insert(key); defer { busyKeys.remove(key) }
        if authorizationTask == nil {
            authorizationTask = Task { try await notifications.requestAuthorization() }
        }
        do {
            guard try await authorizationTask!.value else {
                authorizationTask = nil
                throw ProgramReminderError.notificationsDisabled
            }
        } catch { authorizationTask = nil; throw error }
        authorizationTask = nil
        guard program.start > now() else { throw ProgramReminderError.alreadyStarted }
        guard reminder(for: program, channel: channel) == nil else { return }
        var reminder = ProgramReminder(channel: channel, program: program)
        if reminder.fireDate <= now() {
            reminder.scheduledDate = Date(timeIntervalSince1970: ceil(now().timeIntervalSince1970) + 1)
        }
        reminders.append(reminder); persist()
        await synchronize()
        if let error = deliveryErrors[reminder.id] {
            remove(reminder.id)
            throw ProgramReminderError.scheduling(error)
        }
    }
    func remove(_ id: UUID) {
        let ids = reminders.filter { $0.id == id }.map(\.notificationID)
        reminders.removeAll { $0.id == id }; deliveryErrors.removeValue(forKey: id)
        notifications.remove(ids, delivered: true)
        persist(); requestSync()
    }
    func retry() { requestSync() }
    func channelAvailable(for reminder: ProgramReminder) -> Bool { catalogue?.contains { reminder.matches($0) } ?? true }
    func reconcile(channels: [Channel], programs: (Channel) -> [ProgramGuide.CurrentProgram]) {
        catalogue = channels
        let updated = reminders.map { reminder in
            guard let channel = channels.first(where: { reminder.matches($0) }) else { return reminder }
            return reminder.updating(channel: channel, programs: programs(channel))
        }
        if updated != reminders {
            let changed = zip(reminders, updated).filter { $0.signature != $1.signature }.map { $0.0.notificationID }
            notifications.remove(changed, delivered: true)
            reminders = updated; persist()
        }
        refresh()
    }
    func refresh() {
        notifications.remove(reminders.filter { $0.expiresAt <= now() }.map(\.notificationID), delivered: true)
        let expired = reminders.filter { $0.end < now().addingTimeInterval(-86400) }
        if !expired.isEmpty {
            notifications.remove(expired.map(\.notificationID), delivered: true)
            for reminder in expired { deliveryErrors.removeValue(forKey: reminder.id) }
            reminders.removeAll { entry in expired.contains { $0.id == entry.id } }; persist()
        }
        requestSync()
    }
    func watch(_ reminder: ProgramReminder) {
        pendingWatch = reminder
        consumePendingWatch()
        onActivate?()
    }
    @discardableResult func consumePendingWatch() -> Bool {
        guard let reminder = pendingWatch, onWatch?(reminder) == true else { return false }
        pendingWatch = nil
        remove(reminder.id)
        return true
    }
    private func requestWatch(notificationID: String) {
        guard let reminder = reminders.first(where: { $0.notificationID == notificationID }) else { return }
        watch(reminder)
    }
    private func ignore(notificationID: String) {
        if let reminder = reminders.first(where: { $0.notificationID == notificationID }) { remove(reminder.id) }
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(reminders) { defaults.set(data, forKey: Self.preference) }
    }
    func synchronize() async {
        requestSync()
        await withCheckedContinuation { waiters.append($0) }
    }
    private func requestSync() {
        needsSync = true
        guard syncTask == nil else { return }
        syncTask = Task { [weak self] in
            guard let self else { return }
            while self.needsSync {
                self.needsSync = false
                await self.syncOnce()
            }
            self.syncTask = nil
            self.scheduleExpiry()
            let waiters = self.waiters; self.waiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }
    private func scheduleExpiry() {
        expiryTask?.cancel(); expiryTask = nil
        guard let deadline = reminders.map(\.expiresAt).filter({ $0 > now() }).min() else { return }
        let delay = max(0.05, deadline.timeIntervalSince(now()))
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.refresh()
        }
    }
    private func syncOnce() async {
        let pending = await notifications.pendingSignatures()
        // A due request may still be queued by macOS (for example during wake).
        // Keep it until explicit cancellation; passing the start must not race
        // the system's delivery. Only future requests can be newly scheduled.
        let desired = reminders.filter { channelAvailable(for: $0) && $0.expiresAt > now() }
        let desiredIDs = Set(desired.map(\.notificationID))
        notifications.remove(pending.keys.filter { !desiredIDs.contains($0) }, delivered: false)
        for reminder in desired {
            guard reminders.contains(reminder), channelAvailable(for: reminder), reminder.fireDate > now() else { continue }
            if pending[reminder.notificationID] == reminder.signature { deliveryErrors.removeValue(forKey: reminder.id); continue }
            do {
                try await notifications.schedule(reminder)
                deliveryErrors.removeValue(forKey: reminder.id)
            } catch {
                if reminders.contains(where: { $0.id == reminder.id }) { deliveryErrors[reminder.id] = error.localizedDescription }
            }
            // A cancel or schedule update while awaiting the native center is
            // followed by another pass, so a late add cannot revive old work.
            if !reminders.contains(reminder) || !channelAvailable(for: reminder) || reminder.expiresAt <= now() {
                notifications.remove([reminder.notificationID], delivered: true)
                needsSync = true
            }
        }
    }
}
