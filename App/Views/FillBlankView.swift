import SwiftData
import SwiftUI

struct FillBlankView: View {
    let lesson: Lesson
    @Environment(\.modelContext) private var context
    @Query private var progress: [WordProgress]
    @State private var session: FillBlankSession?
    @State private var answer = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Вставь слово").font(.largeTitle.weight(.bold))
                if let session {
                    content(session)
                } else {
                    ProgressView()
                }
            }
            .padding(16)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("")
        .task { await startIfNeeded() }
    }

    @ViewBuilder
    private func content(_ s: FillBlankSession) -> some View {
        if case .unavailable(let reason) = s.status {
            Card(fill: Theme.warningFill) {
                CardLabel(text: "Без модели", color: Theme.warningText)
                Text(reason + " Задания без контекста: вспомните слово по переводу.")
            }
        } else if let notice = s.modelNotice {
            Card(fill: Theme.warningFill) {
                Text(notice).font(.subheadline)
            }
        }

        switch s.phase {
        case .loading:
            Card {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Составляю задание…").foregroundStyle(Theme.secondaryText)
                }
            }
        case .finished:
            Card {
                CardLabel(text: "Готово")
                Text("\(s.correctCount) из \(s.total) верно").font(.title.weight(.bold))
                Button {
                    Task { await restart() }
                } label: {
                    Text("Ещё раз")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        case .answering, .checked:
            if let ex = s.current { task(ex, session: s) }
        }
    }

    @ViewBuilder
    private func task(_ ex: FillBlankExercise, session s: FillBlankSession) -> some View {
        Card {
            HStack {
                CardLabel(text: ex.source == .model ? "Предложение" : "Как по-итальянски?")
                Spacer()
                Text("\(s.index + 1) из \(s.total)").font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            if ex.source == .model {
                Text(ex.sentence).font(.title2)
            }
            Text(ex.hintRU).font(.title3.weight(ex.source == .model ? .regular : .semibold))
                .foregroundStyle(ex.source == .model ? Theme.secondaryText : .primary)

            TextField("Пропущенное слово", text: $answer)
                .textFieldStyle(.plain)
                .font(.title3)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .focused($focused)
                .disabled(s.phase != .answering)
                .onSubmit { primaryAction(s) }
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(Theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if case .checked(let result) = s.phase {
                HStack(spacing: 12) {
                    Image(systemName: result.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(result.isCorrect ? Theme.accent : Theme.feminine)
                    Text(result.feedbackRU)
                    Spacer(minLength: 0)
                    SpeakButton(text: spokenAnswer(ex), label: "Прослушать ответ", size: 40)
                }
            }

            Button {
                primaryAction(s)
            } label: {
                Text(s.phase == .answering ? "Проверить" : "Дальше")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }

    /// The whole sentence with the answer filled in, or the word alone.
    private func spokenAnswer(_ ex: FillBlankExercise) -> String {
        ex.source == .model
            ? ex.sentence.replacingOccurrences(of: FillBlankExercise.blank, with: ex.answer)
            : ex.answer
    }

    private func primaryAction(_ s: FillBlankSession) {
        if s.phase == .answering {
            s.submit(answer, in: context)
        } else {
            answer = ""
            Task {
                await s.next()
                focused = true
            }
        }
    }

    private func startIfNeeded() async {
        guard session == nil else { return }
        await restart()
    }

    private func restart() async {
        let map = Dictionary(progress.map { ($0.wordID, $0) }, uniquingKeysWith: { a, _ in a })
        let s = FillBlankSession(lessonTitle: lesson.title,
                                 words: FillBlankSession.pickWords(from: lesson, progress: map),
                                 status: .current())
        session = s
        answer = ""
        await s.start()
        focused = true
    }
}
