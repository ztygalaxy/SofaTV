import Foundation

/// Convert device input to bounded volume steps without carrying touchpad inertia.
struct VideoVolumeScroll {
    private var remainder = 0.0
    private var lastTimestamp: TimeInterval?
    private var lastDirection = 0.0

    mutating func reset() {
        remainder = 0; lastTimestamp = nil; lastDirection = 0
    }
    mutating func adjustment(horizontal: Double, vertical: Double, precise: Bool,
                             inverted: Bool, momentum: Bool, timestamp: TimeInterval) -> Float? {
        guard horizontal.isFinite, vertical.isFinite, timestamp.isFinite,
              !momentum, abs(vertical) > abs(horizontal) else { return nil }
        // Volume follows physical wheel direction, independent of natural scrolling preferences.
        let delta = inverted ? -vertical : vertical
        let direction = delta > 0 ? 1.0 : -1.0
        let newGesture = lastTimestamp.map { timestamp < $0 || timestamp - $0 > 0.3 } ?? true
        if newGesture || direction != lastDirection {
            remainder = 0
        }
        lastTimestamp = timestamp; lastDirection = direction
        guard precise else { remainder = 0; return Float(direction * 0.05) }
        remainder += delta * 0.0025
        let steps = (remainder * 100 + direction * 1e-9).rounded(.towardZero)
        guard steps != 0 else { return nil }
        let adjustment = steps / 100
        remainder -= adjustment
        return Float(adjustment)
    }
}
