import AppKit
import Testing
import UserNotifications
import SwiftUI
@testable import SofaTV

@MainActor private final class ReminderNotificationsFixture: ProgramReminderNotifications {
    var onWatch: ((String) -> Void)?
    var onIgnore: ((String) -> Void)?
    var allowed = true
    var authorizations = 0
    var pending: [String: ProgramReminder] = [:]
    var delivered: Set<String> = []
    var additions: [ProgramReminder] = []
    var hold = false
    var waiting: CheckedContinuation<Void, Never>?
    var fail = false
    func configure() {}
    func requestAuthorization() async throws -> Bool { authorizations += 1; return allowed }
    func pendingSignatures() async -> [String: String] { pending.mapValues(\.signature) }
    func schedule(_ reminder: ProgramReminder) async throws {
        additions.append(reminder)
        if hold { await withCheckedContinuation { waiting = $0 } }
        if fail { throw URLError(.cannotConnectToHost) }
        pending[reminder.notificationID] = reminder
    }
    func remove(_ identifiers: [String], delivered: Bool) {
        for identifier in identifiers {
            pending.removeValue(forKey: identifier)
            if delivered { self.delivered.remove(identifier) }
        }
    }
    func release() { hold = false; let value = waiting; waiting = nil; value?.resume() }
}

@MainActor @Suite("节目提醒", .serialized)
struct ProgramReminderTests {
    @MainActor private final class Fixture {
        @MainActor final class Clock { var date = Date(timeIntervalSince1970: 1_800_000_000) }
        let name = "sofatv-reminder-test-" + UUID().uuidString
        let defaults: UserDefaults
        let notifications = ReminderNotificationsFixture()
        let clock = Clock()
        var date: Date { get { clock.date } set { clock.date = newValue } }
        lazy var store = ProgramReminderStore(defaults: defaults, notifications: notifications, now: { [clock] in clock.date })
        init() { defaults = UserDefaults(suiteName: name)! }
        func clean() { notifications.release(); defaults.removePersistentDomain(forName: name) }
    }
    private var channel: Channel { Channel(name: "测试频道", group: "测试", url: URL(string: "https://example.invalid/live.m3u8")!, epgID: "test") }
    private func program(_ f: Fixture, offset: TimeInterval = 3600, title: String = "节目一") -> ProgramGuide.CurrentProgram {
        .init(title: title, start: f.date.addingTimeInterval(offset), end: f.date.addingTimeInterval(offset + 1800))
    }
    private func settle(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    @Test func addingCancellingAndRestartingKeepOneSystemRequestAtProgrammeStart() async throws {
        let f = Fixture(); defer { f.clean() }
        let program = program(f)
        f.store.start(); await f.store.synchronize()
        #expect(f.notifications.authorizations == 0, "Startup must not ask for notification permission")
        try await f.store.toggle(program, channel: channel)
        let saved = try #require(f.store.reminders.first)
        #expect(f.notifications.pending[saved.notificationID]?.start == program.start)
        #expect(f.notifications.pending.count == 1 && f.notifications.authorizations == 1)
        let restored = ProgramReminderStore(defaults: f.defaults, notifications: f.notifications, now: { f.date })
        restored.start(); await restored.synchronize()
        #expect(restored.reminders == [saved] && f.notifications.additions.count == 1)
        try await restored.toggle(program, channel: channel); await restored.synchronize()
        #expect(restored.reminders.isEmpty && f.notifications.pending.isEmpty)
    }

    @Test func deniedPermissionAndSchedulingFailureDoNotClaimASavedReminder() async throws {
        let f = Fixture(); defer { f.clean() }
        f.notifications.allowed = false
        do { try await f.store.toggle(program(f), channel: channel); Issue.record("Denied authorization must fail") }
        catch { #expect(error is ProgramReminderError) }
        #expect(f.store.reminders.isEmpty && f.notifications.pending.isEmpty)
        f.notifications.allowed = true; f.notifications.fail = true
        do { try await f.store.toggle(program(f), channel: channel); Issue.record("Scheduling failure must be reported") }
        catch { #expect(error is ProgramReminderError) }
        await f.store.synchronize()
        #expect(f.store.reminders.isEmpty && f.notifications.pending.isEmpty && f.store.busyKeys.isEmpty)
    }

    @Test func programmesAlreadyStartedCannotBeAdded() async throws {
        let f = Fixture(); defer { f.clean() }
        do { try await f.store.toggle(program(f, offset: -10), channel: channel); Issue.record("A started programme must be rejected") }
        catch { #expect(error is ProgramReminderError) }
        #expect(f.notifications.authorizations == 0 && f.store.reminders.isEmpty)
    }

    @Test func scheduleChangesAndChannelRenamesReplaceTheSameRequest() async throws {
        let f = Fixture(); defer { f.clean() }
        let original = program(f)
        try await f.store.toggle(original, channel: channel)
        let id = try #require(f.store.reminders.first?.id)
        var renamed = channel; renamed.customName = "我的频道"
        let changed = program(f, offset: 4200)
        f.store.reconcile(channels: [renamed], programs: { _ in [changed] })
        await f.store.synchronize()
        let saved = try #require(f.store.reminders.first)
        #expect(saved.id == id && saved.start == changed.start && saved.channelName == "我的频道")
        #expect(f.notifications.pending.count == 1 && f.notifications.pending[saved.notificationID]?.start == changed.start)
        f.store.reconcile(channels: [renamed], programs: { _ in [] })
        await f.store.synchronize()
        #expect(f.store.reminders.first?.start == changed.start, "A temporary EPG gap must not move or delete a reminder")
    }

    @Test func ambiguousRepeatedTitlesDoNotMoveTheReminderToAnotherBroadcast() {
        let f = Fixture(); defer { f.clean() }
        let original = program(f)
        let reminder = ProgramReminder(channel: channel, program: original)
        let earlier = program(f, offset: 3000), later = program(f, offset: 4200)
        #expect(reminder.updating(channel: channel, programs: [earlier, later]).start == original.start)
        #expect(reminder.updating(channel: channel, programs: [program(f, offset: 8 * 3600)]).start == original.start)
    }

    @Test func missingChannelsSuspendDeliveryWithoutLosingTheSavedIntention() async throws {
        let f = Fixture(); defer { f.clean() }
        let original = program(f)
        try await f.store.toggle(original, channel: channel)
        let saved = try #require(f.store.reminders.first)
        f.store.reconcile(channels: [], programs: { _ in [] }); await f.store.synchronize()
        #expect(f.store.reminders == [saved] && f.notifications.pending.isEmpty)
        #expect(!f.store.channelAvailable(for: saved))
        f.store.reconcile(channels: [channel], programs: { _ in [original] }); await f.store.synchronize()
        #expect(f.notifications.pending.count == 1)
    }

    @Test func aLateNativeAddCannotReviveACancelledReminder() async throws {
        let f = Fixture(); defer { f.clean() }
        f.notifications.hold = true
        let program = program(f)
        let adding = Task { try await f.store.toggle(program, channel: channel) }
        try await settle { f.notifications.waiting != nil }
        let saved = try #require(f.store.reminders.first)
        f.store.remove(saved.id)
        f.notifications.release(); try await adding.value
        await f.store.synchronize()
        #expect(f.store.reminders.isEmpty && f.notifications.pending.isEmpty)
    }

    @Test func aScheduleUpdateDuringNativeAddKeepsOnlyTheLatestTime() async throws {
        let f = Fixture(); defer { f.clean() }
        f.notifications.hold = true
        let original = program(f), updated = program(f, offset: 4200)
        let adding = Task { try await f.store.toggle(original, channel: channel) }
        try await settle { f.notifications.waiting != nil }
        f.store.reconcile(channels: [channel], programs: { _ in [updated] })
        f.notifications.release(); try await adding.value
        let saved = try #require(f.store.reminders.first)
        #expect(saved.start == updated.start && f.notifications.pending.count == 1)
        #expect(f.notifications.pending[saved.notificationID]?.start == updated.start)
    }

    @Test func elapsedTimeAndIgnoreNeverStartPlaybackButWatchCanWaitForAppStartup() async throws {
        let f = Fixture(); defer { f.clean() }
        let original = program(f)
        try await f.store.toggle(original, channel: channel)
        let saved = try #require(f.store.reminders.first)
        var plays: [UUID] = []
        f.store.onWatch = { plays.append($0.id); return true }
        f.date = original.start.addingTimeInterval(1)
        f.store.refresh(); await f.store.synchronize()
        #expect(plays.isEmpty, "Reaching the programme start must never autoplay")
        #expect(f.notifications.pending[saved.notificationID] != nil, "Refreshing at the start must not cancel a notification awaiting system delivery")
        f.notifications.onIgnore?(saved.notificationID)
        #expect(plays.isEmpty && f.store.reminders.isEmpty)
        let next = program(f)
        try await f.store.toggle(next, channel: channel)
        let pending = try #require(f.store.reminders.first)
        f.store.onWatch = nil
        f.notifications.onWatch?(pending.notificationID)
        #expect(plays.isEmpty)
        f.store.onWatch = { plays.append($0.id); return true }
        #expect(f.store.consumePendingWatch())
        #expect(plays == [pending.id] && f.store.reminders.isEmpty)
        #expect(!f.store.consumePendingWatch())
    }

    @Test func nativePayloadNotifiesTenSecondsEarlyWithoutButtonsAndBodyTapPlays() {
        let f = Fixture(); defer { f.clean() }
        let program = program(f)
        let reminder = ProgramReminder(channel: channel, program: program)
        let request = SystemProgramReminderNotifications.request(for: reminder)
        let trigger = request.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.repeats == false && trigger?.dateComponents.timeZone == TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        #expect(trigger.flatMap { calendar.date(from: $0.dateComponents) } == program.start.addingTimeInterval(-10))
        let category = SystemProgramReminderNotifications.notificationCategory()
        #expect(category.actions.isEmpty)
        let notifications = SystemProgramReminderNotifications()
        #expect(notifications.responds(to: NSSelectorFromString("userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:")),
                "The async delegate must expose the system's Objective-C callback")
        var watched = 0, ignored = 0
        notifications.onWatch = { _ in watched += 1 }; notifications.onIgnore = { _ in ignored += 1 }
        notifications.receive(action: "sofatv.program.ignore", notificationID: reminder.notificationID)
        notifications.receive(action: UNNotificationDismissActionIdentifier, notificationID: reminder.notificationID)
        #expect(watched == 0 && ignored == 2)
        notifications.receive(action: "sofatv.program.watch", notificationID: reminder.notificationID)
        notifications.receive(action: UNNotificationDefaultActionIdentifier, notificationID: reminder.notificationID)
        #expect(watched == 2)
        notifications.receive(action: UNNotificationDefaultActionIdentifier, notificationID: "another-feature")
        #expect(watched == 2)
    }

    @Test func pendingRequestsExpireTwentySecondsAfterTriggerWithoutRearming() async throws {
        let f = Fixture(); defer { f.clean() }
        let original = program(f)
        try await f.store.toggle(original, channel: channel)
        let saved = try #require(f.store.reminders.first)
        #expect(saved.fireDate == original.start.addingTimeInterval(-10))
        f.date = saved.fireDate.addingTimeInterval(19)
        f.store.refresh(); await f.store.synchronize()
        #expect(f.notifications.pending[saved.notificationID] != nil)
        f.date = saved.pendingDeliveryDeadline
        f.store.refresh(); await f.store.synchronize()
        #expect(f.notifications.pending.isEmpty && f.notifications.additions.count == 1)
        #expect(f.store.reminders.count == 1, "Expiring a notification keeps the programme available in the reminder list")
    }

    @Test func deliveredNotificationsSurviveCleanupAndRemainClickableAfterRestart() async throws {
        let f = Fixture(); defer { f.clean() }
        let original = program(f)
        try await f.store.toggle(original, channel: channel)
        let saved = try #require(f.store.reminders.first)
        f.notifications.pending.removeValue(forKey: saved.notificationID)
        f.notifications.delivered.insert(saved.notificationID)

        f.date = saved.pendingDeliveryDeadline
        f.store.refresh(); await f.store.synchronize()
        #expect(f.notifications.delivered == [saved.notificationID])

        f.date = original.start.addingTimeInterval(60)
        let restored = ProgramReminderStore(defaults: f.defaults, notifications: f.notifications, now: { f.date })
        restored.start(); await restored.synchronize()
        var renamed = channel
        renamed.customName = "我的频道"
        restored.reconcile(channels: [renamed], programs: { _ in [original] })
        await restored.synchronize()
        #expect(f.notifications.delivered == [saved.notificationID])
        #expect(f.notifications.additions.count == 1)

        var watched: ProgramReminder?
        restored.onWatch = { watched = $0; return true }
        f.notifications.onWatch?(saved.notificationID)
        #expect(watched?.id == saved.id && watched?.channelName == renamed.displayName)
        #expect(f.notifications.delivered.isEmpty && restored.reminders.isEmpty)
    }

    @Test func bookingInsideTheLeadWindowNotifiesPromptly() async throws {
        let f = Fixture(); defer { f.clean() }
        try await f.store.toggle(program(f, offset: 5), channel: channel)
        let saved = try #require(f.store.reminders.first)
        #expect(saved.fireDate == f.date.addingTimeInterval(1))
        #expect(saved.pendingDeliveryDeadline == saved.fireDate.addingTimeInterval(20))
        #expect(f.notifications.pending.count == 1)
    }

    @Test func aDownloadedGuideReschedulesSavedReminders() async throws {
        let f = Fixture(); defer { f.clean() }
        let original = program(f), updated = program(f, offset: 4200)
        try await f.store.toggle(original, channel: channel)
        let id = try #require(f.store.reminders.first?.id)
        func entry(_ program: ProgramGuide.CurrentProgram) throws -> ProgramGuideCacheEntry {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMddHHmmss Z"
            let xml = "<tv><programme channel=\"test\" start=\"\(formatter.string(from: program.start))\" stop=\"\(formatter.string(from: program.end))\"><title>\(program.title)</title></programme></tv>"
            return ProgramGuideCacheEntry(fetchedAt: f.date, guide: try ProgramGuide.parse(Data(xml.utf8)))
        }
        let cached = try entry(original), downloaded = try entry(updated)
        let store = ProgramGuideStore(now: { [clock = f.clock] in clock.date }, cachedGuide: { cached },
                                      refreshGuide: { downloaded }, observeSystemEvents: false, reminders: f.store)
        defer { store.stop() }
        store.setChannels([channel])
        try await settle { store.nextRefreshAt != nil }
        await f.store.synchronize()
        let saved = try #require(f.store.reminders.first)
        #expect(saved.id == id && saved.start == updated.start)
        #expect(f.notifications.pending[saved.notificationID]?.start == updated.start)
    }

    @Test func renderReminderListAndGuideButtons() async throws {
        guard let directory = ProcessInfo.processInfo.environment["SOFATV_REMINDER_PREVIEW_DIR"] else { return }
        let f = Fixture(); defer { f.clean() }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let now = ISO8601DateFormatter().date(from: "2026-11-08T10:00:00+08:00")!
        f.date = now
        let guide = try ProgramGuide.parse(Data("""
        <tv><programme channel="test" start="20261108093000 +0800" stop="20261108103000 +0800"><title>正在播出的节目</title></programme>
        <programme channel="test" start="20261108103000 +0800" stop="20261108110000 +0800"><title>纪录片：山河之间</title></programme>
        <programme channel="test" start="20261108110000 +0800" stop="20261108120000 +0800"><title>午间新闻</title></programme>
        <programme channel="test" start="20261108120000 +0800" stop="20261108130000 +0800"><title>经典剧场</title></programme></tv>
        """.utf8))
        let entry = ProgramGuideCacheEntry(fetchedAt: now, guide: guide)
        let store = ProgramGuideStore(now: { now }, cachedGuide: { entry }, refreshGuide: { entry },
                                      observeSystemEvents: false, reminders: f.store)
        defer { store.stop() }
        store.setChannels([channel])
        try await settle { store.nextRefreshAt != nil }
        let future = try #require(store.schedule(for: channel).programs.first { $0.title.contains("纪录片") })
        try await f.store.toggle(future, channel: channel)
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func capture(_ view: NSView, size: NSSize, name: String) async throws {
            let window = NSPanel(contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .darkAqua)
            view.frame = NSRect(origin: .zero, size: size); window.contentView = view; window.orderBack(nil)
            for _ in 0..<25 { view.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(10)) }
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(name + ".png"))
            window.close(); withExtendedLifetime(window) {}
        }
        for presentation in [ProgramGuidePreview.Presentation.embedded, .fullscreen] {
            let preview = ProgramGuidePreview()
            preview.setPresentation(presentation)
            let host = ProgramGuideOverlayHost(preview: preview, store: store, presentation: presentation, playingChannel: channel)
            preview.showPlayingChannel(channel, in: presentation)
            try await capture(host, size: NSSize(width: presentation == .embedded ? 260 : 340, height: 650),
                              name: presentation == .embedded ? "guide" : "guide-fullscreen")
        }
        let list = NSHostingView(rootView: ProgramReminderList(store: f.store)
            .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.dark))
        list.sizingOptions = []
        try await capture(list, size: NSSize(width: 520, height: 420), name: "reminders")
    }
}
