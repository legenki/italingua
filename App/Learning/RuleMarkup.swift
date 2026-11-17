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
///     table: Буква | Название* | Звук   ← header; "*" marks columns to speak
///     A | a | [а]            ← rows until a blank line
nonisolated enum RuleBlock: Equatable, Sendable {
    case paragraph(String)
    case bullets([String])
    case callout([String])
    case example(italian: String, russian: String)
    case conjugation(Conjugation)
    case table(RuleTable)
}

nonisolated struct RuleTable: Equatable, Sendable {
    let header: [String]
    let rows: [[String]]
    /// Columns marked with "*" in the header; their cells are read aloud.
    let spokenColumns: [Int]

    /// Text for speech for one row, or nil when the table has nothing to speak.
    func spoken(_ row: [String]) -> String? {
        let parts = spokenColumns.compactMap { $0 < row.count ? row[$0] : nil }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
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
            } else if line.hasPrefix("table:") {
                let raw = cells(String(line.dropFirst(6)))
                var rows: [[String]] = []
                while i + 1 < lines.count {
                    let row = lines[i + 1].trimmingCharacters(in: .whitespaces)
                    if row.isEmpty { break }
                    rows.append(cells(row))
                    i += 1
                }
                let marked = { (h: String) in h.hasSuffix("*") && !h.hasSuffix("**") }
                let spoken = raw.indices.filter { marked(raw[$0]) }
                let header = raw.map { marked($0) ? String($0.dropLast()).trimmingCharacters(in: .whitespaces) : $0 }
                blocks.append(.table(RuleTable(header: header, rows: rows, spokenColumns: spoken)))
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
        let blocks = parse(text)
        // Tables read badly as one line; they appear in the preview only when
        // the rule has nothing else.
        let prose = blocks.filter { if case .table = $0 { false } else { true } }
        return (prose.isEmpty ? blocks : prose).compactMap { block -> String? in
            switch block {
            case .paragraph(let s): s
            case .bullets(let items), .callout(let items): items.first
            case .example(let it, _): it
            case .conjugation(let c): "\(c.verb) — \(c.gloss)"
            case .table(let t): t.rows.first?.joined(separator: " · ")
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

    private static func cells(_ s: String) -> [String] {
        s.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
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
