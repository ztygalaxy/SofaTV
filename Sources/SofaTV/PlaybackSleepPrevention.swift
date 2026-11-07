import Foundation

/// Owned and updated by the main-actor Library, across all playback windows.
final class PlaybackSleepPrevention {
    static let reason = "SofaTV video playback"
    private var activity: NSObjectProtocol?

    func setPlaying(_ playing: Bool) {
        if playing {
            guard activity == nil else { return }
            activity = ProcessInfo.processInfo.beginActivity(options: .idleDisplaySleepDisabled, reason: Self.reason)
        } else {
            endActivity()
        }
    }

    private func endActivity() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }

    deinit { endActivity() }
}
