import Foundation

/// Types of mistakes we track, so practice can later focus on weak spots.
nonisolated enum MistakeKind: String, CaseIterable, Sendable {
    case article        // il/lo/la, un/uno/una
    case agreement      // gender/number ending of a noun or adjective
    case conjugation    // wrong verb form
    case preposition
    case accent         // è vs e, città vs citta
    case spelling       // small typo
    case vocabulary     // a different word altogether
    case wordOrder
    case other

    var titleRU: String {
        switch self {
        case .article: "Артикль"
        case .agreement: "Род и число"
        case .conjugation: "Спряжение"
        case .preposition: "Предлог"
        case .accent: "Ударение / акцент"
        case .spelling: "Орфография"
        case .vocabulary: "Не то слово"
        case .wordOrder: "Порядок слов"
        case .other: "Другое"
        }
    }
}

nonisolated struct AnswerCheck: Equatable, Sendable {
    let isCorrect: Bool
    let mistake: MistakeKind?
    let feedbackRU: String
}

/// Offline, deterministic checking of a short answer against the expected
/// form. No model involved: the expected answer comes from static content.
nonisolated enum AnswerChecker {
    static let articles: Set<String> = ["il", "lo", "la", "l'", "i", "gli", "le",
                                        "un", "uno", "una", "un'"]
    static let prepositions: Set<String> = ["a", "di", "da", "in", "su", "per", "con", "tra", "fra"]

    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "’", with: "'")
            .lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,!?;:"))
    }

    static func fold(_ s: String) -> String {
        normalize(s).folding(options: .diacriticInsensitive, locale: Locale(identifier: "it"))
    }

    static func check(given: String, expected: String, pos: PartOfSpeech) -> AnswerCheck {
        let g = normalize(given), e = normalize(expected)
        if g == e {
            return AnswerCheck(isCorrect: true, mistake: nil, feedbackRU: "Верно!")
        }
        if g.isEmpty {
            return AnswerCheck(isCorrect: false, mistake: .vocabulary, feedbackRU: "Нужно: \(expected)")
        }
        let kind = classify(given: g, expected: e, pos: pos)
        let hint: String = switch kind {
        case .accent: "Почти: проверь знак ударения."
        case .spelling: "Почти: опечатка."
        case .article: "Артикль не тот."
        case .preposition: "Предлог не тот."
        case .agreement: "Окончание не то: род или число."
        case .conjugation: "Не та форма глагола."
        default: "Другое слово."
        }
        return AnswerCheck(isCorrect: false, mistake: kind, feedbackRU: "\(hint) Нужно: \(expected)")
    }

    static func classify(given g: String, expected e: String, pos: PartOfSpeech) -> MistakeKind {
        if fold(g) == fold(e) { return .accent }

        let gw = g.split(separator: " ").map(String.init)
        let ew = e.split(separator: " ").map(String.init)
        if gw.count > 1 || ew.count > 1 {
            if Set(gw) == Set(ew) { return .wordOrder }
            let gFirst = gw.first ?? "", eFirst = ew.first ?? ""
            if Array(gw.dropFirst()) == Array(ew.dropFirst()), gFirst != eFirst {
                if articles.contains(eFirst) || articles.contains(gFirst) { return .article }
                if prepositions.contains(eFirst) || prepositions.contains(gFirst) { return .preposition }
            }
        }
        if articles.contains(e) && articles.contains(g) { return .article }
        if prepositions.contains(e) && prepositions.contains(g) { return .preposition }

        let gf = fold(g), ef = fold(e)
        let stem = commonPrefixLength(gf, ef)
        let sameStem = stem >= 3 && stem >= min(gf.count, ef.count) - 3
        if sameStem {
            switch pos {
            case .verb: return .conjugation
            case .noun, .adj, .pron, .num: return .agreement
            default: break
            }
        }
        if levenshtein(gf, ef) <= max(1, ef.count / 5) { return .spelling }
        if sameStem { return .agreement }
        return .vocabulary
    }

    static func commonPrefixLength(_ a: String, _ b: String) -> Int {
        zip(a, b).prefix { $0 == $1 }.count
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }
}
