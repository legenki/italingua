import SwiftData
import SwiftUI

/// One grammar topic: the rule in the owner's own words, editable in place.
/// Edits are stored as a synced RuleNote until exported to the curation file.
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
    private var currentText: String { note?.text ?? topic.ruleRU }

    var body: some View {
        Form {
            Section {
                if editing {
                    TextEditor(text: $draft)
                        .frame(minHeight: 220)
                        .font(.body)
                } else if currentText.isEmpty {
                    Text("Правило ещё не написано. Нажмите «Изменить», чтобы записать его своими словами.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(currentText)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Правило")
            } footer: {
                if note != nil {
                    Text("Изменено в приложении. Попадёт в файлы курса после экспорта правил.")
                } else if !topic.ruleRU.isEmpty {
                    Text("Из файлов курса.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(topic.topic)
        .toolbar {
            if editing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { editing = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button("Изменить") {
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
                // Same as the course file: nothing to keep in the app.
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
