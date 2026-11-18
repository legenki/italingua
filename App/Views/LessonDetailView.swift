import SwiftData
import SwiftUI

struct LessonDetailView: View {
    let lesson: Lesson
    @Query private var notes: [RuleNote]
    @Query private var progress: [WordProgress]

    var body: some View {
        let edited = Dictionary(notes.map { ($0.key, $0.text) }, uniquingKeysWith: { a, _ in a })
        let learned = Set(progress.filter(\.isLearned).map(\.wordID))
        let learnedHere = lesson.vocab.filter { learned.contains($0.wordID) }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(lesson.sourceLabel) · \(lesson.level)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(lesson.title)
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Card(padding: 0) {
                    CardLabel(text: "Грамматика").padding([.top, .horizontal], 16)
                    VStack(spacing: 0) {
                        ForEach(Array(lesson.sortedGrammar.enumerated()), id: \.element.id) { index, topic in
                            if index > 0 {
                                Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, 16)
                            }
                            let rule = edited[RuleNote.key(lessonID: lesson.id, topic: topic.topic)] ?? topic.ruleRU
                            NavigationLink {
                                GrammarTopicView(lessonID: lesson.id, topic: topic)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(topic.topic).font(.body.weight(.semibold))
                                        Text(rule.isEmpty ? "Правило не написано" : RuleMarkup.preview(rule))
                                            .font(.subheadline)
                                            .foregroundStyle(Theme.secondaryText)
                                            .lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Theme.secondaryText)
                                }
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 4)
                }

                if !lesson.patterns.isEmpty {
                    Card {
                        CardLabel(text: "Речевые шаблоны")
                        ForEach(lesson.patterns, id: \.self) { pattern in
                            HStack(spacing: 12) {
                                SpeakButton(text: pattern.replacingOccurrences(of: "…", with: ""),
                                            label: "Прослушать шаблон", size: 36)
                                Text(pattern).font(.body.italic())
                            }
                        }
                    }
                }

                NavigationLink {
                    VocabularyView(lesson: lesson)
                } label: {
                    Card {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                CardLabel(text: "Лексика")
                                Text("\(learnedHere) из \(lesson.vocab.count) выучено")
                                    .font(.headline)
                                ProgressView(value: Double(learnedHere), total: Double(max(lesson.vocab.count, 1)))
                                    .tint(Theme.accent)
                            }
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 12) {
                    NavigationLink {
                        FlashcardsView(lesson: lesson)
                    } label: {
                        Label("Карточки", systemImage: "rectangle.on.rectangle.angled")
                            .font(.headline)
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        FillBlankView(lesson: lesson)
                    } label: {
                        Label("Вставь слово", systemImage: "character.cursor.ibeam")
                            .font(.headline)
                            .foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("")
    }
}
