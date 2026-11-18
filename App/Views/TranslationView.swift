import SwiftData
import SwiftUI

/// "Переведи фразу": translate an example sentence of the lesson into Italian;
/// the answer is checked by code and the on-device model.
struct TranslationView: View {
    let lesson: Lesson
    @Environment(\.modelContext) private var context
    @Query private var notes: [RuleNote]
    @State private var session: TranslationSession?
    @State private var answer = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Переведи фразу").font(.largeTitle.weight(.bold))
                if let session { content(session) } else { ProgressView() }
            }
            .padding(16)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("")
        .onAppear(perform: startIfNeeded)
    }

    @ViewBuilder
    private func content(_ s: TranslationSession) -> some View {
        if !ModelStatus.current().isAvailable {
            Card(fill: Theme.warningFill) {
                CardLabel(text: "Без модели", color: Theme.warningText)
                Text("Ответ сравнивается только с образцом. Если написал иначе, сверь сам и отметь результат.")
                    .font(.subheadline)
            }
        }
        if s.phase == .finished {
            finished(s)
        } else if let task = s.current {
            Card {
                HStack {
                    CardLabel(text: "По-итальянски")
                    Spacer()
                    Text("\(s.index + 1) из \(s.total)").font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
                Text(task.russian).font(.title2.weight(.semibold)).textSelection(.enabled)

                TextField("Твой перевод", text: $answer, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .lineLimit(1...4)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
                    .focused($focused)
                    .disabled(s.phase != .answering)
                    .onSubmit { primary(s) }
                    .padding(12)
                    .frame(minHeight: 48)
                    .background(Theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                switch s.phase {
                case .checking:
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Проверяю…").foregroundStyle(Theme.secondaryText)
                    }
                case .checked(let result):
                    ResultView(result: result, task: task, overridden: s.overridden) { s.markMineCorrect() }
                default:
                    EmptyView()
                }

                Button { primary(s) } label: {
                    Text(s.phase == .answering ? "Проверить" : "Дальше")
                        .font(.headline)
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(s.phase == .checking || (s.phase == .answering && answer.trimmingCharacters(in: .whitespaces).isEmpty))
                .keyboardShortcut(.defaultAction)
            }
            Text("Фразы — примеры из правил урока. Свой вариант тоже засчитывается, если он верен.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func finished(_ s: TranslationSession) -> some View {
        Card {
            CardLabel(text: "Готово")
            if s.total == 0 {
                Text("В правилах этого урока нет примеров для перевода.").foregroundStyle(Theme.secondaryText)
            } else {
                Text("\(s.correctCount) из \(s.total) верно").font(.title.weight(.bold))
                Button {
                    answer = ""
                    s.restart()
                    focused = true
                } label: {
                    Text("Ещё раз")
                        .font(.headline)
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func primary(_ s: TranslationSession) {
        switch s.phase {
        case .answering:
            guard !answer.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            Task { await s.submit(answer) }
        case .checked:
            s.next(answer: answer, in: context)
            answer = ""
            focused = true
        default:
            break
        }
    }

    private func startIfNeeded() {
        guard session == nil else { return }
        let edited = Dictionary(notes.map { ($0.key, $0.text) }, uniquingKeysWith: { a, _ in a })
        let texts = lesson.sortedGrammar.map { edited[RuleNote.key(lessonID: lesson.id, topic: $0.topic)] ?? $0.ruleRU }
        let level = lesson.level
        session = TranslationSession(tasks: TranslationSession.tasks(from: lesson, ruleTexts: texts),
                                     level: level,
                                     fixer: ModelStatus.current().isAvailable ? ModelSentenceFixer() : nil)
        focused = true
    }
}

private struct ResultView: View {
    let result: TranslationResult
    let task: TranslationTask
    let overridden: Bool
    let markCorrect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.title2).foregroundStyle(good ? Theme.accent : Theme.warningText)
                Text(title).font(.headline)
                Spacer(minLength: 0)
                SpeakButton(text: result.corrected, label: "Прослушать", size: 40)
            }
            if result.verdict == .corrected || result.verdict == .accents {
                // The answer with removed words struck through and fixes highlighted.
                diffText.font(.title3)
                if !result.mistakes.isEmpty {
                    Text(result.mistakes.map(\.titleRU).joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            if result.verdict != .exact {
                VStack(alignment: .leading, spacing: 2) {
                    CardLabel(text: "Образец")
                    Text(task.reference).font(.body).textSelection(.enabled)
                }
            }
            if !good && !overridden {
                Button(action: markCorrect) {
                    Label(result.verdict == .unchecked ? "Я ответил верно" : "Мой вариант тоже верен",
                          systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            if result.verdict == .corrected {
                Text("Исправление предлагает модель на устройстве — она иногда ошибается.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var good: Bool { result.isCorrect || overridden }

    private var icon: String {
        good ? "checkmark.circle.fill" : result.verdict == .unchecked ? "questionmark.circle.fill" : "exclamationmark.circle.fill"
    }

    private var title: String {
        if overridden { return "Засчитано как верное" }
        switch result.verdict {
        case .exact: return "Верно!"
        case .alternative: return "Верно — твой вариант тоже правильный"
        case .accents: return "Почти: проверь ударения"
        case .corrected: return "Есть ошибки"
        case .unchecked: return "Сравни с образцом"
        }
    }

    private var diffText: Text {
        result.diff.reduce(Text("")) { acc, t in
            let word: Text = switch t.kind {
            case .same: Text(t.text)
            case .removed: Text(t.text).strikethrough().foregroundStyle(Theme.secondaryText)
            case .added: Text(t.text).bold().foregroundStyle(Theme.accent)
            }
            return Text("\(acc)\(word) ")
        }
    }
}
