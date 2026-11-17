import SwiftData
import SwiftUI

struct RootView: View {
    @Query(sort: [SortDescriptor(\Lesson.level), SortDescriptor(\Lesson.order)])
    private var lessons: [Lesson]
    @Query private var progress: [WordProgress]
    @State private var selection: Lesson.ID?
    @State private var showStats = false
    @State private var showSettings = false
    @Query private var ruleNotes: [RuleNote]
    @State private var exportDoc: RuleExportDocument?
    @State private var exporting = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(levels, id: \.self) { level in
                    ForEach(["intro", "main"], id: \.self) { part in
                      let items = lessons.filter { $0.level == level && $0.sourcePart == part }
                      if !items.isEmpty {
                      Section("\(level) · \(part == "intro" ? "Вводный курс" : "Основной курс")") {
                        ForEach(items) { lesson in
                            LessonRow(lesson: lesson, progress: progress(of: lesson, boxes: boxes))
                                .tag(lesson.id)
                        }
                      }
                      }
                    }
                }
            }
            .navigationTitle("Italingua")
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
            .toolbar {
                #if os(macOS)
                SettingsLink { Label("Настройки", systemImage: "gearshape") }
                #else
                Button("Настройки", systemImage: "gearshape") { showSettings = true }
                #endif
                Button("Статистика", systemImage: "chart.bar") { showStats = true }
                Button("Экспорт правил (\(ruleNotes.count))", systemImage: "square.and.arrow.up") {
                    exportDoc = try? RuleExportDocument(
                        notes: ruleNotes.map { ($0.lessonID, $0.topic, $0.text) })
                    exporting = exportDoc != nil
                }
                .disabled(ruleNotes.isEmpty)
                .help("Сохранить правила, написанные в приложении, для tools/import_rules.py")
            }
            .fileExporter(isPresented: $exporting, document: exportDoc,
                          contentType: .json, defaultFilename: "italingua-rules.json") { _ in }
            .sheet(isPresented: $showStats) {
                NavigationStack { StatsView() }
                    #if os(macOS)
                    .frame(minWidth: 460, idealWidth: 520, minHeight: 560, idealHeight: 640)
                    #endif
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }.appAppearance()
            }
        } detail: {
            NavigationStack {
                if let lesson = lessons.first(where: { $0.id == selection }) {
                    LessonDetailView(lesson: lesson)
                } else {
                    ContentUnavailableView("Выберите урок", systemImage: "book")
                }
            }
        }
    }

    private var levels: [String] {
        Array(Set(lessons.map(\.level))).sorted()
    }

    private var boxes: [String: Int] {
        Dictionary(progress.map { ($0.wordID, $0.box) }, uniquingKeysWith: max)
    }

    private func progress(of lesson: Lesson, boxes: [String: Int]) -> LessonProgress {
        LessonProgress(boxes: lesson.vocab.filter(FillBlankSession.isPracticable).map { boxes[$0.wordID] })
    }
}

/// A lesson in the sidebar, laid out like a chat row: status badge, title
/// and how many of its words are known.
private struct LessonRow: View {
    let lesson: Lesson
    let progress: LessonProgress

    var body: some View {
        HStack(spacing: 12) {
            LessonBadge(number: lesson.sourceLesson, progress: progress)
            VStack(alignment: .leading, spacing: 3) {
                Text(lesson.title.isEmpty ? lesson.id : lesson.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text(statusText)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(progress.state == .done ? Theme.accent : .secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        switch progress.state {
        case .notStarted: "Не начат · \(progress.total) слов"
        case .inProgress: "Знакомо \(progress.known) из \(progress.total) слов"
        case .done: "Пройден · \(progress.total) слов"
        }
    }
}

/// Round badge in place of a chat avatar: the lesson number in a grey circle
/// (not started), a progress ring around it (in progress), or a green check (done).
struct LessonBadge: View {
    let number: Int
    let progress: LessonProgress
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            switch progress.state {
            case .done:
                Circle().fill(Theme.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(.white)
            case .inProgress:
                Circle().fill(Theme.accentSoft)
                Circle().stroke(Theme.separator, lineWidth: 3).padding(1.5)
                Circle()
                    .trim(from: 0, to: max(progress.fraction, 0.04))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1.5)
                label.foregroundStyle(Theme.accent)
            case .notStarted:
                Circle().fill(Theme.tile)
                Circle().stroke(Theme.separator, lineWidth: 1)
                label.foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibility)
    }

    private var label: some View {
        Text("\(number)").font(.system(size: size * 0.4, weight: .bold, design: .rounded))
    }

    private var accessibility: String {
        switch progress.state {
        case .notStarted: "Не начат"
        case .inProgress: "В процессе, \(Int(progress.fraction * 100))%"
        case .done: "Пройден"
        }
    }
}
