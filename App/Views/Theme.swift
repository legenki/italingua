import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Variant B "Cards": grouped grey background, white rounded cards, one green
/// accent. Every color has a dark-mode counterpart.
enum Theme {
    static let accent = dynamic(light: 0x1A7A52, dark: 0x3FBF85)
    static let accentSoft = dynamic(light: 0xE7F2EC, dark: 0x1D3A2D)
    static let background = dynamic(light: 0xF2F2F7, dark: 0x000000)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let tile = dynamic(light: 0xF4F7F5, dark: 0x2A2C2B)
    static let secondaryText = dynamic(light: 0x5C5C63, dark: 0xA1A1A8)
    static let separator = dynamic(light: 0xE5E5EA, dark: 0x38383A)
    static let warningFill = dynamic(light: 0xFFF6E8, dark: 0x3A2A12)
    static let warningText = dynamic(light: 0x8A4B00, dark: 0xF5B25A)
    static let masculine = dynamic(light: 0x1D4ED8, dark: 0x7AA2FF)
    static let masculineFill = dynamic(light: 0xE6EEFC, dark: 0x1E2A44)
    static let feminine = dynamic(light: 0xB4232A, dark: 0xFF8A8F)
    static let feminineFill = dynamic(light: 0xFDE8E8, dark: 0x452023)
    static let newBadge = dynamic(light: 0xC2410C, dark: 0xFB923C)

    static let cardRadius: CGFloat = 18

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if os(iOS)
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
        #else
        Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
        #endif
    }
}

#if os(iOS)
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#else
private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif

// MARK: - Building blocks

/// White rounded card on the grouped background.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var fill: Color = Theme.card
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// Small caps section label inside a card: "ПРИМЕРЫ".
struct CardLabel: View {
    let text: String
    var color: Color = Theme.secondaryText

    var body: some View {
        Text(text.uppercased())
            .font(.footnote.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(color)
    }
}

/// Round play/speaker button that reads Italian text aloud.
struct SpeakButton: View {
    let text: String
    var label: String = "Прослушать"
    var size: CGFloat = 44
    var style: Style = .soft

    enum Style { case soft, filled, onAccent }

    @State private var speech = Speech.shared

    var body: some View {
        let playing = speech.isSpeaking(text)
        Button {
            speech.speak(text)
        } label: {
            Image(systemName: playing ? "stop.fill" : "speaker.wave.2.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(foreground)
                .background(background, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(text)")
        .disabled(!Speech.hasItalianVoice)
    }

    private var foreground: Color {
        switch style {
        case .soft: Theme.accent
        case .filled: .white
        case .onAccent: Theme.accent
        }
    }

    private var background: Color {
        switch style {
        case .soft: Theme.accentSoft
        case .filled: Theme.accent
        case .onAccent: .white
        }
    }
}

/// "m" / "f" pill, colored by gender; part of speech otherwise.
struct WordTag: View {
    let item: VocabItem

    var body: some View {
        let (text, fg, bg): (String, Color, Color) = switch item.gender {
        case "m": ("m" + (item.isPlural ? " pl" : ""), Theme.masculine, Theme.masculineFill)
        case "f": ("f" + (item.isPlural ? " pl" : ""), Theme.feminine, Theme.feminineFill)
        case "mf": ("m/f", Theme.secondaryText, Theme.tile)
        default: (item.pos.shortRU, Theme.secondaryText, Theme.tile)
        }
        Text(text)
            .font(.footnote.weight(.bold))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Inline **bold** support for rule text.
extension Text {
    init(markup: String) {
        if let attributed = try? AttributedString(
            markdown: markup,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            self.init(attributed)
        } else {
            self.init(markup)
        }
    }
}
