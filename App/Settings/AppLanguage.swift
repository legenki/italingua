import Foundation
#if os(macOS)
import AppKit
#endif

/// Interface language: Russian, English or Spanish, or the system's choice.
/// It also picks the language of translations in the course (word glosses,
/// rules). Applied through `AppleLanguages`, so the system menus follow too;
/// it takes effect after a restart.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, ru, en, es

    var id: String { rawValue }

    /// Language names are shown in their own language and never translated.
    var nativeName: String {
        switch self {
        case .system: String(localized: "Как в системе")
        case .ru: "Русский"
        case .en: "English"
        case .es: "Español"
        }
    }

    static let storageKey = "interfaceLanguage"

    /// What the learner chose in Settings.
    static var chosen: AppLanguage {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// The language the app runs in now: "ru", "en" or "es".
    static var current: String {
        let code = Bundle.main.preferredLocalizations.first ?? "ru"
        return ["ru", "en", "es"].contains(code) ? code : "ru"
    }

    static var locale: Locale { Locale(identifier: current) }

    /// Saves the choice for the next launch.
    static func choose(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    /// Whether the chosen language differs from the one the app runs in.
    static var needsRestart: Bool {
        switch chosen {
        case .system: false
        default: chosen.rawValue != current
        }
    }

    #if os(macOS)
    /// Starts a new copy of the app and quits this one.
    @MainActor static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
    #endif

    /// Picks the text for the running language from a course entry.
    static func pick(ru: String, en: String?, es: String?) -> String {
        switch current {
        case "en": en.flatMap { $0.isEmpty ? nil : $0 } ?? ru
        case "es": es.flatMap { $0.isEmpty ? nil : $0 } ?? ru
        default: ru
        }
    }
}
