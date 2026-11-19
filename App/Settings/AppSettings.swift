import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Light or dark look, chosen in Settings; "system" follows the device.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "Как в системе")
        case .light: String(localized: "Светлая")
        case .dark: String(localized: "Тёмная")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Applies the choice to every window. On macOS this goes through
    /// NSApp.appearance, which (unlike preferredColorScheme) also returns
    /// cleanly to the system look.
    func apply() {
        #if os(macOS)
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        #endif
    }
}

enum SettingsKey {
    static let appearance = "appearance"
    static let voiceAnswers = "voiceAnswers"
}

extension View {
    /// Light/dark override from Settings for this window (iOS) or the app (macOS).
    func appAppearance() -> some View { modifier(AppearanceModifier()) }
}

private struct AppearanceModifier: ViewModifier {
    @AppStorage(SettingsKey.appearance) private var appearance = Appearance.system

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .preferredColorScheme(appearance.colorScheme)
            #endif
            .onChange(of: appearance, initial: true) { _, new in new.apply() }
    }
}
