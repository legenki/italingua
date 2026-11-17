import Foundation

nonisolated struct LeitnerState: Equatable, Sendable {
    var box: Int
    var dueDate: Date
}

/// Leitner system: a correct answer moves the word one box up, a wrong one
/// sends it back to box 1. Each box has its own review interval.
nonisolated enum Leitner {
    static let maxBox = 5
    /// Days until the next review after landing in box N (index = box).
    static let intervals = [0, 1, 2, 4, 8, 16]

    static func next(_ state: LeitnerState, correct: Bool, now: Date,
                     calendar: Calendar = .current) -> LeitnerState {
        let box = correct ? min(state.box + 1, maxBox) : 1
        let due = calendar.date(byAdding: .day, value: intervals[box], to: now) ?? now
        return LeitnerState(box: box, dueDate: due)
    }
}
