import AppKit
import Network

/// A bounded recovery cycle: retry the current route once, then try the other
/// routes. A minute of uninterrupted progress renews the retry budget.
struct PlaybackRecoveryPolicy {
    struct Configuration {
        var startupTimeout: TimeInterval = 40
        var stallTimeout: TimeInterval = 12
        var stableInterval: TimeInterval = 60
        var retryDelay: TimeInterval = 2
        var attemptsPerSource = 2
    }
    enum Action: Equatable {
        case restart(index: Int, delay: TimeInterval)
        case waitingForNetwork
        case exhausted
    }
    let configuration: Configuration
    private(set) var active = false
    private(set) var sourceIndex = 0
    private(set) var attempts: [Int: Int] = [:]
    private(set) var exhausted = false
    private var sourceCount = 0
    private var startedAt: TimeInterval = 0
    private var lastProgressAt: TimeInterval = 0
    private var stableSince: TimeInterval?
    private var lastPosition: Double?
    private var rendered = false
    private var recovering = false
    private var online = true
    private var suspended = false
    private var waitingForNetwork = false

    init(configuration: Configuration = Configuration()) { self.configuration = configuration }

    mutating func begin(sourceCount: Int, index: Int, at now: TimeInterval) {
        let network = online
        self = Self(configuration: configuration)
        online = network; self.sourceCount = sourceCount
        active = sourceCount > 0
        sourceIndex = index; startedAt = now; lastProgressAt = now
    }
    mutating func stop() { active = false; recovering = false; waitingForNetwork = false }
    mutating func started(index: Int, at now: TimeInterval) {
        guard active else { return }
        sourceIndex = index; attempts[index, default: 0] += 1
        startedAt = now; lastProgressAt = now; lastPosition = nil; stableSince = nil
        rendered = false; recovering = false; exhausted = false
    }
    @discardableResult mutating func ready(at now: TimeInterval) -> Bool {
        guard active, !suspended, !exhausted, !waitingForNetwork else { return false }
        recovering = false
        if !rendered { lastProgressAt = now; stableSince = now }
        rendered = true
        return true
    }
    mutating func sample(position: Double?, at now: TimeInterval) -> Action? {
        guard active, !suspended, !recovering, !exhausted else { return nil }
        if rendered, let position, position.isFinite {
            if lastPosition == nil || abs(position - lastPosition!) > 0.05 {
                lastProgressAt = now
                if stableSince == nil { stableSince = now }
                if let stableSince, now - stableSince >= configuration.stableInterval {
                    attempts = [sourceIndex: 1]
                    self.stableSince = now
                }
            }
            lastPosition = position
        }
        let expired = rendered ? now - lastProgressAt >= configuration.stallTimeout
            : now - startedAt >= configuration.startupTimeout
        return expired ? failure() : nil
    }
    mutating func failure() -> Action? {
        guard active, !suspended, !recovering, !exhausted else { return nil }
        stableSince = nil; recovering = true
        guard online else { waitingForNetwork = true; return .waitingForNetwork }
        if attempts[sourceIndex, default: 0] < configuration.attemptsPerSource {
            return .restart(index: sourceIndex, delay: retryDelay)
        }
        let order = (1..<max(1, sourceCount)).map { (sourceIndex + $0) % sourceCount }
        if let next = order.first(where: { attempts[$0, default: 0] < configuration.attemptsPerSource }) {
            return .restart(index: next, delay: retryDelay)
        }
        exhausted = true; recovering = false
        return .exhausted
    }
    private var retryDelay: TimeInterval {
        configuration.retryDelay * pow(2, Double(min(2, max(0, attempts.values.reduce(0, +) - 1))))
    }
    mutating func networkChanged(available: Bool, at now: TimeInterval) -> Action? {
        let wasOnline = online; online = available
        guard active, !suspended, wasOnline != available else { return nil }
        if !available, recovering { waitingForNetwork = true; return .waitingForNetwork }
        guard available, waitingForNetwork || exhausted else { return nil }
        return resume(at: now)
    }
    mutating func suspend() { suspended = true }
    mutating func resume(at now: TimeInterval) -> Action? {
        suspended = false
        guard active else { return nil }
        attempts = [:]; exhausted = false; recovering = true; stableSince = nil
        startedAt = now; lastProgressAt = now
        if !online { waitingForNetwork = true; return .waitingForNetwork }
        waitingForNetwork = false
        return .restart(index: sourceIndex, delay: 0)
    }
}

/// Owns progress polling and platform events; stopping invalidates every pending
/// task, including callbacks already queued by Network or WebKit.
@MainActor final class PlaybackRecoveryMonitor: NSObject {
    var samplePosition: (@MainActor () async -> Double?)?
    var onRestart: ((Int, String) -> Void)?
    var onStatus: ((String) -> Void)?
    var onExhausted: ((String) -> Void)?
    private(set) var policy: PlaybackRecoveryPolicy
    private var generation = UUID()
    private var pollTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private let workspaceNotifications: NotificationCenter
    private let now: () -> TimeInterval
    private let pollsAutomatically: Bool

    init(configuration: PlaybackRecoveryPolicy.Configuration = .init(), observeSystemEvents: Bool = true,
         pollsAutomatically: Bool = true, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        policy = PlaybackRecoveryPolicy(configuration: configuration)
        workspaceNotifications = NSWorkspace.shared.notificationCenter
        self.now = now; self.pollsAutomatically = pollsAutomatically
        super.init()
        if observeSystemEvents {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                let available = path.status == .satisfied
                Task { @MainActor [weak self] in self?.networkChanged(available: available) }
            }
            monitor.start(queue: DispatchQueue(label: "SofaTV.PlaybackConnectivity"))
            pathMonitor = monitor
            let center = workspaceNotifications
            center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
            center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        }
    }
    deinit {
        pollTask?.cancel(); retryTask?.cancel(); pathMonitor?.cancel()
        workspaceNotifications.removeObserver(self)
    }
    @objc private func willSleep() { suspend() }
    @objc private func didWake() { resume() }
    func begin(sourceCount: Int, index: Int) {
        stop()
        policy.begin(sourceCount: sourceCount, index: index, at: now())
        startPolling()
    }
    func started(index: Int) {
        retryTask?.cancel(); retryTask = nil
        generation = UUID()
        policy.started(index: index, at: now())
    }
    func ready() {
        guard policy.ready(at: now()) else { return }
        retryTask?.cancel(); retryTask = nil; generation = UUID()
    }
    func stop() {
        generation = UUID(); pollTask?.cancel(); pollTask = nil
        retryTask?.cancel(); retryTask = nil; policy.stop()
    }
    func failed(_ message: String) { handle(policy.failure(), reason: message) }
    func check(position: Double?) {
        handle(policy.sample(position: position, at: now()), reason: "播放长时间没有进度")
    }
    func networkChanged(available: Bool) {
        handle(policy.networkChanged(available: available, at: now()), reason: "网络已恢复")
    }
    func suspend() {
        generation = UUID(); retryTask?.cancel(); retryTask = nil
        policy.suspend()
    }
    func resume() { handle(policy.resume(at: now()), reason: "电脑已唤醒，重新连接直播") }
    private func startPolling() {
        guard pollsAutomatically else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                let token = self.generation
                let position = await self.samplePosition?()
                guard !Task.isCancelled, self.generation == token else { continue }
                self.check(position: position ?? nil)
            }
        }
    }
    private func handle(_ action: PlaybackRecoveryPolicy.Action?, reason: String) {
        guard let action else { return }
        retryTask?.cancel(); retryTask = nil
        generation = UUID()
        switch action {
        case .restart(let index, let delay):
            onStatus?("正在恢复播放 · 线路 \(index + 1)")
            let token = generation
            retryTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, self.generation == token, self.policy.active, !Task.isCancelled else { return }
                self.retryTask = nil
                self.onRestart?(index, reason)
            }
        case .waitingForNetwork: onStatus?("网络已断开，等待恢复…")
        case .exhausted: onExhausted?("暂时无法恢复播放，可点击刷新重试或选择其他频道。")
        }
    }
}
