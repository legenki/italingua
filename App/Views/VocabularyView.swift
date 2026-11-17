import SwiftData
import SwiftUI

struct VocabularyView: View {
    let lesson: Lesson
    @Query private var progress: [WordProgress]
    @State private var search = ""
    @State private var onlyNew = false

    var body: some View {
        let byID = Dictionary(progress.map { ($0.wordID, $0) }, uniquingKeysWith: { a, _ in a })
        let items = lesson.sortedVocab
        let learned = items.filter { byID[$0.wordID]?.isLearned == true }.count
        let due = items.filter { item in
            guard let p = byID[item.wordID] else { return false }
            return p.box > 0 && p.dueDate <= .now
        }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Лексика").font(.largeTitle.weight(.bold))

                Card {
                    HStack {
                        Text("\(learned) из \(items.count) выучено").font(.headline)
                        Spacer()
                        Text("\(due) к повторению").font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                    ProgressView(value: Double(learned), total: Double(max(items.count, 1)))
                        .tint(Theme.accent)
                }

                if let word = focusWord(items, byID: byID) {
                    FocusWordCard(item: word, dueCount: due, lesson: lesson)
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
                    TextField("Поиск по слову или переводу", text: $search)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                    Toggle("Новые", isOn: $onlyNew)
                        .toggleStyle(.button)
                        .tint(Theme.accent)
                        .font(.subheadline)
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
                            VocabRow(item: item, box: byID[item.wordID]?.box ?? 0)
                        }
                        if shown.isEmpty {
                            Text("Ничего не найдено")
                                .foregroundStyle(Theme.secondaryText)
                                .padding(16)
                        }
                    }
                    .padding(.vertical, 4)
                }
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
            AnswerChecker.fold($0.italian).contains(q) || $0.russian.localizedCaseInsensitiveContains(search)
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
                CardLabel(text: dueCount > 0 ? "Пора повторить" : "Новое слово", color: .white.opacity(0.85))
                Spacer()
                if let g = item.gender {
                    Text(g)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(g == "f" ? Theme.feminine : Theme.masculine)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            Text(item.displayWithArticle)
                .font(.system(size: 34, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            Text(item.russian).font(.title3).opacity(0.9)
            HStack(spacing: 10) {
                SpeakButton(text: item.withArticle, size: 48, style: .onAccent)
                NavigationLink {
                    FillBlankView(lesson: lesson)
                } label: {
                    Text(dueCount > 0 ? "Повторить \(dueCount)" : "Тренировка")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct VocabRow: View {
    let item: VocabItem
    let box: Int

    var body: some View {
        HStack(spacing: 12) {
            SpeakButton(text: item.withArticle)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayWithArticle).font(.body.weight(.semibold))
                    if item.isNew {
                        Text("НОВОЕ").font(.caption2.weight(.bold)).foregroundStyle(Theme.newBadge)
                    }
                }
                Text(item.russian + (item.formOf.map { " · от \($0)" } ?? ""))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            WordTag(item: item)
            LeitnerDots(box: box)
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
        .accessibilityLabel("Уровень \(box) из \(Leitner.maxBox)")
    }
}
