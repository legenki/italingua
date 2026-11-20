import SwiftData
import SwiftUI

/// One grammar topic: the rule as cards, editable in place. Edits are stored
/// as a synced RuleNote until exported to the curation file.
struct GrammarTopicView: View {
    let lessonID: String
    let topic: GrammarTopic

    @Environment(\.modelContext) private var context
    @Query private var notes: [RuleNote]
    @State private var editing = false
    @State private var draft = ""

    init(lessonID: String, topic: GrammarTopic) {
        self.lessonID = lessonID
        self.topic = topic
        let key = RuleNote.key(lessonID: lessonID, topic: topic.topic)
        _notes = Query(filter: #Predicate<RuleNote> { $0.key == key },
                       sort: \RuleNote.updatedAt, order: .reverse)
    }

    private var note: RuleNote? { notes.first }
    /// Rules are edited in Russian (they go back into the course files), so
    /// edits show and can be made only in the Russian interface.
    private var editable: Bool { AppLanguage.current == "ru" }
    private var currentText: String { (editable ? note?.text : nil) ?? topic.rule }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(topic.title)
                    .font(.s(.largeTitle).weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                if editing {
                    Card {
                        CardLabel(text: String(localized: "Правило"))
                        TextEditor(text: $draft)
                            .font(.s(.body).monospaced())
                            .frame(minHeight: 320)
                            .scrollContentBackground(.hidden)
                        Text(String(localized: "Разметка: «• пункт», «! осторожно», «ex: Italiano | Перевод», «conj: verbo | перевод» и шесть строк вида «io parl|o», **жирный**."))
                            .font(.s(.caption))
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else if currentText.isEmpty {
                    Card {
                        Text(String(localized: "Правило ещё не написано. Нажмите «Изменить», чтобы записать его своими словами."))
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else {
                    RuleBlocksView(text: currentText)
                }

                if !editing, editable, note != nil {
                    Label(String(localized: "Изменено в приложении."),
                          systemImage: "pencil.circle")
                        .font(.s(.footnote))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(16)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("")
        // Counts for the "rules" step of a running study session.
        .onAppear { StudySession.shared.noteTopic(lessonID: lessonID, topic: topic.topic) }
        .toolbar {
            if editing {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Отмена")) { editing = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Сохранить")) { save() }
                }
            } else if editable {
                ToolbarItem(placement: .primaryAction) {
                    Button(String(localized: "Изменить")) {
                        draft = currentText
                        editing = true
                    }
                }
            }
        }
    }

    private func save() {
        let text = ContentImporter.normalizedRule(draft)
        let bundled = ContentImporter.normalizedRule(topic.ruleRU)
        do {
            let existing = try context.ruleNote(lessonID: lessonID, topic: topic.topic)
            if text == bundled {
                if let existing { context.delete(existing) }
            } else if let existing {
                existing.text = text
                existing.updatedAt = .now
            } else {
                context.insert(RuleNote(key: RuleNote.key(lessonID: lessonID, topic: topic.topic), text: text))
            }
            try context.save()
            editing = false
        } catch {
            assertionFailure("Saving rule failed: \(error)")
        }
    }
}
