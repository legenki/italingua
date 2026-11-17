import CloudKit
import SwiftData
import SwiftUI

struct StatsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var progress: [WordProgress]
    @Query(sort: \Mistake.date, order: .reverse) private var mistakes: [Mistake]
    @Query private var vocab: [VocabItem]
    @State private var iCloudStatus = "проверяю…"

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
            Section("Синхронизация") {
                LabeledContent("iCloud", value: iCloudStatus)
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
        .task { iCloudStatus = await Self.checkICloud() }
        .navigationTitle("Статистика")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { dismiss() }
            }
        }
    }

    /// Asks CloudKit directly, so sync problems are visible without Console.
    static func checkICloud() async -> String {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "ItalinguaCloudKitContainer") as? String,
              !id.isEmpty else { return "контейнер не настроен" }
        do {
            switch try await CKContainer(identifier: id).accountStatus() {
            case .available: return "подключён"
            case .noAccount: return "нет входа в iCloud"
            case .restricted: return "ограничен"
            case .temporarilyUnavailable: return "временно недоступен"
            case .couldNotDetermine: return "не удалось определить"
            @unknown default: return "неизвестно"
            }
        } catch {
            return "ошибка: \(error.localizedDescription)"
        }
    }

    private var mistakeCounts: [(MistakeKind, Int)] {
        let counts = Dictionary(grouping: mistakes, by: \.kind).mapValues(\.count)
        return MistakeKind.allCases.compactMap { k in counts[k].map { (k, $0) } }
    }
}
