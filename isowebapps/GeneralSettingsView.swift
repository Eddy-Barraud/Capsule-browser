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

/// Compatibility alias in case of legacy references
typealias UBlockSettingsView = GeneralSettingsView

/// General app configuration, presentation modes, and uBlock Origin Lite view
struct GeneralSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    #if os(macOS)
    // macOS Window presentation mode
    @AppStorage("windowPresentationMode") private var windowPresentationMode: WindowPresentationMode = .singleWindow
    @AppStorage("sleepingTabsEnabled") private var sleepingTabsEnabled = true
    #endif
    
    // Persistent Filter List & Mode Preferences in UserDefaults
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
    
    @State private var isRecompiling = false
    @State private var recompileSuccess = false
    
    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
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
                        systemImage: "shield.checkered",
                        badge: "\(manager.activeRulesCount.formatted()) active rules"
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
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
                    
                    // Regional Lists
                    macOSSectionCard(
                        title: "Regional Lists",
                        systemImage: "globe.europe.africa.fill"
                    ) {
                        Toggle("French Regional Filters (fra-0)", isOn: $filterFrench)
                            .toggleStyle(.checkbox)
                    }
                    
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
                    
                    // Recompile action card
                    macOSSectionCard(
                        title: "Apply Rule Changes",
                        systemImage: "arrow.triangle.2.circlepath"
                    ) {
                        HStack {
                            Text("Recompiles WebKit rulesets with your currently enabled filter lists.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                recompileRules()
                            } label: {
                                HStack(spacing: 6) {
                                    if isRecompiling {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                                    Text(recompileSuccess ? "Rules Updated ✓" : "Apply & Recompile")
                                        .font(.subheadline.bold())
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRecompiling)
                        }
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.visible)
            
            Divider()
            
            // Pinned Bottom Bar
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 540, idealWidth: 580, maxWidth: 650, minHeight: 520, idealHeight: 620, maxHeight: 780)
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
            
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(16)
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
                
                // Live Metric Status
                Section(header: Text("Protection Status")) {
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
                }
                
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
                
                // Manual Recompilation Trigger
                Section {
                    Button {
                        recompileRules()
                    } label: {
                        HStack {
                            Spacer()
                            if isRecompiling {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .padding(.trailing, 4)
                            }
                            Text(recompileSuccess ? "Rules Updated ✓" : "Apply & Recompile Rules")
                                .bold()
                            Spacer()
                        }
                    }
                    .disabled(isRecompiling)
                }
            }
            .navigationTitle("General Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
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
            }
        }
    }
}
