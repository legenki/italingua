import Foundation
import FoundationModels

/// A sentence to translate from Russian. Both sides come from the examples in
/// the lesson's rules (`ex:` lines), which are static and checked by hand.
nonisolated struct TranslationTask: Identifiable, Equatable, Sendable {
    let id = UUID()
    let lessonID: String
    let russian: String
    let reference: String
}

/// Result of checking a free answer.
nonisolated struct TranslationResult: Equatable, Sendable {
    enum Verdict: Equatable, Sendable {
        /// Same as the reference.
        case exact
        /// Different from the reference, but the model found nothing to fix.
        case alternative
        /// Only accents differ from the reference.
        case accents
        /// The model corrected something.
        case corrected
        /// No model: the learner compares with the reference themselves.
        case unchecked
    }

    let verdict: Verdict
    /// The fixed sentence (the reference when no model fix is available).
    let corrected: String
    /// Word-by-word comparison of the answer with `corrected`.
    let diff: [DiffToken]
    /// Mistake types found by comparing the changed words.
    let mistakes: [MistakeKind]

    var isCorrect: Bool { verdict == .exact || verdict == .alternative }
}

nonisolated struct DiffToken: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable { case same, removed, added }
    let id: Int
    let text: String
    let kind: Kind
}

nonisolated protocol SentenceFixing: Sendable {
    /// The learner's sentence with real mistakes fixed, or unchanged if correct.
    func fix(answer: String, reference: String, level: String) async throws -> String
}

/// Checks a free translation. The deterministic parts (exact match, accents,
/// diff, mistake types) are code; the model only proposes a minimal fix.
/// Measured on sample answers: asking the model for a verdict directly gave
/// both false alarms ("Vivo a Mosca") and misses ("Noi parlano"); a minimal
/// fix compared with the answer was far more reliable.
nonisolated enum TranslationChecker {
    static func check(answer: String, task: TranslationTask, level: String,
                      fixer: (any SentenceFixing)?) async -> TranslationResult {
        let a = words(answer), ref = words(task.reference)
        if a == ref {
            return TranslationResult(verdict: .exact, corrected: task.reference,
                                     diff: diff(a, ref), mistakes: [])
        }
        if a.map(fold) == ref.map(fold) {
            return TranslationResult(verdict: .accents, corrected: task.reference,
                                     diff: diff(a, ref), mistakes: [.accent])
        }
        guard let fixer, let fixed = try? await fixer.fix(answer: answer, reference: task.reference, level: level)
        else {
            return TranslationResult(verdict: .unchecked, corrected: task.reference,
                                     diff: diff(a, ref), mistakes: [])
        }
        var f = words(fixed)
        if f == a {
            return TranslationResult(verdict: .alternative, corrected: answer, diff: diff(a, a), mistakes: [])
        }
        // A "fix" that shares little with the answer is a rewrite, not a fix:
        // compare with the reference instead.
        if overlap(a, f) < 0.5 { f = ref }
        let d = diff(a, f)
        return TranslationResult(verdict: .corrected, corrected: f == ref ? task.reference : fixed,
                                 diff: d, mistakes: classify(d))
    }

    /// Lower-case words without punctuation; apostrophes stay with the word.
    static func words(_ s: String) -> [String] {
        AnswerChecker.normalize(s)
            .components(separatedBy: CharacterSet(charactersIn: " .,!?;:«»\"…"))
            .filter { !$0.isEmpty }
    }

    static func fold(_ s: String) -> String { AnswerChecker.fold(s) }

    static func overlap(_ a: [String], _ b: [String]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(lcs(a, b).count) / Double(max(a.count, b.count))
    }

    /// Longest common subsequence of words, as index pairs.
    static func lcs(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        var t = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                t[i][j] = a[i] == b[j] ? t[i + 1][j + 1] + 1 : max(t[i + 1][j], t[i][j + 1])
            }
        }
        var out: [(Int, Int)] = [], i = 0, j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { out.append((i, j)); i += 1; j += 1 }
            else if t[i + 1][j] >= t[i][j + 1] { i += 1 } else { j += 1 }
        }
        return out
    }

    /// Answer words that are gone are "removed", words of the fix that are new are "added".
    static func diff(_ a: [String], _ b: [String]) -> [DiffToken] {
        var out: [DiffToken] = []
        var i = 0, j = 0
        func push(_ t: String, _ k: DiffToken.Kind) { out.append(DiffToken(id: out.count, text: t, kind: k)) }
        for (x, y) in lcs(a, b) {
            while i < x { push(a[i], .removed); i += 1 }
            while j < y { push(b[j], .added); j += 1 }
            push(a[x], .same); i = x + 1; j = y + 1
        }
        while i < a.count { push(a[i], .removed); i += 1 }
        while j < b.count { push(b[j], .added); j += 1 }
        return out
    }

    /// Pairs each removed run with the added run after it and lets the word
    /// checker name the mistake (article, agreement, accent…).
    static func classify(_ d: [DiffToken]) -> [MistakeKind] {
        var kinds: [MistakeKind] = []
        var removed: [String] = [], added: [String] = []
        func flush() {
            defer { removed = []; added = [] }
            guard !(removed.isEmpty && added.isEmpty) else { return }
            if removed.isEmpty || added.isEmpty {
                let word = (removed + added).joined(separator: " ")
                kinds.append(AnswerChecker.articles.contains(word) ? .article
                             : AnswerChecker.prepositions.contains(word) ? .preposition : .other)
                return
            }
            let check = AnswerChecker.check(given: removed.joined(separator: " "),
                                            expected: added.joined(separator: " "), pos: .other)
            kinds.append(check.mistake ?? .other)
        }
        for t in d {
            switch t.kind {
            case .same: flush()
            case .removed: if !added.isEmpty { flush() }; removed.append(t.text)
            case .added: added.append(t.text)
            }
        }
        flush()
        var seen = Set<MistakeKind>()
        return kinds.filter { seen.insert($0).inserted }
    }
}

// MARK: - Foundation Models

@Generable
nonisolated struct SentenceFix {
    @Guide(description: "The learner's sentence with every grammar mistake fixed, changed as little as possible. If it is already correct Italian with the same meaning, repeat it unchanged.")
    var corrected: String
}

nonisolated struct ModelSentenceFixer: SentenceFixing {
    static func instructions(level: String) -> String {
        """
        You are a careful Italian teacher. A learner (CEFR \(level)) translated a sentence into Italian. \
        You get a reference translation and the learner's sentence.
        Fix only real mistakes: articles, agreement, verb forms, prepositions, accents, spelling, missing words.
        Keep the learner's own word choice and word order when they are also correct Italian (synonyms are fine).
        Examples:
        Reference: Abito a Mosca. Learner: Vivo a Mosca. -> Vivo a Mosca.
        Reference: Ho due fratelli. Learner: Ho due fratello. -> Ho due fratelli.
        Reference: Mia madre lavora. Learner: La mia madre lavora. -> Mia madre lavora.
        """
    }

    func fix(answer: String, reference: String, level: String) async throws -> String {
        let session = LanguageModelSession(model: ModelFillBlankGenerator.model,
                                           instructions: Self.instructions(level: level))
        return try await session.respond(to: "Reference: \(reference) Learner: \(answer) ->",
                                         generating: SentenceFix.self,
                                         options: GenerationOptions(temperature: 0)).content.corrected
    }
}
