import Foundation

@main struct PlaybackVolumeChecks {
    static func main() {
        func near(_ actual: Float, _ expected: Float) { precondition(abs(actual - expected) < 0.00001) }
        var state = PlaybackVolume()
        state.setVolume(0.67)
        state.toggleMute()
        precondition(state.isMuted); near(state.volume, 0); near(state.volumeBeforeMute, 0.67)
        state.restoreChannelVolume(0.25)
        state.restoreChannelVolume(0.9)
        precondition(state.isMuted); near(state.volume, 0); near(state.volumeBeforeMute, 0.67)
        state.toggleMute()
        precondition(!state.isMuted); near(state.volume, 0.67)
        // Once unmuted, the next channel still restores its own preference.
        state.restoreChannelVolume(0.25)
        near(state.volume, 0.25)
        state.setVolume(0)
        precondition(state.isMuted); near(state.volumeBeforeMute, 0.25)
        state.setVolume(0) // Repeated zero must not erase the remembered level.
        state.restoreChannelVolume(0.8)
        state.toggleMute()
        near(state.volume, 0.25)
        state.toggleMute()
        state.setVolume(0.12) // Explicit slider/wheel adjustment releases mute.
        precondition(!state.isMuted); near(state.volume, 0.12)
        state.toggleMute()
        var restored = PlaybackVolume(isMuted: state.isMuted, volumeBeforeMute: state.volumeBeforeMute)
        restored.restoreChannelVolume(0.8)
        precondition(restored.isMuted); near(restored.volume, 0)
        restored.toggleMute(); near(restored.volume, 0.12)
        restored.setVolume(2); near(restored.volume, 1)
        restored.setVolume(-1); precondition(restored.isMuted); near(restored.volume, 0)
        restored.toggleMute(); near(restored.volume, 1)
        let unchanged = restored
        restored.setVolume(.nan); precondition(restored == unchanged)
        restored.setVolume(.infinity); precondition(restored == unchanged)
        var legacy = PlaybackVolume(volumeBeforeMute: 0.42)
        legacy.restoreChannelVolume(0)
        legacy.toggleMute(); near(legacy.volume, 0.42)
        var invalid = PlaybackVolume(isMuted: true, volumeBeforeMute: .nan)
        invalid.toggleMute(); near(invalid.volume, 0.3)
        print("Playback volume checks passed: mute restore, cross-channel silence, zero input, explicit adjustment and persisted mute")
    }
}
