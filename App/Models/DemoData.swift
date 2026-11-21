#if DEBUG
import Foundation
import SwiftData

/// Sample progress for App Store screenshots. Debug builds only, and only when
/// the app is launched with `-demoData` (e.g. `xcrun simctl launch <device>
/// com.y6a9lrqdh7.italingua -demoData`). Replaces all progress on that device.
enum DemoData {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-demoData") }

    static func seed(into context: ModelContext, now: Date = .now) throws {
        try context.delete(model: WordProgress.self)
        try context.delete(model: ReviewLog.self)
        try context.delete(model: Mistake.self)
        try context.delete(model: FavoriteWord.self)
        try context.delete(model: SessionRecord.self)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, hour: Int = 19) -> Date {
            calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: offset, to: today)!)!
        }

        let lessons = try context.fetch(FetchDescriptor<Lesson>(sortBy: [
            SortDescriptor(\.level), SortDescriptor(\.sourcePart), SortDescriptor(\.order),
        ]))
        // Share of familiar words per lesson, in course order: three intro
        // lessons done, then lessons in progress, the rest not started.
        let shares: [Double] = [1, 1, 1, 0.75, 0.45, 0.2, 0.08]
        var practised: [(word: String, lesson: String)] = []
        var dueToday = 0
        for (index, lesson) in lessons.prefix(shares.count).enumerated() {
            let words = lesson.vocab.filter(FillBlankSession.isPracticable).map(\.wordID).sorted()
            let count = Int((Double(words.count) * shares[index]).rounded())
            for (n, wordID) in words.prefix(count).enumerated() {
                let p = WordProgress(wordID: wordID)
                p.box = shares[index] == 1 ? 5 : [4, 3, 2, 3, 1][n % 5]
                p.correctCount = 2 + n % 4
                p.wrongCount = n % 3 == 0 ? 1 : 0
                p.lastReviewed = day(-(n % 6))
                // A handful due today, the rest spread over the coming week.
                if dueToday < 18 && p.box < 5 && n % 2 == 0 {
                    p.dueDate = today
                    dueToday += 1
                } else {
                    p.dueDate = day(1 + n % 6, hour: 0)
                }
                context.insert(p)
                practised.append((wordID, lesson.id))
            }
        }

        // Two weeks of answers, ending today; the last nine days in a row.
        let answers = [10, 0, 16, 24, 0, 21, 28, 14, 19, 26, 17, 23, 30, 16]
        for (i, total) in answers.enumerated() where !practised.isEmpty {
            let offset = i - (answers.count - 1)
            for n in 0..<total {
                let item = practised[(i * 31 + n) % practised.count]
                context.insert(ReviewLog(date: day(offset, hour: 18 + n % 4), wordID: item.word, lessonID: item.lesson,
                                         correct: n % 7 != 3, exercise: n % 3 == 0 ? .fillBlank : .flashcards))
            }
        }

        // The latest answer is in the lesson being learned, so "Continue" points at it.
        if let current = lessons.dropFirst(3).first,
           let word = current.vocab.filter(FillBlankSession.isPracticable).map(\.wordID).sorted().first {
            context.insert(ReviewLog(date: now.addingTimeInterval(3600 * 24), wordID: word, lessonID: current.id,
                                     correct: true, exercise: .flashcards))
        }

        let kinds: [(MistakeKind, Int)] = [(.article, 7), (.conjugation, 5), (.agreement, 4), (.accent, 3), (.preposition, 2)]
        for (kind, count) in kinds {
            for n in 0..<count {
                let item = practised[(n * 17) % max(practised.count, 1)]
                context.insert(Mistake(date: day(-n), lessonID: item.lesson, wordID: item.word, kind: kind,
                                       exercise: .fillBlank, prompt: "", expected: "", given: ""))
            }
        }

        for (n, item) in practised.enumerated() where n % 23 == 5 {
            context.insert(FavoriteWord(wordID: item.word, addedAt: day(-n % 9)))
        }

        // Medals: most days of the last three weeks, a couple of sessions without one.
        for offset in -20...(-1) where offset % 4 != 0 {
            let medal = offset % 5 != 0
            context.insert(SessionRecord(sessionKey: "demo\(offset)", finishedAt: day(offset),
                                         lessonID: lessons.first?.id ?? "", seconds: medal ? 2100 : 2700, medal: medal))
        }
        try context.save()
    }
}
#endif
