import SwiftUI

/// Renders a rule written in RuleMarkup as a column of cards (variant B).
struct RuleBlocksView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(Self.sections(RuleMarkup.parse(text)).enumerated()), id: \.offset) { _, section in
                switch section {
                case .text(let blocks): TextCard(blocks: blocks)
                case .callout(let lines): CalloutCard(lines: lines)
                case .conjugation(let c): ConjugationCard(conjugation: c)
                case .examples(let items): ExamplesCard(items: items)
                case .table(let t): TableCard(table: t)
                }
            }
        }
        // Selectable, so the system "Speak Selection" (⌥Esc) can read it too.
        .textSelection(.enabled)
    }

    enum Section {
        case text([RuleBlock])
        case callout([String])
        case conjugation(Conjugation)
        case examples([(String, String)])
        case table(RuleTable)
    }

    /// Paragraphs and bullets that follow each other share one card; so do examples.
    static func sections(_ blocks: [RuleBlock]) -> [Section] {
        var out: [Section] = []
        for block in blocks {
            switch block {
            case .paragraph, .bullets:
                if case .text(let prev) = out.last {
                    out[out.count - 1] = .text(prev + [block])
                } else {
                    out.append(.text([block]))
                }
            case .callout(let lines):
                out.append(.callout(lines))
            case .conjugation(let c):
                out.append(.conjugation(c))
            case .table(let t):
                out.append(.table(t))
            case .example(let it, let ru):
                if case .examples(let prev) = out.last {
                    out[out.count - 1] = .examples(prev + [(it, ru)])
                } else {
                    out.append(.examples([(it, ru)]))
                }
            }
        }
        return out
    }
}

private struct TextCard: View {
    let blocks: [RuleBlock]

    var body: some View {
        Card {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let s):
                    Text(markup: s).font(.s(.body))
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Circle().fill(Theme.accent).frame(width: 6, height: 6)
                                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                                Text(markup: item)
                            }
                        }
                    }
                default:
                    EmptyView()
                }
            }
        }
    }
}

private struct CalloutCard: View {
    let lines: [String]

    var body: some View {
        Card(fill: Theme.warningFill) {
            CardLabel(text: "Осторожно", color: Theme.warningText)
            ForEach(lines, id: \.self) { Text(markup: $0) }
        }
    }
}

private struct ConjugationCard: View {
    let conjugation: Conjugation

    var body: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conjugation.verb).font(.s(.title2).weight(.semibold))
                    Text(conjugation.gloss).font(.s(.subheadline)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                SpeakButton(text: conjugation.spoken, label: "Прослушать формы", style: .filled)
            }
            // io/tu/lui in the left column, noi/voi/loro in the right one.
            let half = (conjugation.rows.count + 1) / 2
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<half, id: \.self) { i in
                    GridRow {
                        tile(conjugation.rows[i])
                        if i + half < conjugation.rows.count {
                            tile(conjugation.rows[i + half])
                        }
                    }
                }
            }
        }
    }

    private func tile(_ row: Conjugation.Row) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.person).font(.s(.caption).weight(.medium)).foregroundStyle(Theme.secondaryText)
            Text("\(row.stem)\(Text(row.ending).bold().foregroundStyle(Theme.accent))")
                .font(.s(.title3))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ExamplesCard: View {
    let items: [(String, String)]

    var body: some View {
        Card(padding: 0) {
            CardLabel(text: "Примеры")
                .padding([.top, .horizontal], 16)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, 72)
                    }
                    HStack(spacing: 12) {
                        SpeakButton(text: item.0, label: "Прослушать пример")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(markup: item.0).font(.s(.body))
                            Text(item.1).font(.s(.subheadline)).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .padding(.bottom, 6)
        }
    }
}

private struct TableCard: View {
    let table: RuleTable

    var body: some View {
        Card(padding: 0) {
            // Wide tables scroll sideways on a narrow screen instead of squeezing.
            ViewThatFits(in: .horizontal) {
                grid
                ScrollView(.horizontal, showsIndicators: false) { grid }
            }
            .padding(.vertical, 6)
        }
    }

    private var speaks: Bool { !table.spokenColumns.isEmpty }

    private var grid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 0) {
            GridRow {
                if speaks { Color.clear.frame(width: 1, height: 1) }
                ForEach(Array(table.header.enumerated()), id: \.offset) { _, title in
                    Text(title)
                        .font(.s(.caption).weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize()
                }
            }
            .padding(.vertical, 8)

            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                Rectangle().fill(Theme.separator).frame(height: 1)
                GridRow(alignment: .center) {
                    if speaks {
                        if let text = table.spoken(row) {
                            SpeakButton(text: text, label: "Прослушать", size: 32)
                        } else {
                            Color.clear.frame(width: 32, height: 32)
                        }
                    }
                    ForEach(Array(table.header.indices), id: \.self) { col in
                        let cell = col < row.count ? row[col] : ""
                        Text(markup: cell)
                            .font(table.spokenColumns.contains(col) ? .body.weight(.semibold) : .body)
                            .foregroundStyle(col == 0 || table.spokenColumns.contains(col) ? .primary : Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, speaks ? 6 : 10)
            }
        }
        .padding(.horizontal, 16)
    }
}
