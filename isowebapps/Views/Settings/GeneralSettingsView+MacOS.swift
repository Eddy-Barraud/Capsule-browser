//
//  GeneralSettingsView+MacOS.swift
//  isowebapps
//
//  Description:
//  macOS layout for `GeneralSettingsView`.
//

#if os(macOS)
import SwiftUI
import AppKit

extension GeneralSettingsView {
    private var iCloudSyncStatusSubtitle: String {
        if let lastSynced = syncManager.lastSuccessfulSyncDate {
            return "Last synced \(lastSynced.formatted(date: .abbreviated, time: .shortened))"
        }
        if syncManager.isSyncingWithCloud {
            return "Checking iCloud capsules..."
        }
        return "iCloud sync active"
    }
    
    var macOSLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue.gradient)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(.title2.bold())
                    Text("General preferences, window presentation, and ad blocking")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)
            
            Divider()
            
            ScrollView(.vertical) {
                VStack(spacing: 18) {
                    MacOSSectionCard(
                        title: "iCloud Sync",
                        systemImage: syncManager.isICloudSyncEnabled ? "icloud.fill" : "icloud.slash",
                        badge: syncManager.isICloudSyncEnabled ? "Enabled" : "Local Only",
                        footer: "Synchronize your capsules, groups, and isolated cookies across your devices using iCloud."
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Toggle("Sync Capsules with iCloud", isOn: iCloudToggleBinding)
                                    .toggleStyle(.checkbox)
                                    .disabled(syncManager.isSyncingWithCloud || syncManager.isResettingICloudData)
                                
                                if syncManager.isSyncingWithCloud {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 14, height: 14)
                                    Text("Checking iCloud capsules...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(height: 20, alignment: .leading)
                            .animation(nil, value: syncManager.isSyncingWithCloud)
                            
                            Text(
                                syncManager.isICloudSyncEnabled
                                    ? "Your capsules are currently synced with iCloud."
                                    : "iCloud sync is off by default. Your capsules are stored only on this device."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            
                            if syncManager.isICloudSyncEnabled {
                                Text(iCloudSyncStatusSubtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(height: 14, alignment: .leading)
                            }
                            
                            if let errorMessage = syncManager.syncStatusError {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .fixedSize(horizontal: false, vertical: true)
                                    
                                    HStack(spacing: 8) {
                                        Button("Retry Sync") {
                                            syncManager.retrySync()
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .disabled(syncManager.isSyncingWithCloud || syncManager.isResettingICloudData)
                                        
                                        Button("Reset iCloud Data…", role: .destructive) {
                                            isShowingResetICloudAlert = true
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .disabled(syncManager.isSyncingWithCloud || syncManager.isResettingICloudData)
                                    }
                                }
                            } else {
                                HStack(spacing: 8) {
                                    if syncManager.isICloudSyncEnabled {
                                        Button("Sync Now") {
                                            syncManager.retrySync()
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .disabled(syncManager.isSyncingWithCloud || syncManager.isResettingICloudData)
                                    }
                                    
                                    Button("Reset iCloud Data…", role: .destructive) {
                                        isShowingResetICloudAlert = true
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(syncManager.isSyncingWithCloud || syncManager.isResettingICloudData)
                                }
                            }
                            
                            if syncManager.isResettingICloudData {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 14, height: 14)
                                    Text(syncManager.resetStatusMessage ?? "Resetting iCloud data...")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            } else if let resetMsg = syncManager.resetStatusMessage {
                                Text(resetMsg)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            #if DEBUG
                            if syncManager.isICloudSyncEnabled {
                                Divider()
                                    .padding(.vertical, 2)
                                Button("Initialize CloudKit Schema (Debug)") {
                                    Task {
                                        await syncManager.initializeCloudKitDevelopmentSchema()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                if let schemaMsg = syncManager.schemaInitStatusMessage {
                                    Text(schemaMsg)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            #endif
                        }
                    }
                    
                    MacOSSectionCard(
                        title: "Default Search Engine",
                        systemImage: "magnifyingglass",
                        footer: "Used when searching from the home screen search bar or any web capsule address bar."
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Search Engine", selection: $defaultSearchEngine) {
                                ForEach(SearchEngine.allCases) { engine in
                                    Text(engine.displayName).tag(engine)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            
                            if defaultSearchEngine == .custom {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Custom Search URL (include query argument such as ?q=)")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    
                                    TextField("https://search.brave.com/search?q=", text: $customSearchEngineURL)
                                        .textFieldStyle(.roundedBorder)
                                }
                                .padding(.top, 2)
                            } else {
                                HStack(spacing: 6) {
                                    Image(systemName: "globe")
                                        .foregroundStyle(.blue)
                                        .font(.caption)
                                    Text(defaultSearchEngine.defaultQueryPrefix + "...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 2)
                            }
                        }
                    }
                    
                    MacOSSectionCard(
                        title: "Capsule Opening Mode",
                        systemImage: "macwindow.on.rectangle",
                        footer: "Select how capsules open when launched from the home screen or links."
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Opening Mode", selection: $windowPresentationMode) {
                                Text("One View").tag(WindowPresentationMode.singleWindow)
                                Text("Windows").tag(WindowPresentationMode.separateWindows)
                                Text("Tabs").tag(WindowPresentationMode.tabs)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            
                            HStack(spacing: 8) {
                                Image(systemName: windowPresentationMode.iconName)
                                    .foregroundStyle(.blue)
                                Text(modeDescription(for: windowPresentationMode))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 2)
                        }
                    }
                    
                    MacOSSectionCard(
                        title: "Performance & Memory",
                        systemImage: "bolt.fill",
                        footer: "Audio and media playback will continue playing in the background."
                    ) {
                        Toggle("Sleeping Tabs & Background Throttling", isOn: $sleepingTabsEnabled)
                            .toggleStyle(.checkbox)
                        Text("Puts background tabs and inactive windows to sleep after 5 minutes to reduce CPU and memory usage, freeing RAM while dedicating system resources to the active capsule.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    MacOSSectionCard(
                        title: "uBlock Origin Lite",
                        systemImage: ublockMasterEnabled ? "shield.checkered" : "shield.slash",
                        badge: ublockMasterEnabled ? "\(manager.activeRulesCount.formatted()) active rules" : "Disabled"
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle("Enable uBlock Origin Lite Protection", isOn: $ublockMasterEnabled)
                                .toggleStyle(.checkbox)
                                .font(.subheadline.weight(.semibold))
                            
                            if ublockMasterEnabled {
                                HStack(spacing: 24) {
                                    Label("\(manager.activeRulesCount.formatted()) rules", systemImage: "bolt.shield.fill")
                                        .font(.subheadline.weight(.medium))
                                    Label("\(manager.activeListsCount) compiled lists", systemImage: "list.bullet.rectangle.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                                
                                Divider()
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Filtering Level")
                                        .font(.subheadline.weight(.semibold))
                                    
                                    Picker("Filtering Level", selection: $blockingMode) {
                                        ForEach(BlockingMode.allCases) { mode in
                                            Text(mode.rawValue).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .labelsHidden()
                                    
                                    Text(blockingMode.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Content blocking, scriptlet defusers, and cosmetic element hiding are disabled across all capsules.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    MacOSSectionCard(
                        title: "Filter Lists",
                        systemImage: "checklist",
                        footer: "Declarative ad, tracking, and malware blocking powered by WebKit Native Rules."
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("uBlock filters (Built-in)", isOn: $filterUblockFilters)
                            Toggle("uBlock Badware & Malware Risks", isOn: $filterUblockBadware)
                            Toggle("EasyList (Ad Removal)", isOn: $filterEasyList)
                            Toggle("EasyPrivacy (Tracker Protection)", isOn: $filterEasyPrivacy)
                            Toggle("AdGuard Mobile Ads", isOn: $filterAdGuardMobile)
                            Toggle("URLhaus (Malicious Hosts)", isOn: $filterURLhaus)
                            Toggle("Annoyances (Cookie Warnings & Popups)", isOn: $filterAnnoyances)
                            Toggle("Block Local Network / LAN Probing", isOn: $filterBlockLAN)
                        }
                        .toggleStyle(.checkbox)
                    }
                    .opacity(ublockMasterEnabled ? 1.0 : 0.5)
                    .disabled(!ublockMasterEnabled)
                    
                    MacOSSectionCard(
                        title: "Regional Lists",
                        systemImage: "globe.europe.africa.fill"
                    ) {
                        Toggle("French Regional Filters (fra-0)", isOn: $filterFrench)
                            .toggleStyle(.checkbox)
                    }
                    .opacity(ublockMasterEnabled ? 1.0 : 0.5)
                    .disabled(!ublockMasterEnabled)
                    
                    MacOSSectionCard(
                        title: "Page Cleanup & Scriptlets",
                        systemImage: "wand.and.stars"
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Cosmetic Element Hiding (Collapse Ad Banners)", isOn: $cosmeticHiding)
                            Toggle("Scriptlet Defusers (Neutralize Anti-Adblock)", isOn: $scriptletDefusers)
                        }
                        .toggleStyle(.checkbox)
                    }
                    .opacity(ublockMasterEnabled ? 1.0 : 0.5)
                    .disabled(!ublockMasterEnabled)
                    
                    MacOSSectionCard(
                        title: "Credits & License",
                        systemImage: "doc.text.fill"
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Copyright © 2026 Eddy Barraud. Capsule Browser is free and open-source software licensed under the GNU General Public License v3.0 (GPLv3).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text("Content blocking rulesets and scriptlets are powered by uBlock Origin Lite (uBOL-home) by Raymond Hill (gorhill) and filter list maintainers (EasyList, EasyPrivacy, AdGuard, Peter Lowe, URLhaus), licensed under GPLv3.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 16) {
                                Link("uBlock Origin Lite (GitHub)", destination: URL(string: "https://github.com/uBlockOrigin/uBOL-home")!)
                                Link("GPLv3 License", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
                            }
                            .font(.caption.weight(.medium))
                            .padding(.top, 2)
                        }
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.visible)
            
            Divider()
            
            HStack(spacing: 12) {
                if hasUncompiledChanges {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("List settings changed. Compile rules to apply.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if hasUncompiledChanges {
                    Button {
                        recompileRules()
                    } label: {
                        HStack(spacing: 6) {
                            if isRecompiling {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text(isRecompiling ? "Compiling Rules..." : "Compile new rules")
                                .bold()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(isRecompiling)
                } else {
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 540, idealWidth: 580, maxWidth: 650, minHeight: 520, idealHeight: 620, maxHeight: 780)
        .onAppear {
            if savedSnapshot == nil {
                savedSnapshot = currentSnapshot
            }
        }
    }
    
    private func modeDescription(for mode: WindowPresentationMode) -> String {
        switch mode {
        case .singleWindow:
            return "Replaces the current view inside the main window."
        case .separateWindows:
            return "Opens each capsule in its own independent window."
        case .tabs:
            return "Opens each capsule in a macOS native tab within the main window."
        }
    }
}
#endif
