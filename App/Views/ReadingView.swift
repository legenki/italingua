import SwiftData
import SwiftUI

/// "Чтение": the on-device model writes a short text on the lesson's words,
/// or rewrites the learner's own Italian text for their level. Course words
/// found in the text are listed with translations from the static content.
struct ReadingView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case lesson, own
        var id: String { rawValue }
        var title: String { self == .lesson ? String(localized: "Текст урока") : String(localized: "Свой текст") }
    }

    let lesson: Lesson
    @Query private var vocab: [VocabItem]
    @Query private var favorites: [FavoriteWord]
    @State private var mode = Mode.lesson
    @State private var level: String
    @State private var original = ""
    @State private var reading: ReadingText?
    @State private var working = false
    @State private var error: String?
    @State private var readDone = false

    init(lesson: Lesson) {
        self.lesson = lesson
        _level = State(initialValue: lesson.level)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "Чтение")).font(.s(.largeTitle).weight(.bold))
                Picker(String(localized: "Текст"), selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: mode) { reading = nil; error = nil }

                if !ModelStatus.current().isAvailable {
                    Card(fill: Theme.warningFill) {
                        CardLabel(text: String(localized: "Без модели"), color: Theme.warningText)
                        Text(String(localized: "Тексты пишет Apple Intelligence на устройстве, а сейчас модель недоступна."))
                            .font(.s(.subheadline))
                    }
                } else {
                    switch mode {
                    case .lesson: lessonControls
                    case .own: ownControls
                    }
                }

                if let error {
                    Text(error).font(.s(.subheadline)).foregroundStyle(Theme.feminine)
                }
                if let reading { result(reading) }
            }
            .padding(16)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("")
    }

    // MARK: - Controls

    private var lessonControls: some View {
        Card {
            Text(String(localized: "Короткий рассказ из слов этого урока, на уровне \(lesson.level)."))
                .foregroundStyle(Theme.secondaryText)
            ActionButton(title: reading == nil ? String(localized: "Составить текст") : String(localized: "Другой текст"), working: working) {
                await run {
                    let words = lesson.sortedVocab.filter(FillBlankSession.isPracticable)
                        .filter { [.noun, .verb, .adj, .adv].contains($0.pos) }
                        .shuffled().prefix(14).map(\.italian)
                    return try await ReadingGenerator.lessonText(words: Array(words),
                                                                 topics: lesson.sortedGrammar.map(\.topic),
                                                                 level: lesson.level)
                }
            }
        }
    }

    private var ownControls: some View {
        Card {
            Text(String(localized: "Вставь итальянский текст — статью, письмо, абзац из книги. Модель перескажет его проще."))
                .foregroundStyle(Theme.secondaryText)
            TextEditor(text: $original)
                .font(.s(.body))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
                .padding(8)
                .background(Theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack {
                Text(String(localized: "Уровень"))
                Picker(String(localized: "Уровень"), selection: $level) {
                    Text("A1").tag("A1")
                    Text("A2").tag("A2")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
            }
            ActionButton(title: String(localized: "Упростить"), working: working) {
                await run { try await ReadingGenerator.adapt(original, level: level) }
            }
            .disabled(original.trimmingCharacters(in: .whitespacesAndNewlines).count < 20)
        }
    }

    private func run(_ make: @escaping () async throws -> ReadingText) async {
        working = true
        error = nil
        defer { working = false }
        do {
            reading = try await make()
            readDone = false
        } catch {
            self.error = String(localized: "Модель не справилась: \(error.localizedDescription) Попробуй ещё раз.")
        }
    }

    // MARK: - Result

    @ViewBuilder
    private func result(_ r: ReadingText) -> some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    CardLabel(text: mode == .lesson ? String(localized: "Текст · \(lesson.level)") : String(localized: "Проще · \(level)"))
                    if !r.title.isEmpty { Text(r.title).font(.s(.title2).weight(.bold)) }
                }
                Spacer()
                SpeakButton(text: r.text, label: String(localized: "Прослушать весь текст"), style: .filled)
            }
            Text(r.text)
                .font(.s(.title3))
                .lineSpacing(5)
                .textSelection(.enabled)
            Text(String(localized: "Текст составлен моделью на устройстве и может содержать ошибки."))
                .font(.s(.caption))
                .foregroundStyle(Theme.secondaryText)
            Button {
                StudySession.shared.noteReading(lessonID: lesson.id)
                readDone = true
            } label: {
                Label(readDone ? String(localized: "Прочитано") : String(localized: "Я прочитал текст"),
                      systemImage: readDone ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.s(.headline))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(readDone)
        }

        Card(padding: 0) {
            CardLabel(text: String(localized: "По предложениям")).padding([.top, .horizontal], 16)
            VStack(spacing: 0) {
                ForEach(Array(r.sentences.enumerated()), id: \.offset) { i, sentence in
                    if i > 0 { Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, 72) }
                    HStack(spacing: 12) {
                        SpeakButton(text: sentence, label: String(localized: "Прослушать предложение"))
                        Text(sentence).textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .padding(.bottom, 6)
        }

        let words = ReadingGenerator.glossary(for: r.text, vocab: glossaryVocab)
        if !words.isEmpty {
            let starred = Set(favorites.map(\.wordID))
            Card(padding: 0) {
                CardLabel(text: String(localized: "Слова из курса")).padding([.top, .horizontal], 16)
                VStack(spacing: 0) {
                    ForEach(Array(words.enumerated()), id: \.element.wordID) { i, item in
                        if i > 0 { Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, 72) }
                        HStack(spacing: 12) {
                            SpeakButton(text: item.withArticle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayWithArticle).font(.s(.body).weight(.semibold))
                                Text(item.translation).font(.s(.subheadline)).foregroundStyle(Theme.secondaryText)
                            }
                            Spacer(minLength: 8)
                            FavoriteButton(wordID: item.wordID, isFavorite: starred.contains(item.wordID))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.bottom, 6)
                .textSelection(.enabled)
            }
        }
    }

    /// Words of this level and the ones before it.
    private var glossaryVocab: [VocabItem] {
        vocab.filter { ($0.lesson?.level ?? "") <= lesson.level }
    }
}

private struct ActionButton: View {
    let title: String
    let working: Bool
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 8) {
                if working { ProgressView().controlSize(.small).tint(Theme.onAccent) }
                Text(working ? String(localized: "Модель пишет…") : title)
            }
            .font(.s(.headline))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(working)
    }
}
