import Foundation

@main struct VideoVolumeScrollChecks {
    static func main() {
        var input = VideoVolumeScroll()
        var timestamp = 0.0
        func scroll(_ y: Double, x: Double = 0, precise: Bool = false, inverted: Bool = false, momentum: Bool = false) -> Float? {
            timestamp += 0.01
            return input.adjustment(horizontal: x, vertical: y, precise: precise, inverted: inverted,
                                    momentum: momentum, timestamp: timestamp)
        }
        func near(_ actual: Float?, _ expected: Float) {
            precondition(actual != nil && abs(actual! - expected) < 0.00001, "Unexpected adjustment: \(String(describing: actual))")
        }
        near(scroll(1), 0.05)
        near(scroll(-1), -0.05)
        near(scroll(1, inverted: true), -0.05)
        near(scroll(-1, inverted: true), 0.05)
        near(scroll(100), 0.05) // Each coarse wheel event is a predictable 5% step.
        precondition(scroll(0, x: 4) == nil)
        precondition(scroll(1, x: 8) == nil)
        precondition(scroll(12, precise: true, momentum: true) == nil)
        precondition(scroll(.nan) == nil)
        input.reset()
        for _ in 0..<3 { precondition(scroll(1, precise: true) == nil) }
        near(scroll(1, precise: true), 0.01) // Small trackpad events are accumulated, not discarded.
        input.reset()
        var volume: Float = 0.30
        for _ in 0..<80 { volume += scroll(1, precise: true) ?? 0 }
        precondition(abs(volume - 0.50) < 0.00001)
        input.reset()
        precondition(scroll(3, precise: true) == nil)
        precondition(scroll(-1, precise: true) == nil) // Reversing does not fight leftover upward input.
        near(scroll(-3, precise: true), -0.01)
        input.reset()
        precondition(scroll(3, precise: true) == nil)
        timestamp += 1
        precondition(scroll(1, precise: true) == nil) // A later gesture starts fresh.
        input.reset()
        precondition(scroll(1, precise: true) == nil)
        print("Video volume input checks passed: wheel, natural scrolling, precise input, direction changes, inertia and idle reset")
    }
}
