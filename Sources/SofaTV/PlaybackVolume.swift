import Foundation

/// App-wide mute is separate from per-channel volume preferences and playback-engine handoff.
struct PlaybackVolume: Equatable {
    private(set) var volume: Float
    private(set) var isMuted: Bool
    private(set) var volumeBeforeMute: Float

    init(isMuted: Bool = false, volumeBeforeMute: Float = 0.3) {
        let remembered = Self.normalized(volumeBeforeMute) ?? 0.3
        self.volumeBeforeMute = remembered > 0 ? remembered : 0.3
        self.isMuted = isMuted
        volume = isMuted ? 0 : self.volumeBeforeMute
    }
    mutating func setVolume(_ value: Float) {
        guard let level = Self.normalized(value) else { return }
        if level > 0 {
            volume = level; volumeBeforeMute = level; isMuted = false
        } else {
            if volume > 0 { volumeBeforeMute = volume }
            volume = 0; isMuted = true
        }
    }
    mutating func toggleMute() {
        if isMuted || volume == 0 {
            volume = volumeBeforeMute; isMuted = false
        } else {
            volumeBeforeMute = volume; volume = 0; isMuted = true
        }
    }
    mutating func restoreChannelVolume(_ value: Float) {
        // Switching channels must neither release mute nor replace its remembered level.
        guard !isMuted else { return }
        volume = Self.normalized(value) ?? 0.3
        if volume > 0 { volumeBeforeMute = volume }
    }
    private static func normalized(_ value: Float) -> Float? {
        guard value.isFinite else { return nil }
        return (min(1, max(0, value)) * 100).rounded() / 100
    }
}
