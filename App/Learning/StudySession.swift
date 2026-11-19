import Foundation
import Observation
import SwiftData

/// A 40-minute study session over one lesson (design A "Маршрут"): read the
/// rules, listen to the words, check yourself with flashcards, read a text.
/// Doing all four steps in time earns the "medal of the day".
///
/// Progress is reported by the screens (`noteTopic`, `noteSpoken`, `noteCard`,
/// `noteReading`) and kept in UserDefaults, so a session survives a restart.
@Observable
final class StudySession {
    static let shared = StudySession()
    static let duration: TimeInterval = 40 * 60

    enum Step: Int, CaseIterable, Identifiable, Codable {
        case rules, words, cards, reading
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .rules: String(localized: "Правила")
            case .words: String(localized: "Слова")
            case .cards: String(localized: "Карточки")
            case .reading: String(localized: "Чтение")
            }
        }

        var task: String {
            switch self {
            case .rules: String(localized: "Повторить правила")
            case .words: String(localized: "Поучить слова")
            case .cards: String(localized: "Проверить себя карточками")
            case .reading: String(localized: "Почитать текст")
            }
        }
    }

    /// Everything that is saved between launches.
    struct State: Codable, Equatable {
        var lessonID: String
        var startedAt: Date
        /// Seconds counted before the latest pause.
        var elapsedBeforePause: TimeInterval = 0
        /// Set while the timer runs.
        var runningSince: Date?
        var topics: Set<String> = []
        var spoken: Set<String> = []
        var cards: Set<String> = []
        var reading = false
        var finishedAt: Date?
        var targets: [Int]
        /// Lower-cased spoken forms of the lesson's words, to recognise them in `noteSpoken`.
        var wordForms: Set<String>
    }

    private(set) var state: State? {
        didSet { save() }
    }

    private static let key = "studySession"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        }
    }

    // MARK: - Lifecycle

    func start(lesson: Lesson, now: Date = .now) {
        let practicable = lesson.sortedVocab.filter(FillBlankSession.isPracticable)
        let cards = lesson.sortedVocab.filter { $0.pos != .proper }
        state = State(lessonID: lesson.id, startedAt: now, runningSince: now,
                      targets: [max(lesson.grammar.count, 1), min(10, max(practicable.count, 1)),
                                min(20, max(cards.count, 1)), 1],
                      wordForms: Set(lesson.vocab.map { Self.form($0.withArticle) } + lesson.vocab.map { Self.form($0.italian) }))
    }

    func pause(now: Date = .now) {
        guard var s = state, let since = s.runningSince else { return }
        s.elapsedBeforePause += now.timeIntervalSince(since)
        s.runningSince = nil
        state = s
    }

    func resume(now: Date = .now) {
        guard var s = state, s.runningSince == nil, s.finishedAt == nil else { return }
        s.runningSince = now
        state = s
    }

    /// Ends the session early or clears a finished one.
    func reset() { state = nil }

    // MARK: - Progress from the screens

    func noteTopic(lessonID: String, topic: String) {
        update(lessonID) { $0.topics.insert(topic) }
    }

    /// Called for everything the app speaks; counts only this lesson's words.
    func noteSpoken(_ text: String) {
        guard let s = state, s.wordForms.contains(Self.form(text)) else { return }
        update(s.lessonID) { $0.spoken.insert(Self.form(text)) }
    }

    func noteCard(lessonID: String, wordID: String) {
        update(lessonID) { $0.cards.insert(wordID) }
    }

    func noteReading(lessonID: String) {
        update(lessonID) { $0.reading = true }
    }

    private func update(_ lessonID: String, _ change: (inout State) -> Void, now: Date = .now) {
        guard var s = state, s.lessonID == lessonID, s.finishedAt == nil else { return }
        change(&s)
        if Step.allCases.allSatisfy({ Self.done($0, in: s) }) {
            s.elapsedBeforePause = Self.elapsed(s, now: now)
            s.runningSince = nil
            s.finishedAt = now
        }
        state = s
    }

    // MARK: - Reading the state

    var isActive: Bool { state != nil }
    var isRunning: Bool { state?.runningSince != nil }
    var isFinished: Bool { state?.finishedAt != nil }

    func elapsed(now: Date = .now) -> TimeInterval {
        state.map { Self.elapsed($0, now: now) } ?? 0
    }

    func remaining(now: Date = .now) -> TimeInterval {
        max(Self.duration - elapsed(now: now), 0)
    }

    func progress(_ step: Step) -> (done: Int, target: Int) {
        guard let s = state else { return (0, 1) }
        return (min(Self.count(step, in: s), s.targets[step.rawValue]), s.targets[step.rawValue])
    }

    func isDone(_ step: Step) -> Bool { state.map { Self.done(step, in: $0) } ?? false }

    var doneSteps: Int { Step.allCases.filter(isDone).count }

    /// The first step that is not done yet.
    var currentStep: Step? { Step.allCases.first { !isDone($0) } }

    /// All four steps within 40 minutes.
    var earnedMedal: Bool {
        guard let s = state, s.finishedAt != nil else { return false }
        return Self.elapsed(s, now: .now) <= Self.duration
    }

    static func elapsed(_ s: State, now: Date) -> TimeInterval {
        s.elapsedBeforePause + (s.runningSince.map { now.timeIntervalSince($0) } ?? 0)
    }

    static func count(_ step: Step, in s: State) -> Int {
        switch step {
        case .rules: s.topics.count
        case .words: s.spoken.count
        case .cards: s.cards.count
        case .reading: s.reading ? 1 : 0
        }
    }

    static func done(_ step: Step, in s: State) -> Bool {
        count(step, in: s) >= s.targets[step.rawValue]
    }

    static func form(_ text: String) -> String {
        AnswerChecker.normalize(Speech.spokenForm(text))
    }

    private func save() {
        if let state, let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.key)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.key)
        }
    }
}
