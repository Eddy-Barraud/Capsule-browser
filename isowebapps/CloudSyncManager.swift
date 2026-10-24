//
//  CloudSyncManager.swift
//  isowebapps
//
//  Created on 17/10/2026.
//
//  Description:
//  Manages optional iCloud (CloudKit) synchronization for SwiftData models (`WebAppItem`
//  and `WebAppGroup`). Defaults to local-only storage (`cloudKitDatabase: .none`),
//  orchestrates data migration when toggling iCloud sync on or off, and resolves
//  same-name capsule sync clashes sequentially one capsule at a time.
//

import Foundation
import SwiftUI
import SwiftData
import CoreData
import Combine

/// Value snapshot of a `WebAppGroup` for safe cross-container transfer.
public struct GroupSnapshot: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    public let displayOrder: Int
    
    init(from group: WebAppGroup) {
        self.id = group.id
        self.name = group.name
        self.createdAt = group.createdAt
        self.displayOrder = group.displayOrder
    }
}

/// Value snapshot of a `WebAppItem` for safe cross-container transfer and conflict resolution.
public struct CapsuleSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let urlString: String
    public let lastOpenedURLString: String?
    public let iconData: Data?
    public let createdAt: Date
    public let lastVisited: Date?
    public let isUBlockEnabled: Bool
    public let openLinksInSafariReaderMode: Bool
    public let deleteCookiesOnClose: Bool
    public let displayOrder: Int
    public let isolatedCookiesData: Data?
    public let groupName: String?
    
    init(from item: WebAppItem) {
        self.id = item.id
        self.name = item.name
        self.urlString = item.urlString
        self.lastOpenedURLString = item.lastOpenedURLString
        self.iconData = item.iconData
        self.createdAt = item.createdAt
        self.lastVisited = item.lastVisited
        self.isUBlockEnabled = item.isUBlockEnabled
        self.openLinksInSafariReaderMode = item.openLinksInSafariReaderMode
        self.deleteCookiesOnClose = item.deleteCookiesOnClose
        self.displayOrder = item.displayOrder
        self.isolatedCookiesData = item.isolatedCookiesData
        self.groupName = item.group?.name
    }
}

/// Represents a single sync conflict where a local capsule and an iCloud capsule share the same name.
public struct CapsuleSyncConflict: Identifiable, Equatable {
    public let id = UUID()
    public let localCapsule: CapsuleSnapshot
    public let cloudCapsuleID: UUID
    public let cloudCapsuleName: String
    public let cloudCapsuleURL: String
    /// If the local capsule was already inserted before a late CloudKit import arrived, holds its inserted UUID.
    public let insertedLocalCapsuleID: UUID?
}

@MainActor
public final class CloudSyncManager: ObservableObject {
    public static let shared = CloudSyncManager()
    public static let storageKey = "iCloudSyncEnabled"
    public static let cloudKitContainerIdentifier = "iCloud.fr.trevalim.isowebapps"
    
    @Published public private(set) var isICloudSyncEnabled: Bool
    @Published public private(set) var activeContainer: ModelContainer
    @Published public private(set) var containerRefreshID: UUID = UUID()
    @Published public private(set) var isSyncingWithCloud: Bool = false
    @Published public private(set) var syncStatusError: String? = nil
    
    /// Sequential queue of same-name capsule conflicts presented one at a time.
    @Published public private(set) var pendingConflicts: [CapsuleSyncConflict] = []
    @Published public private(set) var totalConflictsInBatch: Int = 0
    @Published public private(set) var resolvedConflictsInBatch: Int = 0
    
    public var currentConflict: CapsuleSyncConflict? {
        pendingConflicts.first
    }
    
    private var localContainerInstance: ModelContainer?
    private var cloudContainerInstance: ModelContainer?
    private var remoteChangeObserver: NSObjectProtocol?
    private var remoteChangeDebounceTask: Task<Void, Never>?
    
    /// Tracks capsules uploaded in the current activation session so late CloudKit imports with matching names also trigger conflict resolution.
    private var uploadedSessionCapsules: [UUID: CapsuleSnapshot] = [:]
    
    private static let appSchema = Schema([
        WebAppItem.self,
        WebAppGroup.self,
    ])
    
    private static var localStoreURL: URL {
        ensureApplicationSupportDirectory()
        return URL.applicationSupportDirectory.appending(path: "LocalStore.store")
    }
    
    private static var cloudStoreURL: URL {
        ensureApplicationSupportDirectory()
        return URL.applicationSupportDirectory.appending(path: "CloudStore.store")
    }
    
    private static func ensureApplicationSupportDirectory() {
        try? FileManager.default.createDirectory(
            at: URL.applicationSupportDirectory,
            withIntermediateDirectories: true
        )
    }
    
    private init() {
        let enabled = UserDefaults.standard.object(forKey: Self.storageKey) as? Bool ?? false
        self.isICloudSyncEnabled = enabled
        
        if enabled {
            let (container, errorMessage) = Self.makeCloudContainer()
            self.syncStatusError = errorMessage
            if errorMessage == nil {
                self.cloudContainerInstance = container
            } else {
                self.localContainerInstance = container
            }
            self.activeContainer = container
        } else {
            let container = Self.makeLocalContainer()
            self.localContainerInstance = container
            self.activeContainer = container
        }
        
        setupRemoteChangeObserver()
    }
    
    // MARK: - Container Factories
    
    private static func makeLocalContainer() -> ModelContainer {
        let config = ModelConfiguration(
            "LocalStore",
            schema: appSchema,
            url: localStoreURL,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: appSchema, configurations: [config])
        } catch {
            fatalError("Could not create Local ModelContainer: \(error)")
        }
    }
    
    private static func makeCloudContainer() -> (container: ModelContainer, errorMessage: String?) {
        migrateLegacyDefaultStoreIfNeeded()
        
        let config = ModelConfiguration(
            "CloudStore",
            schema: appSchema,
            url: cloudStoreURL,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
        do {
            let container = try ModelContainer(for: appSchema, configurations: [config])
            return (container, nil)
        } catch {
            let message = "iCloud Sync could not connect to \(cloudKitContainerIdentifier): \(error.localizedDescription)"
            #if DEBUG
            print("[CloudSyncManager] \(message)")
            #endif
            return (makeLocalContainer(), message)
        }
    }
    
    /// One-time migration from the legacy unnamed `default.store` into `CloudStore.store` if needed.
    private static func migrateLegacyDefaultStoreIfNeeded() {
        let fm = FileManager.default
        let targetURL = cloudStoreURL
        guard !fm.fileExists(atPath: targetURL.path(percentEncoded: false)) else { return }
        
        let legacyURL = URL.applicationSupportDirectory.appending(path: "default.store")
        guard fm.fileExists(atPath: legacyURL.path(percentEncoded: false)) else { return }
        
        let legacyConfig = ModelConfiguration(
            schema: appSchema,
            url: legacyURL,
            cloudKitDatabase: .none
        )
        let targetConfig = ModelConfiguration(
            "CloudStore",
            schema: appSchema,
            url: targetURL,
            cloudKitDatabase: .none
        )
        
        guard let legacyContainer = try? ModelContainer(for: appSchema, configurations: [legacyConfig]),
              let targetContainer = try? ModelContainer(for: appSchema, configurations: [targetConfig]) else {
            return
        }
        
        let legacyContext = legacyContainer.mainContext
        let targetContext = targetContainer.mainContext
        
        let existingTargetItems = (try? targetContext.fetch(FetchDescriptor<WebAppItem>())) ?? []
        guard existingTargetItems.isEmpty else { return }
        
        let legacyGroups = (try? legacyContext.fetch(FetchDescriptor<WebAppGroup>())) ?? []
        let legacyItems = (try? legacyContext.fetch(FetchDescriptor<WebAppItem>())) ?? []
        guard !legacyGroups.isEmpty || !legacyItems.isEmpty else { return }
        
        var groupMap: [String: WebAppGroup] = [:]
        for g in legacyGroups {
            let copiedGroup = WebAppGroup(id: g.id, name: g.name, displayOrder: g.displayOrder)
            copiedGroup.createdAt = g.createdAt
            targetContext.insert(copiedGroup)
            let key = normalizedName(g.name)
            if !key.isEmpty {
                groupMap[key] = copiedGroup
            }
        }
        
        for item in legacyItems {
            let copiedItem = WebAppItem(
                id: item.id,
                name: item.name,
                urlString: item.urlString,
                lastOpenedURLString: item.lastOpenedURLString,
                iconData: item.iconData,
                createdAt: item.createdAt,
                lastVisited: item.lastVisited,
                isUBlockEnabled: item.isUBlockEnabled,
                openLinksInSafariReaderMode: item.openLinksInSafariReaderMode,
                deleteCookiesOnClose: item.deleteCookiesOnClose,
                displayOrder: item.displayOrder,
                isolatedCookiesData: item.isolatedCookiesData
            )
            if let gName = item.group?.name {
                copiedItem.group = groupMap[normalizedName(gName)]
            }
            targetContext.insert(copiedItem)
        }
        try? targetContext.save()
    }
    
    private func getLocalContainer() -> ModelContainer {
        if let existing = localContainerInstance {
            return existing
        }
        let created = Self.makeLocalContainer()
        localContainerInstance = created
        return created
    }
    
    private func getCloudContainer() -> ModelContainer {
        if let existing = cloudContainerInstance {
            return existing
        }
        let (created, errorMessage) = Self.makeCloudContainer()
        syncStatusError = errorMessage
        if errorMessage == nil {
            cloudContainerInstance = created
        }
        return created
    }
    
    // MARK: - Deactivation Flows (iCloud ON -> OFF)
    
    /// Deactivates iCloud sync and copies the current iCloud capsules and groups into local app storage.
    public func deactivateKeepingCurrentDataLocally() {
        let cloudContext = activeContainer.mainContext
        let groupsSnapshot = fetchGroupSnapshots(from: cloudContext)
        let capsulesSnapshot = fetchCapsuleSnapshots(from: cloudContext)
        
        let localContainer = getLocalContainer()
        let localContext = localContainer.mainContext
        
        // Replace local store content with the current state from iCloud
        clearAllData(in: localContext)
        insertSnapshots(groups: groupsSnapshot, capsules: capsulesSnapshot, into: localContext)
        try? localContext.save()
        
        uploadedSessionCapsules.removeAll()
        clearConflicts()
        syncStatusError = nil
        switchToContainer(localContainer, cloudEnabled: false)
    }
    
    /// Deactivates iCloud sync and resets local app storage to an empty state.
    public func deactivateStartingWithEmptyLocalData() {
        let localContainer = getLocalContainer()
        let localContext = localContainer.mainContext
        
        clearAllData(in: localContext)
        try? localContext.save()
        
        uploadedSessionCapsules.removeAll()
        clearConflicts()
        syncStatusError = nil
        switchToContainer(localContainer, cloudEnabled: false)
    }
    
    // MARK: - Activation Flows (iCloud OFF -> ON)
    
    /// Activates iCloud sync, deletes local app data, and switches to the iCloud copy.
    public func activateDeletingLocalDataAndSwitchToCloud() {
        let localContainer = getLocalContainer()
        let localContext = localContainer.mainContext
        clearAllData(in: localContext)
        try? localContext.save()
        
        uploadedSessionCapsules.removeAll()
        clearConflicts()
        
        let cloudContainer = getCloudContainer()
        switchToContainer(cloudContainer, cloudEnabled: syncStatusError == nil)
    }
    
    /// Activates iCloud sync, uploads local app data to iCloud, and queues any same-name capsule clashes for one-at-a-time user resolution.
    public func activateUploadingLocalDataToCloud() {
        let localContainer = getLocalContainer()
        let localContext = localContainer.mainContext
        let localGroups = fetchGroupSnapshots(from: localContext)
        let localCapsules = fetchCapsuleSnapshots(from: localContext)
        
        let cloudContainer = getCloudContainer()
        guard syncStatusError == nil else {
            switchToContainer(localContainer, cloudEnabled: false)
            return
        }
        
        switchToContainer(cloudContainer, cloudEnabled: true)
        
        guard !localGroups.isEmpty || !localCapsules.isEmpty else {
            return
        }
        
        isSyncingWithCloud = true
        
        Task { @MainActor in
            // Allow CloudKit container a brief window to load cached/imported records
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.performLocalToCloudMerge(localGroups: localGroups, localCapsules: localCapsules)
            self.isSyncingWithCloud = false
        }
    }
    
    // MARK: - Merge & Sequential Conflict Resolution
    
    private func performLocalToCloudMerge(localGroups: [GroupSnapshot], localCapsules: [CapsuleSnapshot]) {
        let cloudContext = getCloudContainer().mainContext
        let existingCloudGroups = (try? cloudContext.fetch(FetchDescriptor<WebAppGroup>())) ?? []
        let existingCloudCapsules = (try? cloudContext.fetch(FetchDescriptor<WebAppItem>())) ?? []
        
        // 1. Merge groups by normalized name
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
        
        // 2. Index existing iCloud capsules by normalized name
        var cloudCapsuleByNormalizedName: [String: WebAppItem] = [:]
        for cloudItem in existingCloudCapsules {
            let key = Self.normalizedName(cloudItem.name)
            if !key.isEmpty, cloudCapsuleByNormalizedName[key] == nil {
                cloudCapsuleByNormalizedName[key] = cloudItem
            }
        }
        
        var conflicts: [CapsuleSyncConflict] = []
        uploadedSessionCapsules.removeAll()
        
        // 3. Process each local capsule: upload immediately if unique, or enqueue conflict if name matches
        for localCapsule in localCapsules {
            let key = Self.normalizedName(localCapsule.name)
            if let existingCloudItem = cloudCapsuleByNormalizedName[key], !key.isEmpty {
                // If already identical in ID, treat as same capsule; otherwise ask user one at a time
                if existingCloudItem.id != localCapsule.id || existingCloudItem.urlString != localCapsule.urlString {
                    conflicts.append(
                        CapsuleSyncConflict(
                            localCapsule: localCapsule,
                            cloudCapsuleID: existingCloudItem.id,
                            cloudCapsuleName: existingCloudItem.name,
                            cloudCapsuleURL: existingCloudItem.urlString,
                            insertedLocalCapsuleID: nil
                        )
                    )
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
        containerRefreshID = UUID()
        
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
            // Skip local capsule: keep the iCloud version untouched and remove any late-synced local duplicate
            if let duplicate = insertedLocalDuplicate {
                cloudContext.delete(duplicate)
            }
        }
        
        uploadedSessionCapsules.removeValue(forKey: conflict.localCapsule.id)
        if let insertedID = conflict.insertedLocalCapsuleID {
            uploadedSessionCapsules.removeValue(forKey: insertedID)
        }
        
        try? cloudContext.save()
        containerRefreshID = UUID()
        
        if pendingConflicts.isEmpty {
            totalConflictsInBatch = 0
            resolvedConflictsInBatch = 0
        }
    }
    
    // MARK: - Late CloudKit Import Clash Detection & Remote Refresh
    
    private func setupRemoteChangeObserver() {
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
    
    private func scheduleRemoteChangeHandling() {
        guard isICloudSyncEnabled else { return }
        remoteChangeDebounceTask?.cancel()
        remoteChangeDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.handleRemoteStoreChange()
        }
    }
    
    private func handleRemoteStoreChange() {
        guard isICloudSyncEnabled else { return }
        let cloudContext = getCloudContainer().mainContext
        guard let allCapsules = try? cloudContext.fetch(FetchDescriptor<WebAppItem>()) else { return }
        
        var newlyDetectedConflicts: [CapsuleSyncConflict] = []
        
        // 1. Check capsules uploaded during the current activation session
        for (uploadedID, snapshot) in uploadedSessionCapsules {
            let key = Self.normalizedName(snapshot.name)
            guard !key.isEmpty else { continue }
            
            if let remoteMatch = allCapsules.first(where: {
                $0.id != uploadedID && Self.normalizedName($0.name) == key
            }) {
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
            }
        }
        
        // 2. Also detect any same-name duplicate capsules arriving from another device
        var seenByName: [String: WebAppItem] = [:]
        for item in allCapsules.sorted(by: { $0.createdAt < $1.createdAt }) {
            let key = Self.normalizedName(item.name)
            guard !key.isEmpty else { continue }
            if let earlierItem = seenByName[key], earlierItem.id != item.id {
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
                seenByName[key] = item
            }
        }
        
        if !newlyDetectedConflicts.isEmpty {
            enqueueConflicts(newlyDetectedConflicts)
        }
        
        objectWillChange.send()
    }
    
    private func enqueueConflicts(_ conflicts: [CapsuleSyncConflict]) {
        if pendingConflicts.isEmpty {
            totalConflictsInBatch = conflicts.count
            resolvedConflictsInBatch = 0
        } else {
            totalConflictsInBatch += conflicts.count
        }
        pendingConflicts.append(contentsOf: conflicts)
    }
    
    private func clearConflicts() {
        pendingConflicts.removeAll()
        totalConflictsInBatch = 0
        resolvedConflictsInBatch = 0
    }
    
    // MARK: - Helpers
    
    private func switchToContainer(_ container: ModelContainer, cloudEnabled: Bool) {
        UserDefaults.standard.set(cloudEnabled, forKey: Self.storageKey)
        isICloudSyncEnabled = cloudEnabled
        activeContainer = container
        containerRefreshID = UUID()
    }
    
    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    private func fetchGroupSnapshots(from context: ModelContext) -> [GroupSnapshot] {
        let descriptor = FetchDescriptor<WebAppGroup>(
            sortBy: [SortDescriptor(\.displayOrder, order: .forward), SortDescriptor(\.createdAt, order: .forward)]
        )
        let groups = (try? context.fetch(descriptor)) ?? []
        return groups.map { GroupSnapshot(from: $0) }
    }
    
    private func fetchCapsuleSnapshots(from context: ModelContext) -> [CapsuleSnapshot] {
        let descriptor = FetchDescriptor<WebAppItem>(
            sortBy: [SortDescriptor(\.displayOrder, order: .forward), SortDescriptor(\.createdAt, order: .forward)]
        )
        let items = (try? context.fetch(descriptor)) ?? []
        return items.map { CapsuleSnapshot(from: $0) }
    }
    
    private func clearAllData(in context: ModelContext) {
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
    
    private func insertSnapshots(
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
    
    private func makeWebAppItem(
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
}

// MARK: - Sequential Sync Clash Alert Modifier

public struct ICloudSyncConflictAlertModifier: ViewModifier {
    @ObservedObject var syncManager: CloudSyncManager
    
    private var isPresentedBinding: Binding<Bool> {
        Binding(
            get: { syncManager.currentConflict != nil },
            set: { _ in }
        )
    }
    
    public func body(content: Content) -> some View {
        content
            .alert(
                conflictAlertTitle,
                isPresented: isPresentedBinding,
                presenting: syncManager.currentConflict
            ) { _ in
                Button("Overwrite iCloud Content", role: .destructive) {
                    syncManager.resolveCurrentConflict(overwriteCloud: true)
                }
                Button("Skip Local Capsule", role: .cancel) {
                    syncManager.resolveCurrentConflict(overwriteCloud: false)
                }
            } message: { conflict in
                Text(
                    """
                    A capsule named "\(conflict.localCapsule.name)" already exists in iCloud.
                    
                    Local URL: \(conflict.localCapsule.urlString)
                    iCloud URL: \(conflict.cloudCapsuleURL)
                    
                    Do you want to overwrite the iCloud capsule with your local version, or skip copying this local capsule?
                    """
                )
            }
    }
    
    private var conflictAlertTitle: String {
        guard let conflict = syncManager.currentConflict else {
            return "iCloud Sync Clash"
        }
        if syncManager.totalConflictsInBatch > 1 {
            let currentNumber = min(syncManager.resolvedConflictsInBatch + 1, syncManager.totalConflictsInBatch)
            return "Sync Clash (\(currentNumber) of \(syncManager.totalConflictsInBatch)): \"\(conflict.localCapsule.name)\""
        }
        return "Sync Clash: \"\(conflict.localCapsule.name)\""
    }
}

public extension View {
    /// Presents a one-at-a-time resolution alert whenever `CloudSyncManager` detects same-name capsule sync clashes.
    @MainActor
    func iCloudSyncConflictAlert(syncManager: CloudSyncManager) -> some View {
        modifier(ICloudSyncConflictAlertModifier(syncManager: syncManager))
    }
}
