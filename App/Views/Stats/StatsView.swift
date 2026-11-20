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
    @State private var iCloudStatus = String(localized: "проверяю…")

    var body: some View {
        let data = realData
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "Статистика")).font(.s(.largeTitle).weight(.bold))
                if data.totalAnswers == 0 {
                    Text(String(localized: "Графики заполнятся, когда появятся ответы в карточках и упражнениях."))
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
                Button(String(localized: "Готово")) { dismiss() }
            }
        }
    }

    private var lessonInputs: [StatsData.LessonInput] {
        lessons.map { lesson in
            StatsData.LessonInput(
                id: lesson.id,
                label: (lesson.sourcePart == "intro" ? String(localized: "В") : String(localized: "У")) + "\(lesson.sourceLesson)",
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
            CardLabel(text: String(localized: "Система"))
            LabeledContent("iCloud", value: iCloudStatus)
            let status = ModelStatus.current()
            LabeledContent(String(localized: "Модель для упражнений"), value: status.isAvailable ? String(localized: "готова") : String(localized: "недоступна"))
            if case .unavailable(let reason) = status {
                Text(reason).font(.s(.caption)).foregroundStyle(Theme.secondaryText)
            }
        }
        .font(.s(.subheadline))
    }

    /// Whether this build was code signed, and so carries the iCloud
    /// entitlement. Filled in from the CODE_SIGNING_ALLOWED build setting.
    private static var hasICloudEntitlement: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "ItalinguaCodeSigned") as? String) != "NO"
    }

    /// Asks CloudKit directly, so sync problems are visible without Console.
    static func checkICloud() async -> String {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "ItalinguaCloudKitContainer") as? String,
              !id.isEmpty else { return String(localized: "контейнер не настроен") }
        // CKContainer traps (crashes the app) when the build has no iCloud
        // entitlement, e.g. an unsigned command-line build.
        guard hasICloudEntitlement else { return String(localized: "сборка без подписи, синхронизации нет") }
        do {
            switch try await CKContainer(identifier: id).accountStatus() {
            case .available: return String(localized: "подключён")
            case .noAccount: return String(localized: "нет входа в iCloud")
            case .restricted: return String(localized: "ограничен")
            case .temporarilyUnavailable: return String(localized: "временно недоступен")
            case .couldNotDetermine: return String(localized: "не удалось определить")
            @unknown default: return String(localized: "неизвестно")
            }
        } catch {
            return String(localized: "ошибка: \(error.localizedDescription)")
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
