//
//  UBlockOriginExtensionManager+Compilation.swift
//  isowebapps
//
//  Description:
//  Multi-core DNR ruleset parsing, concurrent `WKContentRuleList` compilation,
//  scriptlet/cosmetic resource loading, and fallback rule generation.
//

import Foundation
import WebKit

private nonisolated struct PreparedRulesetPayload: Sendable {
    let index: Int
    let identifier: String
    let url: URL
    let encodedJSON: String
    let ruleCount: Int
}

private nonisolated struct ScriptLoadSpec: Sendable {
    let order: Int
    let url: URL
    let injectionTime: WKUserScriptInjectionTime
    let world: WKContentWorld
}

private nonisolated struct LoadedScriptPayload: Sendable {
    let order: Int
    let code: String
    let injectionTime: WKUserScriptInjectionTime
    let world: WKContentWorld
}

extension UBlockOriginExtensionManager {
    /// Loads enabled rulesets from bundle/symlinks, converts them in parallel on background cores, and compiles them.
    func loadRulesAndScriptsAsync(forceRecompile: Bool = false, expectedGeneration: UInt64) async {
        let defaults = UserDefaults.standard
        let config = UBlockFilterConfiguration.fromDefaults(defaults)
        
        guard config.masterEnabled else {
            guard loadGeneration == expectedGeneration, !Task.isCancelled else { return }
            self.compiledRuleLists = []
            self.cosmeticUserScripts = []
            self.activeRulesCount = 0
            self.activeListsCount = 0
            self.compiledConfiguration = config
            return
        }
        
        let rulesetURLs = Self.locateRulesetJSONFiles(for: config)
        let availableIdentifiers: Set<String> = await withCheckedContinuation { continuation in
            WKContentRuleListStore.default().getAvailableContentRuleListIdentifiers { identifiers in
                continuation.resume(returning: Set(identifiers ?? []))
            }
        }
        guard loadGeneration == expectedGeneration, !Task.isCancelled else { return }
        
        // 1. Concurrent lookup for already-compiled rule lists when not force-recompiling
        var compiledByIndex: [Int: (list: WKContentRuleList, count: Int)] = [:]
        var indicesToCompile: [(index: Int, url: URL, identifier: String, hasStoredList: Bool)] = []
        
        if !forceRecompile {
            let lookupTargets = rulesetURLs.enumerated().map { idx, url -> (Int, URL, String, Bool) in
                let identifier = "uBlock_" + url.deletingPathExtension().lastPathComponent
                return (idx, url, identifier, availableIdentifiers.contains(identifier))
            }
            
            let lookupResults: [(Int, URL, String, Bool, WKContentRuleList?)] = await withTaskGroup(
                of: (Int, URL, String, Bool, WKContentRuleList?).self
            ) { group in
                for (idx, url, identifier, hasStored) in lookupTargets {
                    group.addTask { @MainActor in
                        guard hasStored else { return (idx, url, identifier, false, nil) }
                        let list = try? await Self.lookUpContentRuleList(identifier: identifier)
                        return (idx, url, identifier, true, list)
                    }
                }
                var collected: [(Int, URL, String, Bool, WKContentRuleList?)] = []
                collected.reserveCapacity(lookupTargets.count)
                for await result in group {
                    collected.append(result)
                }
                return collected
            }
            
            for (idx, url, identifier, hasStored, existingList) in lookupResults {
                if let existingList {
                    let savedCount = defaults.integer(forKey: "ublock_rulecount_\(identifier)")
                    compiledByIndex[idx] = (existingList, savedCount)
                } else {
                    indicesToCompile.append((idx, url, identifier, hasStored))
                }
            }
        } else {
            for (idx, url) in rulesetURLs.enumerated() {
                let identifier = "uBlock_" + url.deletingPathExtension().lastPathComponent
                indicesToCompile.append((idx, url, identifier, availableIdentifiers.contains(identifier)))
            }
        }
        
        guard loadGeneration == expectedGeneration, !Task.isCancelled else { return }
        
        // 2. Multi-core off-MainActor DNR JSON parsing, regex conversion, and JSON serialization
        if !indicesToCompile.isEmpty {
            let staleIdentifiers = indicesToCompile.filter(\.hasStoredList).map(\.identifier)
            if !staleIdentifiers.isEmpty {
                await withTaskGroup(of: Void.self) { group in
                    for id in staleIdentifiers {
                        group.addTask { @MainActor in
                            await Self.removeContentRuleListIfPresent(identifier: id)
                        }
                    }
                }
            }
            
            let preparedPayloads: [PreparedRulesetPayload] = await Task.detached(priority: .userInitiated) {
                await withTaskGroup(of: PreparedRulesetPayload?.self) { group in
                    for item in indicesToCompile {
                        group.addTask {
                            guard !Task.isCancelled,
                                  let data = try? Data(contentsOf: item.url),
                                  let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
                                return nil
                            }
                            let wkRules = UBlockRuleCompiler.shared.convertDNRToWebKitRuleList(dnrRules: json)
                            guard !wkRules.isEmpty,
                                  let encodedData = try? JSONSerialization.data(withJSONObject: wkRules, options: []),
                                  let encodedString = String(data: encodedData, encoding: .utf8) else {
                                return nil
                            }
                            return PreparedRulesetPayload(
                                index: item.index,
                                identifier: item.identifier,
                                url: item.url,
                                encodedJSON: encodedString,
                                ruleCount: wkRules.count
                            )
                        }
                    }
                    
                    var results: [PreparedRulesetPayload] = []
                    results.reserveCapacity(indicesToCompile.count)
                    for await payload in group {
                        if let payload {
                            results.append(payload)
                        }
                    }
                    return results
                }
            }.value
            
            guard loadGeneration == expectedGeneration, !Task.isCancelled else { return }
            
            // Compile prepared JSON lists into WKContentRuleListStore concurrently
            let compiledPayloads: [(Int, String, WKContentRuleList, Int)] = await withTaskGroup(
                of: (Int, String, WKContentRuleList, Int)?.self
            ) { group in
                for payload in preparedPayloads {
                    group.addTask { @MainActor in
                        if let compiled = await Self.compileSingleList(
                            identifier: payload.identifier,
                            encodedJSON: payload.encodedJSON,
                            fallbackSourceURL: payload.url
                        ) {
                            return (payload.index, payload.identifier, compiled, payload.ruleCount)
                        }
                        return nil
                    }
                }
                var results: [(Int, String, WKContentRuleList, Int)] = []
                results.reserveCapacity(preparedPayloads.count)
                for await result in group {
                    if let result {
                        results.append(result)
                    }
                }
                return results
            }
            
            for (idx, identifier, compiled, count) in compiledPayloads {
                compiledByIndex[idx] = (compiled, count)
                defaults.set(count, forKey: "ublock_rulecount_\(identifier)")
            }
        }
        
        guard loadGeneration == expectedGeneration, !Task.isCancelled else { return }
        
        var newCompiledLists: [WKContentRuleList] = []
        var totalRuleCount = 0
        for idx in 0..<rulesetURLs.count {
            if let entry = compiledByIndex[idx] {
                newCompiledLists.append(entry.list)
                totalRuleCount += entry.count
            }
        }
        
        // Fallback rules only if enabled files failed to compile, NOT when all filter lists are intentionally disabled
        if newCompiledLists.isEmpty && config.anyFilterListEnabled {
            let fallbackRules = Self.defaultFallbackAdblockRules()
            if let fallbackData = try? JSONSerialization.data(withJSONObject: fallbackRules, options: []),
               let fallbackString = String(data: fallbackData, encoding: .utf8),
               let fallbackCompiled = await Self.compileSingleList(
                   identifier: "uBlock_fallback",
                   encodedJSON: fallbackString,
                   explicitFallbackRules: fallbackRules
               ) {
                newCompiledLists.append(fallbackCompiled)
                totalRuleCount += fallbackRules.count
            }
        }
        
        guard loadGeneration == expectedGeneration, !Task.isCancelled else { return }
        self.compiledRuleLists = newCompiledLists
        self.activeRulesCount = totalRuleCount
        self.activeListsCount = newCompiledLists.count
        self.compiledConfiguration = config
        
        // 3. Load cosmetic scripts and scriptlets concurrently off the MainActor
        let activeRulesetIDs = config.activeRulesetIDs
        var scriptSpecs: [ScriptLoadSpec] = []
        var orderCounter = 0
        
        if config.effectiveScriptletDefusers {
            for rid in activeRulesetIDs {
                if let mainURL = Self.locateScriptFile(named: "scriptlet-main-\(rid).js") {
                    scriptSpecs.append(ScriptLoadSpec(order: orderCounter, url: mainURL, injectionTime: .atDocumentStart, world: .page))
                    orderCounter += 1
                }
                if let isoURL = Self.locateScriptFile(named: "scriptlet-isolated-\(rid).js") {
                    scriptSpecs.append(ScriptLoadSpec(order: orderCounter, url: isoURL, injectionTime: .atDocumentStart, world: .defaultClient))
                    orderCounter += 1
                }
            }
        }
        
        if config.effectiveCosmeticHiding {
            for rid in activeRulesetIDs {
                if let cosURL = Self.locateScriptFile(named: "cosmetic-specific-\(rid).js") {
                    scriptSpecs.append(ScriptLoadSpec(order: orderCounter, url: cosURL, injectionTime: .atDocumentStart, world: .defaultClient))
                    orderCounter += 1
                }
            }
        }
        
        let loadedScripts: [LoadedScriptPayload] = await Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: LoadedScriptPayload?.self) { group in
                for spec in scriptSpecs {
                    group.addTask {
                        guard !Task.isCancelled,
                              let code = try? String(contentsOf: spec.url, encoding: .utf8),
                              !code.isEmpty else {
                            return nil
                        }
                        return LoadedScriptPayload(
                            order: spec.order,
                            code: code,
                            injectionTime: spec.injectionTime,
                            world: spec.world
                        )
                    }
                }
                var results: [LoadedScriptPayload] = []
                results.reserveCapacity(scriptSpecs.count)
                for await payload in group {
                    if let payload {
                        results.append(payload)
                    }
                }
                return results.sorted { $0.order < $1.order }
            }
        }.value
        
        guard loadGeneration == expectedGeneration, !Task.isCancelled else { return }
        
        var scripts: [WKUserScript] = loadedScripts.map { payload in
            WKUserScript(
                source: payload.code,
                injectionTime: payload.injectionTime,
                forMainFrameOnly: false,
                in: payload.world
            )
        }
        
        if config.effectiveCosmeticHiding {
            let genericScript = WKUserScript(
                source: Self.genericHideCSSScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .defaultClient
            )
            scripts.append(genericScript)
        }
        
        self.cosmeticUserScripts = scripts
    }
    
    // MARK: - WKContentRuleListStore Helpers
    
    private static func lookUpContentRuleList(identifier: String) async throws -> WKContentRuleList? {
        try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: identifier) { list, error in
                if let list {
                    continuation.resume(returning: list)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private static func removeContentRuleListIfPresent(identifier: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            WKContentRuleListStore.default().removeContentRuleList(forIdentifier: identifier) { _ in
                continuation.resume()
            }
        }
    }
    
    /// Compiles a single rule list into a `WKContentRuleList`, running lazy chunked fallback if needed
    /// and cleaning up any temporary identifiers from `WKContentRuleListStore`.
    private static func compileSingleList(
        identifier: String,
        encodedJSON: String,
        fallbackSourceURL: URL? = nil,
        explicitFallbackRules: [[String: Any]]? = nil
    ) async -> WKContentRuleList? {
        if let ruleList = try? await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: encodedJSON
        ) {
            return ruleList
        }
        
        let fallbackRules: [[String: Any]]
        if let explicitFallbackRules {
            fallbackRules = explicitFallbackRules
        } else if let fallbackSourceURL {
            fallbackRules = await Task.detached(priority: .userInitiated) {
                guard let data = try? Data(contentsOf: fallbackSourceURL),
                      let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
                    return []
                }
                return UBlockRuleCompiler.shared.convertDNRToWebKitRuleList(dnrRules: json)
            }.value
        } else {
            fallbackRules = []
        }
        
        guard !fallbackRules.isEmpty else { return nil }
        
        var verifiedRules: [[String: Any]] = []
        var tempIdentifiersToCleanup: [String] = []
        let chunkSize = 500
        let chunks = stride(from: 0, to: fallbackRules.count, by: chunkSize).map {
            Array(fallbackRules[$0 ..< min($0 + chunkSize, fallbackRules.count)])
        }
        
        for (idx, chunk) in chunks.enumerated() {
            if let chunkData = try? JSONSerialization.data(withJSONObject: chunk, options: []),
               let chunkString = String(data: chunkData, encoding: .utf8) {
                let tempChunkID = "temp_\(identifier)_\(idx)"
                tempIdentifiersToCleanup.append(tempChunkID)
                do {
                    _ = try await WKContentRuleListStore.default().compileContentRuleList(
                        forIdentifier: tempChunkID,
                        encodedContentRuleList: chunkString
                    )
                    verifiedRules.append(contentsOf: chunk)
                } catch {
                    for (sIdx, singleRule) in chunk.enumerated() {
                        if let sData = try? JSONSerialization.data(withJSONObject: [singleRule], options: []),
                           let sString = String(data: sData, encoding: .utf8) {
                            let tempSingleID = "temp_single_\(identifier)_\(idx)_\(sIdx)"
                            tempIdentifiersToCleanup.append(tempSingleID)
                            if (try? await WKContentRuleListStore.default().compileContentRuleList(
                                forIdentifier: tempSingleID,
                                encodedContentRuleList: sString
                            )) != nil {
                                verifiedRules.append(singleRule)
                            }
                        }
                    }
                }
            }
        }
        
        for tempID in tempIdentifiersToCleanup {
            await removeContentRuleListIfPresent(identifier: tempID)
        }
        
        guard !verifiedRules.isEmpty,
              let validData = try? JSONSerialization.data(withJSONObject: verifiedRules, options: []),
              let validString = String(data: validData, encoding: .utf8) else {
            return nil
        }
        
        return try? await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: validString
        )
    }
    
    // MARK: - Resource Location
    
    private nonisolated static func locateRulesetJSONFiles(for config: UBlockFilterConfiguration) -> [URL] {
        var targets: [String] = []
        if config.ublockFilters { targets.append("ublock-filters.json") }
        if config.ublockBadware { targets.append("ublock-badware.json") }
        if config.easylist { targets.append("easylist.json") }
        if config.easyprivacy { targets.append("easyprivacy.json") }
        if config.adguardMobile { targets.append("adguard-mobile.json") }
        if config.urlhaus { targets.append("urlhaus-full.json") }
        if config.effectiveAnnoyances {
            targets.append("annoyances-cookies.json")
            targets.append("annoyances-overlays.json")
        }
        if config.blockLan { targets.append("block-lan.json") }
        if config.frenchFilters { targets.append("fra-0.json") }
        
        var urls: [URL] = []
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
            if !found,
               let directURL = Bundle.main.url(
                   forResource: (t as NSString).deletingPathExtension,
                   withExtension: (t as NSString).pathExtension
               ) {
                urls.append(directURL)
            }
        }
        
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
    
    private nonisolated static func locateScriptFile(named filename: String) -> URL? {
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        
        if let directURL = Bundle.main.url(forResource: name, withExtension: ext) {
            return directURL
        }
        
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
    
    private nonisolated static let genericHideCSSScript = """
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
    
    private nonisolated static func defaultFallbackAdblockRules() -> [[String: Any]] {
        [
            [
                "trigger": [
                    "url-filter": ".*",
                    "if-domain": ["*doubleclick.net", "*googlesyndication.com", "*google-analytics.com", "*adservice.google.com", "*taboola.com", "*outbrain.com", "*adnxs.com", "*amazon-adsystem.com", "*rubiconproject.com", "*popads.net", "*criteo.com"]
                ],
                "action": ["type": "block"]
            ],
            [
                "trigger": [
                    "url-filter": ".*\\/ads.*",
                    "load-type": ["third-party"],
                    "resource-type": ["script", "image", "raw"]
                ],
                "action": ["type": "block"]
            ],
            [
                "trigger": [
                    "url-filter": ".*\\/pagead.*",
                    "load-type": ["third-party"],
                    "resource-type": ["script", "image", "raw"]
                ],
                "action": ["type": "block"]
            ],
            [
                "trigger": [
                    "url-filter": ".*\\/analytics.*",
                    "load-type": ["third-party"],
                    "resource-type": ["script", "image", "raw"]
                ],
                "action": ["type": "block"]
            ]
        ]
    }
}
