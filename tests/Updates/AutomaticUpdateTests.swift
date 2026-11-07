import Foundation

@MainActor
struct AutomaticUpdateTests {
    private func fixture(version: String = "0.0.4") -> VerifiedUpdate {
        VerifiedUpdate(version: SemanticVersion(version)!, notes: "更新", asset: UpdateAsset(name: "test.zip", sha256: String(repeating: "a", count: 64)),
                       downloadURL: URL(string: "https://example.com/test.zip")!, releaseURL: URL(string: "https://example.com")!)
    }

    func testWaitsForDeadlineAndShowsOnlyOnce() async throws {
        let policy = AutomaticUpdateCheck(delay: .milliseconds(80))
        var shown = 0
        let update = fixture()
        policy.start(isWatching: { false }, fetch: { update }, show: { _ in shown += 1 })
        try await Task.sleep(for: .milliseconds(20))
        check(shown == 0)
        try await Task.sleep(for: .milliseconds(100))
        check(shown == 1)
        policy.start(isWatching: { false }, fetch: { update }, show: { _ in shown += 1 })
        try await Task.sleep(for: .milliseconds(100))
        check(shown == 1)
    }

    func testWatchingAtDeadlineSuppressesLateResult() async throws {
        let policy = AutomaticUpdateCheck(delay: .milliseconds(60))
        var watching = true
        var shown = false
        let update = fixture()
        policy.start(isWatching: { watching }, fetch: {
            try await Task.sleep(for: .milliseconds(160))
            return update
        }, show: { _ in shown = true })
        try await Task.sleep(for: .milliseconds(100))
        watching = false
        try await Task.sleep(for: .milliseconds(120))
        check(!shown)
        policy.cancel()
    }

    func testWatchingBeforeLateResponsePreventsPrompt() async throws {
        let policy = AutomaticUpdateCheck(delay: .milliseconds(40))
        var watching = false
        var shown = false
        let update = fixture()
        policy.start(isWatching: { watching }, fetch: {
            try await Task.sleep(for: .milliseconds(140))
            return update
        }, show: { _ in shown = true })
        try await Task.sleep(for: .milliseconds(80))
        watching = true
        try await Task.sleep(for: .milliseconds(110))
        check(!shown)
        policy.cancel()
    }

    func testCancelledForManualCheckDoesNotShowAutomaticPrompt() async throws {
        let policy = AutomaticUpdateCheck(delay: .milliseconds(50))
        var shown = false
        let update = fixture()
        policy.start(isWatching: { false }, fetch: { update }, show: { _ in shown = true })
        policy.cancel()
        try await Task.sleep(for: .milliseconds(100))
        check(!shown)
    }

    func testSkipsExactVersionButAllowsNextRelease() async throws {
        let name = "SofaTV.UpdateTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("0.0.4", forKey: AutomaticUpdateCheck.skippedVersionKey)
        for version in ["0.0.4", "0.0.5"] {
            let policy = AutomaticUpdateCheck(defaults: defaults, delay: .milliseconds(20))
            var shown = false
            let update = fixture(version: version)
            policy.start(isWatching: { false }, fetch: { update }, show: { _ in shown = true })
            try await Task.sleep(for: .milliseconds(70))
            check(shown == (version == "0.0.5"))
            policy.cancel()
        }
    }

    func testEmptyAndFailedChecksAreSilent() async throws {
        for failure in [false, true] {
            let policy = AutomaticUpdateCheck(delay: .milliseconds(20))
            var shown = false
            policy.start(isWatching: { false }, fetch: {
                if failure { throw URLError(.notConnectedToInternet) }
                return nil
            }, show: { _ in shown = true })
            try await Task.sleep(for: .milliseconds(70))
            check(!shown)
            policy.cancel()
        }
    }
}
