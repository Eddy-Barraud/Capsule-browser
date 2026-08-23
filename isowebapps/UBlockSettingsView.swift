//
//  UBlockSettingsView.swift
//  isowebapps
//
//  Created on 23/08/2026.
//
//  Description:
//  Preferences interface for managing uBlock Origin Lite content blocking rules.
//  Enables users to select filtering modes (Optimal, Complete, Basic), toggle individual
//  rulesets (EasyList, EasyPrivacy, Malware, Annoyances, LAN protection), enable cosmetic
//  element hiding and scriptlets, and monitor total compiled active rules.
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

/// uBlock Origin Lite configuration and statistics view
struct UBlockSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Persistent Filter List & Mode Preferences in UserDefaults
    @AppStorage("ublock_blocking_mode") private var blockingMode: BlockingMode = .optimal
    @AppStorage("ublock_filter_ublock_filters") private var filterUblockFilters = true
    @AppStorage("ublock_filter_ublock_badware") private var filterUblockBadware = true
    @AppStorage("ublock_filter_easylist") private var filterEasyList = true
    @AppStorage("ublock_filter_easyprivacy") private var filterEasyPrivacy = true
    @AppStorage("ublock_filter_urlhaus") private var filterURLhaus = true
    @AppStorage("ublock_filter_annoyances") private var filterAnnoyances = false
    @AppStorage("ublock_filter_block_lan") private var filterBlockLAN = true
    @AppStorage("ublock_cosmetic_hiding") private var cosmeticHiding = true
    @AppStorage("ublock_scriptlet_defusers") private var scriptletDefusers = true
    
    @State private var isRecompiling = false
    @State private var recompileSuccess = false
    @State private var activeRulesCount = UBlockOriginExtensionManager.shared.activeRulesCount
    @State private var activeListsCount = UBlockOriginExtensionManager.shared.activeListsCount
    
    var body: some View {
        NavigationStack {
            Form {
                // Header Banner
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 38))
                            .foregroundStyle(.blue.gradient)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("uBlock Origin Lite")
                                .font(.title3.bold())
                            Text("Fast, declarative content blocker powered by WebKit Native Rules")
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
                        Text("\(activeRulesCount.formatted()) rules")
                            .foregroundStyle(.secondary)
                            .bold()
                    }
                    HStack {
                        Label("Compiled Rule Lists", systemImage: "list.bullet.rectangle.fill")
                        Spacer()
                        Text("\(activeListsCount) lists")
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Mode Selection
                Section(header: Text("Filtering Level")) {
                    Picker("Mode", selection: $blockingMode) {
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
                    Toggle("URLhaus (Malicious Hosts)", isOn: $filterURLhaus)
                    Toggle("Annoyances (Cookie Warnings & Popups)", isOn: $filterAnnoyances)
                    Toggle("Block Local Network / LAN Probing", isOn: $filterBlockLAN)
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
            .navigationTitle("uBlock Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                activeRulesCount = UBlockOriginExtensionManager.shared.activeRulesCount
                activeListsCount = UBlockOriginExtensionManager.shared.activeListsCount
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 480)
        #endif
    }
    
    /// Triggers background compilation and updates metric counters
    private func recompileRules() {
        isRecompiling = true
        recompileSuccess = false
        
        Task {
            await UBlockOriginExtensionManager.shared.recompile()
            await MainActor.run {
                activeRulesCount = UBlockOriginExtensionManager.shared.activeRulesCount
                activeListsCount = UBlockOriginExtensionManager.shared.activeListsCount
                isRecompiling = false
                recompileSuccess = true
            }
        }
    }
}
