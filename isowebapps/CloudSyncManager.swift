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
import CloudKit
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
    public nonisolated static let storageKey = "iCloudSyncEnabled"
    public nonisolated static let cloudKitContainerIdentifier = "iCloud.fr.trevalim.isowebapps"
    
    @Published public private(set) var isICloudSyncEnabled: Bool
    @Published public private(set) var activeContainer: ModelContainer
    @Published public private(set) var containerRefreshID: UUID = UUID()
    @Published public private(set) var isSyncingWithCloud: Bool = false
    @Published public private(set) var syncStatusError: String? = nil
    @Published public private(set) var lastSuccessfulSyncDate: Date? = nil
    @Published public var isSettingsSheetPresented: Bool = false
    @Published public private(set) var schemaInitStatusMessage: String? = nil
    
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
    private var cloudKitEventObserver: NSObjectProtocol?
    private var remoteChangeDebounceTask: Task<Void, Never>?
    private var activeCloudKitEventIDs: Set<UUID> = []
    private var isPerformingInitialMerge: Bool = false
    private var hasCompletedInitialCloudImport: Bool = false
    private var lastKnownStoreSignature: Int?
    
    #if DEBUG
    private static let debugSchemaInitializedKey = "cloudKitDebugSchemaInitialized_v2_1"
    #endif
    
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
        
        deduplicateStore(in: self.activeContainer.mainContext)
        self.lastKnownStoreSignature = Self.computeStoreSignature(in: self.activeContainer.mainContext)
        setupRemoteChangeObserver()
        setupCloudKitEventObserver()
        
        if enabled {
            Task { @MainActor [weak self] in
                await self?.verifyICloudAccountStatus()
                #if DEBUG
                await self?.initializeCloudKitDevelopmentSchemaIfNeeded()
                #endif
            }
        }
    }
    
    deinit {
        if let observer = remoteChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let eventObserver = cloudKitEventObserver {
            NotificationCenter.default.removeObserver(eventObserver)
        }
        remoteChangeDebounceTask?.cancel()
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
        activeCloudKitEventIDs.removeAll()
        hasCompletedInitialCloudImport = false
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
        activeCloudKitEventIDs.removeAll()
        hasCompletedInitialCloudImport = false
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
        hasCompletedInitialCloudImport = false
        syncStatusError = nil
        
        let cloudContainer = getCloudContainer()
        let cloudReady = (syncStatusError == nil)
        switchToContainer(cloudContainer, cloudEnabled: cloudReady)
        
        guard cloudReady else { return }
        
        isSyncingWithCloud = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.updateIsSyncingFlag() }
            await self.verifyICloudAccountStatus()
            #if DEBUG
            await self.initializeCloudKitDevelopmentSchemaIfNeeded()
            #endif
            await self.waitForInitialCloudImport(timeoutSeconds: 8.0)
            guard self.isICloudSyncEnabled else { return }
            self.handleRemoteStoreChange()
        }
    }
    
    /// Activates iCloud sync, uploads local app data to iCloud, and queues any same-name capsule clashes for one-at-a-time user resolution.
    public func activateUploadingLocalDataToCloud() {
        let localContainer = getLocalContainer()
        let localContext = localContainer.mainContext
        let localGroups = fetchGroupSnapshots(from: localContext)
        let localCapsules = fetchCapsuleSnapshots(from: localContext)
        
        hasCompletedInitialCloudImport = false
        syncStatusError = nil
        
        let cloudContainer = getCloudContainer()
        guard syncStatusError == nil else {
            switchToContainer(localContainer, cloudEnabled: false)
            return
        }
        
        switchToContainer(cloudContainer, cloudEnabled: true)
        
        isPerformingInitialMerge = true
        isSyncingWithCloud = true
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isPerformingInitialMerge = false
                self.updateIsSyncingFlag()
            }
            await self.verifyICloudAccountStatus()
            #if DEBUG
            await self.initializeCloudKitDevelopmentSchemaIfNeeded()
            #endif
            await self.waitForInitialCloudImport(timeoutSeconds: 8.0)
            guard self.isICloudSyncEnabled else { return }
            if !localGroups.isEmpty || !localCapsules.isEmpty {
                self.performLocalToCloudMerge(localGroups: localGroups, localCapsules: localCapsules)
            }
            self.handleRemoteStoreChange()
        }
    }
    
    // MARK: - Lifecycle & Manual Retry
    
    /// Called when the app becomes active to pick up any CloudKit changes imported while backgrounded.
    public func handleAppDidBecomeActive() {
        guard isICloudSyncEnabled else { return }
        Task { @MainActor [weak self] in
            await self?.verifyICloudAccountStatus()
            self?.scheduleRemoteChangeHandling()
        }
    }
    
    /// Re-verifies iCloud account status, flushes any unsaved local edits, and refreshes from the CloudKit store.
    public func retrySync() {
        guard isICloudSyncEnabled else { return }
        syncStatusError = nil
        isSyncingWithCloud = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.updateIsSyncingFlag() }
            await self.verifyICloudAccountStatus()
            let context = self.activeContainer.mainContext
            if context.hasChanges {
                try? context.save()
            }
            self.handleRemoteStoreChange()
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
        
        // 3. Process each local capsule: upload immediately if unique, auto-merge if identical URL, or enqueue conflict if URL differs
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
                    // Same name and same normalized URL: auto-merge missing metadata without prompting
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
        lastKnownStoreSignature = Self.computeStoreSignature(in: cloudContext)
        containerRefreshID = UUID()
        
        if pendingConflicts.isEmpty {
            totalConflictsInBatch = 0
            resolvedConflictsInBatch = 0
        }
    }
    
    // MARK: - CloudKit Event & Account Monitoring
    
    private func setupCloudKitEventObserver() {
        cloudKitEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
                return
            }
            if let error = event.error as NSError?,
               ((error.userInfo[NSFilePathErrorKey] as? String)?.contains("SchemaInit.sqlite") == true ||
                String(describing: error).contains("SchemaInit.sqlite")) {
                return
            }
            let eventID = event.identifier
            let eventTypeRaw = event.type.rawValue
            let endDate = event.endDate
            let succeeded = event.succeeded
            let errorMessage = event.error.map { Self.describeCloudKitError($0, eventType: event.type) }
            
            Task { @MainActor [weak self] in
                self?.handleCloudKitEvent(
                    id: eventID,
                    eventTypeRaw: eventTypeRaw,
                    endDate: endDate,
                    succeeded: succeeded,
                    errorMessage: errorMessage
                )
            }
        }
    }
    
    private func handleCloudKitEvent(
        id: UUID,
        eventTypeRaw: Int,
        endDate: Date?,
        succeeded: Bool,
        errorMessage: String?
    ) {
        guard isICloudSyncEnabled else { return }
        let eventType = NSPersistentCloudKitContainer.EventType(rawValue: eventTypeRaw)
        
        if endDate == nil {
            activeCloudKitEventIDs.insert(id)
            updateIsSyncingFlag()
            return
        }
        
        activeCloudKitEventIDs.remove(id)
        if eventType == .import {
            hasCompletedInitialCloudImport = true
        }
        
        if succeeded {
            if eventType == .import || eventType == .export {
                lastSuccessfulSyncDate = endDate
                syncStatusError = nil
            }
            if eventType == .import {
                scheduleRemoteChangeHandling()
            }
        } else if let errorMessage {
            syncStatusError = errorMessage
            #if DEBUG
            print("[CloudSyncManager] CloudKit event error: \(errorMessage)")
            #endif
        }
        
        updateIsSyncingFlag()
    }
    
    private func updateIsSyncingFlag() {
        isSyncingWithCloud = isPerformingInitialMerge || !activeCloudKitEventIDs.isEmpty
    }
    
    private func waitForInitialCloudImport(timeoutSeconds: TimeInterval) async {
        let minimumWaitNanos: UInt64 = 1_500_000_000
        let pollIntervalNanos: UInt64 = 250_000_000
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        
        try? await Task.sleep(nanoseconds: minimumWaitNanos)
        while !hasCompletedInitialCloudImport && Date() < deadline && isICloudSyncEnabled {
            try? await Task.sleep(nanoseconds: pollIntervalNanos)
        }
    }
    
    private func verifyICloudAccountStatus() async {
        let container = CKContainer(identifier: Self.cloudKitContainerIdentifier)
        do {
            let status = try await container.accountStatus()
            guard isICloudSyncEnabled else { return }
            switch status {
            case .available:
                break
            case .noAccount:
                syncStatusError = "No iCloud account is signed in on this device. Sign in to iCloud in System Settings / Settings to sync capsules."
            case .restricted:
                syncStatusError = "iCloud access is restricted on this device (Screen Time or MDM profile)."
            case .temporarilyUnavailable:
                syncStatusError = "Your iCloud account is temporarily unavailable. Please verify your iCloud settings and try again."
            case .couldNotDetermine:
                syncStatusError = "Could not verify iCloud account status. Check your internet connection and iCloud permissions."
            @unknown default:
                break
            }
        } catch {
            guard isICloudSyncEnabled else { return }
            syncStatusError = "Unable to verify iCloud status: \(error.localizedDescription)"
        }
    }
    
    nonisolated private static func describeCloudKitError(
        _ error: Error,
        eventType: NSPersistentCloudKitContainer.EventType
    ) -> String {
        let phase: String = switch eventType {
        case .setup: "setup"
        case .import: "download"
        case .export: "upload"
        @unknown default: "sync"
        }
        
        let nsError = error as NSError
        if nsError.domain == CKErrorDomain, let ckCode = CKError.Code(rawValue: nsError.code) {
            switch ckCode {
            case .notAuthenticated:
                return "iCloud \(phase) failed: not signed in to iCloud."
            case .networkUnavailable, .networkFailure:
                return "iCloud \(phase) paused: no internet connection."
            case .quotaExceeded:
                return "iCloud \(phase) failed: your iCloud storage is full."
            case .serverRejectedRequest, .invalidArguments:
                return "iCloud \(phase) rejected by CloudKit (\(nsError.localizedDescription)). Ensure the CloudKit schema is deployed to Production in Apple CloudKit Console."
            case .permissionFailure:
                return "iCloud \(phase) failed: missing CloudKit permission or entitlement."
            case .badContainer:
                return "iCloud \(phase) failed: invalid CloudKit container (\(cloudKitContainerIdentifier))."
            case .partialFailure:
                if let partials = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error],
                   let firstPartial = partials.values.first {
                    return describeCloudKitError(firstPartial, eventType: eventType)
                }
                return "iCloud \(phase) partially failed: \(nsError.localizedDescription)"
            default:
                return "iCloud \(phase) error (\(ckCode.rawValue)): \(nsError.localizedDescription)"
            }
        }
        return "iCloud \(phase) error: \(error.localizedDescription)"
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
        let didDeduplicate = deduplicateStore(in: cloudContext)
        guard let allCapsules = try? cloudContext.fetch(FetchDescriptor<WebAppItem>()) else { return }
        
        var newlyDetectedConflicts: [CapsuleSyncConflict] = []
        var didAutoMerge = false
        var mergedDuplicateIDs = Set<UUID>()
        
        // 1. Check capsules uploaded during the current activation session
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
                    // Identical URL: let section 2 auto-merge and clear session tracking
                    uploadedSessionCapsules.removeValue(forKey: uploadedID)
                }
            }
        }
        
        // 2. Also detect any same-name duplicate capsules arriving from another device
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
            IsolatedCookieManager.shared.invalidateRestoreCache()
            containerRefreshID = UUID()
            objectWillChange.send()
        }
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
        _ = deduplicateStore(in: container.mainContext)
        lastKnownStoreSignature = Self.computeStoreSignature(in: container.mainContext)
        IsolatedCookieManager.shared.invalidateRestoreCache()
        UserDefaults.standard.set(cloudEnabled, forKey: Self.storageKey)
        isICloudSyncEnabled = cloudEnabled
        activeContainer = container
        containerRefreshID = UUID()
    }
    
    /// Automatically merges and deletes duplicate `WebAppGroup` and `WebAppItem` records
    /// that share the same `id` (or groups sharing the same normalized name), which can occur
    /// when CloudKit imports records that were already migrated locally.
    @discardableResult
    public func deduplicateActiveStore() -> Bool {
        return deduplicateStore(in: activeContainer.mainContext)
    }
    
    @discardableResult
    public func deduplicateStore(in context: ModelContext) -> Bool {
        let allGroups = (try? context.fetch(FetchDescriptor<WebAppGroup>())) ?? []
        let allItems = (try? context.fetch(FetchDescriptor<WebAppItem>())) ?? []
        
        var didChange = false
        var removedGroupCount = 0
        var removedItemCount = 0
        
        // 1. Deduplicate WebAppGroups by ID first, then by normalized name.
        // Sort so the group with the most attached items (or earliest createdAt) is kept as primary.
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
        
        // Reassign any items pointing to duplicate groups before deleting them
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
        
        // 2. Deduplicate WebAppItems that share the exact same UUID
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
            hasher.combine(item.lastOpenedURLString)
            hasher.combine(item.displayOrder)
            hasher.combine(item.isUBlockEnabled)
            hasher.combine(item.openLinksInSafariReaderMode)
            hasher.combine(item.deleteCookiesOnClose)
            hasher.combine(item.iconData?.count)
            hasher.combine(item.isolatedCookiesData?.count)
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
    
    #if DEBUG
    private func initializeCloudKitDevelopmentSchemaIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.debugSchemaInitializedKey) else { return }
        await initializeCloudKitDevelopmentSchema()
    }
    
    /// Pushes the complete `WebAppItem` and `WebAppGroup` Core Data / SwiftData schema to the CloudKit Development environment
    /// so it can be deployed to Production in Apple's CloudKit Console.
    public func initializeCloudKitDevelopmentSchema() async {
        schemaInitStatusMessage = "Initializing CloudKit Development schema..."
        let containerID = Self.cloudKitContainerIdentifier
        let resultMessage: String = await Task.detached(priority: .utility) {
            Self.runCloudKitSchemaInitialization(containerIdentifier: containerID)
        }.value
        schemaInitStatusMessage = resultMessage
        if resultMessage.hasPrefix("Success") {
            UserDefaults.standard.set(true, forKey: Self.debugSchemaInitializedKey)
        }
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
    #endif
    
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
    let isSettingsSheetSlot: Bool
    
    private var isPresentedBinding: Binding<Bool> {
        Binding(
            get: {
                syncManager.currentConflict != nil &&
                (isSettingsSheetSlot ? syncManager.isSettingsSheetPresented : !syncManager.isSettingsSheetPresented)
            },
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
    func iCloudSyncConflictAlert(syncManager: CloudSyncManager, isSettingsSheetSlot: Bool = false) -> some View {
        modifier(ICloudSyncConflictAlertModifier(syncManager: syncManager, isSettingsSheetSlot: isSettingsSheetSlot))
    }
}
