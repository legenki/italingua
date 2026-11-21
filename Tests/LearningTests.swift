import Foundation
import SwiftData
import Testing
@testable import Italingua

@MainActor
struct ImporterTests {
    @Test func importsBundledLevelsAndIsIdempotent() throws {
        let container = try AppContainer.make(inMemory: true)
        let context = container.mainContext
        let defaults = UserDefaults(suiteName: "importer-\(UUID())")!
        let bundle = Bundle(for: BundleToken.self)
        let appBundle = Bundle.allBundles.first { $0.bundleURL.pathExtension == "app" } ?? bundle

        try ContentImporter.importBundledContent(into: context, bundle: appBundle, defaults: defaults)
        let lessons = try context.fetch(FetchDescriptor<Lesson>())
        let words = try context.fetchCount(FetchDescriptor<VocabItem>())
        #expect(lessons.count == 40)
        #expect(Set(lessons.map(\.level)) == ["A1", "A2"])
        #expect(words > 1800)
        #expect(lessons.allSatisfy { !$0.grammar.isEmpty })

        // Second run with the same JSON must not duplicate anything.
        try ContentImporter.importBundledContent(into: context, bundle: appBundle, defaults: defaults)
        #expect(try context.fetchCount(FetchDescriptor<Lesson>()) == 40)
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
        #expect(try context.fetchCount(FetchDescriptor<Lesson>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<GrammarTopic>()) == 1)
        let lesson = try #require(try context.fetch(FetchDescriptor<Lesson>()).first)
        #expect(lesson.vocab.map(\.wordID) == ["a1/caffe"])
        #expect(lesson.grammar.count == 1)
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
        #expect(ModelFillBlankGenerator.blank("c'è", in: "C’è un bar qui.") == "___ un bar qui.")
        #expect(ModelFillBlankGenerator.blank("caffè", in: "Bevo un caffe.") == nil)
    }

    @Test func describesReflexiveInfinitiveAsInfinitive() {
        let w = TargetWord(wordID: "a1/chiamarsi", lessonID: "a1-04", italian: "chiamarsi", russian: "зваться", pos: .verb, gender: nil)
        #expect(ModelFillBlankGenerator.describe(w) == "verb, infinitive")
    }
}

/// Runs only where Apple Intelligence is available. Generates real sentences
/// and checks the target word is really blanked out.
@MainActor
struct ModelSmokeTests {
    @Test(.enabled(if: ModelStatus.current().isAvailable), .timeLimit(.minutes(4)))
    func generatesSentencesWithTarget() async throws {
        let words = [
            TargetWord(wordID: "a1/caffe", lessonID: "a1-01", italian: "caffè", russian: "кофе", pos: .noun, gender: "m"),
            TargetWord(wordID: "a1/parlo", lessonID: "a1-06", italian: "parlo", russian: "я говорю", pos: .verb, gender: nil),
            TargetWord(wordID: "a1/in albergo", lessonID: "a1-06", italian: "in albergo", russian: "в гостинице", pos: .phrase, gender: nil),
            TargetWord(wordID: "a1/stanco", lessonID: "a1-01", italian: "stanco", russian: "уставший", pos: .adj, gender: nil),
            // These used to be rejected by the default guardrails.
            TargetWord(wordID: "a1/madre", lessonID: "a1-01", italian: "madre", russian: "мать", pos: .noun, gender: "f"),
            TargetWord(wordID: "a1/mio", lessonID: "a1-01", italian: "mio", russian: "мой", pos: .pron, gender: nil),
            TargetWord(wordID: "a1/due", lessonID: "a1-01", italian: "due", russian: "два", pos: .num, gender: nil),
            TargetWord(wordID: "a1/con", lessonID: "a1-01", italian: "con", russian: "с", pos: .prep, gender: nil),
            // A2: past forms must stay as they are.
            TargetWord(wordID: "a2/dimenticavo", lessonID: "a2-02", italian: "dimenticavo", russian: "я забыл", pos: .verb, gender: nil),
            TargetWord(wordID: "a2/abbiamo mangiato", lessonID: "a2-04", italian: "abbiamo mangiato", russian: "мы поели", pos: .verb, gender: nil),
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
        #expect(produced >= words.count - 1)
    }
}

struct RuleMarkupTests {
    @Test func parsesAllBlockKinds() {
        let text = """
        Intro with **bold**.
        • one
        • two
        ! careful
        ! still careful
        conj: parlare | говорить
        io parl|o
        tu parl|i
        lui/lei parl|a
        noi parl|iamo
        voi parl|ate
        loro pàrl|ano

        ex: Abito a Mosca. | Я живу в Москве.
        """
        let blocks = RuleMarkup.parse(text)
        #expect(blocks.count == 5)
        #expect(blocks[0] == .paragraph("Intro with **bold**."))
        #expect(blocks[1] == .bullets(["one", "two"]))
        #expect(blocks[2] == .callout(["careful", "still careful"]))
        guard case .conjugation(let c) = blocks[3] else { Issue.record("no table"); return }
        #expect(c.verb == "parlare" && c.gloss == "говорить" && c.rows.count == 6)
        #expect(c.rows[2] == .init(person: "lui/lei", stem: "parl", ending: "a"))
        #expect(c.spoken.hasPrefix("io parlo, tu parli"))
        #expect(blocks[4] == .example(italian: "Abito a Mosca.", russian: "Я живу в Москве."))
    }

    @Test func irregularRowsHaveNoEnding() {
        let blocks = RuleMarkup.parse("conj: essere | быть\nio sono\ntu sei")
        guard case .conjugation(let c) = blocks.first else { Issue.record("no table"); return }
        #expect(c.rows[0] == .init(person: "io", stem: "sono", ending: ""))
    }

    @Test func parsesTables() {
        let blocks = RuleMarkup.parse("table: Буква | Название* | Звук\nA a | a | [а]\nB b | bi | [б]\n\nex: Ciao. | Привет.")
        #expect(blocks.count == 2)
        guard case .table(let t) = blocks.first else { Issue.record("no table"); return }
        #expect(t.header == ["Буква", "Название", "Звук"])
        #expect(t.spokenColumns == [1])
        #expect(t.rows == [["A a", "a", "[а]"], ["B b", "bi", "[б]"]])
        #expect(t.spoken(t.rows[1]) == "bi")
        #expect(Speech.spokenForm("libro → libri") == "libro , libri")
    }

    @Test(arguments: ["A1", "A2"])
    func bundledRulesAllParse(level: String) throws {
        let url = Bundle.allBundles.first { $0.bundleURL.pathExtension == "app" }!
            .url(forResource: level, withExtension: "json", subdirectory: "Content")!
        let file = try JSONDecoder().decode(ContentFileDTO.self, from: Data(contentsOf: url))
        #expect(file.lessons.count == 20)
        for lesson in file.lessons {
            for g in lesson.grammar {
                let blocks = RuleMarkup.parse(g.rule_ru)
                #expect(!blocks.isEmpty, "\(lesson.id) \(g.topic)")
                for case .conjugation(let c) in blocks {
                    #expect(c.rows.count == 6, "\(lesson.id) \(c.verb)")
                }
                for case .table(let t) in blocks {
                    #expect(!t.rows.isEmpty && t.rows.allSatisfy { $0.count == t.header.count },
                            "\(lesson.id) \(g.topic)")
                }
            }
        }
    }
}

struct ArticleTests {
    @Test(arguments: [
        ("lavoro", "m", false, "il lavoro"),
        ("studente", "m", false, "lo studente"),
        ("zio", "m", false, "lo zio"),
        ("amico", "m", false, "l'amico"),
        ("amica", "f", false, "l'amica"),
        ("casa", "f", false, "la casa"),
        ("amici", "m", true, "gli amici"),
        ("libri", "m", true, "i libri"),
        ("case", "f", true, "le case"),
        ("hotel", "m", false, "l'hotel"),
        ("hotel", "m", true, "gli hotel"),
        ("pneumatico", "m", false, "lo pneumatico"),
        ("pneumatici", "m", true, "gli pneumatici"),
    ])
    func definite(word: String, gender: String, plural: Bool, expected: String) {
        #expect(Articles.withArticle(word, gender: gender, plural: plural) == expected)
    }

    @Test func skipsPhrasesAndExistingArticles() {
        #expect(Articles.withArticle("la sera", gender: "f", plural: false) == nil)
        #expect(Articles.withArticle("Italia", gender: "f", plural: false) == nil)
    }
}

struct SpokenAnswerTests {
    @Test(arguments: [
        ("Casa.", "casa", "casa"),
        ("è la casa", "casa", "casa"),
        ("Buongiorno, signora!", "buongiorno", "buongiorno"),
        ("grazie mille", "grazie mille", "grazie mille"),
        ("Cosa", "casa", "cosa"),
        ("", "casa", ""),
    ])
    func picksExpectedWord(transcript: String, expected: String, result: String) {
        #expect(SpeechInput.answer(from: transcript, expected: expected) == result)
    }
}

struct LessonProgressTests {
    @Test func states() {
        #expect(LessonProgress(boxes: [nil, nil]).state == .notStarted)
        #expect(LessonProgress(boxes: [1, nil]).state == .inProgress)   // practised, last answer wrong
        #expect(LessonProgress(boxes: [2, 1]).state == .inProgress)
        #expect(LessonProgress(boxes: [2, 5]).state == .done)
        #expect(LessonProgress(boxes: []).state == .notStarted)
        #expect(LessonProgress(boxes: [2, nil, 3, 1]).fraction == 0.5)
    }
}

struct FlashcardSessionTests {
    private func card(_ id: String) -> Flashcard {
        Flashcard(wordID: id, italian: id, spoken: id, russian: "ru-" + id, gender: nil, note: nil)
    }

    @Test func runsThroughDeckAndRepeatsLearning() {
        let s = FlashcardSession(cards: ["a", "b", "c"].map(card))
        s.flipped = true
        s.answer(knew: true)
        #expect(s.flipped == false && s.index == 1)
        s.answer(knew: false)
        s.undo()
        #expect(s.index == 1 && s.learning.isEmpty)
        s.answer(knew: false)
        s.answer(knew: true)
        #expect(s.isFinished && s.known.count == 2 && s.learning.map(\.id) == ["b"])
        s.restartWithLearning()
        #expect(s.total == 1 && s.current?.id == "b" && s.known.isEmpty)
        s.restartAll()
        #expect(s.total == 3)
    }

    @Test func unknownAndDueWordsComeFirst() {
        let cards = ["new", "known", "due", "weak"].map(card)
        let ordered = FlashcardSession.order(cards, boxes: ["known": 4, "due": 3, "weak": 1], due: ["due"])
        #expect(Set(ordered.prefix(3).map(\.id)) == ["new", "due", "weak"])
        #expect(ordered.last?.id == "known")
    }
}

struct StatsDataTests {
    let cal = Calendar(identifier: .gregorian)
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12))! }

    func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: now)! }

    @Test func activityStreakAndAccuracy() {
        let answers: [(date: Date, correct: Bool)] = [
            (daysAgo(0), true), (daysAgo(0), false),
            (daysAgo(1), true),
            (daysAgo(2), true),
            (daysAgo(4), false),          // gap on day 3 ends the streak
            (daysAgo(20), true),          // outside the 14-day window
        ]
        let lessons = [StatsData.LessonInput(id: "l1", label: "В1", title: "T", wordIDs: ["a", "b", "c", "d"])]
        let data = StatsData.make(answers: answers, boxes: ["a": 5, "b": 2, "c": 1],
                                  dueDates: ["a": daysAgo(-3), "b": daysAgo(2), "c": daysAgo(-1)],
                                  lessons: lessons, mistakes: [.article, .article, .accent],
                                  now: now, calendar: cal)
        #expect(data.days.count == StatsData.dayCount)
        #expect(data.days.last?.total == 2 && data.todayAnswers == 2)
        #expect(data.streak == 3)
        #expect(data.accuracy7 == 3.0 / 5.0)
        #expect(data.totalWords == 4 && data.known == 2 && data.learned == 1)
        #expect(data.stages.map(\.count) == [1, 1, 1, 0, 1])
        #expect(data.dueToday == 1)                       // "b" is overdue
        #expect(data.forecast.map(\.count) == [1, 1, 0, 1, 0, 0, 0])
        #expect(data.mistakes.first?.kind == .article && data.mistakes.first?.count == 2)
        #expect(data.lessons.first?.progress.known == 2)
    }

    @Test func streakSurvivesUntilFirstAnswerOfTheDay() {
        let data = StatsData.make(answers: [(daysAgo(1), true), (daysAgo(2), true)], boxes: [:], dueDates: [:],
                                  lessons: [], mistakes: [], now: now, calendar: cal)
        #expect(data.streak == 2 && data.todayAnswers == 0 && data.accuracy7 == 1)
    }

    @Test func russianDayWords() {
        // Forms come from the string catalog, so compare with the catalog's values.
        let (one, few, many) = (String(localized: "день"), String(localized: "дня"), String(localized: "дней"))
        #expect([1, 2, 5, 11, 21, 22, 25].map { dayWord($0, language: "ru") } == [one, few, many, many, one, few, many])
        #expect([1, 2, 21].map { dayWord($0, language: "en") } == [one, many, many])
        #expect(inARowWord(1, language: "es") == " seguido")
        #expect(inARowWord(2, language: "es") == String(localized: " подряд"))
    }
}

struct TodayTests {
    @Test func greetingByHour() {
        let cal = Calendar.current
        func at(_ h: Int) -> Date { cal.date(bySettingHour: h, minute: 0, second: 0, of: .now)! }
        #expect(TodayView.greeting(at: at(9)) == "Buongiorno!")
        #expect(TodayView.greeting(at: at(19)) == "Buonasera!")
        #expect(TodayView.greeting(at: at(2)) == "Buonanotte!")
    }

    @Test func russianWordForms() {
        let (one, few, many) = (String(localized: "слово"), String(localized: "слова"), String(localized: "слов"))
        #expect([1, 3, 5, 21].map { wordWord($0, language: "ru") } == [one, few, many, one])
        #expect([1, 3].map { wordWord($0, language: "es") } == [one, many])
        #expect(waitingWord(21, language: "ru") == String(localized: " ждёт"))
        #expect(waitingWord(2, language: "ru") == String(localized: " ждут"))
        #expect("вторник, 18 ноября".capitalizedFirst == "Вторник, 18 ноября")
    }
}

@MainActor
struct FavoriteTests {
    @Test func toggleAddsRemovesAndClearsDuplicates() throws {
        let container = try AppContainer.make(inMemory: true)
        let ctx = container.mainContext
        #expect(try ctx.toggleFavorite(wordID: "a1/casa") == true)
        ctx.insert(FavoriteWord(wordID: "a1/casa"))       // a duplicate from another device
        try ctx.save()
        #expect(try ctx.toggleFavorite(wordID: "a1/casa") == false)
        #expect(try ctx.fetchCount(FetchDescriptor<FavoriteWord>()) == 0)
    }
}

@MainActor
struct ProgressMergeTests {
    @Test func duplicateRowsAddUpTheirCounts() throws {
        let container = try AppContainer.make(inMemory: true)
        let ctx = container.mainContext
        let a = WordProgress(wordID: "a1/casa"), b = WordProgress(wordID: "a1/casa")
        a.correctCount = 3; a.wrongCount = 1
        b.correctCount = 2; b.wrongCount = 1
        b.lastReviewed = .now
        ctx.insert(a); ctx.insert(b)
        try ctx.save()
        let p = try ctx.progress(for: "a1/casa")
        #expect(p.correctCount == 5)
        #expect(p.wrongCount == 2)
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<WordProgress>()) == 1)
    }
}

@MainActor
struct FillBlankSessionTests {
    @Test func secondNextDoesNotSkipAWord() async throws {
        let container = try AppContainer.make(inMemory: true)
        let words = (1...3).map {
            TargetWord(wordID: "a1/w\($0)", lessonID: "a1-01", italian: "w\($0)", russian: "w", pos: .noun, gender: "m")
        }
        let s = FillBlankSession(lessonTitle: "T", words: words, status: .unavailable("test"),
                                 generator: FallbackFillBlankGenerator())
        await s.start()
        s.submit("w1", in: container.mainContext)
        await s.next()
        await s.next()   // a double tap: the task is not checked yet
        #expect(s.index == 1)
        #expect(s.current?.wordID == "a1/w2")
    }
}

struct GeneratorLevelTests {
    @Test func levelFromLessonID() {
        let w = TargetWord(wordID: "a2/x", lessonID: "a2-05", italian: "x", russian: "x", pos: .noun, gender: "m")
        #expect(ModelFillBlankGenerator.level(of: w) == "A2")
        #expect(ModelFillBlankGenerator.instructions(level: "A1").contains("present tense"))
        #expect(ModelFillBlankGenerator.instructions(level: "A2").contains("imperfetto"))
    }
}

struct TranslationCheckerTests {
    struct FakeFixer: SentenceFixing {
        let answer: String
        func fix(answer: String, reference: String, level: String) async throws -> String { self.answer }
    }
    let task = TranslationTask(lessonID: "a1-01", russian: "Я живу в Москве.", reference: "Abito a Mosca.")

    @Test func exactMatchNeedsNoModel() async {
        let r = await TranslationChecker.check(answer: "abito a Mosca", task: task, level: "A1", fixer: nil)
        #expect(r.verdict == .exact && r.isCorrect)
    }

    @Test func accentsOnly() async {
        let t = TranslationTask(lessonID: "a1-01", russian: "Кофе горячий.", reference: "Il caffè è caldo.")
        let r = await TranslationChecker.check(answer: "Il caffe e caldo", task: t, level: "A1", fixer: nil)
        #expect(r.verdict == .accents && r.mistakes == [.accent])
    }

    @Test func modelKeepsAnswerMeansAlternative() async {
        let r = await TranslationChecker.check(answer: "Vivo a Mosca.", task: task, level: "A1",
                                               fixer: FakeFixer(answer: "Vivo a Mosca."))
        #expect(r.verdict == .alternative && r.isCorrect)
    }

    @Test func correctionIsDiffedAndClassified() async {
        let r = await TranslationChecker.check(answer: "Abito in Mosca", task: task, level: "A1",
                                               fixer: FakeFixer(answer: "Abito a Mosca."))
        #expect(r.verdict == .corrected && !r.isCorrect)
        #expect(r.diff.map(\.text) == ["abito", "in", "a", "mosca"])
        #expect(r.diff.map(\.kind) == [.same, .removed, .added, .same])
        #expect(r.mistakes == [.preposition])
    }

    @Test func rewriteFallsBackToReference() async {
        let t = TranslationTask(lessonID: "a1-01", russian: "Кофе горячий.", reference: "Il caffè è caldo.")
        let r = await TranslationChecker.check(answer: "Il caffe molto caldo", task: t, level: "A1",
                                               fixer: FakeFixer(answer: "L'acqua è fredda."))
        #expect(r.corrected == "Il caffè è caldo.")
    }

    @Test func noModelLetsLearnerDecide() async {
        let r = await TranslationChecker.check(answer: "Vivo a Mosca", task: task, level: "A1", fixer: nil)
        #expect(r.verdict == .unchecked && r.corrected == "Abito a Mosca.")
    }
}

@MainActor
struct ReadingTests {
    @Test func sentencesSplit() {
        let r = ReadingText(title: "T", text: "Marco abita a Roma. Ha una casa grande! Ti piace?")
        #expect(r.sentences.count == 3)
    }

    @Test func glossaryFindsCourseWords() throws {
        let container = try AppContainer.make(inMemory: true)
        let ctx = container.mainContext
        let casa = VocabItem(wordID: "a1/casa", order: 0, italian: "casa", russian: "дом", posRaw: "noun",
                             gender: "m", number: nil, stress: nil, formOf: nil)
        let caffe = VocabItem(wordID: "a1/caffe", order: 1, italian: "caffè", russian: "кофе", posRaw: "noun",
                             gender: "m", number: nil, stress: nil, formOf: nil)
        let mare = VocabItem(wordID: "a1/mare", order: 2, italian: "mare", russian: "море", posRaw: "noun",
                             gender: "m", number: nil, stress: nil, formOf: nil)
        [casa, caffe, mare].forEach(ctx.insert)
        let found = ReadingGenerator.glossary(for: "Bevo un caffe a casa.", vocab: [casa, caffe, mare])
        #expect(found.map(\.italian) == ["caffè", "casa"])

        let acqua = VocabItem(wordID: "a1/acqua", order: 3, italian: "acqua", russian: "вода", posRaw: "noun",
                              gender: "f", number: nil, stress: nil, formOf: nil)
        let fare = VocabItem(wordID: "a1/fare", order: 4, italian: "fare", russian: "делать", posRaw: "verb",
                             gender: nil, number: nil, stress: nil, formOf: nil)
        let fareLaSpesa = VocabItem(wordID: "a1/fare la spesa", order: 5, italian: "fare la spesa", russian: "ходить за покупками", posRaw: "phrase",
                                    gender: nil, number: nil, stress: nil, formOf: nil)
        [acqua, fare, fareLaSpesa].forEach(ctx.insert)
        let elidedAndPhrase = ReadingGenerator.glossary(for: "Bevo l'acqua e vado a fare la spesa.",
                                                        vocab: [casa, acqua, fare, fareLaSpesa])
        #expect(elidedAndPhrase.map(\.italian) == ["acqua", "fare la spesa"])
    }
}

@MainActor
struct TranslationTaskTests {
    @Test func tasksComeFromRuleExamples() throws {
        let container = try AppContainer.make(inMemory: true)
        let lesson = Lesson(id: "a1-01", level: "A1", order: 1, title: "T", sourcePart: "intro", sourceLesson: 1, patterns: [])
        container.mainContext.insert(lesson)
        let rules = ["Текст.\nex: **Abito** a Mosca. | Я живу в Москве.\nex: Ciao! | Привет!", "ex: Ciao! | Привет!"]
        let tasks = TranslationSession.tasks(from: lesson, ruleTexts: rules, count: 10)
        #expect(tasks.count == 2)
        #expect(tasks.contains { $0.reference == "Abito a Mosca." && $0.russian == "Я живу в Москве." })
    }
}

struct ModelReadingSmokeTests {
    @Test(.enabled(if: ModelStatus.current().isAvailable), .timeLimit(.minutes(2)))
    func fixerAndReadingWork() async throws {
        let fixed = try await ModelSentenceFixer().fix(answer: "Ho due fratello.", reference: "Ho due fratelli.", level: "A1")
        print("FIX: \(fixed)")
        #expect(TranslationChecker.words(fixed) == ["ho", "due", "fratelli"])
        let text = try await ReadingGenerator.lessonText(words: ["casa", "amico", "caffè"], topics: ["Артикль"], level: "A1")
        print("READ: \(text.title) — \(text.text)")
        #expect(text.sentences.count >= 3)
    }
}

struct WordSearchTests {
    @Test func ranking() {
        #expect(WordSearch.rank(query: "casa", italian: "casa", russian: "дом") == 0)
        #expect(WordSearch.rank(query: "cas", italian: "casalinga", russian: "домохозяйка") == 1)
        #expect(WordSearch.rank(query: "spesa", italian: "fare la spesa", russian: "делать покупки") == 2)
        #expect(WordSearch.rank(query: "citta", italian: "città", russian: "город") == 0)
        #expect(WordSearch.rank(query: "дом", italian: "casa", russian: "дом") == 4)
        #expect(WordSearch.rank(query: "musica", italian: "canzone", russian: "música") == 4)
        #expect(WordSearch.rank(query: "xyz", italian: "casa", russian: "дом") == nil)
        #expect(WordSearch.rank(query: "  ", italian: "casa", russian: "дом") == nil)
    }
}

@MainActor
struct TextScaleTests {
    @Test func stepsStayInRange() {
        let scale = TextScale.shared
        let saved = scale.step
        defer { scale.step = saved }
        scale.step = 0
        #expect(scale.factor == 1)
        for _ in 0..<20 { scale.grow() }
        #expect(scale.step == TextScale.range.upperBound && !scale.canGrow)
        for _ in 0..<20 { scale.shrink() }
        #expect(scale.step == TextScale.range.lowerBound && abs(scale.factor - 0.8) < 0.001)
    }
}

@MainActor
struct StudySessionTests {
    @Test func stepsTimerAndMedal() throws {
        let container = try AppContainer.make(inMemory: true)
        let ctx = container.mainContext
        let lesson = Lesson(id: "a1-01", level: "A1", order: 1, title: "T", sourcePart: "intro", sourceLesson: 1, patterns: [])
        ctx.insert(lesson)
        let topic = GrammarTopic(order: 0, topic: "Алфавит", ruleRU: "")
        topic.lesson = lesson
        ctx.insert(topic)
        let word = VocabItem(wordID: "a1/casa", order: 0, italian: "casa", russian: "дом", posRaw: "noun",
                             gender: "f", number: nil, stress: nil, formOf: nil)
        word.lesson = lesson
        ctx.insert(word)

        let session = StudySession()
        defer { session.reset() }
        // Notes are timed with the real clock, so the session starts just before now.
        let t0 = Date.now.addingTimeInterval(-700)
        session.start(lesson: lesson, now: t0)
        #expect(session.isRunning && session.currentStep == .rules)
        #expect(abs(session.remaining(now: t0.addingTimeInterval(600)) - 30 * 60) < 0.001)

        session.pause(now: t0.addingTimeInterval(600))
        #expect(abs(session.elapsed(now: t0.addingTimeInterval(5000)) - 600) < 0.001)
        session.resume()

        session.noteTopic(lessonID: "a1-02", topic: "Алфавит")      // another lesson: ignored
        #expect(!session.isDone(.rules))
        session.noteTopic(lessonID: "a1-01", topic: "Алфавит")
        session.noteSpoken("la casa")
        session.noteSpoken("casa")
        #expect(session.progress(.words).done == 1)
        session.noteSpoken("il mare")                               // not a word of the lesson
        session.noteCard(lessonID: "a1-01", wordID: "a1/casa")
        #expect(session.doneSteps == 3 && session.currentStep == .reading)
        session.noteReading(lessonID: "a1-01")
        #expect(session.isFinished && session.earnedMedal)
    }
}

struct MedalStatsTests {
    @Test func calendarStreakAndBest() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome")!
        // Wednesday 18 November 2026, noon.
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12))!
        func day(_ n: Int, _ minutes: Double, _ medal: Bool) -> (finishedAt: Date, lessonID: String, seconds: Double, medal: Bool) {
            (cal.date(byAdding: .day, value: -n, to: now)!, "a1-01", minutes * 60, medal)
        }
        let s = MedalStats.make(records: [day(0, 37, true), day(1, 39, true), day(2, 45, false), day(3, 33, true)],
                                weeks: 2, now: now, calendar: cal)
        #expect(s.days.count == 14)
        #expect(cal.component(.weekday, from: s.days[0].date) == 2)        // starts on Monday
        #expect(s.days.filter { $0.kind == .medal }.count == 3)
        #expect(s.days.filter { $0.kind == .session }.count == 1)
        #expect(s.days.contains { $0.isToday && $0.kind == .medal })
        #expect(s.total == 3 && s.thisWeek == 2)                          // Sun 15 belongs to last week
        #expect(s.streak == 2)                                            // the day without a medal breaks it
        #expect(s.bestMinutes == 33)
        #expect(s.recent.first?.minutes == 37)
    }
}

#if os(macOS)
import AppKit

@MainActor
struct ThemeColorTests {
    /// SwiftUI resolves dynamic colors on its render thread; a main-actor
    /// provider trapped there (TestFlight build 2 crash on iPhone).
    @Test func dynamicColorResolvesOffTheMainThread() async {
        let color = NSColor(Theme.card)
        let red = await Task.detached {
            color.usingColorSpace(.sRGB)?.redComponent
        }.value
        #expect(red != nil)
    }
}
#endif
