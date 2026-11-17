import SwiftData
import SwiftUI

struct RootView: View {
    @Query(sort: [SortDescriptor(\Lesson.level), SortDescriptor(\Lesson.order)])
    private var lessons: [Lesson]
    @Query private var progress: [WordProgress]
    @State private var selection: Lesson.ID?
    @State private var showStats = false
    @Query private var ruleNotes: [RuleNote]
    @State private var exportDoc: RuleExportDocument?
    @State private var exporting = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(levels, id: \.self) { level in
                    Section(level) {
                        ForEach(lessons.filter { $0.level == level }) { lesson in
                            LessonRow(lesson: lesson, learned: learnedCount(in: lesson))
                                .tag(lesson.id)
                        }
                    }
                }
            }
            .navigationTitle("Italingua")
            .toolbar {
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

    private var learnedIDs: Set<String> {
        Set(progress.filter(\.isLearned).map(\.wordID))
    }

    private func learnedCount(in lesson: Lesson) -> Int {
        let ids = learnedIDs
        return lesson.vocab.filter { ids.contains($0.wordID) }.count
    }
}

private struct LessonRow: View {
    let lesson: Lesson
    let learned: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(lesson.title.isEmpty ? lesson.id : lesson.title)
                .font(.headline)
            HStack {
                Text(lesson.sourceLabel)
                Spacer()
                Text("\(learned)/\(lesson.vocab.count) слов")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
