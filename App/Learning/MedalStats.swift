import Foundation

/// Medal history for the statistics screen.
nonisolated struct MedalStats: Sendable {
    enum DayKind: Sendable, Equatable { case none, session, medal }

    struct Day: Identifiable, Sendable {
        let date: Date
        let kind: DayKind
        let isToday: Bool
        var id: Date { date }
    }

    struct Session: Identifiable, Sendable {
        let finishedAt: Date
        let lessonID: String
        let minutes: Int
        let medal: Bool
        var id: Date { finishedAt }
    }

    /// Whole weeks (Monday first) ending with the current one, oldest first.
    var days: [Day] = []
    var total = 0
    var thisWeek = 0
    /// Days in a row with a medal, ending today or yesterday.
    var streak = 0
    /// Fastest session that earned a medal, in minutes.
    var bestMinutes: Int?
    var recent: [Session] = []

    static func make(records: [(finishedAt: Date, lessonID: String, seconds: Double, medal: Bool)],
                     weeks: Int = 6, now: Date = .now, calendar base: Calendar = .current) -> MedalStats {
        var calendar = base
        calendar.firstWeekday = 2
        var out = MedalStats()
        let today = calendar.startOfDay(for: now)
        let medalDays = Set(records.filter(\.medal).map { calendar.startOfDay(for: $0.finishedAt) })
        let sessionDays = Set(records.map { calendar.startOfDay(for: $0.finishedAt) })

        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let first = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: weekStart)!
        out.days = (0..<(weeks * 7)).compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: offset, to: first) else { return nil }
            let kind: DayKind = medalDays.contains(d) ? .medal : sessionDays.contains(d) ? .session : .none
            return Day(date: d, kind: kind, isToday: d == today)
        }

        out.total = records.filter(\.medal).count
        out.thisWeek = records.filter { $0.medal && $0.finishedAt >= weekStart }.count
        var cursor = medalDays.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        while medalDays.contains(cursor) {
            out.streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        out.bestMinutes = records.filter(\.medal).map { Int(($0.seconds / 60).rounded(.up)) }.min()
        out.recent = records.sorted { $0.finishedAt > $1.finishedAt }.prefix(5).map {
            Session(finishedAt: $0.finishedAt, lessonID: $0.lessonID,
                    minutes: Int(($0.seconds / 60).rounded(.up)), medal: $0.medal)
        }
        return out
    }
}
