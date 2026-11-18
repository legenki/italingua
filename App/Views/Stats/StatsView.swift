import CloudKit
import SwiftData
import SwiftUI

/// Statistics built with Swift Charts (the "Графики" design, chosen over gauges).
struct StatsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var progress: [WordProgress]
    @Query private var logs: [ReviewLog]
    @Query private var mistakes: [Mistake]
    @Query private var sessions: [SessionRecord]
    @Query(sort: [SortDescriptor(\Lesson.level), SortDescriptor(\Lesson.sourcePart), SortDescriptor(\Lesson.order)])
    private var lessons: [Lesson]
    @State private var iCloudStatus = "проверяю…"

    var body: some View {
        let data = realData
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Статистика").font(.s(.largeTitle).weight(.bold))
                if data.totalAnswers == 0 {
                    Text("Графики заполнятся, когда появятся ответы в карточках и упражнениях.")
                        .font(.s(.footnote))
                        .foregroundStyle(Theme.secondaryText)
                }

                MedalsCard(
                    stats: MedalStats.make(records: sessions.map {
                        (finishedAt: $0.finishedAt, lessonID: $0.lessonID, seconds: $0.seconds, medal: $0.medal)
                    }),
                    lessons: lessons)

                StatsChartsView(data: data)

                systemCard
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .task { iCloudStatus = await Self.checkICloud() }
        .toolbar {
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
                Text(reason).font(.s(.caption)).foregroundStyle(Theme.secondaryText)
            }
        }
        .font(.s(.subheadline))
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

/// Learning stages from grey (new) through lighter to full accent (learned).
enum StageStyle {
    static func color(_ stage: Int) -> Color {
        let colors = [Theme.separator] + Theme.accentRamp
        return colors[min(max(stage, 0), colors.count - 1)]
    }
}

extension Double {
    var percent: String { "\(Int((self * 100).rounded()))%" }
}
