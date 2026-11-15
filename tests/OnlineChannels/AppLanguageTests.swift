import Testing
@testable import SofaTV

struct AppLanguageTests {
    @Test func systemUsesChineseForChineseAndEnglishForOtherPrimaryLanguages() {
        #expect(AppLanguage.system.resolved(for: ["zh-Hans-CN"]) == .chinese)
        #expect(AppLanguage.system.resolved(for: ["zh-Hant-TW"]) == .chinese)
        #expect(AppLanguage.system.resolved(for: ["yue-Hant-HK"]) == .chinese)
        #expect(AppLanguage.system.resolved(for: ["fr-FR", "zh-Hans"]) == .english)
        #expect(AppLanguage.system.resolved(for: []) == .english)
    }

    @Test func manualLanguageOverridesTheSystemLanguage() {
        #expect(AppLanguage.english.resolved(for: ["zh-Hans"]) == .english)
        #expect(AppLanguage.chinese.resolved(for: ["en-US"]) == .chinese)
    }
}
