//
//  CloudSyncManager+Events.swift
//  isowebapps
//
//  Description:
//  CloudKit event monitoring, account status verification, sync indicator debouncing,
//  and error classification for `CloudSyncManager`.
//

import Foundation
import CoreData
import CloudKit

extension CloudSyncManager {
    // MARK: - CloudKit Event & Account Monitoring
    
    func setupCloudKitEventObserver() {
        cloudKitEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
                return
            }
            let eventID = event.identifier
            let eventTypeRaw = event.type.rawValue
            let endDate = event.endDate
            let succeeded = event.succeeded
            let errorMessage: String?
            if let error = event.error, !Self.isTransientOrIgnorableCloudKitEventError(error) {
                errorMessage = Self.describeCloudKitError(error, eventType: event.type)
            } else {
                errorMessage = nil
            }
            
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
    
    public nonisolated static func shouldTrackCloudKitEventTypeForSyncIndicator(
        _ eventType: NSPersistentCloudKitContainer.EventType?
    ) -> Bool {
        switch eventType {
        case .import, .export:
            return true
        case .setup, .none:
            return false
        @unknown default:
            return false
        }
    }
    
    public nonisolated static func shouldThrottleVerification(
        lastVerifiedAt: Date?,
        now: Date,
        cooldown: TimeInterval,
        force: Bool
    ) -> Bool {
        guard !force, let lastVerifiedAt else { return false }
        return now.timeIntervalSince(lastVerifiedAt) < cooldown
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
        let trackForIndicator = Self.shouldTrackCloudKitEventTypeForSyncIndicator(eventType)
        
        if endDate == nil {
            if trackForIndicator {
                activeCloudKitEventIDs.insert(id)
                updateIsSyncingFlag()
            }
            return
        }
        
        if trackForIndicator {
            activeCloudKitEventIDs.remove(id)
        }
        if eventType == .import && succeeded {
            hasCompletedInitialCloudImport = true
        }
        
        if succeeded {
            if eventType == .import || eventType == .export {
                if let endDate {
                    if lastSuccessfulSyncDate == nil || abs(endDate.timeIntervalSince(lastSuccessfulSyncDate!)) >= 1.0 {
                        lastSuccessfulSyncDate = endDate
                    }
                }
                if syncStatusError != nil {
                    syncStatusError = nil
                }
            }
            if eventType == .import {
                IsolatedCookieManager.shared.invalidateRestoreCache()
                scheduleRemoteChangeHandling()
            }
        } else if let errorMessage {
            if syncStatusError != errorMessage {
                syncStatusError = errorMessage
            }
            #if DEBUG
            print("[CloudSyncManager] CloudKit event error: \(errorMessage)")
            #endif
        }
        
        if trackForIndicator {
            updateIsSyncingFlag()
        }
    }
    
    func updateIsSyncingFlag(immediate: Bool = false) {
        let userInitiated = isPerformingInitialMerge || isManualSyncInFlight
        let hasPassiveEvents = !activeCloudKitEventIDs.isEmpty
        
        if userInitiated {
            syncIndicatorShowTask?.cancel()
            syncIndicatorShowTask = nil
            syncIndicatorHideTask?.cancel()
            syncIndicatorHideTask = nil
            if !isSyncingWithCloud {
                isSyncingWithCloud = true
            }
            return
        }
        
        if hasPassiveEvents {
            syncIndicatorHideTask?.cancel()
            syncIndicatorHideTask = nil
            if !isSyncingWithCloud {
                if immediate {
                    syncIndicatorShowTask?.cancel()
                    syncIndicatorShowTask = nil
                    isSyncingWithCloud = true
                } else if syncIndicatorShowTask == nil {
                    let delay = passiveSyncShowDelayNanos
                    syncIndicatorShowTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: delay)
                        guard let self, !Task.isCancelled else { return }
                        self.syncIndicatorShowTask = nil
                        if !self.activeCloudKitEventIDs.isEmpty && !self.isSyncingWithCloud {
                            self.isSyncingWithCloud = true
                        }
                    }
                }
            }
            return
        }
        
        syncIndicatorShowTask?.cancel()
        syncIndicatorShowTask = nil
        if isSyncingWithCloud {
            if immediate {
                syncIndicatorHideTask?.cancel()
                syncIndicatorHideTask = nil
                isSyncingWithCloud = false
            } else if syncIndicatorHideTask == nil {
                let delay = passiveSyncHideDelayNanos
                syncIndicatorHideTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: delay)
                    guard let self, !Task.isCancelled else { return }
                    self.syncIndicatorHideTask = nil
                    if !self.isPerformingInitialMerge && !self.isManualSyncInFlight && self.activeCloudKitEventIDs.isEmpty && self.isSyncingWithCloud {
                        self.isSyncingWithCloud = false
                    }
                }
            }
        }
    }
    
    func waitForInitialCloudImport(timeoutSeconds: TimeInterval) async {
        let minimumWaitNanos: UInt64 = 1_500_000_000
        let pollIntervalNanos: UInt64 = 250_000_000
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        
        try? await Task.sleep(nanoseconds: minimumWaitNanos)
        while !hasCompletedInitialCloudImport && Date() < deadline && isICloudSyncEnabled {
            try? await Task.sleep(nanoseconds: pollIntervalNanos)
        }
    }
    
    func verifyICloudAccountStatus(force: Bool = false) async {
        guard !isVerifyingAccountStatus else { return }
        let now = Date()
        guard !Self.shouldThrottleVerification(
            lastVerifiedAt: lastAccountVerificationDate,
            now: now,
            cooldown: accountVerificationCooldown,
            force: force
        ) else {
            return
        }
        isVerifyingAccountStatus = true
        defer {
            isVerifyingAccountStatus = false
            lastAccountVerificationDate = Date()
        }
        
        let container = CKContainer(identifier: Self.cloudKitContainerIdentifier)
        do {
            let status = try await container.accountStatus()
            guard isICloudSyncEnabled else { return }
            let resolvedError: String?
            switch status {
            case .available:
                resolvedError = nil
            case .noAccount:
                resolvedError = "No iCloud account is signed in on this device. Sign in to iCloud in System Settings / Settings to sync capsules."
            case .restricted:
                resolvedError = "iCloud access is restricted on this device (Screen Time or MDM profile)."
            case .temporarilyUnavailable:
                resolvedError = "Your iCloud account is temporarily unavailable. Please verify your iCloud settings and try again."
            case .couldNotDetermine:
                resolvedError = "Could not verify iCloud account status. Check your internet connection and iCloud permissions."
            @unknown default:
                resolvedError = nil
            }
            if let resolvedError, syncStatusError != resolvedError {
                syncStatusError = resolvedError
            }
        } catch {
            guard isICloudSyncEnabled else { return }
            let message = "Unable to verify iCloud status: \(error.localizedDescription)"
            if syncStatusError != message {
                syncStatusError = message
            }
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
    
    /// Returns `true` for internal CoreData/CloudKit recovery errors (such as `CKError.changeTokenExpired`,
    /// cancelled temporary-store requests, or `SchemaInit.sqlite` teardown) that should not surface to the user.
    public nonisolated static func isTransientOrIgnorableCloudKitEventError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if (nsError.userInfo[NSFilePathErrorKey] as? String)?.contains("SchemaInit.sqlite") == true ||
            String(describing: nsError).contains("SchemaInit.sqlite") {
            return true
        }
        if nsError.domain == NSCocoaErrorDomain && nsError.code == 134407 {
            return true
        }
        if nsError.domain == CKErrorDomain, let ckCode = CKError.Code(rawValue: nsError.code) {
            switch ckCode {
            case .changeTokenExpired:
                return true
            case .partialFailure:
                if let partials = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error], !partials.isEmpty {
                    return partials.values.allSatisfy { isTransientOrIgnorableCloudKitEventError($0) }
                }
                return false
            default:
                return false
            }
        }
        return false
    }
}
