import SwiftData
import SwiftUI

/// Quizlet-style flashcards for a lesson: tap to flip, swipe right or press
/// "Знаю" if you knew the word, swipe left for "Ещё учу".
struct FlashcardsView: View {
    /// Words of the deck: a lesson's vocabulary, or due words from several lessons.
    let items: [VocabItem]
    var title = "Карточки"

    init(lesson: Lesson) {
        items = lesson.sortedVocab
    }

    init(items: [VocabItem], title: String) {
        self.items = items
        self.title = title
    }

    @Environment(\.modelContext) private var context
    @Query private var progress: [WordProgress]
    @State private var session: FlashcardSession?
    @AppStorage("flashcardFront") private var front = FlashcardSession.Side.italian
    /// Cards whose answer was already saved in this run; undo + re-answer saves once.
    @State private var recorded: Set<String> = []
    @State private var drag: CGSize = .zero
    /// True while a card flies off, so quick double input does not skip a card.
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.largeTitle.weight(.bold))
                if let session {
                    if session.isFinished {
                        summary(session)
                    } else {
                        run(session)
                    }
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
        .toolbar {
            // In the top bar, like the "All | Missed" switch in Phone › Recents;
            // on iOS 26 / macOS 26 the segmented control gets the glass capsule look.
            ToolbarItem(placement: .principal) {
                Picker("Сначала", selection: $front) {
                    ForEach(FlashcardSession.Side.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()
                .help("Какой стороной показывать карточку сначала")
            }
        }
        .onAppear(perform: startIfNeeded)
    }

    // MARK: - Run

    @ViewBuilder
    private func run(_ s: FlashcardSession) -> some View {
        VStack(spacing: 8) {
            HStack {
                Counter(count: s.learning.count, title: "Ещё учу", color: Theme.warningText, fill: Theme.warningFill)
                Spacer()
                Text("\(s.index + 1) / \(s.total)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Counter(count: s.known.count, title: "Знаю", color: Theme.accent, fill: Theme.accentSoft)
            }
            ProgressView(value: Double(s.index), total: Double(max(s.total, 1)))
                .tint(Theme.accent)
        }

        if let card = s.current {
            CardView(card: card, front: front, flipped: s.flipped, drag: drag)
                .id(card.id)
                .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity),
                                        removal: .opacity))
                .onTapGesture { flip(s) }
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { drag = $0.translation }
                        .onEnded { value in
                            if abs(value.translation.width) > 110 {
                                answer(s, knew: value.translation.width > 0)
                            } else {
                                withAnimation(.spring(duration: 0.3)) { drag = .zero }
                            }
                        }
                )
        }

        HStack(spacing: 12) {
            RoundAction(systemImage: "xmark", label: "Ещё учу", color: Theme.warningText, fill: Theme.warningFill) {
                answer(s, knew: false)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            Spacer()
            Button {
                withAnimation(.spring(duration: 0.3)) { s.undo() }
            } label: {
                Label("Назад", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .disabled(s.index == 0)
            .keyboardShortcut("z", modifiers: .command)
            Spacer()
            RoundAction(systemImage: "checkmark", label: "Знаю", color: Theme.onAccent, fill: Theme.accent) {
                answer(s, knew: true)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .padding(.horizontal, 8)

        // Space flips the card; the button is invisible but keeps the shortcut.
        Button("Перевернуть") { flip(s) }
            .keyboardShortcut(.space, modifiers: [])
            .opacity(0)
            .frame(height: 0)
            .accessibilityHidden(true)

        Text("Нажми на карточку, чтобы перевернуть. Смахни вправо — знаю, влево — ещё учу. На Mac: пробел, ← и →.")
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    private func flip(_ s: FlashcardSession) {
        withAnimation(.spring(duration: 0.45)) { s.flipped.toggle() }
    }

    private func answer(_ s: FlashcardSession, knew: Bool) {
        guard !busy, let card = s.current else { return }
        busy = true
        withAnimation(.easeOut(duration: 0.2)) {
            drag = CGSize(width: knew ? 600 : -600, height: drag.height)
        }
        if !recorded.contains(card.id) {
            recorded.insert(card.id)
            do {
                try context.recordAnswer(wordID: card.wordID, lessonID: card.lessonID,
                                          correct: knew, exercise: .flashcards)
                try context.save()
            } catch {
                assertionFailure("Saving progress failed: \(error)")
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            drag = .zero
            withAnimation(.spring(duration: 0.35)) { _ = s.answer(knew: knew) }
            busy = false
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private func summary(_ s: FlashcardSession) -> some View {
        let total = s.known.count + s.learning.count
        Card {
            CardLabel(text: "Готово")
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Theme.warningFill, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: total == 0 ? 0 : Double(s.known.count) / Double(total))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(total == 0 ? "—" : "\(s.known.count * 100 / total)%")
                        .font(.title2.weight(.bold).monospacedDigit())
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Знаю: \(s.known.count)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                    Label("Ещё учу: \(s.learning.count)", systemImage: "arrow.trianglehead.2.clockwise")
                        .foregroundStyle(Theme.warningText)
                }
                .font(.headline)
            }
            if !s.learning.isEmpty {
                WideButton(title: "Повторить «ещё учу» (\(s.learning.count))", filled: true) {
                    recorded = []
                    withAnimation { s.restartWithLearning() }
                }
            }
            WideButton(title: "Начать заново", filled: s.learning.isEmpty) {
                recorded = []
                withAnimation { s.restartAll() }
            }
        }
        if !s.learning.isEmpty {
            Card(padding: 0) {
                CardLabel(text: "Ещё учу").padding([.top, .horizontal], 16)
                VStack(spacing: 0) {
                    ForEach(Array(s.learning.enumerated()), id: \.element.id) { i, card in
                        if i > 0 { Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, 72) }
                        HStack(spacing: 12) {
                            SpeakButton(text: card.spoken)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.italian).font(.body.weight(.semibold))
                                Text(card.russian).font(.subheadline).foregroundStyle(Theme.secondaryText)
                            }
                            Spacer(minLength: 0)
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

    // MARK: - Setup

    private func startIfNeeded() {
        guard session == nil else { return }
        let boxes = Dictionary(progress.map { ($0.wordID, $0.box) }, uniquingKeysWith: max)
        let due = Set(progress.filter { $0.box > 0 && $0.dueDate <= .now }.map(\.wordID))
        let cards = items.filter { $0.pos != .proper }.map { item in
            Flashcard(wordID: item.wordID, lessonID: item.lesson?.id ?? "", italian: item.displayWithArticle, spoken: item.withArticle,
                      russian: item.russian, gender: item.gender,
                      note: item.formOf.map { "форма от \($0)" })
        }
        session = FlashcardSession(cards: FlashcardSession.order(cards, boxes: boxes, due: due))
    }
}

// MARK: - Pieces

private struct CardView: View {
    let card: Flashcard
    let front: FlashcardSession.Side
    let flipped: Bool
    let drag: CGSize

    var body: some View {
        let showsItalian = (front == .italian) != flipped
        ZStack {
            face(italian: front == .italian)
                .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (0, 1, 0), perspective: 0.4)
                .opacity(flipped ? 0 : 1)
            face(italian: front != .italian)
                .rotation3DEffect(.degrees(flipped ? 0 : -180), axis: (0, 1, 0), perspective: 0.4)
                .opacity(flipped ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 340)
        .overlay(alignment: .top) { swipeHint }
        .offset(x: drag.width, y: drag.height * 0.2)
        .rotationEffect(.degrees(Double(drag.width) / 25))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(showsItalian ? card.italian : card.russian)
        .accessibilityHint("Нажми, чтобы перевернуть")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var swipeHint: some View {
        let progress = min(abs(drag.width) / 110, 1)
        if drag.width != 0 {
            Text(drag.width > 0 ? "ЗНАЮ" : "ЕЩЁ УЧУ")
                .font(.headline.weight(.heavy))
                .foregroundStyle(drag.width > 0 ? Theme.accent : Theme.warningText)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(.background, in: Capsule())
                .overlay(Capsule().stroke(drag.width > 0 ? Theme.accent : Theme.warningText, lineWidth: 2))
                .opacity(progress)
                .padding(.top, 18)
                .offset(x: drag.width)
        }
    }

    private func face(italian: Bool) -> some View {
        VStack(spacing: 14) {
            HStack {
                CardLabel(text: italian ? "Итальянский" : "Русский")
                Spacer()
                if italian, let g = card.gender {
                    Text(g)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(g == "f" ? Theme.feminine : Theme.masculine)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(g == "f" ? Theme.feminineFill : Theme.masculineFill,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            Spacer(minLength: 0)
            Text(italian ? card.italian : card.russian)
                .font(.system(size: 36, weight: .bold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .lineLimit(3)
            if italian, let note = card.note {
                Text(note).font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
            if italian {
                SpeakButton(text: card.spoken, label: "Прослушать слово", size: 48, style: .filled)
            } else {
                Color.clear.frame(height: 48)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
    }
}

private struct Counter: View {
    let count: Int
    let title: String
    let color: Color
    let fill: Color

    var body: some View {
        HStack(spacing: 6) {
            Text("\(count)").font(.headline.monospacedDigit())
            Text(title).font(.subheadline)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(fill, in: Capsule())
    }
}

private struct RoundAction: View {
    let systemImage: String
    let label: String
    let color: Color
    let fill: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 64, height: 64)
                    .background(fill, in: Circle())
                Text(label).font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct WideButton: View {
    let title: String
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(filled ? Theme.onAccent : Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(filled ? Theme.accent : Theme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
