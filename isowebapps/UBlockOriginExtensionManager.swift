//
//  UBlockOriginExtensionManager.swift
//  isowebapps
//
//  Created on 23/08/2026.
//
//  Description:
//  Core engine orchestrating uBlock Origin Lite declarativeNetRequest rules,
//  scriptlet defusers, and cosmetic CSS filters. Manages parallel compilation of
//  independent `WKContentRuleList` instances, dynamic re-compilation on preference
//  updates, and injection into `WKWebViewConfiguration`.
//

import Foundation
import WebKit
import Combine

/// Loads uBlock Origin Lite DNR rules, cosmetic filter scripts, and WebKit content blocker rules
/// to provide full ad-blocking and privacy protection inside WKWebView.
public final class UBlockOriginExtensionManager: ObservableObject {
    public static let shared = UBlockOriginExtensionManager()
    
    /// Array of actively compiled WebKit native rule lists
    private var compiledRuleLists: [WKContentRuleList] = []
    
    /// Injected user scripts for DOM cosmetic hiding and scriptlet defusers
    private var cosmeticUserScripts: [WKUserScript] = []
    
    private var isInitialized = false
    @Published public private(set) var activeRulesCount: Int = 0
    @Published public private(set) var activeListsCount: Int = 0
    
    private init() {}
    
    /// Prepares content blocking rule lists and user scripts asynchronously during app startup
    public func prepare() async {
        guard !isInitialized else { return }
        let currentCompilerVersion = 2
        let savedCompilerVersion = UserDefaults.standard.integer(forKey: "ublock_compiler_version")
        let needsForcedRecompile = (savedCompilerVersion < currentCompilerVersion)
        await loadRulesAndScriptsAsync(forceRecompile: needsForcedRecompile)
        if needsForcedRecompile {
            UserDefaults.standard.set(currentCompilerVersion, forKey: "ublock_compiler_version")
        }
        isInitialized = true
    }
    
    /// Recompiles rule lists dynamically based on updated user settings from the settings view
    public func recompile() async {
        await loadRulesAndScriptsAsync(forceRecompile: true)
    }
    
    /// Applies active uBlock Origin rules and scripts to a `WKWebViewConfiguration`
    public func applyToConfiguration(_ config: WKWebViewConfiguration) {
        for ruleList in compiledRuleLists {
            config.userContentController.add(ruleList)
        }
        
        for script in cosmeticUserScripts {
            config.userContentController.addUserScript(script)
        }
    }
    
    /// Removes compiled uBlock Origin rules and cosmetic user scripts from a `WKWebViewConfiguration`
    public func removeFromConfiguration(_ config: WKWebViewConfiguration) {
        for ruleList in compiledRuleLists {
            config.userContentController.remove(ruleList)
        }
        config.userContentController.removeAllUserScripts()
    }
    
    /// Loads enabled rulesets from bundle/symlinks, converts them, and compiles them in parallel
    private func loadRulesAndScriptsAsync(forceRecompile: Bool = false) async {
        let defaults = UserDefaults.standard
        
        let ublockFilters = defaults.object(forKey: "ublock_filter_ublock_filters") as? Bool ?? true
        let ublockBadware = defaults.object(forKey: "ublock_filter_ublock_badware") as? Bool ?? true
        let easylist = defaults.object(forKey: "ublock_filter_easylist") as? Bool ?? true
        let easyprivacy = defaults.object(forKey: "ublock_filter_easyprivacy") as? Bool ?? true
        let adguardMobile = defaults.object(forKey: "ublock_filter_adguard_mobile") as? Bool ?? true
        let urlhaus = defaults.object(forKey: "ublock_filter_urlhaus") as? Bool ?? true
        let annoyances = defaults.object(forKey: "ublock_filter_annoyances") as? Bool ?? true
        let blockLan = defaults.object(forKey: "ublock_filter_block_lan") as? Bool ?? true
        let frenchFilters = defaults.object(forKey: "ublock_filter_french") as? Bool ?? false
        let cosmeticHiding = defaults.object(forKey: "ublock_cosmetic_hiding") as? Bool ?? true
        let scriptletDefusers = defaults.object(forKey: "ublock_scriptlet_defusers") as? Bool ?? true
        
        // Find uBlock rulesets from shared folder / Bundle
        let rulesetURLs = locateRulesetJSONFiles(
            includeUblockFilters: ublockFilters,
            includeUblockBadware: ublockBadware,
            includeEasyList: easylist,
            includeEasyPrivacy: easyprivacy,
            includeAdguardMobile: adguardMobile,
            includeURLhaus: urlhaus,
            includeAnnoyances: annoyances,
            includeBlockLan: blockLan,
            includeFrenchFilters: frenchFilters
        )
        
        #if DEBUG
        print("[UBlockOriginExtensionManager] Found \(rulesetURLs.count) ruleset files to process:")
        for url in rulesetURLs {
            print("  -> \(url.lastPathComponent) at \(url.path)")
        }
        #endif
        
        var newCompiledLists: [WKContentRuleList] = []
        var totalRuleCount = 0
        
        for url in rulesetURLs {
            let listIdentifier = "uBlock_" + url.deletingPathExtension().lastPathComponent
            
            let existingList: WKContentRuleList? = try? await withCheckedThrowingContinuation { continuation in
                WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: listIdentifier) { list, error in
                    if let list = list {
                        continuation.resume(returning: list)
                    } else if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            
            if !forceRecompile, existingList != nil {
                #if DEBUG
                print("[UBlockOriginExtensionManager] Loaded existing compiled ruleset: \(listIdentifier)")
                #endif
                newCompiledLists.append(existingList!)
                totalRuleCount += defaults.integer(forKey: "ublock_rulecount_\(listIdentifier)")
            } else {
                if forceRecompile {
                    _ = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        WKContentRuleListStore.default().removeContentRuleList(forIdentifier: listIdentifier) { error in
                            if let error = error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: ())
                            }
                        }
                    }
                }
                
                if let data = try? Data(contentsOf: url),
                   let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                    let wkRules = UBlockRuleCompiler.shared.convertDNRToWebKitRuleList(dnrRules: json)
                    
                    #if DEBUG
                    print("[UBlockOriginExtensionManager] \(url.lastPathComponent): converted \(json.count) DNR rules to \(wkRules.count) WebKit rules")
                    #endif
                    
                    if let compiled = await compileSingleList(identifier: listIdentifier, rules: wkRules) {
                        newCompiledLists.append(compiled)
                        totalRuleCount += wkRules.count
                        defaults.set(wkRules.count, forKey: "ublock_rulecount_\(listIdentifier)")
                    }
                } else {
                    #if DEBUG
                    print("[UBlockOriginExtensionManager] Warning: failed to parse JSON from \(url.path)")
                    #endif
                }
            }
        }
        
        // Fallback or basic rules if no files compiled
        if newCompiledLists.isEmpty {
            #if DEBUG
            print("[UBlockOriginExtensionManager] No ruleset files compiled! Using default fallback adblock rules.")
            #endif
            let fallbackRules = defaultFallbackAdblockRules()
            if let fallbackCompiled = await compileSingleList(identifier: "uBlock_fallback", rules: fallbackRules) {
                newCompiledLists.append(fallbackCompiled)
                totalRuleCount += fallbackRules.count
            }
        }
        
        
        await MainActor.run {
            self.compiledRuleLists = newCompiledLists
            self.activeRulesCount = totalRuleCount
            self.activeListsCount = newCompiledLists.count
        }
        
        #if DEBUG
        print("[UBlockOriginExtensionManager] Total active rule lists: \(newCompiledLists.count), total rules active: \(totalRuleCount)")
        #endif
        
        // 2. Load cosmetic scripts and scriptlets
        var scripts: [WKUserScript] = []
        
        var activeRulesetIds: [String] = []
        if ublockFilters { activeRulesetIds.append("ublock-filters") }
        if ublockBadware { activeRulesetIds.append("ublock-badware") }
        if easylist { activeRulesetIds.append("easylist") }
        if easyprivacy { activeRulesetIds.append("easyprivacy") }
        if adguardMobile { activeRulesetIds.append("adguard-mobile") }
        if urlhaus { activeRulesetIds.append("urlhaus-full") }
        if annoyances {
            activeRulesetIds.append("annoyances-cookies")
            activeRulesetIds.append("annoyances-overlays")
        }
        if blockLan { activeRulesetIds.append("block-lan") }
        if frenchFilters { activeRulesetIds.append("fra-0") }
        
        // A. Scriptlet Defusers (MAIN & ISOLATED worlds)
        if scriptletDefusers {
            for rid in activeRulesetIds {
                // 1. Main world scriptlet (.page)
                if let mainURL = locateScriptFile(named: "scriptlet-main-\(rid).js"),
                   let code = try? String(contentsOf: mainURL, encoding: .utf8), !code.isEmpty {
                    let mainScript = WKUserScript(
                        source: code,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: false,
                        in: .page
                    )
                    scripts.append(mainScript)
                    #if DEBUG
                    print("[UBlockOriginExtensionManager] Injected MAIN scriptlet: \(mainURL.lastPathComponent)")
                    #endif
                }
                
                // 2. Isolated world scriptlet (.defaultClient)
                if let isoURL = locateScriptFile(named: "scriptlet-isolated-\(rid).js"),
                   let code = try? String(contentsOf: isoURL, encoding: .utf8), !code.isEmpty {
                    let isoScript = WKUserScript(
                        source: code,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: false,
                        in: .defaultClient
                    )
                    scripts.append(isoScript)
                    #if DEBUG
                    print("[UBlockOriginExtensionManager] Injected ISOLATED scriptlet: \(isoURL.lastPathComponent)")
                    #endif
                }
            }
        }
        
        // B. Cosmetic CSS Hiding (ISOLATED world)
        if cosmeticHiding {
            for rid in activeRulesetIds {
                if let cosURL = locateScriptFile(named: "cosmetic-specific-\(rid).js"),
                   let code = try? String(contentsOf: cosURL, encoding: .utf8), !code.isEmpty {
                    let cosScript = WKUserScript(
                        source: code,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: false,
                        in: .defaultClient
                    )
                    scripts.append(cosScript)
                    #if DEBUG
                    print("[UBlockOriginExtensionManager] Injected specific cosmetic CSS: \(cosURL.lastPathComponent)")
                    #endif
                }
            }
            
            // Generic cosmetic hiding for standard ad containers across web pages
            let genericHideCSS = """
            (function() {
                const style = document.createElement('style');
                style.type = 'text/css';
                style.id = 'ublock-cosmetic-generic';
                style.innerHTML = `
                    .ad, .ads, .ad-banner, .ad-placement, .ad-container,
                    .sponsored-post, [data-ad-unit], [data-ad-slot],
                    .taboola, .outbrain, .google-ad, .adsbygoogle,
                    div[id^="div-gpt-ad"], div[id^="google_ads_iframe"],
                    .native-ad, .ad-box, .banner-ads, #sponsorText {
                        display: none !important;
                        visibility: hidden !important;
                        height: 0 !important;
                        width: 0 !important;
                        opacity: 0 !important;
                        pointer-events: none !important;
                    }
                `;
                (document.head || document.documentElement).appendChild(style);
            })();
            """
            let genericScript = WKUserScript(
                source: genericHideCSS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .defaultClient
            )
            scripts.append(genericScript)
        }
        
        self.cosmeticUserScripts = scripts
        #if DEBUG
        print("[UBlockOriginExtensionManager] Total active user scripts: \(scripts.count)")
        #endif
    }
    
    /// Compiles a single rule list into a `WKContentRuleList`, running chunked fallback if needed
    private func compileSingleList(identifier: String, rules: [[String: Any]]) async -> WKContentRuleList? {
        guard !rules.isEmpty else { return nil }
        
        // 1. Attempt compiling full ruleset list
        if let jsonData = try? JSONSerialization.data(withJSONObject: rules, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            do {
                let ruleList = try await WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: identifier,
                    encodedContentRuleList: jsonString
                )
                #if DEBUG
                print("[UBlockOriginExtensionManager] Successfully compiled \(identifier) (\(rules.count) rules)")
                #endif
                return ruleList
            } catch {
                #if DEBUG
                print("[UBlockOriginExtensionManager] \(identifier) batch compile failed: \(error.localizedDescription). Filtering rules...")
                #endif
            }
        }
        
        // 2. Filter chunk by chunk to eliminate invalid rules
        var verifiedRules: [[String: Any]] = []
        let chunkSize = 500
        let chunks = stride(from: 0, to: rules.count, by: chunkSize).map {
            Array(rules[$0 ..< min($0 + chunkSize, rules.count)])
        }
        
        for (idx, chunk) in chunks.enumerated() {
            if let chunkData = try? JSONSerialization.data(withJSONObject: chunk, options: []),
               let chunkString = String(data: chunkData, encoding: .utf8) {
                do {
                    _ = try await WKContentRuleListStore.default().compileContentRuleList(
                        forIdentifier: "temp_\(identifier)_\(idx)",
                        encodedContentRuleList: chunkString
                    )
                    verifiedRules.append(contentsOf: chunk)
                } catch {
                    // Filter single rule within failing chunk
                    for (sIdx, singleRule) in chunk.enumerated() {
                        if let sData = try? JSONSerialization.data(withJSONObject: [singleRule], options: []),
                           let sString = String(data: sData, encoding: .utf8) {
                            if let _ = try? await WKContentRuleListStore.default().compileContentRuleList(
                                forIdentifier: "temp_single_\(identifier)_\(sIdx)",
                                encodedContentRuleList: sString
                            ) {
                                verifiedRules.append(singleRule)
                            }
                        }
                    }
                }
            }
        }
        
        if let validData = try? JSONSerialization.data(withJSONObject: verifiedRules, options: []),
           let validString = String(data: validData, encoding: .utf8) {
            if let ruleList = try? await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: validString
            ) {
                #if DEBUG
                print("[UBlockOriginExtensionManager] Successfully compiled \(identifier): \(verifiedRules.count) verified rules (from \(rules.count))")
                #endif
                return ruleList
            }
        }
        return nil
    }
    
    /// Locates ruleset JSON files across app bundles, submodules, and symlinks
    private func locateRulesetJSONFiles(
        includeUblockFilters: Bool,
        includeUblockBadware: Bool,
        includeEasyList: Bool,
        includeEasyPrivacy: Bool,
        includeAdguardMobile: Bool,
        includeURLhaus: Bool,
        includeAnnoyances: Bool,
        includeBlockLan: Bool,
        includeFrenchFilters: Bool
    ) -> [URL] {
        var targets: [String] = []
        if includeUblockFilters { targets.append("ublock-filters.json") }
        if includeUblockBadware { targets.append("ublock-badware.json") }
        if includeEasyList { targets.append("easylist.json") }
        if includeEasyPrivacy { targets.append("easyprivacy.json") }
        if includeAdguardMobile { targets.append("adguard-mobile.json") }
        if includeURLhaus { targets.append("urlhaus-full.json") }
        if includeAnnoyances {
            targets.append("annoyances-cookies.json")
            targets.append("annoyances-overlays.json")
        }
        if includeBlockLan { targets.append("block-lan.json") }
        if includeFrenchFilters { targets.append("fra-0.json") }
        
        var urls: [URL] = []
        
        // 1. Check Bundle resources in various common locations
        let bundleCandidates = [
            Bundle.main.url(forResource: "rulesets/main", withExtension: nil),
            Bundle.main.url(forResource: "rulesets", withExtension: nil),
            Bundle.main.resourceURL?.appendingPathComponent("rulesets/main"),
            Bundle.main.resourceURL?.appendingPathComponent("rulesets"),
            Bundle.main.resourceURL
        ].compactMap { $0 }
        
        for t in targets {
            var found = false
            for baseURL in bundleCandidates {
                let fileURL = baseURL.appendingPathComponent(t)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    urls.append(fileURL)
                    found = true
                    break
                }
            }
            if !found {
                if let directURL = Bundle.main.url(forResource: (t as NSString).deletingPathExtension, withExtension: (t as NSString).pathExtension) {
                    urls.append(directURL)
                }
            }
        }
        
        // 2. Fallback relative shared folder or bundle folder check for simulator/macOS development
        if urls.isEmpty {
            let relativePaths = [
                "isowebapps/rulesets/main",
                "shared/uBOL-home/chromium/rulesets/main"
            ]
            let currentDir = FileManager.default.currentDirectoryPath
            for t in targets {
                for rel in relativePaths {
                    let fullPath = "\(currentDir)/\(rel)/\(t)"
                    if FileManager.default.fileExists(atPath: fullPath) {
                        urls.append(URL(fileURLWithPath: fullPath))
                        break
                    }
                }
            }
        }
        
        return urls
    }
    
    /// Locates a script file (.js) across app bundles, submodules, and development paths
    private func locateScriptFile(named filename: String) -> URL? {
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        
        // 1. Direct bundle lookup by name and extension
        if let directURL = Bundle.main.url(forResource: name, withExtension: ext) {
            return directURL
        }
        
        // 2. Bundle resource URL candidates
        let bundleCandidates = [
            Bundle.main.resourceURL?.appendingPathComponent("rulesets/scripting"),
            Bundle.main.resourceURL?.appendingPathComponent("rulesets"),
            Bundle.main.resourceURL
        ].compactMap { $0 }
        
        for baseURL in bundleCandidates {
            let fileURL = baseURL.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }
        
        // 3. Fallback relative paths for local development / simulator
        let currentDir = FileManager.default.currentDirectoryPath
        let relativePaths = [
            "isowebapps/rulesets/scripting",
            "rulesets/scripting"
        ]
        for rel in relativePaths {
            let fullPath = "\(currentDir)/\(rel)/\(filename)"
            if FileManager.default.fileExists(atPath: fullPath) {
                return URL(fileURLWithPath: fullPath)
            }
        }
        
        return nil
    }
    
    /// Built-in fallback rule set used if no external ruleset files are available
    private func defaultFallbackAdblockRules() -> [[String: Any]] {
        return [
            [
                "trigger": [
                    "url-filter": ".*",
                    "if-domain": ["*doubleclick.net", "*googlesyndication.com", "*google-analytics.com", "*adservice.google.com", "*taboola.com", "*outbrain.com", "*adnxs.com", "*amazon-adsystem.com", "*rubiconproject.com", "*popads.net", "*criteo.com"]
                ],
                "action": [
                    "type": "block"
                ]
            ],
            [
                "trigger": [
                    "url-filter": ".*\\/ads.*",
                    "load-type": ["third-party"],
                    "resource-type": ["script", "image", "raw"]
                ],
                "action": [
                    "type": "block"
                ]
            ],
            [
                "trigger": [
                    "url-filter": ".*\\/pagead.*",
                    "load-type": ["third-party"],
                    "resource-type": ["script", "image", "raw"]
                ],
                "action": [
                    "type": "block"
                ]
            ],
            [
                "trigger": [
                    "url-filter": ".*\\/analytics.*",
                    "load-type": ["third-party"],
                    "resource-type": ["script", "image", "raw"]
                ],
                "action": [
                    "type": "block"
                ]
            ]
        ]
    }
}
