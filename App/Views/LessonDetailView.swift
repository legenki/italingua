import SwiftData
import SwiftUI

struct LessonDetailView: View {
    let lesson: Lesson

    var body: some View {
        List {
            Section("Грамматика") {
                ForEach(lesson.sortedGrammar) { topic in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(topic.topic)
                        if !topic.ruleRU.isEmpty {
                            Text(topic.ruleRU)
                                .font(.callout)
                                .foregroundStyle(.secondary)
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
