import Observation
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Text size chosen with the "A / A" buttons, like in the Dictionary app.
/// macOS ignores Dynamic Type, so every font in the app goes through
/// `Font.s(_:)` / `Font.scaledSystem(size:)`, which multiply by this factor.
/// It is @Observable: a view that reads a scaled font while building its body
/// is redrawn when the size changes, and keeps its state.
@Observable
final class TextScale {
    static let shared = TextScale()
    static let range = -2...5
    private static let key = "textScaleStep"

    var step: Int {
        didSet { UserDefaults.standard.set(step, forKey: Self.key) }
    }

    init() {
        step = (UserDefaults.standard.object(forKey: Self.key) as? Int).map { min(max($0, Self.range.lowerBound), Self.range.upperBound) } ?? 0
    }

    /// 0.8 … 1.5 in steps of 10 %.
    var factor: CGFloat { 1 + CGFloat(step) * 0.1 }

    var canShrink: Bool { step > Self.range.lowerBound }
    var canGrow: Bool { step < Self.range.upperBound }

    func shrink() { if canShrink { step -= 1 } }
    func grow() { if canGrow { step += 1 } }
}

extension Font {
    /// A text style at the app's text size.
    static func s(_ style: Font.TextStyle) -> Font {
        let (size, weight) = base(style)
        return .system(size: scaled(size, style: style), weight: weight)
    }

    /// `.system(size:)` at the app's text size.
    static func scaledSystem(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        .system(size: scaled(size, style: nil), weight: weight, design: design)
    }

    private static func scaled(_ size: CGFloat, style: Font.TextStyle?) -> CGFloat {
        let factor = TextScale.shared.factor
        #if os(iOS)
        // Keep Dynamic Type on iPhone and apply the app's size on top of it.
        if let style { return UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: size * factor) }
        #endif
        return size * factor
    }

    /// Platform default sizes of the text styles.
    private static func base(_ style: Font.TextStyle) -> (CGFloat, Font.Weight) {
        #if os(macOS)
        switch style {
        case .largeTitle: (26, .regular)
        case .title: (22, .regular)
        case .title2: (17, .regular)
        case .title3: (15, .regular)
        case .headline: (13, .bold)
        case .subheadline: (11, .regular)
        case .callout: (12, .regular)
        case .footnote: (10, .regular)
        case .caption: (10, .regular)
        case .caption2: (10, .regular)
        default: (13, .regular)
        }
        #else
        switch style {
        case .largeTitle: (34, .regular)
        case .title: (28, .regular)
        case .title2: (22, .regular)
        case .title3: (20, .regular)
        case .headline: (17, .semibold)
        case .subheadline: (15, .regular)
        case .callout: (16, .regular)
        case .footnote: (13, .regular)
        case .caption: (12, .regular)
        case .caption2: (11, .regular)
        default: (17, .regular)
        }
        #endif
    }
}

#if os(iOS)
private extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}
#endif

/// "A / A" buttons: smaller and larger text (⌘− and ⌘+).
struct TextSizeButtons: View {
    @State private var scale = TextScale.shared

    var body: some View {
        ControlGroup {
            Button { scale.shrink() } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .disabled(!scale.canShrink)
            .keyboardShortcut("-", modifiers: .command)
            .help("Уменьшить текст (⌘−)")
            .accessibilityLabel("Уменьшить текст")
            Button { scale.grow() } label: {
                Image(systemName: "textformat.size.larger")
            }
            .disabled(!scale.canGrow)
            .keyboardShortcut("+", modifiers: .command)
            .help("Увеличить текст (⌘+)")
            .accessibilityLabel("Увеличить текст")
        }
    }
}
