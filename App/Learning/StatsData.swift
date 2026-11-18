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
    var isSample = false

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
        data.stages = ["Новые", "Изучаю", "Знакомо", "Закрепляю", "Выучено"].enumerated().map {
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
                      progress: LessonProgress(boxes: lesson.wordIDs.map { boxes[$0] }))
        }

        let kinds = Dictionary(grouping: mistakes, by: { $0 }).mapValues(\.count)
        data.mistakes = MistakeKind.allCases.compactMap { k in kinds[k].map { MistakeCount(kind: k, count: $0) } }
            .sorted { $0.count > $1.count }
        return data
    }

    /// Plausible numbers for judging the design before there is real history.
    static func sample(lessons: [LessonInput], now: Date = .now, calendar: Calendar = .current) -> StatsData {
        var rng = SeededRandom(seed: 7)
        var answers: [(date: Date, correct: Bool)] = []
        for offset in 0..<20 where offset != 9 && offset != 10 {
            let day = calendar.date(byAdding: .day, value: -offset, to: now)!
            let count = offset == 0 ? 14 : Int.random(in: 8...36, using: &rng)
            let skill = 0.62 + Double(20 - offset) * 0.012
            for _ in 0..<count { answers.append((day, Double.random(in: 0...1, using: &rng) < skill)) }
        }
        var boxes: [String: Int] = [:]
        var due: [String: Date] = [:]
        for (i, lesson) in lessons.enumerated() {
            let reach = i < 3 ? 1.0 : (i < 7 ? 0.6 : (i < 9 ? 0.2 : 0))
            for id in lesson.wordIDs where Double.random(in: 0...1, using: &rng) < reach {
                let box = i < 2 ? Int.random(in: 2...5, using: &rng) : Int.random(in: 1...4, using: &rng)
                boxes[id] = box
                due[id] = calendar.date(byAdding: .day, value: Int.random(in: -1...6, using: &rng), to: now)
            }
        }
        let kinds: [MistakeKind] = Array(repeating: .article, count: 14) + Array(repeating: .conjugation, count: 9)
            + Array(repeating: .agreement, count: 7) + Array(repeating: .accent, count: 5)
            + Array(repeating: .preposition, count: 4) + Array(repeating: .spelling, count: 3)
        var data = make(answers: answers, boxes: boxes, dueDates: due, lessons: lessons,
                        mistakes: kinds, now: now, calendar: calendar)
        data.isSample = true
        return data
    }
}

/// Small deterministic generator so the sample looks the same every time.
nonisolated struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
