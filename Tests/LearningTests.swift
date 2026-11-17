import Foundation
import SwiftData
import Testing
@testable import Italingua

@MainActor
struct ImporterTests {
    @Test func importsBundledA1AndIsIdempotent() throws {
        let container = try AppContainer.make(inMemory: true)
        let context = container.mainContext
        let defaults = UserDefaults(suiteName: "importer-\(UUID())")!
        let bundle = Bundle(for: BundleToken.self)
        let appBundle = Bundle.allBundles.first { $0.bundleURL.pathExtension == "app" } ?? bundle

        try ContentImporter.importBundledContent(into: context, bundle: appBundle, defaults: defaults)
        let lessons = try context.fetch(FetchDescriptor<Lesson>())
        let words = try context.fetchCount(FetchDescriptor<VocabItem>())
        #expect(lessons.count == 20)
        #expect(words > 700)
        #expect(lessons.allSatisfy { !$0.grammar.isEmpty })

        // Second run with the same JSON must not duplicate anything.
        try ContentImporter.importBundledContent(into: context, bundle: appBundle, defaults: defaults)
        #expect(try context.fetchCount(FetchDescriptor<Lesson>()) == 20)
        #expect(try context.fetchCount(FetchDescriptor<VocabItem>()) == words)
    }

    @Test func reimportKeepsProgress() throws {
        let container = try AppContainer.make(inMemory: true)
        let context = container.mainContext
        let json = """
        {"level":"A1","lessons":[{"id":"a1-01","title":"T","grammar":[{"topic":"x","rule_ru":""}],
         "vocab":[{"it":"caffè","ru":"кофе","pos":"noun","gender":"m"}],"patterns":[]}]}
        """.data(using: .utf8)!
        try ContentImporter.importLevel(data: json, into: context)
        try context.progress(for: "a1/caffe").record(correct: true)
        try context.save()

        try ContentImporter.importLevel(data: json, into: context)
        #expect(try context.fetchCount(FetchDescriptor<VocabItem>()) == 1)
        #expect(try context.progress(for: "a1/caffe").box == 1)
    }

    @Test func ruleNoteDroppedOnceBundledTextMatches() throws {
        let container = try AppContainer.make(inMemory: true)
        let context = container.mainContext
        func json(_ rule: String) -> Data {
            """
            {"level":"A1","lessons":[{"id":"a1-01","title":"T","grammar":[{"topic":"Род","rule_ru":"\(rule)"}],
             "vocab":[{"it":"casa","ru":"дом","pos":"noun","gender":"f"}],"patterns":[]}]}
            """.data(using: .utf8)!
        }
        try ContentImporter.importLevel(data: json(""), into: context)
        context.insert(RuleNote(key: RuleNote.key(lessonID: "a1-01", topic: "Род"), text: "Мой текст\n"))
        try context.save()

        try ContentImporter.importLevel(data: json("Другой"), into: context)
        #expect(try context.fetchCount(FetchDescriptor<RuleNote>()) == 1)   // differs: keep
        try ContentImporter.importLevel(data: json("Мой текст"), into: context)
        #expect(try context.fetchCount(FetchDescriptor<RuleNote>()) == 0)   // merged: drop
    }

    @Test func ruleExportShape() throws {
        let doc = try RuleExportDocument(notes: [("a1-01", "Род", "Текст")],
                                         now: Date(timeIntervalSince1970: 0))
        let obj = try JSONSerialization.jsonObject(with: doc.data) as! [String: Any]
        let rules = obj["rules"] as! [String: [String: String]]
        #expect(rules["a1-01"]?["Род"] == "Текст")
    }

    @Test func wordIDFoldsAccentsAndApostrophes() {
        #expect(ContentImporter.wordID(level: "A1", italian: "C’è") == "a1/c'e")
        #expect(ContentImporter.wordID(level: "A1", italian: "città") == "a1/citta")
    }
}

private final class BundleToken {}

struct LeitnerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func correctMovesUpWrongResets() {
        var s = LeitnerState(box: 0, dueDate: .distantPast)
        s = Leitner.next(s, correct: true, now: now)
        #expect(s.box == 1)
        for _ in 0..<10 { s = Leitner.next(s, correct: true, now: now) }
        #expect(s.box == Leitner.maxBox)
        s = Leitner.next(s, correct: false, now: now)
        #expect(s.box == 1)
    }

    @Test func dueDateFollowsInterval() {
        let s = Leitner.next(LeitnerState(box: 2, dueDate: now), correct: true, now: now)
        #expect(s.box == 3)
        let days = Calendar.current.dateComponents([.day], from: now, to: s.dueDate).day
        #expect(days == Leitner.intervals[3])
    }
}

struct AnswerCheckerTests {
    @Test(arguments: [
        ("caffè", "caffè", true),
        ("  Caffè ", "caffè", true),
        ("c'è", "c’è", true),
    ])
    func accepts(given: String, expected: String, ok: Bool) {
        #expect(AnswerChecker.check(given: given, expected: expected, pos: .noun).isCorrect == ok)
    }

    @Test func classifiesMistakes() {
        #expect(AnswerChecker.classify(given: "caffe", expected: "caffè", pos: .noun) == .accent)
        #expect(AnswerChecker.classify(given: "parli", expected: "parlo", pos: .verb) == .conjugation)
        #expect(AnswerChecker.classify(given: "bella", expected: "bello", pos: .adj) == .agreement)
        #expect(AnswerChecker.classify(given: "la", expected: "il", pos: .art) == .article)
        #expect(AnswerChecker.classify(given: "in centro", expected: "a centro", pos: .phrase) == .preposition)
        #expect(AnswerChecker.classify(given: "ristorant", expected: "ristorante", pos: .noun) == .agreement)
        #expect(AnswerChecker.classify(given: "gatto", expected: "cane", pos: .noun) == .vocabulary)
    }
}

struct BlankingTests {
    @Test func blanksWholeWordOnly() {
        #expect(ModelFillBlankGenerator.blank("in", in: "Abito in Italia.") == "Abito ___ Italia.")
        #expect(ModelFillBlankGenerator.blank("in", in: "Inizio domani.") == nil)
        #expect(ModelFillBlankGenerator.blank("Caffè", in: "Bevo un caffè.") == "Bevo un ___.")
        #expect(ModelFillBlankGenerator.blank("c’è", in: "C'è un bar qui.") == "___ un bar qui.")
        #expect(ModelFillBlankGenerator.blank("caffè", in: "Bevo un caffe.") == nil)
    }
}

/// Runs only where Apple Intelligence is available. Generates real sentences
/// and checks the target word is really blanked out.
@MainActor
struct ModelSmokeTests {
    @Test(.enabled(if: ModelStatus.current().isAvailable), .timeLimit(.minutes(2)))
    func generatesSentencesWithTarget() async throws {
        let words = [
            TargetWord(wordID: "a1/caffe", lessonID: "a1-01", italian: "caffè", russian: "кофе", pos: .noun, gender: "m"),
            TargetWord(wordID: "a1/parlo", lessonID: "a1-06", italian: "parlo", russian: "я говорю", pos: .verb, gender: nil),
            TargetWord(wordID: "a1/in albergo", lessonID: "a1-06", italian: "in albergo", russian: "в гостинице", pos: .phrase, gender: nil),
            TargetWord(wordID: "a1/stanco", lessonID: "a1-01", italian: "stanco", russian: "уставший", pos: .adj, gender: nil),
        ]
        var produced = 0
        for w in words {
            do {
                let ex = try await ModelFillBlankGenerator().makeExercise(for: w, lessonTitle: "Il presente dei verbi in -are")
                print("FM[\(w.italian)]: \(ex.sentence)")
                #expect(ex.sentence.contains(FillBlankExercise.blank))
                produced += 1
            } catch {
                print("FM[\(w.italian)] failed: \(error.localizedDescription)")
            }
        }
        #expect(produced >= 3)
    }
}
