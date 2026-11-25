//
//  CloudSyncManager+Deduplication.swift
//  isowebapps
//
//  Description:
//  Remote store change handling, duplicate capsule/group collapsing,
//  and structural store signature computation for `CloudSyncManager`.
//

import Foundation
import SwiftData
import CoreData
import Combine

extension CloudSyncManager {
    // MARK: - Late CloudKit Import Clash Detection & Remote Refresh
    
    func setupRemoteChangeObserver() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRemoteChangeHandling()
            }
        }
    }
    
    func scheduleRemoteChangeHandling() {
        guard isICloudSyncEnabled else { return }
        remoteChangeDebounceTask?.cancel()
        remoteChangeDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.handleRemoteStoreChange()
        }
    }
    
    func handleRemoteStoreChange() {
        guard isICloudSyncEnabled else { return }
        let cloudContext = getCloudContainer().mainContext
        let didDeduplicate = deduplicateStore(in: cloudContext)
        guard let allCapsules = try? cloudContext.fetch(FetchDescriptor<WebAppItem>()) else { return }
        
        var newlyDetectedConflicts: [CapsuleSyncConflict] = []
        var didAutoMerge = false
        var mergedDuplicateIDs = Set<UUID>()
        
        for (uploadedID, snapshot) in uploadedSessionCapsules {
            let key = Self.normalizedName(snapshot.name)
            guard !key.isEmpty else { continue }
            
            if let remoteMatch = allCapsules.first(where: {
                $0.id != uploadedID && Self.normalizedName($0.name) == key
            }) {
                if Self.shouldQueueConflict(
                    localName: snapshot.name,
                    localURL: snapshot.urlString,
                    cloudName: remoteMatch.name,
                    cloudURL: remoteMatch.urlString
                ) {
                    let alreadyQueued = pendingConflicts.contains(where: {
                        Self.normalizedName($0.localCapsule.name) == key
                    })
                    if !alreadyQueued {
                        newlyDetectedConflicts.append(
                            CapsuleSyncConflict(
                                localCapsule: snapshot,
                                cloudCapsuleID: remoteMatch.id,
                                cloudCapsuleName: remoteMatch.name,
                                cloudCapsuleURL: remoteMatch.urlString,
                                insertedLocalCapsuleID: uploadedID
                            )
                        )
                    }
                } else {
                    uploadedSessionCapsules.removeValue(forKey: uploadedID)
                }
            }
        }
        
        var seenByName: [String: WebAppItem] = [:]
        for item in allCapsules.sorted(by: { $0.createdAt < $1.createdAt }) {
            let key = Self.normalizedName(item.name)
            guard !key.isEmpty else { continue }
            if let earlierItem = seenByName[key], earlierItem.id != item.id {
                if Self.shouldQueueConflict(
                    localName: item.name,
                    localURL: item.urlString,
                    cloudName: earlierItem.name,
                    cloudURL: earlierItem.urlString
                ) {
                    let alreadyQueued = pendingConflicts.contains(where: {
                        Self.normalizedName($0.localCapsule.name) == key
                    }) || newlyDetectedConflicts.contains(where: {
                        Self.normalizedName($0.localCapsule.name) == key
                    })
                    if !alreadyQueued {
                        newlyDetectedConflicts.append(
                            CapsuleSyncConflict(
                                localCapsule: CapsuleSnapshot(from: item),
                                cloudCapsuleID: earlierItem.id,
                                cloudCapsuleName: earlierItem.name,
                                cloudCapsuleURL: earlierItem.urlString,
                                insertedLocalCapsuleID: item.id
                            )
                        )
                    }
                } else {
                    mergeItemMetadata(from: item, into: earlierItem)
                    mergedDuplicateIDs.insert(item.id)
                    uploadedSessionCapsules.removeValue(forKey: item.id)
                    cloudContext.delete(item)
                    didAutoMerge = true
                }
            } else {
                seenByName[key] = item
            }
        }
        
        if didAutoMerge {
            try? cloudContext.save()
        }
        
        if !newlyDetectedConflicts.isEmpty {
            enqueueConflicts(newlyDetectedConflicts)
        }
        
        let currentSignature = Self.computeStoreSignature(in: cloudContext)
        let storeChanged = (lastKnownStoreSignature != currentSignature)
        
        if storeChanged || didDeduplicate || didAutoMerge || !newlyDetectedConflicts.isEmpty || !mergedDuplicateIDs.isEmpty {
            lastKnownStoreSignature = currentSignature
            objectWillChange.send()
        }
    }
    
    // MARK: - Deduplication & Signatures
    
    @discardableResult
    public func deduplicateStore(in context: ModelContext) -> Bool {
        let allGroups = (try? context.fetch(FetchDescriptor<WebAppGroup>())) ?? []
        let allItems = (try? context.fetch(FetchDescriptor<WebAppItem>())) ?? []
        
        var didChange = false
        var removedGroupCount = 0
        var removedItemCount = 0
        
        let sortedGroups = allGroups.sorted {
            let count0 = ($0.items ?? []).count
            let count1 = ($1.items ?? []).count
            if count0 != count1 { return count0 > count1 }
            return $0.createdAt < $1.createdAt
        }
        
        var canonicalGroupByID: [UUID: WebAppGroup] = [:]
        var canonicalGroupByName: [String: WebAppGroup] = [:]
        var duplicateGroups: [(duplicate: WebAppGroup, canonical: WebAppGroup)] = []
        
        for group in sortedGroups {
            let normName = Self.normalizedName(group.name)
            if let existingByID = canonicalGroupByID[group.id] {
                duplicateGroups.append((group, existingByID))
            } else if !normName.isEmpty, let existingByName = canonicalGroupByName[normName] {
                duplicateGroups.append((group, existingByName))
            } else {
                canonicalGroupByID[group.id] = group
                if !normName.isEmpty {
                    canonicalGroupByName[normName] = group
                }
            }
        }
        
        let deletedGroupIDs = Set(duplicateGroups.map { ObjectIdentifier($0.duplicate) })
        
        for (duplicate, canonical) in duplicateGroups {
            if let dupItems = duplicate.items {
                for item in dupItems {
                    item.group = canonical
                }
            }
            for item in allItems where item.group != nil && ObjectIdentifier(item.group!) == ObjectIdentifier(duplicate) {
                item.group = canonical
            }
            context.delete(duplicate)
            removedGroupCount += 1
            didChange = true
        }
        
        for item in allItems {
            if let g = item.group, deletedGroupIDs.contains(ObjectIdentifier(g)) {
                if let canonical = canonicalGroupByID[g.id] ?? canonicalGroupByName[Self.normalizedName(g.name)] {
                    item.group = canonical
                    didChange = true
                }
            }
        }
        
        var itemsByID: [UUID: [WebAppItem]] = [:]
        for item in allItems {
            itemsByID[item.id, default: []].append(item)
        }
        
        for (_, groupOfSameID) in itemsByID where groupOfSameID.count > 1 {
            let sorted = groupOfSameID.sorted { a, b in
                let aHasGroup = (a.group != nil && !deletedGroupIDs.contains(ObjectIdentifier(a.group!)))
                let bHasGroup = (b.group != nil && !deletedGroupIDs.contains(ObjectIdentifier(b.group!)))
                if aHasGroup != bHasGroup { return aHasGroup }
                let aHasIcon = (a.iconData != nil)
                let bHasIcon = (b.iconData != nil)
                if aHasIcon != bHasIcon { return aHasIcon }
                return (a.lastVisited ?? a.createdAt) > (b.lastVisited ?? b.createdAt)
            }
            
            guard let primary = sorted.first else { continue }
            for duplicate in sorted.dropFirst() {
                if primary.group == nil, let dupGroup = duplicate.group, !deletedGroupIDs.contains(ObjectIdentifier(dupGroup)) {
                    primary.group = canonicalGroupByID[dupGroup.id] ?? canonicalGroupByName[Self.normalizedName(dupGroup.name)] ?? dupGroup
                }
                if primary.iconData == nil, let dupIcon = duplicate.iconData {
                    primary.iconData = dupIcon
                }
                if primary.isolatedCookiesData == nil, let dupCookies = duplicate.isolatedCookiesData {
                    primary.isolatedCookiesData = dupCookies
                }
                if primary.lastOpenedURLString == nil, let dupLastURL = duplicate.lastOpenedURLString {
                    primary.lastOpenedURLString = dupLastURL
                }
                if primary.lastVisited == nil, let dupVisited = duplicate.lastVisited {
                    primary.lastVisited = dupVisited
                }
                context.delete(duplicate)
                removedItemCount += 1
                didChange = true
            }
        }
        
        if didChange {
            try? context.save()
            #if DEBUG
            print("[CloudSyncManager] Deduplicated store: removed \(removedGroupCount) duplicate group(s) and \(removedItemCount) duplicate capsule(s).")
            #endif
        }
        return didChange
    }
    
    public static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    /// Normalizes a URL string for equality comparison across synced devices.
    public static func normalizedURL(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if var components = URLComponents(string: trimmed) {
            components.scheme = components.scheme?.lowercased()
            components.host = components.host?.lowercased()
            if components.path == "/" {
                components.path = ""
            } else if components.path.hasSuffix("/") {
                components.path = String(components.path.dropLast())
            }
            if let normalized = components.string {
                return normalized
            }
        }
        return trimmed.lowercased().hasSuffix("/") ? String(trimmed.lowercased().dropLast()) : trimmed.lowercased()
    }
    
    /// Returns `true` only when two capsules share a non-empty normalized name but point to different normalized URLs.
    public static func shouldQueueConflict(
        localName: String,
        localURL: String,
        cloudName: String,
        cloudURL: String
    ) -> Bool {
        let normLocalName = normalizedName(localName)
        let normCloudName = normalizedName(cloudName)
        guard !normLocalName.isEmpty, normLocalName == normCloudName else {
            return false
        }
        return normalizedURL(localURL) != normalizedURL(cloudURL)
    }
    
    /// Computes an in-memory structural signature of all groups and capsules in a store to detect remote CloudKit changes.
    public static func computeStoreSignature(in context: ModelContext) -> Int {
        let groups = (try? context.fetch(FetchDescriptor<WebAppGroup>())) ?? []
        let items = (try? context.fetch(FetchDescriptor<WebAppItem>())) ?? []
        
        var hasher = Hasher()
        hasher.combine(groups.count)
        for group in groups.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(group.id)
            hasher.combine(group.name)
            hasher.combine(group.displayOrder)
        }
        hasher.combine(items.count)
        for item in items.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(item.id)
            hasher.combine(item.name)
            hasher.combine(item.urlString)
            hasher.combine(item.displayOrder)
            hasher.combine(item.isUBlockEnabled)
            hasher.combine(item.openLinksInSafariReaderMode)
            hasher.combine(item.deleteCookiesOnClose)
            hasher.combine(item.iconData?.count)
            hasher.combine(item.group?.id)
        }
        return hasher.finalize()
    }
    
    private func mergeItemMetadata(from source: WebAppItem, into target: WebAppItem) {
        if target.group == nil, let sourceGroup = source.group {
            target.group = sourceGroup
        }
        if target.iconData == nil, let sourceIcon = source.iconData {
            target.iconData = sourceIcon
        }
        if target.isolatedCookiesData == nil, let sourceCookies = source.isolatedCookiesData {
            target.isolatedCookiesData = sourceCookies
        }
        if target.lastOpenedURLString == nil, let sourceLastURL = source.lastOpenedURLString {
            target.lastOpenedURLString = sourceLastURL
        }
        if let sourceVisited = source.lastVisited {
            if target.lastVisited == nil || sourceVisited > target.lastVisited! {
                target.lastVisited = sourceVisited
            }
        }
    }
}
