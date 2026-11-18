import Foundation
import SwiftData

enum AppContainer {
    static let contentModels: [any PersistentModel.Type] = [Lesson.self, GrammarTopic.self, VocabItem.self]
    static let progressModels: [any PersistentModel.Type] = [WordProgress.self, Mistake.self, RuleNote.self, ReviewLog.self, FavoriteWord.self]

    /// Two stores in one container:
    /// - "Content": local only, rebuilt from the bundled JSON;
    /// - "Progress": synced via CloudKit. `.automatic` uses the container
    ///   from the entitlements, and falls back to a local store when the
    ///   app is built without them (e.g. unsigned command-line builds).
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let content: ModelConfiguration
        let progress: ModelConfiguration
        if inMemory {
            content = ModelConfiguration("Content", schema: Schema(contentModels),
                                         isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            progress = ModelConfiguration("Progress", schema: Schema(progressModels),
                                          isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            // Own folder, so unsandboxed (unsigned) builds do not litter
            // ~/Library/Application Support with generic store names.
            let dir = URL.applicationSupportDirectory.appending(path: "Italingua", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            content = ModelConfiguration("Content", schema: Schema(contentModels),
                                         url: dir.appending(path: "Content.store"),
                                         cloudKitDatabase: .none)
            progress = ModelConfiguration("Progress", schema: Schema(progressModels),
                                          url: dir.appending(path: "Progress.store"),
                                          cloudKitDatabase: .automatic)
        }
        return try ModelContainer(for: Schema(contentModels + progressModels),
                                  configurations: [content, progress])
    }
}
