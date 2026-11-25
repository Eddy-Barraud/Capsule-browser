//
//  UBlockOriginExtensionManager.swift
//  isowebapps
//
//  Created on 23/08/2026.
//
//  Description:
//  Core engine orchestrating uBlock Origin Lite declarativeNetRequest rules,
//  scriptlet defusers, and cosmetic CSS filters. Manages lifecycle, caching,
//  and injection into `WKWebViewConfiguration`.
//

import Foundation
import WebKit
import Combine

/// Snapshot of user content-blocking settings read once per load/compile pass.
nonisolated struct UBlockFilterConfiguration: Sendable, Equatable {
    let masterEnabled: Bool
    let blockingModeRaw: String
    let ublockFilters: Bool
    let ublockBadware: Bool
    let easylist: Bool
    let easyprivacy: Bool
    let adguardMobile: Bool
    let urlhaus: Bool
    let annoyances: Bool
    let blockLan: Bool
    let frenchFilters: Bool
    let cosmeticHiding: Bool
    let scriptletDefusers: Bool
    
    var effectiveAnnoyances: Bool {
        annoyances && blockingModeRaw != "Basic"
    }
    
    var effectiveCosmeticHiding: Bool {
        cosmeticHiding && blockingModeRaw != "Basic"
    }
    
    var effectiveScriptletDefusers: Bool {
        scriptletDefusers && blockingModeRaw != "Basic"
    }
    
    var anyFilterListEnabled: Bool {
        ublockFilters || ublockBadware || easylist || easyprivacy ||
        adguardMobile || urlhaus || effectiveAnnoyances || blockLan || frenchFilters
    }
    
    var activeRulesetIDs: [String] {
        var ids: [String] = []
        if ublockFilters { ids.append("ublock-filters") }
        if ublockBadware { ids.append("ublock-badware") }
        if easylist { ids.append("easylist") }
        if easyprivacy { ids.append("easyprivacy") }
        if adguardMobile { ids.append("adguard-mobile") }
        if urlhaus { ids.append("urlhaus-full") }
        if effectiveAnnoyances {
            ids.append("annoyances-cookies")
            ids.append("annoyances-overlays")
        }
        if blockLan { ids.append("block-lan") }
        if frenchFilters { ids.append("fra-0") }
        return ids
    }
    
    static func fromDefaults(_ defaults: UserDefaults = .standard) -> UBlockFilterConfiguration {
        UBlockFilterConfiguration(
            masterEnabled: defaults.object(forKey: "ublock_master_enabled") as? Bool ?? true,
            blockingModeRaw: defaults.string(forKey: "ublock_blocking_mode") ?? "Complete",
            ublockFilters: defaults.object(forKey: "ublock_filter_ublock_filters") as? Bool ?? true,
            ublockBadware: defaults.object(forKey: "ublock_filter_ublock_badware") as? Bool ?? true,
            easylist: defaults.object(forKey: "ublock_filter_easylist") as? Bool ?? true,
            easyprivacy: defaults.object(forKey: "ublock_filter_easyprivacy") as? Bool ?? true,
            adguardMobile: defaults.object(forKey: "ublock_filter_adguard_mobile") as? Bool ?? true,
            urlhaus: defaults.object(forKey: "ublock_filter_urlhaus") as? Bool ?? true,
            annoyances: defaults.object(forKey: "ublock_filter_annoyances") as? Bool ?? true,
            blockLan: defaults.object(forKey: "ublock_filter_block_lan") as? Bool ?? true,
            frenchFilters: defaults.object(forKey: "ublock_filter_french") as? Bool ?? false,
            cosmeticHiding: defaults.object(forKey: "ublock_cosmetic_hiding") as? Bool ?? true,
            scriptletDefusers: defaults.object(forKey: "ublock_scriptlet_defusers") as? Bool ?? true
        )
    }
}

/// Loads uBlock Origin Lite DNR rules, cosmetic filter scripts, and WebKit content blocker rules
/// to provide full ad-blocking and privacy protection inside `WKWebView`.
@MainActor
public final class UBlockOriginExtensionManager: ObservableObject {
    public static let shared = UBlockOriginExtensionManager()
    
    static let currentCompilerVersion = 3
    
    /// Notification broadcast when rules and scripts are recompiled
    public nonisolated static let didUpdateRulesNotification = Notification.Name("UBlockOriginDidUpdateRulesNotification")
    
    /// Notification broadcast when a specific capsule's uBlock toggle is updated in settings
    public nonisolated static let capsuleUBlockSettingChangedNotification = Notification.Name("UBlockOriginCapsuleUBlockSettingChangedNotification")
    
    var compiledRuleLists: [WKContentRuleList] = []
    var cosmeticUserScripts: [WKUserScript] = []
    
    var isInitialized = false
    var loadTask: Task<Void, Never>?
    var loadGeneration: UInt64 = 0
    @Published public internal(set) var activeRulesCount: Int = 0
    @Published public internal(set) var activeListsCount: Int = 0
    @Published var compiledConfiguration: UBlockFilterConfiguration? = nil
    
    public var isLoaded: Bool {
        isInitialized
    }
    
    public var hasInMemoryCaches: Bool {
        !compiledRuleLists.isEmpty || !cosmeticUserScripts.isEmpty
    }
    
    private init() {}
    
    /// Prepares content blocking rule lists and user scripts asynchronously during app startup or reopen.
    public func prepare() async {
        if isInitialized { return }
        if let existing = loadTask {
            await existing.value
            return
        }
        
        loadGeneration &+= 1
        let expectedGeneration = loadGeneration
        let savedCompilerVersion = UserDefaults.standard.integer(forKey: "ublock_compiler_version")
        let needsForcedRecompile = (savedCompilerVersion < Self.currentCompilerVersion)
        
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadRulesAndScriptsAsync(
                forceRecompile: needsForcedRecompile,
                expectedGeneration: expectedGeneration
            )
            guard self.loadGeneration == expectedGeneration, !Task.isCancelled else { return }
            if needsForcedRecompile {
                UserDefaults.standard.set(Self.currentCompilerVersion, forKey: "ublock_compiler_version")
            }
            self.isInitialized = true
        }
        loadTask = task
        await task.value
        if loadGeneration == expectedGeneration {
            loadTask = nil
        }
    }
    
    /// Recompiles rule lists dynamically based on updated user settings from the settings view.
    public func recompile() async {
        loadTask?.cancel()
        loadTask = nil
        loadGeneration &+= 1
        let expectedGeneration = loadGeneration
        isInitialized = false
        
        await loadRulesAndScriptsAsync(forceRecompile: true, expectedGeneration: expectedGeneration)
        guard loadGeneration == expectedGeneration, !Task.isCancelled else { return }
        UserDefaults.standard.set(Self.currentCompilerVersion, forKey: "ublock_compiler_version")
        isInitialized = true
        NotificationCenter.default.post(name: Self.didUpdateRulesNotification, object: nil)
    }
    
    /// Releases in-memory compiled rule lists and user scripts when no web capsules are active.
    /// Keeps `activeRulesCount` and `activeListsCount` intact so Settings UI remains accurate.
    public func releaseInMemoryCaches() {
        loadGeneration &+= 1
        loadTask?.cancel()
        loadTask = nil
        compiledRuleLists.removeAll(keepingCapacity: false)
        cosmeticUserScripts.removeAll(keepingCapacity: false)
        isInitialized = false
        #if DEBUG
        print("[Memory] UBlockOriginExtensionManager released in-memory rule lists and user scripts")
        #endif
    }
    
    /// Applies active uBlock Origin rules and scripts to a `WKWebViewConfiguration`
    public func applyToConfiguration(_ config: WKWebViewConfiguration) {
        removeFromConfiguration(config)
        
        let masterEnabled = UserDefaults.standard.object(forKey: "ublock_master_enabled") as? Bool ?? true
        guard masterEnabled else { return }
        
        for ruleList in compiledRuleLists {
            config.userContentController.add(ruleList)
        }
        
        for script in cosmeticUserScripts {
            config.userContentController.addUserScript(script)
        }
    }
    
    /// Removes compiled uBlock Origin rules and cosmetic user scripts from a `WKWebViewConfiguration`
    public func removeFromConfiguration(_ config: WKWebViewConfiguration) {
        config.userContentController.removeAllContentRuleLists()
        config.userContentController.removeAllUserScripts()
    }
}
