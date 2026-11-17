import Foundation
import Observation
import SwiftData

/// One practice run of "fill in the missing word" over a lesson's vocabulary.
@Observable
final class FillBlankSession {
    enum Phase: Equatable {
        case loading
        case answering
        case checked(AnswerCheck)
        case finished
    }

    let lessonTitle: String
    let status: ModelStatus
    private(set) var words: [TargetWord]
    private(set) var index = 0
    private(set) var current: FillBlankExercise?
    private(set) var phase: Phase = .loading
    private(set) var correctCount = 0
    /// Set when the model failed and a context-free task was shown instead.
    private(set) var modelNotice: String?

    private let generator: any FillBlankGenerating
    private let fallback = FallbackFillBlankGenerator()

    init(lessonTitle: String, words: [TargetWord], status: ModelStatus,
         generator: (any FillBlankGenerating)? = nil) {
        self.lessonTitle = lessonTitle
        self.words = words
        self.status = status
        self.generator = generator ?? (status.isAvailable ? ModelFillBlankGenerator() : FallbackFillBlankGenerator())
    }

    var total: Int { words.count }

    /// Picks words that are due first (never practised count as due), with
    /// some shuffling so repeated runs are not identical.
    static func pickWords(from lesson: Lesson, progress: [String: WordProgress],
                          count: Int = 5, now: Date = .now) -> [TargetWord] {
        let eligible = lesson.sortedVocab.filter { item in
            item.pos != .proper && !item.italian.contains(where: { "…/()".contains($0) })
                && !item.italian.contains("...")
        }
        let ranked = eligible
            .map { ($0, progress[$0.wordID]?.dueDate ?? .distantPast) }
            .sorted { $0.1 < $1.1 }
        let due = ranked.filter { $0.1 <= now }.map(\.0).shuffled()
        let later = ranked.filter { $0.1 > now }.map(\.0)
        return (due + later).prefix(count).map { item in
            TargetWord(wordID: item.wordID, lessonID: lesson.id, italian: item.italian,
                       russian: item.russian, pos: item.pos, gender: item.gender)
        }
    }

    func start() async {
        index = 0
        correctCount = 0
        await load()
    }

    func submit(_ answer: String, in context: ModelContext) {
        guard let ex = current, phase == .answering else { return }
        let result = AnswerChecker.check(given: answer, expected: ex.answer, pos: ex.pos)
        if result.isCorrect { correctCount += 1 }
        do {
            try context.progress(for: ex.wordID).record(correct: result.isCorrect)
            if let kind = result.mistake {
                context.insert(Mistake(lessonID: ex.lessonID, wordID: ex.wordID, kind: kind,
                                       exercise: .fillBlank, prompt: ex.sentence,
                                       expected: ex.answer, given: answer))
            }
            try context.save()
        } catch {
            assertionFailure("Saving progress failed: \(error)")
        }
        phase = .checked(result)
    }

    func next() async {
        index += 1
        await load()
    }

    private func load() async {
        guard index < words.count else {
            current = nil
            phase = .finished
            return
        }
        phase = .loading
        let word = words[index]
        do {
            current = try await generator.makeExercise(for: word, lessonTitle: lessonTitle)
        } catch {
            modelNotice = "Модель не ответила (\(error.localizedDescription)). Задание без контекста."
            current = try? await fallback.makeExercise(for: word, lessonTitle: lessonTitle)
        }
        phase = .answering
    }
}
