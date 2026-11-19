import SwiftData
import SwiftUI

/// Design A "Сегодня": shown when no lesson is selected. Greeting, the lesson
/// to continue, reviews due, the streak, today's goal and a word of the day.
struct TodayView: View {
    /// Selects a lesson in the sidebar.
    let openLesson: (Lesson.ID) -> Void

    @Query(sort: [SortDescriptor(\Lesson.level), SortDescriptor(\Lesson.sourcePart), SortDescriptor(\Lesson.order)])
    private var lessons: [Lesson]
    @Query private var progress: [WordProgress]
    @Query(sort: \ReviewLog.date, order: .reverse) private var logs: [ReviewLog]
    @Query(sort: \FavoriteWord.addedAt, order: .reverse) private var favorites: [FavoriteWord]
    @Query private var vocab: [VocabItem]

    var body: some View {
        let boxes = Dictionary(progress.map { ($0.wordID, $0.box) }, uniquingKeysWith: max)
        let stats = StatsData.make(answers: logs.map { (date: $0.date, correct: $0.correct) },
                                   boxes: boxes, dueDates: [:], lessons: [], mistakes: [])
        let due = dueWords
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)
                        .locale(AppLanguage.locale)).capitalizedFirst)
                        .font(.s(.subheadline).weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(Self.greeting()).font(.s(.largeTitle).weight(.bold))
                    Text(logs.isEmpty ? String(localized: "Начнём с первого урока: выбери его ниже или в списке слева.")
                                      : String(localized: "Продолжим с того места, где остановились."))
                        .foregroundStyle(Theme.secondaryText)
                }

                if let lesson = continueLesson {
                    ContinueCard(lesson: lesson, progress: lessonProgress(lesson, boxes: boxes),
                                 open: { openLesson(lesson.id) })
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) { tiles(stats: stats, due: due) }
                    VStack(spacing: 14) { tiles(stats: stats, due: due) }
                }

                if let word = wordOfTheDay {
                    WordOfTheDay(item: word, isFavorite: favorites.contains { $0.wordID == word.wordID })
                }

                FavoritesCard(items: FavoritesView.items(favorites: favorites, vocab: vocab))
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 800, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("")
    }

    @ViewBuilder
    private func tiles(stats: StatsData, due: [VocabItem]) -> some View {
        Tile(label: String(localized: "К повторению")) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(due.count)").font(.scaledSystem(size: 34, weight: .bold)).monospacedDigit()
                Text(wordWord(due.count) + (due.count == 1 ? String(localized: " ждёт") : String(localized: " ждут"))).foregroundStyle(Theme.secondaryText)
            }
            if due.isEmpty {
                Text(String(localized: "Сегодня повторять нечего")).font(.s(.subheadline)).foregroundStyle(Theme.secondaryText)
            } else {
                NavigationLink {
                    FlashcardsView(items: due, title: String(localized: "Повторение"))
                } label: {
                    Text(String(localized: "Повторить сейчас →")).font(.s(.subheadline).weight(.semibold)).foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        Tile(label: String(localized: "Серия")) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "flame.fill").font(.s(.title2))
                    .foregroundStyle(stats.streak > 0 ? Theme.accent : Theme.separator)
                Text("\(stats.streak)").font(.scaledSystem(size: 34, weight: .bold)).monospacedDigit()
                Text(dayWord(stats.streak) + String(localized: " подряд")).foregroundStyle(Theme.secondaryText)
            }
            Text(stats.todayAnswers > 0 ? String(localized: "Сегодня уже занимались") : String(localized: "Позанимайся сегодня, чтобы продлить"))
                .font(.s(.subheadline)).foregroundStyle(Theme.secondaryText)
        }
        Tile(label: String(localized: "Цель дня")) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Theme.separator, lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: min(Double(stats.todayAnswers) / Double(stats.dailyGoal), 1))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(stats.todayAnswers)").font(.s(.headline).monospacedDigit())
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "\(stats.todayAnswers) из \(stats.dailyGoal) ответов")).font(.s(.subheadline).weight(.semibold))
                    Text(String(localized: "карточки и упражнения")).font(.s(.caption)).foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    // MARK: - Data

    /// The lesson of the latest answer; without history, the first lesson not done.
    private var continueLesson: Lesson? {
        if let id = logs.first?.lessonID, let lesson = lessons.first(where: { $0.id == id }) {
            return lesson
        }
        let boxes = Dictionary(progress.map { ($0.wordID, $0.box) }, uniquingKeysWith: max)
        return lessons.first { lessonProgress($0, boxes: boxes).state != .done } ?? lessons.first
    }

    /// Words practised before whose review date has come, across all lessons.
    private var dueWords: [VocabItem] {
        let dueIDs = Set(progress.filter { $0.box > 0 && $0.dueDate <= .now }.map(\.wordID))
        guard !dueIDs.isEmpty else { return [] }
        return lessons.flatMap(\.sortedVocab).filter { dueIDs.contains($0.wordID) }
    }

    /// Same word all day: picked by the date from the lesson to continue,
    /// preferring words not known yet.
    private var wordOfTheDay: VocabItem? {
        guard let lesson = continueLesson else { return nil }
        let boxes = Dictionary(progress.map { ($0.wordID, $0.box) }, uniquingKeysWith: max)
        let pool = lesson.sortedVocab.filter { FillBlankSession.isPracticable($0) && $0.pos == .noun }
        let fresh = pool.filter { (boxes[$0.wordID] ?? 0) < LessonProgress.knownBox }
        let candidates = fresh.isEmpty ? pool : fresh
        guard !candidates.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
        return candidates[day % candidates.count]
    }

    private func lessonProgress(_ lesson: Lesson, boxes: [String: Int]) -> LessonProgress {
        LessonProgress(boxes: lesson.vocab.filter(FillBlankSession.isPracticable).map { boxes[$0.wordID] })
    }

    static func greeting(at date: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<17: "Buongiorno!"
        case 17..<23: "Buonasera!"
        default: "Buonanotte!"
        }
    }
}

// MARK: - Pieces

private struct ContinueCard: View {
    let lesson: Lesson
    let progress: LessonProgress
    let open: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { badge; info; buttons.frame(width: 180) }
            VStack(alignment: .leading, spacing: 16) { HStack(spacing: 16) { badge; info }; buttons }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var badge: some View {
        LessonBadge(number: lesson.sourceLesson, progress: progress, size: 72)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardLabel(text: String(localized: "Продолжить · \(lesson.sourceLabel)"))
            Text(lesson.title).font(.s(.title3).weight(.bold)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ProgressView(value: progress.fraction).tint(Theme.accent)
                Text(String(localized: "знакомо \(progress.known) из \(progress.total)"))
                    .font(.s(.subheadline).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            NavigationLink {
                FlashcardsView(lesson: lesson)
            } label: {
                Text(String(localized: "Карточки"))
                    .font(.s(.headline))
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            Button(action: open) {
                Text(String(localized: "Открыть урок"))
                    .font(.s(.headline))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct Tile<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: label)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

private struct WordOfTheDay: View {
    let item: VocabItem
    let isFavorite: Bool

    var body: some View {
        HStack(spacing: 16) {
            SpeakButton(text: item.withArticle, label: String(localized: "Прослушать слово дня"), size: 48, style: .onAccent)
            VStack(alignment: .leading, spacing: 2) {
                CardLabel(text: String(localized: "Слово дня · \(item.lesson?.sourceLabel ?? "")"), color: Theme.onAccent.opacity(0.85))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.displayWithArticle).font(.s(.title2).weight(.bold))
                    Text("— \(item.translation)").font(.s(.body).weight(.medium)).opacity(0.85)
                }
            }
            Spacer(minLength: 0)
            FavoriteButton(wordID: item.wordID, isFavorite: isFavorite, size: 40, onAccent: true)
            if let lesson = item.lesson {
                NavigationLink {
                    VocabularyView(lesson: lesson)
                } label: {
                    Text(String(localized: "Вся лексика"))
                        .font(.s(.subheadline).weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 40)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.onAccent, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Theme.onAccent)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .textSelection(.enabled)
    }
}

/// The starred-words deck: count, flashcards and the list.
private struct FavoritesCard: View {
    let items: [VocabItem]

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "star.fill")
                .font(.s(.title2))
                .foregroundStyle(Theme.accent)
                .frame(width: 48, height: 48)
                .background(Theme.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                CardLabel(text: String(localized: "Избранное"))
                Text(items.isEmpty ? String(localized: "Отмечай слова звёздочкой") : "\(items.count) \(wordWord(items.count))")
                    .font(.s(.headline))
            }
            Spacer(minLength: 8)
            if !items.isEmpty {
                NavigationLink {
                    FlashcardsView(items: items, title: String(localized: "Избранное"))
                } label: {
                    Text(String(localized: "Карточки"))
                        .font(.s(.subheadline).weight(.semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 40)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            NavigationLink {
                FavoritesView()
            } label: {
                Text(String(localized: "Список"))
                    .font(.s(.subheadline).weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// "слово", "слова", "слов" for a count.
func wordWord(_ n: Int, language: String = AppLanguage.current) -> String {
    guard language == "ru" else { return n == 1 ? String(localized: "слово") : String(localized: "слов") }
    let m10 = n % 10, m100 = n % 100
    if m10 == 1 && m100 != 11 { return String(localized: "слово") }
    if (2...4).contains(m10) && !(12...14).contains(m100) { return String(localized: "слова") }
    return String(localized: "слов")
}

extension String {
    /// "вторник, 18 ноября" → "Вторник, 18 ноября".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
