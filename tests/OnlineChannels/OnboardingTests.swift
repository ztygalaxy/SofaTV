import Foundation
import Testing
@testable import SofaTV

struct OnboardingTests {
    @MainActor @Test(arguments: ["hasShownOnboarding", "channel-lists", "channels", "mainWindowFrame"])
    func showsAutomaticallyOnlyForFreshProfiles(existingKey: String) throws {
        let suite = "OnboardingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(OnboardingWindow.shouldShowOnLaunch(defaults: defaults))
        // Older builds persist the channel library even when it is empty.
        defaults.set(existingKey == "hasShownOnboarding" ? true : Data("[]".utf8), forKey: existingKey)
        #expect(!OnboardingWindow.shouldShowOnLaunch(defaults: defaults))
    }
}
