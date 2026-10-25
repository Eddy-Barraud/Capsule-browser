//
//  GeneralSettingsView.swift
//  isowebapps
//
//  Created on 23/08/2026.
//
//  Description:
//  General settings interface for managing window presentation modes (macOS),
//  sleeping tabs / performance, and uBlock Origin Lite content blocking rules.
//

import SwiftUI
import SafariServices

/// Defines the default search engine used by the home search bar and capsule URL bars
public enum SearchEngine: String, CaseIterable, Identifiable {
    case duckDuckGo = "duckduckgo"
    case google = "google"
    case bing = "bing"
    case custom = "custom"
    
    public var id: String { rawValue }
    
    public static let storageKey = "defaultSearchEngine"
    public static let customURLStorageKey = "customSearchEngineURL"
    
    public var displayName: String {
        switch self {
        case .duckDuckGo: return "DuckDuckGo"
        case .google: return "Google"
        case .bing: return "Bing"
        case .custom: return "Custom"
        }
    }
    
    public var label: String {
        switch self {
        case .duckDuckGo: return "DuckDuckGo (duckduckgo.com)"
        case .google: return "Google (google.com)"
        case .bing: return "Bing (bing.com)"
        case .custom: return "Custom URL"
        }
    }
    
    public var defaultQueryPrefix: String {
        switch self {
        case .duckDuckGo: return "https://duckduckgo.com/?q="
        case .google: return "https://www.google.com/search?q="
        case .bing: return "https://www.bing.com/search?q="
        case .custom: return ""
        }
    }
    
    public func homeURLString(customTemplate: String = UserDefaults.standard.string(forKey: Self.customURLStorageKey) ?? "") -> String {
        switch self {
        case .duckDuckGo: return "https://duckduckgo.com"
        case .google: return "https://www.google.com"
        case .bing: return "https://www.bing.com"
        case .custom:
            let normalized = Self.normalizedCustomTemplate(customTemplate)
            if let url = URL(string: normalized), let scheme = url.scheme, let host = url.host {
                return "\(scheme)://\(host)"
            }
            return "https://duckduckgo.com"
        }
    }
    
    public static func normalizedCustomTemplate(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "https://duckduckgo.com/?q=" }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        return "https://" + trimmed
    }
    
    /// Builds the search URL string for a raw search query.
    public func searchURLString(
        for query: String,
        customTemplate: String = UserDefaults.standard.string(forKey: Self.customURLStorageKey) ?? ""
    ) -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        switch self {
        case .duckDuckGo, .google, .bing:
            return defaultQueryPrefix + encoded
        case .custom:
            let template = Self.normalizedCustomTemplate(customTemplate)
            if template.contains("%s") {
                return template.replacingOccurrences(of: "%s", with: encoded)
            } else if template.contains("{query}") {
                return template.replacingOccurrences(of: "{query}", with: encoded)
            } else {
                return template + encoded
            }
        }
    }
    
    /// Resolves user input from a search or address bar into either a direct URL or a search query URL.
    public static func resolveInput(_ rawInput: String) -> String? {
        let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        
        if text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") {
            return text
        } else if text.contains(".") && !text.contains(" ") {
            return "https://" + text
        } else {
            let rawEngine = UserDefaults.standard.string(forKey: storageKey) ?? SearchEngine.duckDuckGo.rawValue
            let engine = SearchEngine(rawValue: rawEngine) ?? .duckDuckGo
            let customURL = UserDefaults.standard.string(forKey: customURLStorageKey) ?? ""
            return engine.searchURLString(for: text, customTemplate: customURL)
        }
    }
}

/// Defines the broad filtering aggression level for content blocking
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

/// Snapshot of settings that require compiling WebKit rule lists when modified
private struct RuleSettingsSnapshot: Equatable {
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

/// Compatibility alias in case of legacy references
typealias UBlockSettingsView = GeneralSettingsView

/// General app configuration, presentation modes, and uBlock Origin Lite view
struct GeneralSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Default Search Engine Preferences
    @AppStorage(SearchEngine.storageKey) private var defaultSearchEngine: SearchEngine = .duckDuckGo
    @AppStorage(SearchEngine.customURLStorageKey) private var customSearchEngineURL: String = ""
    
    #if os(macOS)
    // macOS Window presentation mode
    @AppStorage("windowPresentationMode") private var windowPresentationMode: WindowPresentationMode = .singleWindow
    @AppStorage("sleepingTabsEnabled") private var sleepingTabsEnabled = true
    #endif
    
    // Persistent Filter List & Mode Preferences in UserDefaults
    @AppStorage("ublock_master_enabled") private var ublockMasterEnabled = true
    @AppStorage("ublock_blocking_mode") private var blockingMode: BlockingMode = .complete
    @AppStorage("ublock_filter_ublock_filters") private var filterUblockFilters = true
    @AppStorage("ublock_filter_ublock_badware") private var filterUblockBadware = true
    @AppStorage("ublock_filter_easylist") private var filterEasyList = true
    @AppStorage("ublock_filter_easyprivacy") private var filterEasyPrivacy = true
    @AppStorage("ublock_filter_adguard_mobile") private var filterAdGuardMobile = true
    @AppStorage("ublock_filter_urlhaus") private var filterURLhaus = true
    @AppStorage("ublock_filter_annoyances") private var filterAnnoyances = true
    @AppStorage("ublock_filter_block_lan") private var filterBlockLAN = true
    @AppStorage("ublock_filter_french") private var filterFrench = false
    @AppStorage("ublock_cosmetic_hiding") private var cosmeticHiding = true
    @AppStorage("ublock_scriptlet_defusers") private var scriptletDefusers = true
    
    @ObservedObject private var manager = UBlockOriginExtensionManager.shared
    @ObservedObject private var syncManager = CloudSyncManager.shared
    
    @State private var isRecompiling = false
    @State private var recompileSuccess = false
    @State private var isShowingActivateICloudAlert = false
    @State private var isShowingDeactivateICloudAlert = false
    
    // Snapshot of rule settings at open/last compile time
    @State private var savedSnapshot: RuleSettingsSnapshot?
    
    private var iCloudToggleBinding: Binding<Bool> {
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
    
    private var currentSnapshot: RuleSettingsSnapshot {
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
    
    private var hasUncompiledChanges: Bool {
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
        .iCloudSyncConflictAlert(syncManager: syncManager)
    }
    
    // MARK: - macOS Layout
    #if os(macOS)
    private var macOSLayout: some View {
        VStack(spacing: 0) {
            // Pinned Header
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
            
            // Scrollable Settings Content with Visible Scrollbar
            ScrollView(.vertical) {
                VStack(spacing: 18) {
                    // iCloud Sync
                    macOSSectionCard(
                        title: "iCloud Sync",
                        systemImage: syncManager.isICloudSyncEnabled ? "icloud.fill" : "icloud.slash",
                        badge: syncManager.isICloudSyncEnabled ? "Enabled" : "Local Only",
                        footer: "Synchronize your capsules, groups, and isolated cookies across your devices using iCloud."
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Toggle("Sync Capsules with iCloud", isOn: iCloudToggleBinding)
                                    .toggleStyle(.checkbox)
                                    .disabled(syncManager.isSyncingWithCloud)
                                
                                if syncManager.isSyncingWithCloud {
                                    ProgressView()
                                        .scaleEffect(0.65)
                                    Text("Checking iCloud capsules...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Text(
                                syncManager.isICloudSyncEnabled
                                    ? "Your capsules are currently synced with iCloud."
                                    : "iCloud sync is off by default. Your capsules are stored only on this device."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            
                            if let errorMessage = syncManager.syncStatusError {
                                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    
                    // Default Search Engine
                    macOSSectionCard(
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
                    
                    // Window Opening Modes
                    macOSSectionCard(
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
                    
                    // Performance & Background Throttling
                    macOSSectionCard(
                        title: "Performance & Memory",
                        systemImage: "bolt.fill",
                        footer: "Audio and media playback will continue playing in the background."
                    ) {
                        Toggle("Sleeping Tabs & Background Throttling", isOn: $sleepingTabsEnabled)
                            .toggleStyle(.checkbox)
                        Text("Freezes background tabs and inactive windows to reduce CPU and memory usage, dedicating system resources to the active capsule.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // uBlock Origin Lite Protection Status & Level
                    macOSSectionCard(
                        title: "uBlock Origin Lite",
                        systemImage: ublockMasterEnabled ? "shield.checkered" : "shield.slash",
                        badge: ublockMasterEnabled ? "\(manager.activeRulesCount.formatted()) active rules" : "Disabled"
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle("Enable uBlock Origin Lite Protection", isOn: $ublockMasterEnabled)
                                .toggleStyle(.checkbox)
                                .font(.subheadline.weight(.semibold))
                            
                            if ublockMasterEnabled {
                                // Active status summary
                                HStack(spacing: 24) {
                                    Label("\(manager.activeRulesCount.formatted()) rules", systemImage: "bolt.shield.fill")
                                        .font(.subheadline.weight(.medium))
                                    Label("\(manager.activeListsCount) compiled lists", systemImage: "list.bullet.rectangle.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                                
                                Divider()
                                
                                // Filtering Level
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
                    
                    // Filter Lists
                    macOSSectionCard(
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
                    
                    // Regional Lists
                    macOSSectionCard(
                        title: "Regional Lists",
                        systemImage: "globe.europe.africa.fill"
                    ) {
                        Toggle("French Regional Filters (fra-0)", isOn: $filterFrench)
                            .toggleStyle(.checkbox)
                    }
                    .opacity(ublockMasterEnabled ? 1.0 : 0.5)
                    .disabled(!ublockMasterEnabled)
                    
                    // Page Cleanup & Scriptlet Defusers
                    macOSSectionCard(
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
                    
                    // Credits & License
                    macOSSectionCard(
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
            
            // Pinned Bottom Bar
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
    
    @ViewBuilder
    private func macOSSectionCard<Content: View>(
        title: String,
        systemImage: String? = nil,
        badge: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.blue)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                if let badge {
                    Spacer()
                    Text(badge)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
    #endif
    
    // MARK: - iOS Layout
    #if os(iOS)
    private var iOSLayout: some View {
        NavigationStack {
            Form {
                // Header Banner
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
                
                // iCloud Sync
                Section(
                    header: Text("iCloud Sync"),
                    footer: Text(
                        syncManager.isICloudSyncEnabled
                            ? "Your capsules, groups, and isolated cookies are synced across your devices via iCloud."
                            : "iCloud sync is off by default. Your capsules are stored only on this device."
                    )
                ) {
                    Toggle("Sync Capsules with iCloud", isOn: iCloudToggleBinding)
                        .disabled(syncManager.isSyncingWithCloud)
                    
                    if syncManager.isSyncingWithCloud {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Checking iCloud capsules...")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if let errorMessage = syncManager.syncStatusError {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                
                // Default Search Engine
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
                
                // Master Toggle
                Section(header: Text("uBlock Origin Lite")) {
                    Toggle("Enable Content Blocking", isOn: $ublockMasterEnabled)
                }
                
                // Live Metric Status
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
                    // Mode Selection
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
                    
                    // Submodule Ruleset Toggles
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
                    
                    // Regional Ruleset Toggles
                    Section(header: Text("Regional Lists")) {
                        Toggle("French Regional Filters (fra-0)", isOn: $filterFrench)
                    }
                    
                    // Scriptlets and Cosmetic DOM Cleanup
                    Section(header: Text("Page Cleanup & Defusers")) {
                        Toggle("Cosmetic Element Hiding (Collapse Ad Banners)", isOn: $cosmeticHiding)
                        Toggle("Scriptlet Defusers (Neutralize Anti-Adblock)", isOn: $scriptletDefusers)
                    }
                }
                
                // Credits & License
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
    #endif
    
    /// Triggers background compilation and updates metric counters
    private func recompileRules() {
        isRecompiling = true
        recompileSuccess = false
        
        Task {
            await manager.recompile()
            await MainActor.run {
                isRecompiling = false
                recompileSuccess = true
                savedSnapshot = currentSnapshot
            }
        }
    }
}
