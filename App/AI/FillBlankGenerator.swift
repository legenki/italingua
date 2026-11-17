import Foundation
import FoundationModels

/// One "fill in the missing word" task. The answer always comes from the
/// static vocabulary; the model only writes the surrounding sentence.
nonisolated struct FillBlankExercise: Identifiable, Equatable, Sendable {
    enum Source: Sendable { case model, fallback }

    let id = UUID()
    let wordID: String
    let lessonID: String
    let pos: PartOfSpeech
    /// Sentence with "___" in place of the answer (or just "___" without context).
    let sentence: String
    let answer: String
    /// Russian gloss of the answer, from the content.
    let hintRU: String
    let source: Source

    static let blank = "___"
}

/// What a generator needs to know about the target word.
nonisolated struct TargetWord: Sendable {
    let wordID: String
    let lessonID: String
    let italian: String
    let russian: String
    let pos: PartOfSpeech
    let gender: String?
}

nonisolated protocol FillBlankGenerating: Sendable {
    func makeExercise(for word: TargetWord, lessonTitle: String) async throws -> FillBlankExercise
}

enum FillBlankError: LocalizedError {
    case targetMissing
    case badGrammar

    var errorDescription: String? {
        switch self {
        case .targetMissing: "Модель не смогла составить предложение с нужным словом."
        case .badGrammar: "Модель не смогла составить грамотное предложение."
        }
    }
}

// MARK: - Foundation Models

@Generable
nonisolated struct SentenceReview {
    @Guide(description: "true only if the sentence is grammatically correct and sounds natural to a native Italian speaker")
    var correct: Bool
}

nonisolated struct ModelFillBlankGenerator: FillBlankGenerating {
    var attempts = 3

    /// Default guardrails reject about half of plain beginner words (madre,
    /// caffè, due…) as "unsafe" — measured on lesson vocabulary. The permissive
    /// setting applies to plain-text responses, so the sentence is generated as
    /// text; the content is ordinary example sentences, checked below.
    static let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    // Prompts are in English on purpose: Russian is not a supported model
    // language, and the Russian hint comes from our content. The examples
    // noticeably improve grammar compared to rules alone.
    static let instructions = """
        You are a careful Italian teacher writing example sentences for adult beginners (CEFR A1).
        Rules:
        - Write exactly one short, grammatically correct, natural Italian sentence (4 to 10 words), present tense.
        - Use only very common words. Conjugate every verb correctly and use correct articles.
        - The sentence must contain the target exactly as given, letter for letter. Never change its form.
        - A verb in the infinitive stays in the infinitive, for example after "voglio", "devo", "posso" or "mi piace".
        - A conjugated verb form stays in that person: "parlo" needs "io", "parliamo" needs "noi", "siete" needs "voi".
        - Answer with the sentence only.
        Examples:
        Target: "libro" (noun) -> Il libro è sul tavolo.
        Target: "parlare" (verb) -> Voglio parlare con il professore.
        Target: "lavoro" (verb form) -> Io lavoro in un ufficio.
        Target: "parliamo" (verb form) -> Noi parliamo italiano a casa.
        Target: "grande" (adjective) -> Roma è una città grande.
        Target: "sempre" (adverb) -> Marco arriva sempre in ritardo.
        Target: "ma" (conjunction) -> Sono stanco, ma sono contento.
        Target: "dove" (question word) -> Dove abiti?
        Target: "con" (preposition) -> Vado al cinema con Laura.
        Target: "avere fame" (fixed expression) -> Dopo il lavoro devo avere fame.
        """

    static let reviewInstructions =
        "You are a strict native Italian proofreader. Judge grammar, articles, verb forms and naturalness."

    func makeExercise(for word: TargetWord, lessonTitle: String) async throws -> FillBlankExercise {
        let target = word.italian.replacingOccurrences(of: "’", with: "'")
        var feedback = ""
        var lastError: Error = FillBlankError.targetMissing
        for _ in 0..<attempts {
            do {
                let session = LanguageModelSession(model: Self.model, instructions: Self.instructions)
                let text = try await session.respond(
                    to: "Target: \"\(target)\" (\(Self.describe(word)))" + feedback,
                    options: GenerationOptions(temperature: 0.5, maximumResponseTokens: 60)).content
                let sentence = Self.clean(text)
                guard let blanked = Self.blank(word.italian, in: sentence) else {
                    feedback = "\nYour previous sentence did not contain \"\(target)\" in exactly this form. Use it unchanged."
                    lastError = FillBlankError.targetMissing
                    continue
                }
                guard try await Self.review(sentence) else {
                    feedback = "\nWrite a simpler sentence with fully correct grammar."
                    lastError = FillBlankError.badGrammar
                    continue
                }
                return FillBlankExercise(wordID: word.wordID, lessonID: word.lessonID, pos: word.pos,
                                         sentence: blanked, answer: word.italian,
                                         hintRU: word.russian, source: .model)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// A second, independent pass: the model proofreads its own sentence.
    /// It catches part of the mistakes (wrong agreement, odd word use).
    static func review(_ sentence: String) async throws -> Bool {
        let session = LanguageModelSession(model: model, instructions: reviewInstructions)
        return try await session.respond(to: "Sentence: \(sentence)", generating: SentenceReview.self,
                                         options: GenerationOptions(temperature: 0)).content.correct
    }

    /// First line of the reply without quotes or an echoed "Target: … ->" prefix.
    static func clean(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.components(separatedBy: .newlines).first ?? s
        if let arrow = s.range(of: "->") { s = String(s[arrow.upperBound...]) }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: " \"«»“”"))
    }

    static func describe(_ w: TargetWord) -> String {
        switch w.pos {
        case .noun: "noun" + (w.gender.map { ", gender \($0)" } ?? "")
        case .verb: w.italian.hasSuffix("re") ? "verb, infinitive" : "verb form"
        case .adj: "adjective"
        case .adv: "adverb"
        case .prep: "preposition"
        case .phrase: "fixed expression"
        case .conj: "conjunction"
        case .pron: "pronoun"
        default: w.pos.rawValue
        }
    }

    /// Replaces the first whole-word occurrence of `target` (case-insensitive,
    /// accent-sensitive) with the blank. Nil if the sentence lacks the target.
    static func blank(_ target: String, in sentence: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: target)
            .replacingOccurrences(of: "'", with: "['’]")
            .replacingOccurrences(of: "’", with: "['’]")
        let pattern = "(?<![\\p{L}])" + escaped + "(?![\\p{L}])"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)),
              let r = Range(m.range, in: sentence)
        else { return nil }
        return sentence.replacingCharacters(in: r, with: FillBlankExercise.blank)
    }
}

// MARK: - Fallback without the model

/// Used when the model is unavailable or fails: recall the word from its
/// Russian gloss, without a context sentence.
nonisolated struct FallbackFillBlankGenerator: FillBlankGenerating {
    func makeExercise(for word: TargetWord, lessonTitle: String) async throws -> FillBlankExercise {
        FillBlankExercise(wordID: word.wordID, lessonID: word.lessonID, pos: word.pos,
                          sentence: FillBlankExercise.blank, answer: word.italian,
                          hintRU: word.russian, source: .fallback)
    }
}
