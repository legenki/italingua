import SwiftData
import SwiftUI

struct StatsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var progress: [WordProgress]
    @Query(sort: \Mistake.date, order: .reverse) private var mistakes: [Mistake]
    @Query private var vocab: [VocabItem]

    var body: some View {
        List {
            Section("Слова") {
                LabeledContent("Выучено", value: "\(progress.filter(\.isLearned).count)")
                LabeledContent("В процессе", value: "\(progress.filter { !$0.isLearned && $0.box > 0 }.count)")
                LabeledContent("К повторению сегодня",
                               value: "\(progress.filter { $0.box > 0 && $0.dueDate <= .now }.count)")
                LabeledContent("Всего в курсе", value: "\(vocab.count)")
            }
            Section("Типы ошибок") {
                if mistakes.isEmpty {
                    Text("Ошибок пока нет").foregroundStyle(.secondary)
                }
                ForEach(mistakeCounts, id: \.0) { kind, count in
                    LabeledContent(kind.titleRU, value: "\(count)")
                }
            }
            if !mistakes.isEmpty {
                Section("Последние ошибки") {
                    ForEach(mistakes.prefix(20)) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(m.given.isEmpty ? "—" : m.given) → \(m.expected)").bold()
                            Text("\(m.kind.titleRU) · \(m.prompt)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Модель на устройстве") {
                let status = ModelStatus.current()
                LabeledContent("Генерация упражнений",
                               value: status.isAvailable ? "доступна" : "недоступна")
                if case .unavailable(let reason) = status {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Русский язык в модели",
                               value: ModelStatus.supportsRussian() ? "поддерживается" : "нет")
            }
        }
        .navigationTitle("Статистика")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { dismiss() }
            }
        }
    }

    private var mistakeCounts: [(MistakeKind, Int)] {
        let counts = Dictionary(grouping: mistakes, by: \.kind).mapValues(\.count)
        return MistakeKind.allCases.compactMap { k in counts[k].map { (k, $0) } }
    }
}
