import AppKit

/// Only speculative channel resolution follows visibility and power state.
/// The foreground webpage and native handoff keep running independently.
@MainActor final class WebMediaWarmupEnvironment: NSObject {
    struct State {
        var isHidden = false
        var hasVisibleWindow = true
        var isLowPowerModeEnabled = false

        var allowsWarmup: Bool { !isHidden && hasVisibleWindow && !isLowPowerModeEnabled }
    }

    var onChange: (() -> Void)?
    var allowsWarmup: Bool { state().allowsWarmup }
    private let state: () -> State
    private let notifications: NotificationCenter

    init(notifications: NotificationCenter = .default,
         state: @escaping () -> State = {
             State(isHidden: NSApp?.isHidden ?? true,
                   hasVisibleWindow: NSApp?.occlusionState.contains(.visible) ?? false,
                   isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled)
         }) {
        self.notifications = notifications; self.state = state
        super.init()
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification,
                     NSApplication.didChangeOcclusionStateNotification, .NSProcessInfoPowerStateDidChange] {
            notifications.addObserver(self, selector: #selector(changed), name: name, object: nil)
        }
    }

    // Power notifications arrive on a global queue; WebKit belongs to the main actor.
    @objc private nonisolated func changed() {
        Task { @MainActor [weak self] in self?.onChange?() }
    }
    deinit { notifications.removeObserver(self) }
}
