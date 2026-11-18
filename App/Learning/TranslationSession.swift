import Foundation
import Observation
import SwiftData

/// "Переведи фразу": Russian sentence → the learner writes it in Italian →
/// the answer is checked (see TranslationChecker).
@Observable
final class TranslationSession {
    enum Phase: Equatable {
        case answering
        case checking
        case checked(TranslationResult)
        case finished
    }

    let level: String
    private(set) var tasks: [TranslationTask]
    private(set) var index = 0
    private(set) var phase: Phase = .answering
    private(set) var correctCount = 0
    /// The learner said their answer is right although the check disagreed.
    private(set) var overridden = false
    private let fixer: (any SentenceFixing)?

    init(tasks: [TranslationTask], level: String, fixer: (any SentenceFixing)?) {
        self.tasks = tasks
        self.level = level
        self.fixer = fixer
        if tasks.isEmpty { phase = .finished }
    }

    var current: TranslationTask? { index < tasks.count ? tasks[index] : nil }
    var total: Int { tasks.count }

    /// Example sentences of the lesson's rules, `count` of them at random.
    static func tasks(from lesson: Lesson, ruleTexts: [String], count: Int = 5) -> [TranslationTask] {
        var seen = Set<String>()
        let all = ruleTexts.flatMap(RuleMarkup.parse).compactMap { block -> TranslationTask? in
            guard case .example(let it, let ru) = block, !ru.isEmpty else { return nil }
            let clean = { (s: String) in s.replacingOccurrences(of: "**", with: "") }
            guard seen.insert(clean(it)).inserted else { return nil }
            return TranslationTask(lessonID: lesson.id, russian: clean(ru), reference: clean(it))
        }
        return Array(all.shuffled().prefix(count))
    }

    func submit(_ answer: String) async {
        guard let task = current, phase == .answering else { return }
        phase = .checking
        overridden = false
        let result = await TranslationChecker.check(answer: answer, task: task, level: level, fixer: fixer)
        phase = .checked(result)
    }

    func markMineCorrect() { overridden = true }

    /// Saves the outcome (activity history and mistake types) and moves on.
    func next(answer: String, in context: ModelContext) {
        guard let task = current, case .checked(let result) = phase else { return }
        let correct = result.isCorrect || overridden
        if correct { correctCount += 1 }
        context.insert(ReviewLog(wordID: "", lessonID: task.lessonID, correct: correct, exercise: .translation))
        if !correct {
            for kind in result.mistakes.isEmpty ? [.other] : result.mistakes {
                context.insert(Mistake(lessonID: task.lessonID, wordID: nil, kind: kind, exercise: .translation,
                                       prompt: task.russian, expected: result.corrected, given: answer))
            }
        }
        try? context.save()
        index += 1
        phase = index < tasks.count ? .answering : .finished
    }

    func restart() {
        tasks.shuffle()
        index = 0
        correctCount = 0
        phase = tasks.isEmpty ? .finished : .answering
    }
}
