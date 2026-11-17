import Foundation
import SwiftData

enum AppContainer {
    static let contentModels: [any PersistentModel.Type] = [Lesson.self, GrammarTopic.self, VocabItem.self]
    static let progressModels: [any PersistentModel.Type] = [WordProgress.self, Mistake.self]

    /// Two stores in one container:
    /// - "Content": local only, rebuilt from the bundled JSON;
    /// - "Progress": synced via CloudKit. `.automatic` uses the container
    ///   from the entitlements, and falls back to a local store when the
    ///   app is built without them (e.g. unsigned command-line builds).
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let content = ModelConfiguration("Content",
                                         schema: Schema(contentModels),
                                         isStoredInMemoryOnly: inMemory,
                                         cloudKitDatabase: .none)
        let progress = ModelConfiguration("Progress",
                                          schema: Schema(progressModels),
                                          isStoredInMemoryOnly: inMemory,
                                          cloudKitDatabase: inMemory ? .none : .automatic)
        return try ModelContainer(for: Schema(contentModels + progressModels),
                                  configurations: [content, progress])
    }
}
