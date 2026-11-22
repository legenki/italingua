#if DEBUG
import CoreData
import Foundation
import SwiftData

/// Creates every progress record type in the CloudKit Development environment,
/// so the schema can be deployed to Production. Debug builds only, signed, run
/// with `-initCloudKitSchema`; the app quits when done. Uses a throwaway local
/// store: Core Data uploads one sample record per type and deletes it again.
enum CloudKitSchema {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-initCloudKitSchema") }

    static func initializeAndExit() -> Never {
        do {
            try initialize()
            print("CloudKitSchema: done")
            exit(0)
        } catch {
            print("CloudKitSchema: failed: \(error)")
            exit(1)
        }
    }

    private static func initialize() throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: AppContainer.progressModels) else {
            throw CocoaError(.coreData)
        }
        let url = URL.temporaryDirectory.appending(path: "SchemaInit-\(UUID().uuidString).store")
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        description.cloudKitContainerOptions =
            NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.y6a9lrqdh7.italingua")

        let container = NSPersistentCloudKitContainer(name: "Progress", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        try container.initializeCloudKitSchema()

        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }
}
#endif
