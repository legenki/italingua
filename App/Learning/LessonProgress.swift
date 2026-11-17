import Foundation

/// How far a lesson's vocabulary has come, for the lesson list.
/// A word counts as "known" once it sits in Leitner box 2 or higher, that is,
/// its last answer was right (a mistake sends it back to box 1). The lesson is
/// done when every word that the exercises use is known.
nonisolated struct LessonProgress: Equatable, Sendable {
    enum State: Equatable, Sendable { case notStarted, inProgress, done }

    let total: Int
    let practiced: Int
    let known: Int

    static let knownBox = 2

    init(total: Int, practiced: Int, known: Int) {
        self.total = total
        self.practiced = practiced
        self.known = known
    }

    /// `boxes` holds the Leitner box of each practicable word (nil = never practised).
    init(boxes: [Int?]) {
        total = boxes.count
        practiced = boxes.compactMap { $0 }.filter { $0 >= 1 }.count
        known = boxes.compactMap { $0 }.filter { $0 >= Self.knownBox }.count
    }

    var fraction: Double { total == 0 ? 0 : Double(known) / Double(total) }

    var state: State {
        if total > 0 && known == total { return .done }
        return practiced == 0 ? .notStarted : .inProgress
    }
}
