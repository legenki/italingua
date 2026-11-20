import SwiftData
import SwiftUI

struct VocabularyView: View {
    let lesson: Lesson
    @Query private var progress: [WordProgress]
    @Query private var favorites: [FavoriteWord]
    @State private var search = ""
    @State private var onlyNew = false

    var body: some View {
        let byID = Dictionary(progress.map { ($0.wordID, $0) }, uniquingKeysWith: { a, _ in a })
        let starred = Set(favorites.map(\.wordID))
        let items = lesson.sortedVocab
        let learned = items.filter { byID[$0.wordID]?.isLearned == true }.count
        let due = items.filter { item in
            guard let p = byID[item.wordID] else { return false }
            return p.box > 0 && p.dueDate <= .now
        }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "Лексика")).font(.s(.largeTitle).weight(.bold))

                Card {
                    HStack {
                        Text(String(localized: "\(learned) из \(items.count) выучено")).font(.s(.headline))
                        Spacer()
                        Text(String(localized: "\(due) к повторению")).font(.s(.subheadline)).foregroundStyle(Theme.secondaryText)
                    }
                    ProgressView(value: Double(learned), total: Double(max(items.count, 1)))
                        .tint(Theme.accent)
                    NavigationLink {
                        FlashcardsView(lesson: lesson)
                    } label: {
                        Label(String(localized: "Учить карточками"), systemImage: "rectangle.on.rectangle.angled")
                            .font(.s(.subheadline).weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }

                if let word = focusWord(items, byID: byID) {
                    FocusWordCard(item: word, dueCount: due, lesson: lesson)
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
                    TextField(String(localized: "Поиск по слову или переводу"), text: $search)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                    Toggle(String(localized: "Новые"), isOn: $onlyNew)
                        .toggleStyle(.button)
                        .tint(Theme.accent)
                        .font(.s(.subheadline))
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                let shown = filtered(items)
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.wordID) { index, item in
                            if index > 0 {
                                Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, 72)
                            }
                            VocabRow(item: item, box: byID[item.wordID]?.box ?? 0, isFavorite: starred.contains(item.wordID))
                        }
                        if shown.isEmpty {
                            Text(String(localized: "Ничего не найдено"))
                                .foregroundStyle(Theme.secondaryText)
                                .padding(16)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .textSelection(.enabled)
            }
            .padding(16)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("")
    }

    /// The word to put on the big card: one that is due, else one never practised.
    private func focusWord(_ items: [VocabItem], byID: [String: WordProgress]) -> VocabItem? {
        items.first { byID[$0.wordID].map { $0.box > 0 && $0.dueDate <= .now } ?? false }
            ?? items.first { byID[$0.wordID] == nil && $0.pos != .proper }
    }

    private func filtered(_ items: [VocabItem]) -> [VocabItem] {
        let base = onlyNew ? items.filter(\.isNew) : items
        guard !search.isEmpty else { return base }
        let q = AnswerChecker.fold(search)
        return base.filter {
            AnswerChecker.fold($0.italian).contains(q) || AnswerChecker.fold($0.translation).contains(q)
        }
    }
}

private struct FocusWordCard: View {
    let item: VocabItem
    let dueCount: Int
    let lesson: Lesson

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CardLabel(text: dueCount > 0 ? String(localized: "Пора повторить") : String(localized: "Новое слово"), color: Theme.onAccent.opacity(0.85))
                Spacer()
                if let g = item.gender {
                    Text(g)
                        .font(.s(.footnote).weight(.bold))
                        .foregroundStyle(g == "f" ? Theme.feminine : Theme.masculine)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.onAccent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            Text(item.displayWithArticle)
                .font(.scaledSystem(size: 34, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            Text(item.translation).font(.s(.title3)).opacity(0.9)
            HStack(spacing: 10) {
                SpeakButton(text: item.withArticle, size: 48, style: .onAccent)
                NavigationLink {
                    FillBlankView(lesson: lesson)
                } label: {
                    Text(dueCount > 0 ? String(localized: "Повторить \(dueCount)") : String(localized: "Тренировка"))
                        .font(.s(.headline))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.onAccent, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Theme.onAccent)
        .padding(22)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct VocabRow: View {
    let item: VocabItem
    let box: Int
    let isFavorite: Bool

    var body: some View {
        HStack(spacing: 12) {
            SpeakButton(text: item.withArticle)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayWithArticle).font(.s(.body).weight(.semibold))
                    if item.isNew {
                        Text(String(localized: "НОВОЕ")).font(.s(.caption2).weight(.bold)).foregroundStyle(Theme.newBadge)
                    }
                }
                Text(item.translation + (item.formOf.map { String(localized: " · от \($0)") } ?? ""))
                    .font(.s(.subheadline))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            WordTag(item: item)
            LeitnerDots(box: box)
            FavoriteButton(wordID: item.wordID, isFavorite: isFavorite)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// Five dots, filled up to the word's Leitner box.
struct LeitnerDots: View {
    let box: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...Leitner.maxBox, id: \.self) { i in
                Circle()
                    .fill(i <= box ? Theme.accent : Theme.separator)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Уровень \(box) из \(Leitner.maxBox)"))
    }
}
