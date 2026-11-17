import Foundation

/// Parsed grammar rule. The text format (also documented in CLAUDE.md):
///
///     Paragraph with **bold**.
///     • bullet
///     ! callout ("watch out") — consecutive lines form one card
///     ex: Abito a Mosca. | Я живу в Москве.
///     conj: parlare | говорить
///     io parl|o              ← six rows, "|" splits stem and ending
///     ...                    ← a blank line ends the table
nonisolated enum RuleBlock: Equatable, Sendable {
    case paragraph(String)
    case bullets([String])
    case callout([String])
    case example(italian: String, russian: String)
    case conjugation(Conjugation)
}

nonisolated struct Conjugation: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        let person: String
        let stem: String
        /// Highlighted part; empty for irregular forms written without "|".
        let ending: String

        var form: String { stem + ending }
    }

    let verb: String
    let gloss: String
    let rows: [Row]

    /// Text for speech: "io parlo, tu parli, …".
    var spoken: String { rows.map { "\($0.person) \($0.form)" }.joined(separator: ", ") }
}

nonisolated enum RuleMarkup {
    static func parse(_ text: String) -> [RuleBlock] {
        var blocks: [RuleBlock] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var i = 0

        func appendGrouped(_ line: String, into make: ([String]) -> RuleBlock,
                           match: (RuleBlock) -> [String]?) {
            if let last = blocks.last, let items = match(last) {
                blocks[blocks.count - 1] = make(items + [line])
            } else {
                blocks.append(make([line]))
            }
        }

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            defer { i += 1 }
            if line.isEmpty { continue }

            if line.hasPrefix("conj:") {
                let (verb, gloss) = split(String(line.dropFirst(5)))
                var rows: [Conjugation.Row] = []
                while i + 1 < lines.count {
                    let row = lines[i + 1].trimmingCharacters(in: .whitespaces)
                    if row.isEmpty { break }
                    rows.append(parseRow(row))
                    i += 1
                }
                blocks.append(.conjugation(Conjugation(verb: verb, gloss: gloss, rows: rows)))
            } else if line.hasPrefix("ex:") {
                let (it, ru) = split(String(line.dropFirst(3)))
                blocks.append(.example(italian: it, russian: ru))
            } else if line.hasPrefix("!") {
                appendGrouped(clean(line.dropFirst()), into: RuleBlock.callout) {
                    if case .callout(let items) = $0 { items } else { nil }
                }
            } else if line.hasPrefix("•") || line.hasPrefix("- ") {
                appendGrouped(clean(line.dropFirst()), into: RuleBlock.bullets) {
                    if case .bullets(let items) = $0 { items } else { nil }
                }
            } else {
                blocks.append(.paragraph(line))
            }
        }
        return blocks
    }

    /// Plain text without markup, for previews in lists.
    static func preview(_ text: String) -> String {
        parse(text).compactMap { block -> String? in
            switch block {
            case .paragraph(let s): s
            case .bullets(let items), .callout(let items): items.first
            case .example(let it, _): it
            case .conjugation(let c): "\(c.verb) — \(c.gloss)"
            }
        }
        .joined(separator: " ")
        .replacingOccurrences(of: "**", with: "")
    }

    private static func clean(_ s: Substring) -> String {
        s.trimmingCharacters(in: .whitespaces)
    }

    private static func split(_ s: String) -> (String, String) {
        let parts = s.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return (parts.first ?? "", parts.count > 1 ? parts[1] : "")
    }

    private static func parseRow(_ row: String) -> Conjugation.Row {
        var words = row.split(separator: " ").map(String.init)
        let form = words.popLast() ?? ""
        let person = words.joined(separator: " ")
        let pieces = form.split(separator: "|", maxSplits: 1).map(String.init)
        return pieces.count == 2
            ? Conjugation.Row(person: person, stem: pieces[0], ending: pieces[1])
            : Conjugation.Row(person: person, stem: form, ending: "")
    }
}
