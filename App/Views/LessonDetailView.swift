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
                        .font(.s(.subheadline).weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(lesson.title)
                        .font(.s(.largeTitle).weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Card(padding: 0) {
                    CardLabel(text: String(localized: "Грамматика")).padding([.top, .horizontal], 16)
                    VStack(spacing: 0) {
                        ForEach(Array(lesson.sortedGrammar.enumerated()), id: \.element.id) { index, topic in
                            if index > 0 {
                                Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, 16)
                            }
                            let rule = (AppLanguage.current == "ru" ? edited[RuleNote.key(lessonID: lesson.id, topic: topic.topic)] : nil) ?? topic.rule
                            NavigationLink {
                                GrammarTopicView(lessonID: lesson.id, topic: topic)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(topic.title).font(.s(.body).weight(.semibold))
                                        Text(rule.isEmpty ? String(localized: "Правило не написано") : RuleMarkup.preview(rule))
                                            .font(.s(.subheadline))
                                            .foregroundStyle(Theme.secondaryText)
                                            .lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.s(.footnote).weight(.semibold))
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
                        CardLabel(text: String(localized: "Речевые шаблоны"))
                        ForEach(lesson.patterns, id: \.self) { pattern in
                            HStack(spacing: 12) {
                                SpeakButton(text: pattern.replacingOccurrences(of: "…", with: ""),
                                            label: String(localized: "Прослушать шаблон"), size: 36)
                                Text(pattern).font(.s(.body).italic())
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
                                CardLabel(text: String(localized: "Лексика"))
                                Text(String(localized: "\(learnedHere) из \(lesson.vocab.count) выучено"))
                                    .font(.s(.headline))
                                ProgressView(value: Double(learnedHere), total: Double(max(lesson.vocab.count, 1)))
                                    .tint(Theme.accent)
                            }
                            Image(systemName: "chevron.right")
                                .font(.s(.footnote).weight(.semibold))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                .buttonStyle(.plain)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    PracticeLink(title: String(localized: "Карточки"), systemImage: "rectangle.on.rectangle.angled", filled: false) {
                        FlashcardsView(lesson: lesson)
                    }
                    PracticeLink(title: String(localized: "Вставь слово"), systemImage: "character.cursor.ibeam", filled: true) {
                        FillBlankView(lesson: lesson)
                    }
                    PracticeLink(title: String(localized: "Переведи фразу"), systemImage: "text.bubble", filled: false) {
                        TranslationView(lesson: lesson)
                    }
                    PracticeLink(title: String(localized: "Чтение"), systemImage: "book.pages", filled: false) {
                        ReadingView(lesson: lesson)
                    }
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

/// One of the practice buttons under a lesson.
private struct PracticeLink<Destination: View>: View {
    let title: String
    let systemImage: String
    let filled: Bool
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            Label(title, systemImage: systemImage)
                .font(.s(.headline))
                .foregroundStyle(filled ? Theme.onAccent : Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(filled ? Theme.accent : Theme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
