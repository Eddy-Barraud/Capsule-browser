//
//  CloudSyncManager+SchemaInit.swift
//  isowebapps
//
//  Description:
//  Debug-only CloudKit Development schema initialization helper for `CloudSyncManager`.
//

import Foundation
import CoreData

#if DEBUG
extension CloudSyncManager {
    public func initializeCloudKitDevelopmentSchema() async {
        schemaInitStatusMessage = "Initializing CloudKit Development schema..."
        let containerID = Self.cloudKitContainerIdentifier
        let resultMessage: String = await Task.detached(priority: .utility) {
            Self.runCloudKitSchemaInitialization(containerIdentifier: containerID)
        }.value
        schemaInitStatusMessage = resultMessage
    }
    
    nonisolated private static func runCloudKitSchemaInitialization(containerIdentifier: String) -> String {
        let model = buildCoreDataMirrorModel()
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "CloudKitSchemaInit-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let storeURL = tempDir.appending(path: "SchemaInit.sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        
        let container = NSPersistentCloudKitContainer(name: "CapsuleSchemaInit", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        defer {
            for store in container.persistentStoreCoordinator.persistentStores {
                try? container.persistentStoreCoordinator.remove(store)
            }
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()
        
        if let loadError {
            return "Schema init store load failed: \(loadError.localizedDescription)"
        }
        
        do {
            try container.initializeCloudKitSchema(options: [])
            return "Success: Development schema pushed to \(containerIdentifier). Open CloudKit Console -> Deploy Schema Changes to Production."
        } catch {
            return "Schema init failed: \(error.localizedDescription)"
        }
    }
    
    nonisolated private static func buildCoreDataMirrorModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        
        let groupEntity = NSEntityDescription()
        groupEntity.name = "WebAppGroup"
        groupEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        
        let itemEntity = NSEntityDescription()
        itemEntity.name = "WebAppItem"
        itemEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        
        func attr(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = true
            return a
        }
        
        let groupRel = NSRelationshipDescription()
        groupRel.name = "group"
        groupRel.destinationEntity = groupEntity
        groupRel.minCount = 0
        groupRel.maxCount = 1
        groupRel.deleteRule = .nullifyDeleteRule
        groupRel.isOptional = true
        
        let itemsRel = NSRelationshipDescription()
        itemsRel.name = "items"
        itemsRel.destinationEntity = itemEntity
        itemsRel.minCount = 0
        itemsRel.maxCount = 0
        itemsRel.deleteRule = .nullifyDeleteRule
        itemsRel.isOptional = true
        
        groupRel.inverseRelationship = itemsRel
        itemsRel.inverseRelationship = groupRel
        
        groupEntity.properties = [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("createdAt", .dateAttributeType),
            attr("displayOrder", .integer64AttributeType),
            itemsRel,
        ]
        
        itemEntity.properties = [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("urlString", .stringAttributeType),
            attr("lastOpenedURLString", .stringAttributeType),
            attr("iconData", .binaryDataAttributeType),
            attr("createdAt", .dateAttributeType),
            attr("lastVisited", .dateAttributeType),
            attr("isUBlockEnabled", .booleanAttributeType),
            attr("openLinksInSafariReaderMode", .booleanAttributeType),
            attr("deleteCookiesOnClose", .booleanAttributeType),
            attr("displayOrder", .integer64AttributeType),
            attr("isolatedCookiesData", .binaryDataAttributeType),
            groupRel,
        ]
        
        model.entities = [groupEntity, itemEntity]
        return model
    }
}
#endif
