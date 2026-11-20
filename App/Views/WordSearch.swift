import SwiftData
import SwiftUI

/// Dictionary-style search over the course vocabulary.
nonisolated enum WordSearch {
    /// Best matches first: exact word, words starting with the query, a word
    /// inside a phrase starting with it, any part of the word, then the
    /// Russian translation. Accents and case are ignored.
    static func rank(query: String, italian: String, russian: String) -> Int? {
        let q = AnswerChecker.fold(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return nil }
        let it = AnswerChecker.fold(italian)
        if it == q { return 0 }
        if it.hasPrefix(q) { return 1 }
        if it.contains(" " + q) || it.contains("'" + q) { return 2 }
        if it.contains(q) { return 3 }
        if AnswerChecker.fold(russian).contains(q) { return 4 }
        return nil
    }

    @MainActor
    static func results(_ query: String, in vocab: [VocabItem], limit: Int = 100) -> [VocabItem] {
        vocab.filter { $0.pos != .proper }
            .compactMap { item in rank(query: query, italian: item.italian, russian: item.translation).map { (item, $0) } }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                if a.0.italian.count != b.0.italian.count { return a.0.italian.count < b.0.italian.count }
                return a.0.wordID < b.0.wordID
            }
            .prefix(limit)
            .map(\.0)
    }
}

/// A search result in the sidebar.
struct WordResultRow: View {
    let item: VocabItem
    let selected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayWithArticle).font(.s(.body).weight(.semibold))
                    .foregroundStyle(selected ? Theme.onAccent : .primary)
                Text(item.translation).font(.s(.subheadline))
                    .foregroundStyle(selected ? Theme.onAccent.opacity(0.85) : .secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Text(item.lesson.map { "\($0.level) · \($0.sourceLabel)" } ?? "")
                .font(.s(.caption))
                .foregroundStyle(selected ? Theme.onAccent.opacity(0.85) : .secondary)
        }
        .padding(.vertical, 6)
    }
}

/// One word, like a dictionary entry: form with article, translation,
/// learning progress and examples from the rules that use it.
struct WordDetailView: View {
    let item: VocabItem
    let openLesson: (String) -> Void
    @Query private var progress: [WordProgress]
    @Query private var favorites: [FavoriteWord]
    @Query private var topics: [GrammarTopic]

    var body: some View {
        let box = progress.filter { $0.wordID == item.wordID }.map(\.box).max() ?? 0
        let due = progress.first { $0.wordID == item.wordID }?.dueDate
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    if let lesson = item.lesson {
                        Text("\(lesson.sourceLabel) · \(lesson.level)")
                            .font(.s(.subheadline).weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    HStack(alignment: .center, spacing: 14) {
                        Text(item.displayWithArticle)
                            .font(.scaledSystem(size: 38, weight: .bold))
                            .textSelection(.enabled)
                        SpeakButton(text: item.withArticle, label: String(localized: "Прослушать слово"), size: 44, style: .filled)
                        FavoriteButton(wordID: item.wordID, isFavorite: favorites.contains { $0.wordID == item.wordID }, size: 36)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        WordTag(item: item)
                        Text(item.pos.shortRU).font(.s(.subheadline)).foregroundStyle(Theme.secondaryText)
                    }
                }

                Card {
                    CardLabel(text: String(localized: "Перевод"))
                    Text(item.translation).font(.s(.title2)).textSelection(.enabled)
                    if let form = item.formOf {
                        Text(String(localized: "Форма от \(form)")).font(.s(.subheadline)).foregroundStyle(Theme.secondaryText)
                    }
                    if let stress = item.stress {
                        Text(String(localized: "Ударение: \(stress)")).font(.s(.subheadline)).foregroundStyle(Theme.secondaryText)
                    }
                }

                Card {
                    CardLabel(text: String(localized: "Как я знаю это слово"))
                    HStack(spacing: 10) {
                        LeitnerDots(box: box)
                        Text(status(box)).font(.s(.body))
                        Spacer()
                        if box > 0, let due {
                            Text(due <= .now ? String(localized: "пора повторить") : String(localized: "повторить \(due.formatted(.relative(presentation: .named)))"))
                                .font(.s(.subheadline))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }

                let examples = self.examples
                if !examples.isEmpty {
                    Card(padding: 0) {
                        CardLabel(text: String(localized: "В примерах из правил")).padding([.top, .horizontal], 16)
                        VStack(spacing: 0) {
                            ForEach(Array(examples.enumerated()), id: \.offset) { i, ex in
                                if i > 0 { Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, 72) }
                                HStack(spacing: 12) {
                                    SpeakButton(text: ex.0, label: String(localized: "Прослушать пример"))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(markup: ex.0).font(.s(.body))
                                        Text(ex.1).font(.s(.subheadline)).foregroundStyle(Theme.secondaryText)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }
                        .padding(.bottom, 6)
                        .textSelection(.enabled)
                    }
                }

                if let lesson = item.lesson {
                    Button { openLesson(lesson.id) } label: {
                        Label(String(localized: "Открыть урок «\(lesson.title)»"), systemImage: "book")
                            .font(.s(.headline))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("")
    }

    private func status(_ box: Int) -> String {
        switch box {
        case 0: String(localized: "Ещё не изучалось")
        case 1: String(localized: "Изучаю")
        case Leitner.maxBox...: String(localized: "Выучено")
        default: String(localized: "Знакомо")
        }
    }

    /// Up to six rule examples that contain the word (whole word, ignoring accents).
    private var examples: [(String, String)] {
        let key = TranslationChecker.words(item.italian).map(TranslationChecker.fold).joined(separator: " ")
        guard !key.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [(String, String)] = []
        for topic in topics {
            for case .example(let it, let ru) in RuleMarkup.parse(topic.rule) {
                let words = " " + TranslationChecker.words(it.replacingOccurrences(of: "**", with: ""))
                    .map(TranslationChecker.fold).joined(separator: " ") + " "
                if (words.contains(" " + key + " ") || words.contains("'" + key + " ")), seen.insert(it).inserted {
                    out.append((it, ru))
                }
                if out.count == 6 { return out }
            }
        }
        return out
    }
}
