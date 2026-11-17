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
        Group {
            if let session {
                content(session)
            } else {
                ProgressView()
            }
        }
        .padding()
        .frame(maxWidth: 560)
        .navigationTitle("Вставь слово")
        .task { await startIfNeeded() }
    }

    @ViewBuilder
    private func content(_ s: FillBlankSession) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if case .unavailable(let reason) = s.status {
                Label(reason + " Задания без контекста.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else if let notice = s.modelNotice {
                Label(notice, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            switch s.phase {
            case .loading:
                HStack { ProgressView(); Text("Составляю задание…") }
            case .finished:
                finished(s)
            case .answering, .checked:
                if let ex = s.current { task(ex, session: s) }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func task(_ ex: FillBlankExercise, session s: FillBlankSession) -> some View {
        Text("Задание \(s.index + 1) из \(s.total)")
            .font(.caption)
            .foregroundStyle(.secondary)
        if ex.source == .model {
            Text(ex.sentence).font(.title2)
        } else {
            Text("Как по-итальянски?").font(.title3)
        }
        Text("Подсказка: \(ex.hintRU)")
            .foregroundStyle(.secondary)

        TextField("Пропущенное слово", text: $answer)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .focused($focused)
            .disabled(s.phase != .answering)
            .onSubmit { primaryAction(s) }

        if case .checked(let result) = s.phase {
            Label(result.feedbackRU, systemImage: result.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.isCorrect ? .green : .red)
        }

        Button(s.phase == .answering ? "Проверить" : "Дальше") { primaryAction(s) }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
    }

    @ViewBuilder
    private func finished(_ s: FillBlankSession) -> some View {
        ContentUnavailableView {
            Label("Готово: \(s.correctCount) из \(s.total)", systemImage: "flag.checkered")
        } actions: {
            Button("Ещё раз") { Task { await restart() } }
                .buttonStyle(.borderedProminent)
        }
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
