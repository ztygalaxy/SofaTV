import Foundation

func check(_ condition: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(condition, "Update check failed", file: file, line: line)
}

func expectThrows<T>(_ operation: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do {
        _ = try operation()
        preconditionFailure("Expected an update error", file: file, line: line)
    } catch {}
}

func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw URLError(.unknown) }
    return value
}

@main struct UpdateChecks {
    @MainActor static func main() async throws {
        let automatic = AutomaticUpdateTests()
        try await automatic.testWaitsForDeadlineAndShowsOnlyOnce()
        try await automatic.testWatchingAtDeadlineSuppressesLateResult()
        try await automatic.testWatchingBeforeLateResponsePreventsPrompt()
        try await automatic.testCancelledForManualCheckDoesNotShowAutomaticPrompt()
        try await automatic.testSkipsExactVersionButAllowsNextRelease()
        try await automatic.testEmptyAndFailedChecksAreSilent()
        print("Automatic update checks passed: deadline, watching suppression, cancellation, skipped versions and silent errors")
        let window = UpdateWindowTests()
        try UpdateMarkdownTests().run()
        await window.testReleaseNotesAdaptToWrappedLinesAndCapAtFifteen()
        try await window.testButtonsAlignAndSkipPersistsWithoutModalSession()
        print("Update window checks passed: adaptive notes, 15-line limit, button alignment and persistent skip")
        let installation = UpdateInstallationTests()
        try installation.testExtractsVerifiesAndReplacesSignedApplication()
        try installation.testTamperedApplicationCannotReplaceExistingVersion()
        try installation.testRejectsUnexpectedArchivePathsAndSymlinks()
        print("Update installation checks passed: checksum, extraction, signature, replacement and rejection of invalid packages")
        try await UpdateDownloadTests().run()
        print("Update download checks passed: local HTTP download, checksum, server errors and cancellation")
        try await UpdateHelperTests().run()
        print("Update helper checks passed: preflight errors, ready handshake and waiting for parent exit")
    }
}
