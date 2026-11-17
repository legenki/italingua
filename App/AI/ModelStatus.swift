import Foundation
import FoundationModels

/// Whether the on-device model can be used, with a message for the UI.
nonisolated enum ModelStatus: Equatable, Sendable {
    case available
    case unavailable(String)

    var isAvailable: Bool { self == .available }

    static func current(model: SystemLanguageModel = .default) -> ModelStatus {
        switch model.availability {
        case .available:
            // Exercises are generated in Italian, so Italian must be supported.
            return model.supportsLocale(Locale(identifier: "it_IT"))
                ? .available
                : .unavailable("Модель не поддерживает итальянский на этом устройстве.")
        case .unavailable(.deviceNotEligible):
            return .unavailable("Это устройство не поддерживает Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Apple Intelligence выключен. Включите его в Настройках.")
        case .unavailable(.modelNotReady):
            return .unavailable("Модель ещё загружается. Попробуйте позже.")
        case .unavailable:
            return .unavailable("Модель недоступна.")
        }
    }

    /// Diagnostics for the stats screen: which languages the model accepts.
    /// Russian matters for later features (explanations, checking answers).
    static func supportsRussian(model: SystemLanguageModel = .default) -> Bool {
        model.supportsLocale(Locale(identifier: "ru_RU"))
    }
}
