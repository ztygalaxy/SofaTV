import Foundation

struct ProgramReminder: Codable, Equatable, Identifiable, Sendable {
    static let notificationPrefix = "sofatv.program."
    let id: UUID
    var channelKey: String
    var channelIdentity: Channel.Identity
    var channelName: String
    var title: String
    var start: Date
    var end: Date
    var scheduledDate: Date? = nil
    var fireDate: Date { scheduledDate ?? start.addingTimeInterval(-10) }
    var expiresAt: Date { fireDate.addingTimeInterval(20) }

    init(channel: Channel, program: ProgramGuide.CurrentProgram, id: UUID = UUID()) {
        self.id = id; channelKey = channel.preferenceKey; channelIdentity = channel.identity
        channelName = channel.displayName; title = program.title; start = program.start; end = program.end
    }
    var notificationID: String { Self.notificationPrefix + id.uuidString }
    var signature: String {
        // Length-prefix text fields so punctuation cannot cause key collisions.
        [channelKey, channelName, title, String(start.timeIntervalSince1970), String(end.timeIntervalSince1970), String(fireDate.timeIntervalSince1970)]
            .map { "\($0.utf8.count):\($0)" }.joined()
    }
    func matches(_ channel: Channel) -> Bool { channelKey == channel.preferenceKey || channelIdentity == channel.identity }
    func matches(_ program: ProgramGuide.CurrentProgram, channel: Channel) -> Bool {
        matches(channel) && start == program.start && title == program.title
    }
    func updating(channel: Channel, programs: [ProgramGuide.CurrentProgram]) -> Self {
        var value = self
        value.channelKey = channel.preferenceKey; value.channelIdentity = channel.identity; value.channelName = channel.displayName
        let candidates = programs.filter { $0.title == title && abs($0.start.timeIntervalSince(start)) <= 3 * 3600 }
            .sorted { abs($0.start.timeIntervalSince(start)) < abs($1.start.timeIntervalSince(start)) }
        // Repeated titles can be ambiguous; do not move a reminder to an unrelated broadcast.
        if let first = candidates.first,
           candidates.count == 1 || abs(first.start.timeIntervalSince(start)) < abs(candidates[1].start.timeIntervalSince(start)) {
            value.start = first.start; value.end = first.end
            if first.start != start { value.scheduledDate = nil }
        }
        return value
    }
}

enum ProgramReminderError: LocalizedError {
    case alreadyStarted, notificationsDisabled, unavailable, scheduling(String)
    var errorDescription: String? {
        switch self {
        case .alreadyStarted: "节目已经开始，无法再添加节目预约。"
        case .notificationsDisabled: "请在“系统设置 → 通知”中允许沙发电视发送通知，再添加预约。"
        case .unavailable: "当前运行环境无法使用系统通知，请从沙发电视 App 中添加预约。"
        case .scheduling(let reason): "预约未能生效：\(reason)"
        }
    }
}

@MainActor protocol ProgramReminderNotifications: AnyObject {
    var onWatch: ((String) -> Void)? { get set }
    var onIgnore: ((String) -> Void)? { get set }
    func configure()
    func requestAuthorization() async throws -> Bool
    func pendingSignatures() async -> [String: String]
    func schedule(_ reminder: ProgramReminder) async throws
    func remove(_ identifiers: [String], delivered: Bool)
}
