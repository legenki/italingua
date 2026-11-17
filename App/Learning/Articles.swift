import Foundation

/// Definite article for a noun, from its gender, number and first letters.
/// The book lists bare nouns; showing "il lavoro", "lo studente", "l'amica"
/// trains the article together with the word.
nonisolated enum Articles {
    static func definite(for word: String, gender: String?, plural: Bool = false) -> String? {
        guard let gender, gender != "mf" else { return nil }
        let w = word.lowercased()
        guard let first = w.first else { return nil }
        let vowel = "aeiouàèéìòù".contains(first)
        let special = w.hasPrefix("z") || w.hasPrefix("gn") || w.hasPrefix("ps")
            || w.hasPrefix("x") || w.hasPrefix("y")
            || (w.hasPrefix("s") && w.dropFirst().first.map { !"aeiouàèéìòù".contains($0) } == true)
            || (w.hasPrefix("i") && w.dropFirst().first.map { "aeiou".contains($0) } == true)

        if gender == "f" {
            if plural { return "le" }
            return vowel ? "l'" : "la"
        }
        if plural { return (vowel || special) ? "gli" : "i" }
        if special { return "lo" }
        return vowel ? "l'" : "il"
    }

    /// "il lavoro", "l'amica"; nil when the word already has an article or
    /// the article cannot be derived.
    static func withArticle(_ word: String, gender: String?, plural: Bool) -> String? {
        let lower = word.lowercased()
        let hasArticle = ["il ", "lo ", "la ", "i ", "gli ", "le ", "l'", "l’"].contains { lower.hasPrefix($0) }
        guard !hasArticle, !word.contains(" "), word.first?.isLowercase == true,
              let art = definite(for: word, gender: gender, plural: plural) else { return nil }
        return art.hasSuffix("'") ? art + word : "\(art) \(word)"
    }
}
