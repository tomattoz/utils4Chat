//  Created by Ivan Kh on 28.08.2023.

import CoreData
import Utils9

public final class DataBase: Sendable {
    public static let shared = DataBase()

    private init() {
    }

    #if DEBUG
    func reset() {
        guard let url = container.persistentStoreDescriptions.first?.url else { return }
        let coordinator = container.persistentStoreCoordinator

        do {
            try coordinator.destroyPersistentStore(at:url, ofType: NSSQLiteStoreType, options: nil)
            try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: nil)
        }
        catch {
            print("Attempted to clear persistent store: " + error.localizedDescription)
        }

    }
    #endif

    private let container: NSPersistentContainer = {
        let modelURL = Bundle.module.url(forResource: "DataBase", withExtension: "momd")!
        let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL)!
        let container = NSPersistentContainer(name: "DataBase", managedObjectModel: managedObjectModel)

        container.loadPersistentStores { _, error in
            log(error)
        }

        return container
    }()

    public var context: NSManagedObjectContext {
        container.viewContext
    }
}

extension NSManagedObjectContext {
    func saveIfNeeded() {
        guard hasChanges else { return }

        tryLog {
            try save()
        }
    }
}

