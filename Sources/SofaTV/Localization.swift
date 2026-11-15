import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case chinese = "zh-Hans"

    static let defaultsKey = "interfaceLanguage"
    var id: Self { self }

    func resolved(for preferredLanguages: [String]) -> Self {
        guard self == .system else { return self }
        let language = preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier }
        switch language {
        case "zh", "yue", "cmn": return .chinese
        default: return .english
        }
    }

    private static let systemLanguages: [String] = {
        // The previous app stored a Chinese override in its own defaults domain.
        // Read the global preference independently of that override.
        return UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
            ?? Locale.preferredLanguages
    }()

    var resolved: Self {
        self == .system ? Self.systemLanguage : self
    }

    private static let systemLanguage = Self.system.resolved(for: systemLanguages)
}

@Observable final class L10n: Sendable {
    static let shared = L10n()
    static let didChange = Notification.Name("SofaTV.interfaceLanguageDidChange")

    private init() {}

    var preference: AppLanguage {
        access(keyPath: \.preference)
        return UserDefaults.standard.string(forKey: AppLanguage.defaultsKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    @MainActor func select(_ preference: AppLanguage) {
        guard preference != self.preference else { return }
        withMutation(keyPath: \.preference) { UserDefaults.standard.set(preference.rawValue, forKey: AppLanguage.defaultsKey) }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    static var language: AppLanguage { shared.preference.resolved }
    static var locale: Locale { Locale(identifier: language.rawValue) }

    private static let english = Bundle.main.path(forResource: AppLanguage.english.rawValue, ofType: "lproj")
        .flatMap(Bundle.init(path:))
    private static let chinese = Bundle.main.path(forResource: AppLanguage.chinese.rawValue, ofType: "lproj")
        .flatMap(Bundle.init(path:))

    static func text(_ value: String.LocalizationValue, language: AppLanguage = L10n.language) -> String {
        let bundle = language == .chinese ? chinese : english
        return String(localized: value, bundle: bundle ?? .main, locale: Locale(identifier: language.rawValue))
    }

    static func configureAtLaunch() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "AppleLanguages")
        // Capture the system choice before setting the process's launch language.
        _ = AppLanguage.system.resolved
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments["AppleLanguages"] = [language.rawValue]
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }
}
