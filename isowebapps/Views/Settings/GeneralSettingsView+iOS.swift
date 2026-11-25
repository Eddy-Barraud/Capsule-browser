//
//  GeneralSettingsView+iOS.swift
//  isowebapps
//
//  Description:
//  iOS layout for `GeneralSettingsView`.
//

#if os(iOS)
import SwiftUI

extension GeneralSettingsView {
    var iOSLayout: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 38))
                            .foregroundStyle(.blue.gradient)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("General Settings")
                                .font(.title3.bold())
                            Text("uBlock Origin Lite ad-blocking and content protection")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section(
                    header: Text("iCloud Sync"),
                    footer: Text(
                        syncManager.isICloudSyncEnabled
                            ? "Your capsules, groups, and isolated cookies are synced across your devices via iCloud."
                            : "iCloud sync is off by default. Your capsules are stored only on this device."
                    )
                ) {
                    Toggle("Sync Capsules with iCloud", isOn: iCloudToggleBinding)
                        .disabled(syncManager.isSyncingWithCloud || syncManager.isResettingICloudData)
                    
                    if syncManager.isSyncingWithCloud {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Syncing with iCloud...")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else if syncManager.isICloudSyncEnabled {
                        Text(
                            syncManager.lastSuccessfulSyncDate.map {
                                "Last synced \($0.formatted(date: .abbreviated, time: .shortened))"
                            } ?? "iCloud sync active"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    
                    if let errorMessage = syncManager.syncStatusError {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        
                        Button("Retry Sync") {
                            syncManager.retrySync()
                        }
                        .disabled(syncManager.isSyncingWithCloud || syncManager.isResettingICloudData)
                    } else if syncManager.isICloudSyncEnabled {
                        Button("Sync Now") {
                            syncManager.retrySync()
                        }
                        .disabled(syncManager.isSyncingWithCloud || syncManager.isResettingICloudData)
                    }
                    
                    Button("Reset iCloud Data…", role: .destructive) {
                        isShowingResetICloudAlert = true
                    }
                    .disabled(syncManager.isSyncingWithCloud || syncManager.isResettingICloudData)
                    
                    if syncManager.isResettingICloudData {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(syncManager.resetStatusMessage ?? "Resetting iCloud data...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let resetMsg = syncManager.resetStatusMessage {
                        Text(resetMsg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    #if DEBUG
                    if syncManager.isICloudSyncEnabled {
                        Button("Initialize CloudKit Schema (Debug)") {
                            Task {
                                await syncManager.initializeCloudKitDevelopmentSchema()
                            }
                        }
                        if let schemaMsg = syncManager.schemaInitStatusMessage {
                            Text(schemaMsg)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    #endif
                }
                
                Section(
                    header: Text("Default Search Engine"),
                    footer: Text("Used when searching from the home screen search bar or any web capsule address bar.")
                ) {
                    Picker("Search Engine", selection: $defaultSearchEngine) {
                        ForEach(SearchEngine.allCases) { engine in
                            Text(engine.label).tag(engine)
                        }
                    }
                    
                    if defaultSearchEngine == .custom {
                        TextField("https://search.brave.com/search?q=", text: $customSearchEngineURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                }
                
                Section(header: Text("uBlock Origin Lite")) {
                    Toggle("Enable Content Blocking", isOn: $ublockMasterEnabled)
                }
                
                Section(header: Text("Protection Status")) {
                    if ublockMasterEnabled {
                        HStack {
                            Label("Active Rules", systemImage: "bolt.shield.fill")
                            Spacer()
                            Text("\(manager.activeRulesCount.formatted()) rules")
                                .foregroundStyle(.secondary)
                                .bold()
                        }
                        HStack {
                            Label("Compiled Rule Lists", systemImage: "list.bullet.rectangle.fill")
                            Spacer()
                            Text("\(manager.activeListsCount) lists")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            Label("Status", systemImage: "shield.slash")
                            Spacer()
                            Text("Disabled")
                                .foregroundStyle(.secondary)
                                .bold()
                        }
                    }
                }
                
                if ublockMasterEnabled {
                    Section(header: Text("Filtering Level")) {
                        Picker("Filtering Level", selection: $blockingMode) {
                            ForEach(BlockingMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        Text(blockingMode.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    
                    Section(header: Text("Filter Lists")) {
                        Toggle("uBlock filters (Built-in)", isOn: $filterUblockFilters)
                        Toggle("uBlock Badware & Malware Risks", isOn: $filterUblockBadware)
                        Toggle("EasyList (Ad Removal)", isOn: $filterEasyList)
                        Toggle("EasyPrivacy (Tracker Protection)", isOn: $filterEasyPrivacy)
                        Toggle("AdGuard Mobile Ads", isOn: $filterAdGuardMobile)
                        Toggle("URLhaus (Malicious Hosts)", isOn: $filterURLhaus)
                        Toggle("Annoyances (Cookie Warnings & Popups)", isOn: $filterAnnoyances)
                        Toggle("Block Local Network / LAN Probing", isOn: $filterBlockLAN)
                    }
                    
                    Section(header: Text("Regional Lists")) {
                        Toggle("French Regional Filters (fra-0)", isOn: $filterFrench)
                    }
                    
                    Section(header: Text("Page Cleanup & Defusers")) {
                        Toggle("Cosmetic Element Hiding (Collapse Ad Banners)", isOn: $cosmeticHiding)
                        Toggle("Scriptlet Defusers (Neutralize Anti-Adblock)", isOn: $scriptletDefusers)
                    }
                }
                
                Section(
                    header: Text("Credits & License"),
                    footer: Text("Copyright © 2026 Eddy Barraud. Capsule Browser is licensed under GPLv3. Content blocking rulesets are powered by uBlock Origin Lite (uBOL-home) by Raymond Hill (gorhill) and filter list maintainers (EasyList, EasyPrivacy, AdGuard, Peter Lowe, URLhaus).")
                ) {
                    Link(destination: URL(string: "https://github.com/uBlockOrigin/uBOL-home")!) {
                        Label("uBlock Origin Lite (GitHub)", systemImage: "link")
                    }
                    Link(destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!) {
                        Label("GNU General Public License v3.0", systemImage: "doc.text")
                    }
                }
            }
            .navigationTitle("General Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if hasUncompiledChanges {
                        Button {
                            recompileRules()
                        } label: {
                            HStack(spacing: 4) {
                                if isRecompiling {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                                Text(isRecompiling ? "Compiling..." : "Compile new rules")
                                    .bold()
                            }
                        }
                        .disabled(isRecompiling)
                    } else {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                if savedSnapshot == nil {
                    savedSnapshot = currentSnapshot
                }
            }
        }
    }
}
#endif
