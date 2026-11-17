import SwiftData
import SwiftUI

@main
struct ItalinguaApp: App {
    private let container: ModelContainer?
    private let startupError: String?

    init() {
        do {
            let container = try AppContainer.make()
            try ContentImporter.importBundledContent(into: container.mainContext)
            self.container = container
            self.startupError = nil
        } catch {
            self.container = nil
            self.startupError = String(describing: error)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView()
                    .modelContainer(container)
            } else {
                ContentUnavailableView("Не удалось открыть данные",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(startupError ?? ""))
            }
        }
    }
}
