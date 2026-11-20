import Foundation
import SwiftData

// Learner progress. Lives in the "Progress" store, which syncs through
// iCloud (CloudKit) when the app is signed with the iCloud entitlement.
// CloudKit rules: no unique constraints, every property has a default,
// no relationships to the local content store (we refer to words by wordID).

@Model
final class WordProgress {
    var wordID: String = ""
    /// Leitner box: 0 = never practised, 1…4 = learning, 5 = learned.
    var box: Int = 0
    var dueDate: Date = Date.distantPast
    var correctCount: Int = 0
    var wrongCount: Int = 0
    var lastReviewed: Date?

    init(wordID: String) {
        self.wordID = wordID
    }

    var isLearned: Bool { box >= Leitner.maxBox }

    func record(correct: Bool, at now: Date = .now) {
        let next = Leitner.next(LeitnerState(box: box, dueDate: dueDate), correct: correct, now: now)
        box = next.box
        dueDate = next.dueDate
        lastReviewed = now
        if correct { correctCount += 1 } else { wrongCount += 1 }
    }
}

@Model
final class Mistake {
    var date: Date = Date.now
    var lessonID: String = ""
    var wordID: String?
    var kindRaw: String = MistakeKind.other.rawValue
    var exerciseRaw: String = ExerciseType.fillBlank.rawValue
    /// The task as shown (e.g. the sentence with a blank).
    var prompt: String = ""
    var expected: String = ""
    var given: String = ""

    init(date: Date = .now, lessonID: String, wordID: String?, kind: MistakeKind,
         exercise: ExerciseType, prompt: String, expected: String, given: String) {
        self.date = date
        self.lessonID = lessonID
        self.wordID = wordID
        self.kindRaw = kind.rawValue
        self.exerciseRaw = exercise.rawValue
        self.prompt = prompt
        self.expected = expected
        self.given = given
    }

    var kind: MistakeKind { MistakeKind(rawValue: kindRaw) ?? .other }
}

nonisolated enum ExerciseType: String, Sendable {
    case fillBlank
    case flashcards
    case translation
}

/// One answer, kept for the activity and accuracy charts. Word progress only
/// stores the current state; this is the history behind it.
@Model
final class ReviewLog {
    var date: Date = Date.now
    var wordID: String = ""
    var lessonID: String = ""
    var correct: Bool = false
    var exerciseRaw: String = ExerciseType.fillBlank.rawValue

    init(date: Date = .now, wordID: String, lessonID: String, correct: Bool, exercise: ExerciseType) {
        self.date = date
        self.wordID = wordID
        self.lessonID = lessonID
        self.correct = correct
        self.exerciseRaw = exercise.rawValue
    }
}

extension ModelContext {
    /// Moves the word's Leitner box and writes the answer to the history.
    func recordAnswer(wordID: String, lessonID: String, correct: Bool, exercise: ExerciseType,
                      at now: Date = .now) throws {
        try progress(for: wordID).record(correct: correct, at: now)
        insert(ReviewLog(date: now, wordID: wordID, lessonID: lessonID, correct: correct, exercise: exercise))
    }

    /// Progress for a word, created on first use. Two devices may each create a
    /// row for the same word before CloudKit syncs; such duplicates are merged.
    func progress(for wordID: String) throws -> WordProgress {
        let rows = try fetch(FetchDescriptor<WordProgress>(predicate: #Predicate { $0.wordID == wordID }))
        guard var keep = rows.first else {
            let p = WordProgress(wordID: wordID)
            insert(p)
            return p
        }
        if rows.count > 1 {
            keep = rows.max { ($0.lastReviewed ?? .distantPast) < ($1.lastReviewed ?? .distantPast) }!
            // Each row counts only the answers given on its own device, so they add up.
            for other in rows where other !== keep {
                keep.correctCount += other.correctCount
                keep.wrongCount += other.wrongCount
                delete(other)
            }
        }
        return keep
    }
}

/// A grammar rule written by the owner in the app. Synced via iCloud and
/// shown instead of the bundled `ruleRU` while it exists.
@Model
final class RuleNote {
    /// "<lessonID>|<topic>", e.g. "a1-01|Род существительных".
    var key: String = ""
    var text: String = ""
    var updatedAt: Date = Date.now

    init(key: String, text: String) {
        self.key = key
        self.text = text
    }

    static func key(lessonID: String, topic: String) -> String { "\(lessonID)|\(topic)" }

    var lessonID: String { String(key.split(separator: "|", maxSplits: 1).first ?? "") }
    var topic: String { String(key.split(separator: "|", maxSplits: 1).dropFirst().first ?? "") }
}

extension ModelContext {
    func ruleNote(lessonID: String, topic: String) throws -> RuleNote? {
        let key = RuleNote.key(lessonID: lessonID, topic: topic)
        let rows = try fetch(FetchDescriptor<RuleNote>(predicate: #Predicate { $0.key == key },
                                                       sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
        for dup in rows.dropFirst() { delete(dup) }   // CloudKit may create duplicates
        return rows.first
    }
}

/// A word the learner starred, for the "Избранное" deck. Synced via iCloud.
@Model
final class FavoriteWord {
    var wordID: String = ""
    var addedAt: Date = Date.now

    init(wordID: String, addedAt: Date = .now) {
        self.wordID = wordID
        self.addedAt = addedAt
    }
}

extension ModelContext {
    /// Stars or unstars a word. Removes every row for it, so duplicates that
    /// two devices created before syncing go away too.
    @discardableResult
    func toggleFavorite(wordID: String) throws -> Bool {
        let rows = try fetch(FetchDescriptor<FavoriteWord>(predicate: #Predicate { $0.wordID == wordID }))
        if rows.isEmpty {
            insert(FavoriteWord(wordID: wordID))
        } else {
            rows.forEach(delete)
        }
        try save()
        return rows.isEmpty
    }
}

/// A finished 40-minute study session; the history behind the medals.
/// Synced via iCloud. `sessionKey` (the start time) prevents saving one twice.
@Model
final class SessionRecord {
    var sessionKey: String = ""
    var finishedAt: Date = Date.now
    var lessonID: String = ""
    var seconds: Double = 0
    var medal: Bool = false

    init(sessionKey: String, finishedAt: Date, lessonID: String, seconds: Double, medal: Bool) {
        self.sessionKey = sessionKey
        self.finishedAt = finishedAt
        self.lessonID = lessonID
        self.seconds = seconds
        self.medal = medal
    }
}

extension ModelContext {
    /// Saves the finished session once.
    func recordSession(_ s: StudySession.State) throws {
        guard let finished = s.finishedAt else { return }
        let key = String(s.startedAt.timeIntervalSince1970)
        guard try fetchCount(FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.sessionKey == key })) == 0
        else { return }
        let seconds = StudySession.elapsed(s, now: finished)
        insert(SessionRecord(sessionKey: key, finishedAt: finished, lessonID: s.lessonID, seconds: seconds,
                             medal: seconds <= StudySession.duration))
        try save()
    }
}
