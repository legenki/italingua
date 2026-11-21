import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Accent palettes the learner can pick in Settings. Each has the main accent,
/// a soft fill and a ramp of shades (lightest → full) for charts.
enum Palette: String, CaseIterable, Identifiable {
    case green, blue, red, ochre

    var id: String { rawValue }

    var title: String {
        switch self {
        case .green: String(localized: "Зелёная")
        case .blue: String(localized: "Синяя")
        case .red: String(localized: "Красная")
        case .ochre: String(localized: "Охра")
        }
    }

    /// (light, dark) pairs.
    fileprivate var accent: (UInt32, UInt32) {
        switch self {
        case .green: (0x1A7A52, 0x3FBF85)
        case .blue: (0x1F5FBF, 0x5B9BFF)
        case .red: (0xB3261E, 0xFF7A70)
        case .ochre: (0x9A6A00, 0xF2C14E)
        }
    }

    fileprivate var soft: (UInt32, UInt32) {
        switch self {
        case .green: (0xE7F2EC, 0x1D3A2D)
        case .blue: (0xE6EEFA, 0x1C2C44)
        case .red: (0xFBE9E7, 0x3D1E1C)
        case .ochre: (0xF8F0DC, 0x3A2E12)
        }
    }

    /// Four steps from light to the accent itself; in dark mode the full
    /// accent is the brightest, so the order still reads "more = stronger".
    fileprivate var ramp: [(UInt32, UInt32)] {
        switch self {
        case .green: [(0xCFE8DA, 0x1F4A35), (0x8CCAA8, 0x2E7A55), (0x4FA77A, 0x37A06C), accent]
        case .blue: [(0xD3E2F8, 0x1E3354), (0x93B6EC, 0x2D5390), (0x5587D6, 0x3E78D6), accent]
        case .red: [(0xF6D2CE, 0x4A2220), (0xE99A92, 0x7E3730), (0xD2564B, 0xC24A40), accent]
        case .ochre: [(0xEFDDB0, 0x45361A), (0xD9B867, 0x7A5E22), (0xBD8F22, 0xC29A3A), accent]
        }
    }

    static let storageKey = "palette"

    static var current: Palette {
        UserDefaults.standard.string(forKey: storageKey).flatMap(Palette.init(rawValue:)) ?? .green
    }
}

/// Variant B "Cards": grouped grey background, white rounded cards, one accent
/// (green by default, see `Palette`). Every color has a dark-mode counterpart.
/// Accent colors are read from the current palette; the window is rebuilt when
/// it changes (RootView `.id(palette)`).
enum Theme {
    static var accent: Color { accent(of: .current) }
    static var accentSoft: Color { dynamic(Palette.current.soft) }
    /// Chart shades, lightest first; the last one equals `accent`.
    static var accentRamp: [Color] { ramp(of: .current) }

    static func accent(of palette: Palette) -> Color { dynamic(palette.accent) }
    static func ramp(of palette: Palette) -> [Color] { palette.ramp.map { dynamic($0) } }
    static var accentMid: Color { accentRamp[1] }
    /// Text and icons on an accent fill: white in light mode; near-black in
    /// dark mode, where accents are bright and white text would be too faint.
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x101211)
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
    /// Side margin of scrolling pages. iPhone/iPad: the same as the inset
    /// lesson list (16), so every screen lines up; the Mac window is roomier.
    #if os(iOS)
    static let pageMargin: CGFloat = 16
    #else
    static let pageMargin: CGFloat = 32
    #endif

    private nonisolated static func dynamic(_ pair: (UInt32, UInt32)) -> Color {
        dynamic(light: pair.0, dark: pair.1)
    }

    /// Nonisolated with a @Sendable provider: SwiftUI resolves these colors on
    /// its async render thread, and a main-actor closure crashed there
    /// (isolation check trap in TestFlight build 2 on iPhone).
    private nonisolated static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if os(iOS)
        Color(UIColor { @Sendable traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
        #else
        Color(NSColor(name: nil) { @Sendable appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
        #endif
    }
}

#if os(iOS)
private extension UIColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#else
private extension NSColor {
    nonisolated convenience init(hex: UInt32) {
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
            .font(.s(.footnote).weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(color)
    }
}

/// Round play/speaker button that reads Italian text aloud.
struct SpeakButton: View {
    let text: String
    var label: String = String(localized: "Прослушать")
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
                .font(.scaledSystem(size: size * 0.38, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(foreground)
                .background(background, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(text)")
        .disabled(!speech.hasItalianVoice)
    }

    private var foreground: Color {
        switch style {
        case .soft: Theme.accent
        case .filled: Theme.onAccent
        case .onAccent: Theme.accent
        }
    }

    private var background: Color {
        switch style {
        case .soft: Theme.accentSoft
        case .filled: Theme.accent
        case .onAccent: Theme.onAccent
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
            .font(.s(.footnote).weight(.bold))
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
