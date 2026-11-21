import Foundation

/// Everything the statistics screen shows, computed from plain values so it
/// can be tested and filled with sample data.
nonisolated struct StatsData: Sendable {
    struct Day: Identifiable, Sendable {
        let date: Date
        let correct: Int
        let wrong: Int
        var total: Int { correct + wrong }
        var accuracy: Double? { total == 0 ? nil : Double(correct) / Double(total) }
        var id: Date { date }
    }

    struct Stage: Identifiable, Sendable {
        let id: Int
        let title: String
        let count: Int
    }

    struct LessonRow: Identifiable, Sendable {
        let id: String
        let label: String
        let title: String
        let progress: LessonProgress
        /// Course section ("A1 · Intro course") and the lesson number in it.
        var section = ""
        var number = 0
    }

    struct MistakeCount: Identifiable, Sendable {
        let kind: MistakeKind
        let count: Int
        var id: String { kind.rawValue }
    }

    struct Forecast: Identifiable, Sendable {
        let date: Date
        let count: Int
        var id: Date { date }
    }

    struct LessonInput: Sendable {
        let id: String
        let label: String
        let title: String
        let wordIDs: [String]
        var section = ""
        var number = 0
    }

    var days: [Day] = []
    var stages: [Stage] = []
    var lessons: [LessonRow] = []
    var mistakes: [MistakeCount] = []
    var forecast: [Forecast] = []
    var totalWords = 0
    var known = 0
    var learned = 0
    var dueToday = 0
    var streak = 0
    var todayAnswers = 0
    var dailyGoal = 20
    var totalAnswers = 0
    /// Share of right answers in the last 7 days; nil without answers.
    var accuracy7: Double?

    static let dayCount = 14

    static func make(answers: [(date: Date, correct: Bool)],
                     boxes: [String: Int],
                     dueDates: [String: Date],
                     lessons: [LessonInput],
                     mistakes: [MistakeKind],
                     now: Date = .now,
                     calendar: Calendar = .current) -> StatsData {
        var data = StatsData()
        let today = calendar.startOfDay(for: now)

        // Activity per day, oldest first.
        let byDay = Dictionary(grouping: answers) { calendar.startOfDay(for: $0.date) }
        data.days = (0..<dayCount).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let list = byDay[day] ?? []
            return Day(date: day, correct: list.filter(\.correct).count, wrong: list.filter { !$0.correct }.count)
        }
        data.todayAnswers = byDay[today]?.count ?? 0
        data.totalAnswers = answers.count

        // Streak: consecutive days with answers, ending today (or yesterday if
        // today has none yet, so the streak is not lost in the morning).
        var cursor = data.todayAnswers > 0 ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        while byDay[cursor] != nil {
            data.streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }

        let weekAgo = calendar.date(byAdding: .day, value: -6, to: today)!
        let week = answers.filter { $0.date >= weekAgo }
        data.accuracy7 = week.isEmpty ? nil : Double(week.filter(\.correct).count) / Double(week.count)

        // Words: only those the course contains.
        let courseWords = lessons.flatMap(\.wordIDs)
        data.totalWords = courseWords.count
        let courseBoxes = courseWords.map { boxes[$0] ?? 0 }
        data.known = courseBoxes.filter { $0 >= LessonProgress.knownBox }.count
        data.learned = courseBoxes.filter { $0 >= Leitner.maxBox }.count
        let stageOf: (Int) -> Int = { box in
            switch box {
            case 0: 0
            case 1: 1
            case 2, 3: 2
            case 4: 3
            default: 4
            }
        }
        let stageCounts = Dictionary(grouping: courseBoxes, by: stageOf).mapValues(\.count)
        data.stages = [String(localized: "Новые"), String(localized: "Изучаю"), String(localized: "Знакомо"), String(localized: "Закрепляю"), String(localized: "Выучено")].enumerated().map {
            Stage(id: $0.offset, title: $0.element, count: stageCounts[$0.offset] ?? 0)
        }

        // Reviews due: overdue ones count for today.
        let practiced = courseWords.filter { (boxes[$0] ?? 0) > 0 }
        let dueDays = practiced.compactMap { id in dueDates[id].map { max(calendar.startOfDay(for: $0), today) } }
        let dueByDay = Dictionary(grouping: dueDays, by: { $0 }).mapValues(\.count)
        data.forecast = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today).map { Forecast(date: $0, count: dueByDay[$0] ?? 0) }
        }
        data.dueToday = dueByDay[today] ?? 0

        data.lessons = lessons.map { lesson in
            LessonRow(id: lesson.id, label: lesson.label, title: lesson.title,
                      progress: LessonProgress(boxes: lesson.wordIDs.map { boxes[$0] }),
                      section: lesson.section, number: lesson.number)
        }

        let kinds = Dictionary(grouping: mistakes, by: { $0 }).mapValues(\.count)
        data.mistakes = MistakeKind.allCases.compactMap { k in kinds[k].map { MistakeCount(kind: k, count: $0) } }
            .sorted { $0.count > $1.count }
        return data
    }
}
