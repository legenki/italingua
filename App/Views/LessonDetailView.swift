import SwiftData
import SwiftUI

struct LessonDetailView: View {
    let lesson: Lesson
    @Query private var notes: [RuleNote]

    var body: some View {
        let edited = Dictionary(notes.map { ($0.key, $0.text) }, uniquingKeysWith: { a, _ in a })
        List {
            Section("Грамматика") {
                ForEach(lesson.sortedGrammar) { topic in
                    let key = RuleNote.key(lessonID: lesson.id, topic: topic.topic)
                    let rule = edited[key] ?? topic.ruleRU
                    NavigationLink {
                        GrammarTopicView(lessonID: lesson.id, topic: topic)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(topic.topic)
                            Text(rule.isEmpty ? "Правило не написано" : rule)
                                .font(.callout)
                                .foregroundStyle(rule.isEmpty ? .tertiary : .secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            if !lesson.patterns.isEmpty {
                Section("Речевые шаблоны") {
                    ForEach(lesson.patterns, id: \.self) { Text($0).italic() }
                }
            }
            Section("Практика") {
                NavigationLink {
                    VocabularyView(lesson: lesson)
                } label: {
                    Label("Лексика (\(lesson.vocab.count))", systemImage: "character.book.closed")
                }
                NavigationLink {
                    FillBlankView(lesson: lesson)
                } label: {
                    Label("Вставь пропущенное слово", systemImage: "text.badge.plus")
                }
            }
        }
        .navigationTitle(lesson.title)
    }
}
