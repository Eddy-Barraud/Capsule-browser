//
//  CloudSyncManager+Merge.swift
//  isowebapps
//
//  Description:
//  Local-to-Cloud merge, sequential conflict resolution, and snapshot helpers
//  for `CloudSyncManager`.
//

import Foundation
import SwiftData

extension CloudSyncManager {
    // MARK: - Merge & Sequential Conflict Resolution
    
    func performLocalToCloudMerge(localGroups: [GroupSnapshot], localCapsules: [CapsuleSnapshot]) {
        let cloudContext = getCloudContainer().mainContext
        let existingCloudGroups = (try? cloudContext.fetch(FetchDescriptor<WebAppGroup>())) ?? []
        let existingCloudCapsules = (try? cloudContext.fetch(FetchDescriptor<WebAppItem>())) ?? []
        
        var groupByNormalizedName: [String: WebAppGroup] = [:]
        for group in existingCloudGroups {
            let key = Self.normalizedName(group.name)
            if !key.isEmpty {
                groupByNormalizedName[key] = group
            }
        }
        
        for localGroup in localGroups {
            let key = Self.normalizedName(localGroup.name)
            if !key.isEmpty, groupByNormalizedName[key] == nil {
                let newGroup = WebAppGroup(
                    id: localGroup.id,
                    name: localGroup.name,
                    displayOrder: localGroup.displayOrder
                )
                newGroup.createdAt = localGroup.createdAt
                cloudContext.insert(newGroup)
                groupByNormalizedName[key] = newGroup
            }
        }
        
        var cloudCapsuleByNormalizedName: [String: WebAppItem] = [:]
        for cloudItem in existingCloudCapsules {
            let key = Self.normalizedName(cloudItem.name)
            if !key.isEmpty, cloudCapsuleByNormalizedName[key] == nil {
                cloudCapsuleByNormalizedName[key] = cloudItem
            }
        }
        
        var conflicts: [CapsuleSyncConflict] = []
        uploadedSessionCapsules.removeAll()
        
        for localCapsule in localCapsules {
            let key = Self.normalizedName(localCapsule.name)
            if let existingCloudItem = cloudCapsuleByNormalizedName[key], !key.isEmpty {
                if existingCloudItem.id == localCapsule.id {
                    mergeSnapshotMetadata(from: localCapsule, into: existingCloudItem, groupMap: groupByNormalizedName)
                } else if Self.shouldQueueConflict(
                    localName: localCapsule.name,
                    localURL: localCapsule.urlString,
                    cloudName: existingCloudItem.name,
                    cloudURL: existingCloudItem.urlString
                ) {
                    conflicts.append(
                        CapsuleSyncConflict(
                            localCapsule: localCapsule,
                            cloudCapsuleID: existingCloudItem.id,
                            cloudCapsuleName: existingCloudItem.name,
                            cloudCapsuleURL: existingCloudItem.urlString,
                            insertedLocalCapsuleID: nil
                        )
                    )
                } else {
                    mergeSnapshotMetadata(from: localCapsule, into: existingCloudItem, groupMap: groupByNormalizedName)
                }
            } else {
                let newItem = makeWebAppItem(from: localCapsule, groupMap: groupByNormalizedName)
                cloudContext.insert(newItem)
                uploadedSessionCapsules[newItem.id] = localCapsule
                if !key.isEmpty {
                    cloudCapsuleByNormalizedName[key] = newItem
                }
            }
        }
        
        try? cloudContext.save()
        lastKnownStoreSignature = Self.computeStoreSignature(in: cloudContext)
        
        if !conflicts.isEmpty {
            enqueueConflicts(conflicts)
        }
    }
    
    /// Resolves the currently active conflict at the head of `pendingConflicts` and advances to the next one.
    public func resolveCurrentConflict(overwriteCloud: Bool) {
        guard !pendingConflicts.isEmpty else { return }
        let conflict = pendingConflicts.removeFirst()
        resolvedConflictsInBatch += 1
        
        let cloudContext = getCloudContainer().mainContext
        let allCloudCapsules = (try? cloudContext.fetch(FetchDescriptor<WebAppItem>())) ?? []
        let allCloudGroups = (try? cloudContext.fetch(FetchDescriptor<WebAppGroup>())) ?? []
        
        var groupByNormalizedName: [String: WebAppGroup] = [:]
        for group in allCloudGroups {
            let key = Self.normalizedName(group.name)
            if !key.isEmpty {
                groupByNormalizedName[key] = group
            }
        }
        
        let targetCloudCapsule = allCloudCapsules.first(where: { $0.id == conflict.cloudCapsuleID })
            ?? allCloudCapsules.first(where: {
                Self.normalizedName($0.name) == Self.normalizedName(conflict.localCapsule.name)
                && $0.id != conflict.insertedLocalCapsuleID
            })
        
        let insertedLocalDuplicate = conflict.insertedLocalCapsuleID.flatMap { insertedID in
            allCloudCapsules.first(where: { $0.id == insertedID })
        }
        
        if overwriteCloud {
            if let cloudItem = targetCloudCapsule {
                applySnapshot(conflict.localCapsule, to: cloudItem, groupMap: groupByNormalizedName, in: cloudContext)
                if let duplicate = insertedLocalDuplicate, duplicate.id != cloudItem.id {
                    cloudContext.delete(duplicate)
                }
            } else if insertedLocalDuplicate == nil {
                let newItem = makeWebAppItem(from: conflict.localCapsule, groupMap: groupByNormalizedName)
                cloudContext.insert(newItem)
            }
        } else {
            if let duplicate = insertedLocalDuplicate {
                cloudContext.delete(duplicate)
            }
        }
        
        uploadedSessionCapsules.removeValue(forKey: conflict.localCapsule.id)
        if let insertedID = conflict.insertedLocalCapsuleID {
            uploadedSessionCapsules.removeValue(forKey: insertedID)
        }
        
        try? cloudContext.save()
        lastKnownStoreSignature = Self.computeStoreSignature(in: cloudContext)
        
        if pendingConflicts.isEmpty {
            totalConflictsInBatch = 0
            resolvedConflictsInBatch = 0
        }
    }
    
    func enqueueConflicts(_ conflicts: [CapsuleSyncConflict]) {
        if pendingConflicts.isEmpty {
            totalConflictsInBatch = conflicts.count
            resolvedConflictsInBatch = 0
        } else {
            totalConflictsInBatch += conflicts.count
        }
        pendingConflicts.append(contentsOf: conflicts)
    }
    
    func clearConflicts() {
        pendingConflicts.removeAll()
        totalConflictsInBatch = 0
        resolvedConflictsInBatch = 0
    }
    
    // MARK: - Snapshot Helpers
    
    func fetchGroupSnapshots(from context: ModelContext) -> [GroupSnapshot] {
        let descriptor = FetchDescriptor<WebAppGroup>(
            sortBy: [SortDescriptor(\.displayOrder, order: .forward), SortDescriptor(\.createdAt, order: .forward)]
        )
        let groups = (try? context.fetch(descriptor)) ?? []
        return groups.map { GroupSnapshot(from: $0) }
    }
    
    func fetchCapsuleSnapshots(from context: ModelContext) -> [CapsuleSnapshot] {
        let descriptor = FetchDescriptor<WebAppItem>(
            sortBy: [SortDescriptor(\.displayOrder, order: .forward), SortDescriptor(\.createdAt, order: .forward)]
        )
        let items = (try? context.fetch(descriptor)) ?? []
        return items.map { CapsuleSnapshot(from: $0) }
    }
    
    func clearAllData(in context: ModelContext) {
        if let items = try? context.fetch(FetchDescriptor<WebAppItem>()) {
            for item in items {
                context.delete(item)
            }
        }
        if let groups = try? context.fetch(FetchDescriptor<WebAppGroup>()) {
            for group in groups {
                context.delete(group)
            }
        }
    }
    
    func insertSnapshots(
        groups: [GroupSnapshot],
        capsules: [CapsuleSnapshot],
        into context: ModelContext
    ) {
        var groupByNormalizedName: [String: WebAppGroup] = [:]
        for groupSnap in groups {
            let group = WebAppGroup(
                id: groupSnap.id,
                name: groupSnap.name,
                displayOrder: groupSnap.displayOrder
            )
            group.createdAt = groupSnap.createdAt
            context.insert(group)
            let key = Self.normalizedName(groupSnap.name)
            if !key.isEmpty {
                groupByNormalizedName[key] = group
            }
        }
        
        for capsuleSnap in capsules {
            let item = makeWebAppItem(from: capsuleSnap, groupMap: groupByNormalizedName)
            context.insert(item)
        }
    }
    
    func makeWebAppItem(
        from snapshot: CapsuleSnapshot,
        groupMap: [String: WebAppGroup]
    ) -> WebAppItem {
        let item = WebAppItem(
            id: snapshot.id,
            name: snapshot.name,
            urlString: snapshot.urlString,
            lastOpenedURLString: snapshot.lastOpenedURLString,
            iconData: snapshot.iconData,
            createdAt: snapshot.createdAt,
            lastVisited: snapshot.lastVisited,
            isUBlockEnabled: snapshot.isUBlockEnabled,
            openLinksInSafariReaderMode: snapshot.openLinksInSafariReaderMode,
            deleteCookiesOnClose: snapshot.deleteCookiesOnClose,
            displayOrder: snapshot.displayOrder,
            isolatedCookiesData: snapshot.isolatedCookiesData
        )
        if let groupName = snapshot.groupName {
            let key = Self.normalizedName(groupName)
            item.group = groupMap[key]
        }
        return item
    }
    
    private func applySnapshot(
        _ snapshot: CapsuleSnapshot,
        to item: WebAppItem,
        groupMap: [String: WebAppGroup],
        in context: ModelContext
    ) {
        item.name = snapshot.name
        item.urlString = snapshot.urlString
        item.lastOpenedURLString = snapshot.lastOpenedURLString
        item.iconData = snapshot.iconData
        item.lastVisited = snapshot.lastVisited
        item.isUBlockEnabled = snapshot.isUBlockEnabled
        item.openLinksInSafariReaderMode = snapshot.openLinksInSafariReaderMode
        item.deleteCookiesOnClose = snapshot.deleteCookiesOnClose
        item.displayOrder = snapshot.displayOrder
        item.isolatedCookiesData = snapshot.isolatedCookiesData
        
        if let groupName = snapshot.groupName {
            let key = Self.normalizedName(groupName)
            if let existingGroup = groupMap[key] {
                item.group = existingGroup
            } else {
                let newGroup = WebAppGroup(name: groupName)
                context.insert(newGroup)
                item.group = newGroup
            }
        } else {
            item.group = nil
        }
    }
    
    private func mergeSnapshotMetadata(
        from snapshot: CapsuleSnapshot,
        into target: WebAppItem,
        groupMap: [String: WebAppGroup]
    ) {
        if target.group == nil, let groupName = snapshot.groupName {
            target.group = groupMap[Self.normalizedName(groupName)]
        }
        if target.iconData == nil, let sourceIcon = snapshot.iconData {
            target.iconData = sourceIcon
        }
        if target.isolatedCookiesData == nil, let sourceCookies = snapshot.isolatedCookiesData {
            target.isolatedCookiesData = sourceCookies
        }
        if target.lastOpenedURLString == nil, let sourceLastURL = snapshot.lastOpenedURLString {
            target.lastOpenedURLString = sourceLastURL
        }
        if let sourceVisited = snapshot.lastVisited {
            if target.lastVisited == nil || sourceVisited > target.lastVisited! {
                target.lastVisited = sourceVisited
            }
        }
    }
}
