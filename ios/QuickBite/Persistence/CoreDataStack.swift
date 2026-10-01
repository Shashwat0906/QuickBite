import CoreData

/// Core Data stack with the model defined in code (no .xcdatamodeld), which
/// keeps the schema reviewable in pull requests and easy to explain.
///
/// Entities
/// - `CartLine`: one line in the local cart (menu item snapshot + options + quantity)
/// - `CartMeta`: single row holding the cart's cafe snapshot and coupon code
final class CoreDataStack {
    let container: NSPersistentContainer
    var viewContext: NSManagedObjectContext { container.viewContext }

    /// - Parameter inMemory: true for unit tests (nothing touches disk).
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "QuickBite", managedObjectModel: Self.model)
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.persistentStoreDescriptions.first?.shouldMigrateStoreAutomatically = true
        container.persistentStoreDescriptions.first?.shouldInferMappingModelAutomatically = true
        container.loadPersistentStores { _, error in
            if let error {
                // A cart cache is not worth crashing for: log and continue in memory.
                assertionFailure("Core Data failed to load: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func save() {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            assertionFailure("Core Data save failed: \(error)")
        }
    }

    /// Built once and shared: loading two models with the same entity names
    /// in one process confuses Core Data (relevant for tests).
    static let model: NSManagedObjectModel = {
        func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = optional
            return a
        }

        let line = NSEntityDescription()
        line.name = "CartLine"
        line.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        line.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("menuItemJSON", .binaryDataAttributeType),
            attribute("optionIDs", .stringAttributeType),
            attribute("quantity", .integer64AttributeType),
            attribute("createdAt", .dateAttributeType),
        ]

        let meta = NSEntityDescription()
        meta.name = "CartMeta"
        meta.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        meta.properties = [
            attribute("cafeJSON", .binaryDataAttributeType, optional: true),
            attribute("couponCode", .stringAttributeType, optional: true),
        ]

        let model = NSManagedObjectModel()
        model.entities = [line, meta]
        return model
    }()
}
