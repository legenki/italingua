import Foundation
import Observation

/// One flashcard: the Italian side (with article for nouns) and the Russian one.
nonisolated struct Flashcard: Identifiable, Equatable, Sendable {
    let wordID: String
    var lessonID: String = ""
    let italian: String
    /// What the speak button reads ("il lavoro").
    let spoken: String
    let russian: String
    let gender: String?
    let note: String?

    var id: String { wordID }
}

/// A Quizlet-style run through a deck: flip the card, then say whether you
/// knew it. "Know" counts as a right answer for the word's Leitner box and
/// "Still learning" as a wrong one, so cards feed the same progress as exercises.
@Observable
final class FlashcardSession {
    enum Side: String, CaseIterable, Identifiable {
        case italian, russian
        var id: String { rawValue }
        var title: String { self == .italian ? "Итальянский" : "Русский" }
    }

    private(set) var deck: [Flashcard]
    private(set) var index = 0
    private(set) var known: [Flashcard] = []
    private(set) var learning: [Flashcard] = []
    var flipped = false

    private let all: [Flashcard]

    init(cards: [Flashcard]) {
        deck = cards
        all = cards
    }

    var current: Flashcard? { index < deck.count ? deck[index] : nil }
    var isFinished: Bool { current == nil }
    var total: Int { deck.count }

    /// Unknown and due words first, then the rest; shuffled inside each group.
    static func order(_ cards: [Flashcard], boxes: [String: Int], due: Set<String>) -> [Flashcard] {
        let first = cards.filter { (boxes[$0.wordID] ?? 0) < LessonProgress.knownBox || due.contains($0.wordID) }
        let firstIDs = Set(first.map(\.wordID))
        let rest = cards.filter { !firstIDs.contains($0.wordID) }
        return first.shuffled() + rest.shuffled()
    }

    /// Records the answer for the current card and moves on.
    /// Returns the card so the caller can store progress.
    @discardableResult
    func answer(knew: Bool) -> Flashcard? {
        guard let card = current else { return nil }
        if knew { known.append(card) } else { learning.append(card) }
        index += 1
        flipped = false
        return card
    }

    /// Steps back one card and forgets its answer (progress already saved stays).
    func undo() {
        guard index > 0 else { return }
        index -= 1
        let card = deck[index]
        known.removeAll { $0.id == card.id }
        learning.removeAll { $0.id == card.id }
        flipped = false
    }

    /// Starts over with only the cards marked "still learning".
    func restartWithLearning() {
        deck = learning.shuffled()
        reset()
    }

    func restartAll() {
        deck = all.shuffled()
        reset()
    }

    private func reset() {
        index = 0
        known = []
        learning = []
        flipped = false
    }
}
