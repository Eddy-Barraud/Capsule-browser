//
//  ICloudSyncConflictAlertModifier.swift
//  isowebapps
//
//  Description:
//  SwiftUI ViewModifier presenting sequential CloudKit sync conflict resolution alerts.
//

import SwiftUI

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
