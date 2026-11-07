import Foundation
import IOKit.pwr_mgt

@main struct PlaybackSleepChecks {
    @MainActor static func main() async throws {
        func assertions() -> [[String: Any]] {
            var unmanaged: Unmanaged<CFDictionary>?
            precondition(IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess)
            let processes = unmanaged!.takeRetainedValue() as NSDictionary
            let current = processes[NSNumber(value: ProcessInfo.processInfo.processIdentifier)] as? [[String: Any]] ?? []
            return current.filter {
                $0[kIOPMAssertionNameKey] as? String == PlaybackSleepPrevention.reason &&
                ($0[kIOPMAssertionLevelKey] as? NSNumber)?.intValue == Int(kIOPMAssertionLevelOn)
            }
        }

        func waitForCount(_ count: Int) async throws {
            for _ in 0..<100 {
                if assertions().count == count { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            preconditionFailure("Expected \(count) playback power assertions, found \(assertions())")
        }

        var prevention: PlaybackSleepPrevention? = PlaybackSleepPrevention()
        try await waitForCount(0)
        prevention!.setPlaying(false)
        try await waitForCount(0)
        prevention!.setPlaying(true)
        try await waitForCount(1)
        precondition(assertions()[0][kIOPMAssertionTypeKey] as? String == kIOPMAssertionTypePreventUserIdleDisplaySleep)
        for _ in 0..<20 { prevention!.setPlaying(true) }
        try await waitForCount(1)
        prevention!.setPlaying(false)
        try await waitForCount(0)
        prevention!.setPlaying(true)
        try await waitForCount(1)
        prevention = nil
        try await waitForCount(0)

        let first = PlaybackSleepPrevention()
        let second = PlaybackSleepPrevention()
        first.setPlaying(true)
        second.setPlaying(true)
        try await waitForCount(2)
        first.setPlaying(false)
        try await waitForCount(1)
        second.setPlaying(false)
        try await waitForCount(0)
        print("Playback sleep checks passed: real display-sleep assertions, repeated starts, stop, disposal and independent players")
    }
}
