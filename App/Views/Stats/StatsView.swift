import CloudKit
import SwiftData
import SwiftUI

/// Statistics in two designs to compare: "Приборы" (gauges) and "Графики"
/// (Swift Charts). The switch in the top bar picks one; the choice is kept.
struct StatsView: View {
    enum Variant: String, CaseIterable, Identifiable {
        case gauges, charts
        var id: String { rawValue }
        var title: String { self == .gauges ? "A · Приборы" : "B · Графики" }
    }

    @Environment(\.dismiss) private var dismiss
    @Query private var progress: [WordProgress]
    @Query private var logs: [ReviewLog]
    @Query private var mistakes: [Mistake]
    @Query(sort: [SortDescriptor(\Lesson.level), SortDescriptor(\Lesson.sourcePart), SortDescriptor(\Lesson.order)])
    private var lessons: [Lesson]
    @AppStorage("statsVariant") private var variant = Variant.gauges
    @State private var showSample = false
    @State private var iCloudStatus = "проверяю…"

    var body: some View {
        let data = showSample ? StatsData.sample(lessons: lessonInputs) : realData
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Статистика").font(.largeTitle.weight(.bold))
                    Spacer()
                    Toggle("Пример", isOn: $showSample)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help("Показать экран на придуманных данных, пока своей истории мало")
                }
                if data.isSample {
                    Text("Придуманные данные: только чтобы оценить дизайн.")
                        .font(.footnote)
                        .foregroundStyle(Theme.warningText)
                } else if data.totalAnswers == 0 {
                    Text("История ответов собирается с этой версии. Включи «Пример», чтобы увидеть экран заполненным.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }

                switch variant {
                case .gauges: StatsGaugesView(data: data)
                case .charts: StatsChartsView(data: data)
                }

                systemCard
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .task { iCloudStatus = await Self.checkICloud() }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Вид", selection: $variant) {
                    ForEach(Variant.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { dismiss() }
            }
        }
    }

    private var lessonInputs: [StatsData.LessonInput] {
        lessons.map { lesson in
            StatsData.LessonInput(
                id: lesson.id,
                label: (lesson.sourcePart == "intro" ? "В" : "У") + "\(lesson.sourceLesson)",
                title: lesson.title,
                wordIDs: lesson.vocab.filter(FillBlankSession.isPracticable).map(\.wordID))
        }
    }

    private var realData: StatsData {
        StatsData.make(
            answers: logs.map { (date: $0.date, correct: $0.correct) },
            boxes: Dictionary(progress.map { ($0.wordID, $0.box) }, uniquingKeysWith: max),
            dueDates: Dictionary(progress.map { ($0.wordID, $0.dueDate) }, uniquingKeysWith: min),
            lessons: lessonInputs,
            mistakes: mistakes.map(\.kind))
    }

    private var systemCard: some View {
        Card {
            CardLabel(text: "Система")
            LabeledContent("iCloud", value: iCloudStatus)
            let status = ModelStatus.current()
            LabeledContent("Модель для упражнений", value: status.isAvailable ? "готова" : "недоступна")
            if case .unavailable(let reason) = status {
                Text(reason).font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
        .font(.subheadline)
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
}

/// Shared colors for the learning stages, used by both variants.
enum StageStyle {
    static let colors: [Color] = [Theme.separator, Theme.warningText, Theme.masculine, Color.teal, Theme.accent]
    static func color(_ stage: Int) -> Color { colors[min(max(stage, 0), colors.count - 1)] }
}

extension Double {
    var percent: String { "\(Int((self * 100).rounded()))%" }
}
