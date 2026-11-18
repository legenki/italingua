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
    private var currentText: String { note?.text ?? topic.ruleRU }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(topic.topic)
                    .font(.s(.largeTitle).weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                if editing {
                    Card {
                        CardLabel(text: "Правило")
                        TextEditor(text: $draft)
                            .font(.s(.body).monospaced())
                            .frame(minHeight: 320)
                            .scrollContentBackground(.hidden)
                        Text("Разметка: «• пункт», «! осторожно», «ex: Italiano | Перевод», «conj: verbo | перевод» и шесть строк вида «io parl|o», **жирный**.")
                            .font(.s(.caption))
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else if currentText.isEmpty {
                    Card {
                        Text("Правило ещё не написано. Нажмите «Изменить», чтобы записать его своими словами.")
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else {
                    RuleBlocksView(text: currentText)
                }

                if !editing, note != nil {
                    Label("Изменено в приложении. Попадёт в файлы курса после экспорта правил.",
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
