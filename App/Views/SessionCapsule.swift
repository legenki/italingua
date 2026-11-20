import SwiftData
import SwiftUI

/// Screens a session step opens from the plan.
enum SessionRoute: Hashable {
    case vocabulary(String)
    case flashcards(String)
    case reading(String)
}

/// The study session in the top bar (design A "Маршрут"): a start button,
/// then a timer ring with the four steps as chips, then the medal.
struct SessionCapsule: View {
    /// Lesson a new session starts with (the selected one, else the next to learn).
    let startLesson: Lesson?
    let lessons: [Lesson]
    /// Opens the screen of a step.
    let open: (StudySession.Step) -> Void

    @State private var session = StudySession.shared
    @State private var showPlan = false
    @Environment(\.modelContext) private var context

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if session.isActive && !session.isFinished {
                // Two buttons in one capsule: the plan, and pause / resume.
                ViewThatFits(in: .horizontal) {
                    running(now: context.date, chips: true)
                    running(now: context.date, chips: false)
                }
            } else {
                Button { tap() } label: { capsule(now: context.date) }
                    .buttonStyle(.plain)
            }
        }
        // A finished session goes into the medal history (once; also after a relaunch).
        .onChange(of: session.isFinished, initial: true) { _, finished in
            if finished, let s = session.state { try? context.recordSession(s) }
        }
        .popover(isPresented: $showPlan, arrowEdge: .bottom) {
            SessionPlan(lesson: sessionLesson, open: { step in showPlan = false; open(step) })
                .font(.s(.body))
                .tint(Theme.accent)
                #if os(iOS)
                // On iPhone a half-height sheet that can be pulled up, not an empty full screen.
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }

    private var sessionLesson: Lesson? {
        session.state.flatMap { s in lessons.first { $0.id == s.lessonID } }
    }

    private func tap() {
        if session.isActive {
            showPlan.toggle()
        } else if let startLesson {
            session.start(lesson: startLesson)
            showPlan = true
        }
    }

    @ViewBuilder
    private func capsule(now: Date) -> some View {
        if !session.isActive {
            HStack(spacing: 12) {
                // Shorter on a narrow (iPhone) top bar.
                ViewThatFits(in: .horizontal) {
                    Text(String(localized: "Сессия на 40 минут")).fixedSize()
                    Text(String(localized: "40 минут")).fixedSize()
                }
                .font(.s(.subheadline).weight(.semibold))
                HStack(spacing: 5) {
                    ForEach(0..<4, id: \.self) { _ in Circle().fill(Theme.separator).frame(width: 7, height: 7) }
                }
                Image(systemName: "play.fill")
                    .font(.s(.subheadline))
                    .frame(width: Self.knob, height: Self.knob)
                    .background(Theme.tile.opacity(0.6), in: Circle())
                    .overlay(Circle().strokeBorder(Theme.separator, lineWidth: 1))
                    .accessibilityLabel(String(localized: "Начать"))
            }
            .padding(.leading, 14)
            .padding(.trailing, Self.inset)
            .frame(height: Self.barHeight)
            .liquidCapsule()
            .opacity(startLesson == nil ? 0.5 : 1)
            .help(startLesson.map { String(localized: "Урок «\($0.title)»: правила, слова, карточки и чтение за 40 минут") } ?? "")
        } else {
            HStack(spacing: 8) {
                Image(systemName: session.earnedMedal ? "medal.fill" : "checkmark.circle.fill")
                    .font(.s(.headline))
                Text(session.earnedMedal ? String(localized: "Медаль дня") : String(localized: "Сессия пройдена")).font(.s(.subheadline).weight(.bold))
                Text(String(localized: "4 шага за \(Int(session.elapsed(now: now) / 60)) мин")).font(.s(.subheadline))
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 14)
            .frame(height: Self.barHeight)
            .liquidCapsule(tint: Theme.accent)
        }
    }

    private func running(now: Date, chips: Bool) -> some View {
        let remaining = session.remaining(now: now)
        let main = HStack(spacing: 8) {
            // The ring fills the capsule's height minus the inset, like the pause button.
            ZStack {
                Circle().inset(by: 2).stroke(Theme.separator, lineWidth: 4)
                Circle().inset(by: 2)
                    .trim(from: 0, to: remaining / StudySession.duration)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: Self.knob, height: Self.knob)
            Text(Self.clock(remaining))
                .font(.s(.subheadline).weight(.bold).monospacedDigit())
                .foregroundStyle(session.isRunning ? .primary : Theme.secondaryText)
            Rectangle().fill(Theme.separator).frame(width: 1, height: 18)
            if chips {
                // Chips share one glass container, so their glass blends like native controls.
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(StudySession.Step.allCases) { StepChip(step: $0, session: session) }
                    }
                }
            } else {
                HStack(spacing: 5) {
                    ForEach(StudySession.Step.allCases) { step in
                        Circle()
                            .fill(session.isDone(step) ? Theme.accent : Theme.separator)
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
        return HStack(spacing: 6) {
            Button { showPlan.toggle() } label: { main.contentShape(Capsule()) }
                .buttonStyle(.plain)
                .help(String(localized: "План сессии"))
            Button {
                session.isRunning ? session.pause() : session.resume()
            } label: {
                Image(systemName: session.isRunning ? "pause.fill" : "play.fill")
                    .font(.s(.subheadline))
                    .frame(width: Self.knob, height: Self.knob)
                    .background(Theme.tile.opacity(0.6), in: Circle())
                    .overlay(Circle().strokeBorder(Theme.separator, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(session.isRunning ? String(localized: "Пауза") : String(localized: "Продолжить"))
            .accessibilityLabel(session.isRunning ? String(localized: "Пауза") : String(localized: "Продолжить"))
        }
        .padding(.horizontal, Self.inset)
        .frame(height: Self.barHeight)
        .liquidCapsule()
    }

    /// As tall as the round toolbar buttons next to it (back, text size).
    #if os(iOS)
    static let barHeight: CGFloat = 44
    #else
    static let barHeight: CGFloat = 36
    #endif
    /// Same gap above, below and beside the ring and the pause button.
    static let inset: CGFloat = 5
    static var knob: CGFloat { barHeight - 2 * inset }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

private struct StepChip: View {
    let step: StudySession.Step
    let session: StudySession

    var body: some View {
        let done = session.isDone(step)
        let current = session.currentStep == step
        let p = session.progress(step)
        HStack(spacing: 4) {
            if done { Image(systemName: "checkmark").font(.s(.caption2).weight(.bold)) }
            Text(step.title + (current && p.target > 1 ? " \(p.done)/\(p.target)" : ""))
        }
        .font(.s(.caption).weight(.semibold))
        .foregroundStyle(done ? Theme.onAccent : current ? Theme.accent : Theme.secondaryText)
        .padding(.horizontal, 10)
        .frame(height: 24)
        // Done: accent glass. Current: glass with a light accent tint.
        .glassEffect(done ? .regular.tint(Theme.accent) : current ? .regular.tint(Theme.accent.opacity(0.12)) : .regular,
                     in: Capsule())
    }
}

/// The plan under the capsule: each step with its progress and a way to it.
private struct SessionPlan: View {
    let lesson: Lesson?
    let open: (StudySession.Step) -> Void
    @State private var session = StudySession.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(localized: "Сессия · \(lesson?.sourceLabel ?? "")")).font(.s(.headline))
                    Spacer()
                    Text(headerTime(context.date)).font(.s(.subheadline)).foregroundStyle(Theme.secondaryText)
                }
                if let lesson {
                    Text(lesson.title).font(.s(.subheadline)).foregroundStyle(Theme.secondaryText)
                }
                VStack(spacing: 0) {
                    ForEach(StudySession.Step.allCases) { step in
                        if step != .rules { Divider().padding(.leading, 44) }
                        row(step)
                    }
                }
                if session.isFinished {
                    hint(session.earnedMedal
                         ? String(localized: "Медаль дня получена! Все 4 шага за \(Int(session.elapsed(now: context.date) / 60)) минут.")
                         : String(localized: "Все шаги пройдены. Медаль — если уложиться в 40 минут, попробуй завтра."))
                } else {
                    hint(String(localized: "Пройди все 4 шага за 40 минут — получишь медаль дня."))
                }
                HStack {
                    if !session.isFinished {
                        Button(session.isRunning ? String(localized: "Пауза") : String(localized: "Продолжить")) {
                            session.isRunning ? session.pause() : session.resume()
                        }
                    }
                    Spacer()
                    Button(session.isFinished ? String(localized: "Новая сессия") : String(localized: "Завершить"), role: session.isFinished ? nil : .destructive) {
                        session.reset()
                    }
                }
                .font(.s(.subheadline))
            }
            #if os(macOS)
            .padding(18)
            .frame(width: 440)
            #else
            // On iPhone the popover becomes a full-width sheet: keep the content off the edges.
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif
        }
    }

    private func headerTime(_ now: Date) -> String {
        if session.isFinished { return String(localized: "готово") }
        let left = session.remaining(now: now)
        return left > 0 ? String(localized: "осталось \(Int((left / 60).rounded(.up))) мин") : String(localized: "время вышло")
    }

    private func row(_ step: StudySession.Step) -> some View {
        let p = session.progress(step)
        let done = session.isDone(step)
        return HStack(spacing: 12) {
            ZStack {
                if done {
                    Circle().fill(Theme.accent)
                    Image(systemName: "checkmark").font(.s(.caption).weight(.bold)).foregroundStyle(Theme.onAccent)
                } else if p.done > 0 {
                    Circle().stroke(Theme.separator, lineWidth: 3.5)
                    Circle().trim(from: 0, to: Double(p.done) / Double(p.target))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                } else {
                    Circle().stroke(Theme.separator, lineWidth: 1.5)
                    Text("\(step.rawValue + 1)").font(.s(.caption).weight(.bold)).foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.task).font(.s(.subheadline).weight(.semibold))
                Text(detail(step, p)).font(.s(.caption)).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            if !done {
                Button(p.done > 0 ? String(localized: "Продолжить") : String(localized: "Открыть")) { open(step) }
                    .buttonStyle(.plain)
                    .font(.s(.subheadline).weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 8)
    }

    private func detail(_ step: StudySession.Step, _ p: (done: Int, target: Int)) -> String {
        switch step {
        case .rules: String(localized: "открыто тем: \(p.done) из \(p.target)")
        case .words: String(localized: "прослушано слов: \(p.done) из \(p.target)")
        case .cards: String(localized: "карточек: \(p.done) из \(p.target)")
        case .reading: p.done > 0 ? String(localized: "текст прочитан") : String(localized: "текст урока, затем «Я прочитал текст»")
        }
    }

    private func hint(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "medal").foregroundStyle(Theme.accent)
            Text(text).font(.s(.subheadline))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension View {
    /// Liquid Glass capsule with a soft neutral shadow. The shadow is a blurred
    /// shape behind the glass, so the text stays sharp.
    func liquidCapsule(tint: Color? = nil) -> some View {
        self
            .glassEffect(.regular.tint(tint).interactive(), in: Capsule())
    }
}
