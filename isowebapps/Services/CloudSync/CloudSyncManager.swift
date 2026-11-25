//
//  CloudSyncManager.swift
//  isowebapps
//
//  Created on 17/10/2026.
//
//  Description:
//  Manages optional iCloud (CloudKit) synchronization for SwiftData models (`WebAppItem`
//  and `WebAppGroup`). Defaults to local-only storage (`cloudKitDatabase: .none`) and
//  orchestrates data migration when toggling iCloud sync on or off.
//

import Foundation
import SwiftUI
import SwiftData
import CoreData
import CloudKit
import Combine

@MainActor
public final class CloudSyncManager: ObservableObject {
    public static let shared = CloudSyncManager()
    public nonisolated static let storageKey = "iCloudSyncEnabled"
    public nonisolated static let cloudKitContainerIdentifier = "iCloud.fr.trevalim.isowebapps"
    
    @Published public private(set) var isICloudSyncEnabled: Bool
    @Published public private(set) var activeContainer: ModelContainer
    @Published public private(set) var containerRefreshID: UUID = UUID()
    @Published public var isSyncingWithCloud: Bool = false
    @Published public var syncStatusError: String? = nil
    @Published public var lastSuccessfulSyncDate: Date? = nil
    @Published public var isSettingsSheetPresented: Bool = false
    @Published public var schemaInitStatusMessage: String? = nil
    @Published public private(set) var isResettingICloudData: Bool = false
    @Published public private(set) var resetStatusMessage: String? = nil
    
    /// Sequential queue of same-name capsule conflicts presented one at a time.
    @Published public var pendingConflicts: [CapsuleSyncConflict] = []
    @Published public var totalConflictsInBatch: Int = 0
    @Published public var resolvedConflictsInBatch: Int = 0
    
    public var currentConflict: CapsuleSyncConflict? {
        pendingConflicts.first
    }
    
    var localContainerInstance: ModelContainer?
    var cloudContainerInstance: ModelContainer?
    var remoteChangeObserver: NSObjectProtocol?
    var cloudKitEventObserver: NSObjectProtocol?
    var remoteChangeDebounceTask: Task<Void, Never>?
    var activeCloudKitEventIDs: Set<UUID> = []
    var isPerformingInitialMerge: Bool = false
    var isManualSyncInFlight: Bool = false
    var isVerifyingAccountStatus: Bool = false
    var lastAccountVerificationDate: Date?
    var lastAppDidBecomeActiveDate: Date?
    nonisolated(unsafe) var syncIndicatorShowTask: Task<Void, Never>?
    nonisolated(unsafe) var syncIndicatorHideTask: Task<Void, Never>?
    var hasCompletedInitialCloudImport: Bool = false
    var lastKnownStoreSignature: Int?
    
    let accountVerificationCooldown: TimeInterval = 30.0
    let appActiveRefreshCooldown: TimeInterval = 5.0
    let passiveSyncShowDelayNanos: UInt64 = 400_000_000
    let passiveSyncHideDelayNanos: UInt64 = 600_000_000
    
    private nonisolated static let pendingCloudStoreResetKey = "pendingCloudStoreFileReset"
    private nonisolated static let didMigrateLegacyDefaultStoreKey = "didMigrateLegacyDefaultStore"
    
    /// Tracks capsules uploaded in the current activation session so late CloudKit imports with matching names also trigger conflict resolution.
    var uploadedSessionCapsules: [UUID: CapsuleSnapshot] = [:]
    
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
            self.lastAppDidBecomeActiveDate = Date()
            Task { @MainActor [weak self] in
                await self?.verifyICloudAccountStatus(force: false)
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
        syncIndicatorShowTask?.cancel()
        syncIndicatorHideTask?.cancel()
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
        deleteCloudStoreFilesIfNeeded()
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
    
    private static func deleteCloudStoreFilesIfNeeded() {
        guard UserDefaults.standard.bool(forKey: pendingCloudStoreResetKey) else { return }
        let fm = FileManager.default
        let basePath = cloudStoreURL.path(percentEncoded: false)
        for suffix in ["", "-wal", "-shm"] {
            let fileURL = URL(filePath: basePath + suffix)
            if fm.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                try? fm.removeItem(at: fileURL)
            }
        }
        UserDefaults.standard.set(false, forKey: pendingCloudStoreResetKey)
    }
    
    private static func migrateLegacyDefaultStoreIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: didMigrateLegacyDefaultStoreKey) else { return }
        let fm = FileManager.default
        let targetURL = cloudStoreURL
        guard !fm.fileExists(atPath: targetURL.path(percentEncoded: false)) else {
            UserDefaults.standard.set(true, forKey: didMigrateLegacyDefaultStoreKey)
            return
        }
        
        let legacyURL = URL.applicationSupportDirectory.appending(path: "default.store")
        guard fm.fileExists(atPath: legacyURL.path(percentEncoded: false)) else {
            UserDefaults.standard.set(true, forKey: didMigrateLegacyDefaultStoreKey)
            return
        }
        
        let legacyConfig = ModelConfiguration(schema: appSchema, url: legacyURL, cloudKitDatabase: .none)
        let targetConfig = ModelConfiguration("CloudStore", schema: appSchema, url: targetURL, cloudKitDatabase: .none)
        
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
        UserDefaults.standard.set(true, forKey: didMigrateLegacyDefaultStoreKey)
    }
    
    func getLocalContainer() -> ModelContainer {
        if let existing = localContainerInstance {
            return existing
        }
        let created = Self.makeLocalContainer()
        localContainerInstance = created
        return created
    }
    
    func getCloudContainer() -> ModelContainer {
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
    
    private func resetCloudSessionState(clearError: Bool) {
        uploadedSessionCapsules.removeAll()
        clearConflicts()
        activeCloudKitEventIDs.removeAll()
        isManualSyncInFlight = false
        syncIndicatorShowTask?.cancel()
        syncIndicatorShowTask = nil
        syncIndicatorHideTask?.cancel()
        syncIndicatorHideTask = nil
        isSyncingWithCloud = false
        hasCompletedInitialCloudImport = false
        if clearError {
            syncStatusError = nil
        }
    }
    
    // MARK: - Deactivation Flows (iCloud ON -> OFF)
    
    /// Deactivates iCloud sync and copies the current iCloud capsules and groups into local app storage.
    public func deactivateKeepingCurrentDataLocally() {
        let cloudContext = activeContainer.mainContext
        let groupsSnapshot = fetchGroupSnapshots(from: cloudContext)
        let capsulesSnapshot = fetchCapsuleSnapshots(from: cloudContext)
        
        let localContainer = getLocalContainer()
        let localContext = localContainer.mainContext
        
        clearAllData(in: localContext)
        insertSnapshots(groups: groupsSnapshot, capsules: capsulesSnapshot, into: localContext)
        try? localContext.save()
        
        resetCloudSessionState(clearError: true)
        switchToContainer(localContainer, cloudEnabled: false)
    }
    
    /// Deactivates iCloud sync and resets local app storage to an empty state.
    public func deactivateStartingWithEmptyLocalData() {
        let localContainer = getLocalContainer()
        let localContext = localContainer.mainContext
        
        clearAllData(in: localContext)
        try? localContext.save()
        
        resetCloudSessionState(clearError: true)
        switchToContainer(localContainer, cloudEnabled: false)
    }
    
    // MARK: - Activation Flows (iCloud OFF -> ON)
    
    /// Activates iCloud sync, deletes local app data, and switches to the iCloud copy.
    public func activateDeletingLocalDataAndSwitchToCloud() {
        let localContainer = getLocalContainer()
        let localContext = localContainer.mainContext
        clearAllData(in: localContext)
        try? localContext.save()
        
        resetCloudSessionState(clearError: true)
        
        let cloudContainer = getCloudContainer()
        let cloudReady = (syncStatusError == nil)
        switchToContainer(cloudContainer, cloudEnabled: cloudReady)
        
        guard cloudReady else { return }
        
        isManualSyncInFlight = true
        updateIsSyncingFlag(immediate: true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isManualSyncInFlight = false
                self.updateIsSyncingFlag()
            }
            await self.verifyICloudAccountStatus(force: true)
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
        isManualSyncInFlight = true
        updateIsSyncingFlag(immediate: true)
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isPerformingInitialMerge = false
                self.isManualSyncInFlight = false
                self.updateIsSyncingFlag()
            }
            await self.verifyICloudAccountStatus(force: true)
            await self.waitForInitialCloudImport(timeoutSeconds: 8.0)
            guard self.isICloudSyncEnabled else { return }
            if !localGroups.isEmpty || !localCapsules.isEmpty {
                self.performLocalToCloudMerge(localGroups: localGroups, localCapsules: localCapsules)
            }
            self.handleRemoteStoreChange()
        }
    }
    
    /// Deletes all capsule/group records stored in the CloudKit private database zone and resets the local CloudKit cache.
    public func resetICloudData(keepCurrentDataLocally: Bool) async {
        guard !isResettingICloudData else { return }
        isResettingICloudData = true
        resetStatusMessage = "Resetting iCloud data..."
        syncStatusError = nil
        defer { isResettingICloudData = false }
        
        let sourceContext = activeContainer.mainContext
        let groupsSnapshot = keepCurrentDataLocally ? fetchGroupSnapshots(from: sourceContext) : []
        let capsulesSnapshot = keepCurrentDataLocally ? fetchCapsuleSnapshots(from: sourceContext) : []
        
        if let cloudContainer = cloudContainerInstance {
            clearAllData(in: cloudContainer.mainContext)
            try? cloudContainer.mainContext.save()
        }
        
        let localContainer = getLocalContainer()
        let localContext = localContainer.mainContext
        clearAllData(in: localContext)
        if keepCurrentDataLocally {
            insertSnapshots(groups: groupsSnapshot, capsules: capsulesSnapshot, into: localContext)
        }
        try? localContext.save()
        
        resetCloudSessionState(clearError: false)
        switchToContainer(localContainer, cloudEnabled: false)
        
        cloudContainerInstance = nil
        UserDefaults.standard.set(true, forKey: Self.pendingCloudStoreResetKey)
        UserDefaults.standard.set(true, forKey: Self.didMigrateLegacyDefaultStoreKey)
        
        do {
            let database = CKContainer(identifier: Self.cloudKitContainerIdentifier).privateCloudDatabase
            let zones = try await database.allRecordZones()
            var zoneIDsToDelete = zones
                .map(\.zoneID)
                .filter { $0.zoneName != CKRecordZone.ID.defaultZoneName }
            let coreDataZoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
            if !zoneIDsToDelete.contains(where: { $0.zoneName == coreDataZoneID.zoneName }) {
                zoneIDsToDelete.append(coreDataZoneID)
            }
            
            for zoneID in zoneIDsToDelete {
                do {
                    try await database.deleteRecordZone(withID: zoneID)
                } catch let ckError as CKError where ckError.code == .zoneNotFound || ckError.code == .userDeletedZone {
                    continue
                }
            }
            
            resetStatusMessage = keepCurrentDataLocally
                ? "iCloud data has been reset. Your capsules are stored locally on this device."
                : "iCloud and local data have been completely reset."
        } catch let ckError as CKError where ckError.code == .zoneNotFound || ckError.code == .userDeletedZone {
            resetStatusMessage = keepCurrentDataLocally
                ? "iCloud data has been reset. Your capsules are stored locally on this device."
                : "iCloud and local data have been completely reset."
        } catch {
            syncStatusError = "Could not delete remote iCloud data: \(error.localizedDescription)"
            resetStatusMessage = "Local CloudKit cache was reset, but remote iCloud cleanup failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Lifecycle & Manual Retry
    
    /// Called when the app becomes active to pick up any CloudKit changes imported while backgrounded.
    public func handleAppDidBecomeActive() {
        guard isICloudSyncEnabled else { return }
        let now = Date()
        if let lastActive = lastAppDidBecomeActiveDate,
           now.timeIntervalSince(lastActive) < appActiveRefreshCooldown {
            return
        }
        lastAppDidBecomeActiveDate = now
        Task { @MainActor [weak self] in
            await self?.verifyICloudAccountStatus(force: false)
            self?.scheduleRemoteChangeHandling()
        }
    }
    
    /// Re-verifies iCloud account status, flushes any unsaved local edits, and refreshes from the CloudKit store.
    public func retrySync() {
        guard isICloudSyncEnabled else { return }
        syncStatusError = nil
        isManualSyncInFlight = true
        updateIsSyncingFlag(immediate: true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isManualSyncInFlight = false
                self.updateIsSyncingFlag()
            }
            await self.verifyICloudAccountStatus(force: true)
            let context = self.activeContainer.mainContext
            if context.hasChanges {
                try? context.save()
            }
            self.handleRemoteStoreChange()
        }
    }
    
    func switchToContainer(_ container: ModelContainer, cloudEnabled: Bool) {
        _ = deduplicateStore(in: container.mainContext)
        lastKnownStoreSignature = Self.computeStoreSignature(in: container.mainContext)
        IsolatedCookieManager.shared.invalidateRestoreCache()
        UserDefaults.standard.set(cloudEnabled, forKey: Self.storageKey)
        isICloudSyncEnabled = cloudEnabled
        activeContainer = container
        containerRefreshID = UUID()
    }
}
