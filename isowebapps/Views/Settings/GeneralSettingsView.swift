//
//  GeneralSettingsView.swift
//  isowebapps
//
//  Created on 23/08/2026.
//
//  Description:
//  General settings interface for managing iCloud Sync, Default Search Engine,
//  macOS window presentation modes, sleeping tabs / performance, and uBlock Origin Lite rules.
//

import SwiftUI

/// Defines the broad filtering aggression level for content blocking.
public enum BlockingMode: String, CaseIterable, Identifiable {
    case optimal = "Optimal"
    case complete = "Complete"
    case basic = "Basic"
    
    public var id: String { rawValue }
    
    var description: String {
        switch self {
        case .optimal:
            return "Recommended: Blocks ads and trackers with highest site compatibility."
        case .complete:
            return "Maximum protection: Aggressively blocks ads, annoyances, and cookie dialogs."
        case .basic:
            return "Lightweight: Blocks known major ad and tracking servers only."
        }
    }
}

/// Snapshot of settings that require compiling WebKit rule lists when modified.
struct RuleSettingsSnapshot: Equatable {
    var ublockMasterEnabled: Bool
    var blockingMode: BlockingMode
    var filterUblockFilters: Bool
    var filterUblockBadware: Bool
    var filterEasyList: Bool
    var filterEasyPrivacy: Bool
    var filterAdGuardMobile: Bool
    var filterURLhaus: Bool
    var filterAnnoyances: Bool
    var filterBlockLAN: Bool
    var filterFrench: Bool
    var cosmeticHiding: Bool
    var scriptletDefusers: Bool
}

struct GeneralSettingsView: View {
    @Environment(\.dismiss) var dismiss
    
    @AppStorage(SearchEngine.storageKey) var defaultSearchEngine: SearchEngine = .duckDuckGo
    @AppStorage(SearchEngine.customURLStorageKey) var customSearchEngineURL: String = ""
    
    #if os(macOS)
    @AppStorage("windowPresentationMode") var windowPresentationMode: WindowPresentationMode = .singleWindow
    @AppStorage("sleepingTabsEnabled") var sleepingTabsEnabled = true
    #endif
    
    @AppStorage("ublock_master_enabled") var ublockMasterEnabled = true
    @AppStorage("ublock_blocking_mode") var blockingMode: BlockingMode = .complete
    @AppStorage("ublock_filter_ublock_filters") var filterUblockFilters = true
    @AppStorage("ublock_filter_ublock_badware") var filterUblockBadware = true
    @AppStorage("ublock_filter_easylist") var filterEasyList = true
    @AppStorage("ublock_filter_easyprivacy") var filterEasyPrivacy = true
    @AppStorage("ublock_filter_adguard_mobile") var filterAdGuardMobile = true
    @AppStorage("ublock_filter_urlhaus") var filterURLhaus = true
    @AppStorage("ublock_filter_annoyances") var filterAnnoyances = true
    @AppStorage("ublock_filter_block_lan") var filterBlockLAN = true
    @AppStorage("ublock_filter_french") var filterFrench = false
    @AppStorage("ublock_cosmetic_hiding") var cosmeticHiding = true
    @AppStorage("ublock_scriptlet_defusers") var scriptletDefusers = true
    
    @ObservedObject var manager = UBlockOriginExtensionManager.shared
    @ObservedObject var syncManager = CloudSyncManager.shared
    
    @State var isRecompiling = false
    @State var isShowingActivateICloudAlert = false
    @State var isShowingDeactivateICloudAlert = false
    @State var isShowingResetICloudAlert = false
    @State var savedSnapshot: RuleSettingsSnapshot?
    @State private var isApplyingBlockingPreset = false
    
    var iCloudToggleBinding: Binding<Bool> {
        Binding(
            get: { syncManager.isICloudSyncEnabled },
            set: { newValue in
                if newValue != syncManager.isICloudSyncEnabled {
                    if newValue {
                        isShowingActivateICloudAlert = true
                    } else {
                        isShowingDeactivateICloudAlert = true
                    }
                }
            }
        )
    }
    
    var currentSnapshot: RuleSettingsSnapshot {
        RuleSettingsSnapshot(
            ublockMasterEnabled: ublockMasterEnabled,
            blockingMode: blockingMode,
            filterUblockFilters: filterUblockFilters,
            filterUblockBadware: filterUblockBadware,
            filterEasyList: filterEasyList,
            filterEasyPrivacy: filterEasyPrivacy,
            filterAdGuardMobile: filterAdGuardMobile,
            filterURLhaus: filterURLhaus,
            filterAnnoyances: filterAnnoyances,
            filterBlockLAN: filterBlockLAN,
            filterFrench: filterFrench,
            cosmeticHiding: cosmeticHiding,
            scriptletDefusers: scriptletDefusers
        )
    }
    
    var currentFilterConfiguration: UBlockFilterConfiguration {
        UBlockFilterConfiguration(
            masterEnabled: ublockMasterEnabled,
            blockingModeRaw: blockingMode.rawValue,
            ublockFilters: filterUblockFilters,
            ublockBadware: filterUblockBadware,
            easylist: filterEasyList,
            easyprivacy: filterEasyPrivacy,
            adguardMobile: filterAdGuardMobile,
            urlhaus: filterURLhaus,
            annoyances: filterAnnoyances,
            blockLan: filterBlockLAN,
            frenchFilters: filterFrench,
            cosmeticHiding: cosmeticHiding,
            scriptletDefusers: scriptletDefusers
        )
    }
    
    var hasUncompiledChanges: Bool {
        if let compiled = manager.compiledConfiguration {
            return compiled != currentFilterConfiguration
        }
        guard let saved = savedSnapshot else { return false }
        return saved != currentSnapshot
    }
    
    var body: some View {
        Group {
            #if os(macOS)
            macOSLayout
            #else
            iOSLayout
            #endif
        }
        .onChange(of: blockingMode) { _, newMode in
            applyBlockingModePreset(newMode)
        }
        .onChange(of: filterAnnoyances) { _, _ in
            syncBlockingModeFromToggles()
        }
        .onChange(of: cosmeticHiding) { _, _ in
            syncBlockingModeFromToggles()
        }
        .onChange(of: scriptletDefusers) { _, _ in
            syncBlockingModeFromToggles()
        }
        .alert("Enable iCloud Sync", isPresented: $isShowingActivateICloudAlert) {
            Button("Upload Local Data to iCloud") {
                syncManager.activateUploadingLocalDataToCloud()
            }
            Button("Delete Local Data & Switch to iCloud", role: .destructive) {
                syncManager.activateDeletingLocalDataAndSwitchToCloud()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Would you like to upload your current local capsules to iCloud, or delete your local app data and switch to your iCloud copy?")
        }
        .alert("Disable iCloud Sync", isPresented: $isShowingDeactivateICloudAlert) {
            Button("Keep Current Data Locally") {
                syncManager.deactivateKeepingCurrentDataLocally()
            }
            Button("Start with Empty Local Data", role: .destructive) {
                syncManager.deactivateStartingWithEmptyLocalData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Would you like to store your current capsules and groups into local app data, or start again with empty local data?")
        }
        .alert("Reset iCloud Data?", isPresented: $isShowingResetICloudAlert) {
            Button("Reset iCloud & Keep Capsules Locally") {
                Task {
                    await syncManager.resetICloudData(keepCurrentDataLocally: true)
                }
            }
            Button("Reset iCloud & Delete All Data", role: .destructive) {
                Task {
                    await syncManager.resetICloudData(keepCurrentDataLocally: false)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes all capsules, groups, and cookies stored in iCloud so sync can start clean. Disable iCloud Sync on other devices first if you want a completely fresh start.")
        }
        .iCloudSyncConflictAlert(syncManager: syncManager, isSettingsSheetSlot: true)
    }
    
    private func applyBlockingModePreset(_ mode: BlockingMode) {
        guard !isApplyingBlockingPreset else { return }
        isApplyingBlockingPreset = true
        defer { isApplyingBlockingPreset = false }
        switch mode {
        case .basic:
            filterAnnoyances = false
            cosmeticHiding = false
            scriptletDefusers = false
        case .optimal:
            filterAnnoyances = false
            cosmeticHiding = true
            scriptletDefusers = true
        case .complete:
            filterAnnoyances = true
            cosmeticHiding = true
            scriptletDefusers = true
        }
    }
    
    private func syncBlockingModeFromToggles() {
        guard !isApplyingBlockingPreset else { return }
        isApplyingBlockingPreset = true
        defer { isApplyingBlockingPreset = false }
        if filterAnnoyances {
            blockingMode = .complete
        } else if cosmeticHiding || scriptletDefusers {
            blockingMode = .optimal
        } else {
            blockingMode = .basic
        }
    }
    
    /// Triggers background multi-core compilation and updates metric counters.
    func recompileRules() {
        isRecompiling = true
        Task {
            await manager.recompile()
            await MainActor.run {
                isRecompiling = false
                savedSnapshot = currentSnapshot
            }
        }
    }
}
