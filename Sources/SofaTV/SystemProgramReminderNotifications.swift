import Foundation
@preconcurrency import UserNotifications

@MainActor final class SystemProgramReminderNotifications: NSObject, ProgramReminderNotifications, UNUserNotificationCenterDelegate {
    var onWatch: ((String) -> Void)?
    var onIgnore: ((String) -> Void)?
    private static let category = "sofatv.program.reminder.no-actions.v5"
    private static let watch = "sofatv.program.watch"
    private static let ignore = "sofatv.program.ignore"
    private var configured = false
    private var center: UNUserNotificationCenter? {
        // UNUserNotificationCenter requires an application bundle. Unit tests
        // and bare SwiftPM executables must not try to create its bundle proxy.
        guard Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }
    func configure() {
        guard !configured, let center else { return }
        configured = true
        center.delegate = self
        center.setNotificationCategories([Self.notificationCategory()])
        Task {
            let old = await center.deliveredNotifications().filter {
                $0.request.identifier.hasPrefix(ProgramReminder.notificationPrefix) && $0.request.content.categoryIdentifier != Self.category
            }
            center.removeDeliveredNotifications(withIdentifiers: old.map { $0.request.identifier })
        }
    }
    static func notificationCategory() -> UNNotificationCategory {
        return UNNotificationCategory(identifier: Self.category, actions: [],
                                      intentIdentifiers: [], options: [.customDismissAction])
    }
    func requestAuthorization() async throws -> Bool {
        guard let center else { throw ProgramReminderError.unavailable }
        configure()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: return true
        case .notDetermined: return try await center.requestAuthorization(options: [.alert, .sound])
        default: return false
        }
    }
    func pendingSignatures() async -> [String: String] {
        guard let center else { return [:] }
        let requests = await center.pendingNotificationRequests()
        return Dictionary(requests.filter { $0.identifier.hasPrefix(ProgramReminder.notificationPrefix) }.map {
            ($0.identifier, $0.content.categoryIdentifier == Self.category ? ($0.content.userInfo["signature"] as? String ?? "") : "")
        }, uniquingKeysWith: { first, _ in first })
    }
    func schedule(_ reminder: ProgramReminder) async throws {
        guard let center else { throw ProgramReminderError.unavailable }
        try await center.add(Self.request(for: reminder))
    }
    static func request(for reminder: ProgramReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.subtitle = reminder.channelName
        content.body = "您预约的\(reminder.channelName)的《\(reminder.title)》即将开播，点击跳转观看。"
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.userInfo = ["signature": reminder.signature]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: reminder.notificationID, content: content, trigger: trigger)
    }
    func remove(_ identifiers: [String], delivered: Bool) {
        guard !identifiers.isEmpty, let center else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        if delivered { center.removeDeliveredNotifications(withIdentifiers: identifiers) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Use the same system notification while watching; never change playback here.
        completionHandler([.banner, .list, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let identifier = response.notification.request.identifier
        let action = response.actionIdentifier
        // Finish the system's callback only after persisting the user's action.
        await receive(action: action, notificationID: identifier)
    }
    func receive(action: String, notificationID: String) {
        guard notificationID.hasPrefix(ProgramReminder.notificationPrefix) else { return }
        if action == Self.watch || action == UNNotificationDefaultActionIdentifier { onWatch?(notificationID) }
        else if action == Self.ignore || action == UNNotificationDismissActionIdentifier { onIgnore?(notificationID) }
    }
}
