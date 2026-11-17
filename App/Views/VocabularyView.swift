import SwiftData
import SwiftUI

struct VocabularyView: View {
    let lesson: Lesson
    @Query private var progress: [WordProgress]
    @State private var search = ""

    var body: some View {
        let boxes = Dictionary(progress.map { ($0.wordID, $0.box) }, uniquingKeysWith: max)
        List(filtered) { item in
            VocabRow(item: item, box: boxes[item.wordID] ?? 0)
        }
        .searchable(text: $search, prompt: "Поиск по слову или переводу")
        .navigationTitle("Лексика")
    }

    private var filtered: [VocabItem] {
        let items = lesson.sortedVocab
        guard !search.isEmpty else { return items }
        let q = AnswerChecker.fold(search)
        return items.filter {
            AnswerChecker.fold($0.italian).contains(q) || $0.russian.localizedCaseInsensitiveContains(search)
        }
    }
}

private struct VocabRow: View {
    let item: VocabItem
    let box: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayItalian).bold()
                    if let g = item.gender {
                        Text(g + (item.number == "pl" ? " pl" : ""))
                            .font(.caption.italic())
                            .foregroundStyle(g == "f" ? .pink : .blue)
                    }
                    Text(item.pos.shortRU)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(item.russian)
                    .foregroundStyle(.secondary)
                if let base = item.formOf {
                    Text("форма: \(base)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            LeitnerDots(box: box)
        }
    }
}

/// Five dots, filled up to the word's Leitner box.
struct LeitnerDots: View {
    let box: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...Leitner.maxBox, id: \.self) { i in
                Circle()
                    .fill(i <= box ? Color.green : Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel("Уровень \(box) из \(Leitner.maxBox)")
    }
}
