//
//  CookieManager.swift
//  isowebapps
//
//  Created on 23/08/2026.
//
//  Description:
//  Manages cookie isolation per web application. Handles extracting cookies from
//  non-persistent WKWebsiteDataStore cookie containers, converting them into
//  `SerializableCookie` structures for SwiftData/CloudKit persistence, restoring
//  them on launch, and selectively clearing site cache/storage.
//

import Foundation
import WebKit
import SwiftData

/// Manages per-webapp cookie isolation and synchronization with SwiftData/CloudKit.
@MainActor
final class IsolatedCookieManager {
    static let shared = IsolatedCookieManager()
    
    /// Tracks which `WebAppItem.id`s have already had their stored `isolatedCookiesData`
    /// merged into a given `storeId` (`group.id ?? item.id`) during the current app session.
    private var restoredItemIDsByStore: [UUID: Set<UUID>] = [:]
    
    /// Tracks in-flight restore tasks per `storeId` so concurrent tab launches await the same restore.
    private var inFlightRestoreTasks: [UUID: Task<Void, Never>] = [:]
    
    /// Coalesced debounced persistence tasks keyed by `WebAppItem.id`.
    private var pendingPersistTasks: [UUID: Task<Void, Never>] = [:]
    
    /// Immediate flush closures matching scheduled debounced saves, keyed by `WebAppItem.id`.
    private var pendingFlushActions: [UUID: @MainActor () async -> Void] = [:]
    
    /// In-flight background flush tasks keyed by `WebAppItem.id` so idle purge can await completion.
    private var inFlightPersistTasks: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
    
    /// In-flight data-clear tasks keyed by `storeId` (`group.id ?? item.id`) so app termination
    /// and immediate capsule relaunch can await completion without racing `WKWebsiteDataStore.remove`.
    private var inFlightClearTasks: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
    
    /// Reference counts of active clears per `WebAppItem.id` so late dismantle flushes do not re-persist cleared URLs.
    private var clearingItemCounts: [UUID: Int] = [:]
    
    /// Latest pending URL string to persist for a `WebAppItem.id`.
    private var pendingURLByItem: [UUID: String] = [:]
    
    /// Cached last-saved cookie array per `WebAppItem.id` to avoid redundant SwiftData writes.
    private var lastSavedCookiesByItem: [UUID: [SerializableCookie]] = [:]
    
    var hasPendingSaves: Bool {
        !pendingPersistTasks.isEmpty || !pendingFlushActions.isEmpty || !inFlightPersistTasks.isEmpty
    }
    
    var hasPendingClears: Bool {
        !inFlightClearTasks.isEmpty
    }
    
    var hasPendingOperations: Bool {
        hasPendingSaves || hasPendingClears
    }
    
    func hasPendingClear(for storeId: UUID) -> Bool {
        inFlightClearTasks[storeId] != nil
    }
    
    func awaitPendingClear(for storeId: UUID) async {
        while let entry = inFlightClearTasks[storeId] {
            await entry.task.value
        }
    }
    
    nonisolated static func normalizeDomainComponent(_ value: String) -> String {
        var normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        while normalized.hasPrefix(".") {
            normalized.removeFirst()
        }
        while normalized.hasSuffix(".") {
            normalized.removeLast()
        }
        return normalized
    }
    
    nonisolated static func host(fromURLString urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let host = URL(string: trimmed)?.host, !host.isEmpty {
            return host
        }
        if !trimmed.contains("://"),
           let host = URL(string: "https://\(trimmed)")?.host, !host.isEmpty {
            return host
        }
        return nil
    }
    
    nonisolated static func host(_ rawHost: String, matchesDomain rawDomain: String) -> Bool {
        let host = normalizeDomainComponent(rawHost)
        let domain = normalizeDomainComponent(rawDomain)
        guard !host.isEmpty, !domain.isEmpty else { return false }
        if host == domain {
            return true
        }
        if host.hasSuffix(".\(domain)") {
            return true
        }
        if domain.hasSuffix(".\(host)") {
            return true
        }
        return false
    }
    
    private static let cookieDecoder = JSONDecoder()
    private static let cookieEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    
    private init() {}
    
    /// Invalidates cached session restore tracking (for example after clearing data or remote sync).
    func invalidateRestoreCache(for storeId: UUID? = nil) {
        if let storeId = storeId {
            restoredItemIDsByStore.removeValue(forKey: storeId)
        } else {
            restoredItemIDsByStore.removeAll()
        }
    }
    
    /// Synchronously checks whether any item for the target store still needs its `isolatedCookiesData` restored.
    /// When this returns `false`, `WKWebView.load(_:)` can start immediately and synchronously.
    func needsRestore(for item: WebAppItem, groupedItems: [WebAppItem] = []) -> Bool {
        guard item.modelContext != nil else { return false }
        let storeId = item.group?.id ?? item.id
        
        if inFlightRestoreTasks[storeId] != nil {
            return true
        }
        
        let alreadyRestored = restoredItemIDsByStore[storeId] ?? []
        var candidates: [WebAppItem] = []
        for groupItem in groupedItems where groupItem.id != item.id {
            if !alreadyRestored.contains(groupItem.id) {
                candidates.append(groupItem)
            }
        }
        if !alreadyRestored.contains(item.id) {
            candidates.append(item)
        }
        
        guard !candidates.isEmpty else {
            return false
        }
        
        let hasAnyStoredCookieData = candidates.contains { candidate in
            guard let data = candidate.isolatedCookiesData else { return false }
            return !data.isEmpty
        }
        
        if !hasAnyStoredCookieData {
            var updated = alreadyRestored
            for candidate in candidates {
                updated.insert(candidate.id)
            }
            restoredItemIDsByStore[storeId] = updated
            return false
        }
        
        return true
    }
    
    /// Restores cookies from a SwiftData `WebAppItem` and its group into the target `WKHTTPCookieStore`
    func restoreCookies(for item: WebAppItem, groupedItems: [WebAppItem] = [], into cookieStore: WKHTTPCookieStore) async {
        guard item.modelContext != nil else { return }
        let storeId = item.group?.id ?? item.id
        
        // Wait for any in-flight data clear on the same store before restoring
        await awaitPendingClear(for: storeId)
        
        // Wait for any in-flight restore on the same store to finish first
        if let inFlight = inFlightRestoreTasks[storeId] {
            await inFlight.value
        }
        
        let alreadyRestored = restoredItemIDsByStore[storeId] ?? []
        let allItemsInScope = groupedItems.filter { $0.id != item.id } + [item]
        let unrestoredItems = allItemsInScope.filter { !alreadyRestored.contains($0.id) }
        guard !unrestoredItems.isEmpty else { return }
        
        let restoreTask = Task { @MainActor in
            // 1. Combine cookies from un-restored items. Deduplicate using a unique key per cookie.
            var combinedCookies: [String: SerializableCookie] = [:]
            let now = Date()
            let decoder = Self.cookieDecoder
            
            // Load grouped items first (so they can be overridden by the item's own cookies)
            for groupItem in groupedItems where groupItem.id != item.id && !alreadyRestored.contains(groupItem.id) {
                if let data = groupItem.isolatedCookiesData,
                   let serializableCookies = try? decoder.decode([SerializableCookie].self, from: data) {
                    for cookie in serializableCookies {
                        if let exp = cookie.expiresDate, exp < now { continue }
                        let key = "\(cookie.name)\0\(cookie.domain)\0\(cookie.path)"
                        combinedCookies[key] = cookie
                    }
                }
            }
            
            // Load the item's own cookies (these take precedence)
            if !alreadyRestored.contains(item.id),
               let data = item.isolatedCookiesData,
               let serializableCookies = try? decoder.decode([SerializableCookie].self, from: data) {
                for cookie in serializableCookies {
                    if let exp = cookie.expiresDate, exp < now { continue }
                    let key = "\(cookie.name)\0\(cookie.domain)\0\(cookie.path)"
                    combinedCookies[key] = cookie
                }
            }
            
            // Mark all items in scope as restored for this store session
            var updatedRestored = self.restoredItemIDsByStore[storeId] ?? []
            for scopedItem in allItemsInScope {
                updatedRestored.insert(scopedItem.id)
            }
            self.restoredItemIDsByStore[storeId] = updatedRestored
            
            guard !combinedCookies.isEmpty else {
                #if DEBUG
                print("[IsolatedCookieManager] No stored cookies found for \(item.name) or its group")
                #endif
                return
            }
            
            // 2. Fetch existing cookies from the native on-disk WKWebsiteDataStore in a single IPC call.
            // Only inject cookies that are not already present in the live/on-disk store so we never
            // clobber fresher rotated session cookies or perform redundant IPC round-trips.
            let existingCookies = await cookieStore.allCookies()
            var existingKeys = Set<String>()
            existingKeys.reserveCapacity(existingCookies.count)
            for existing in existingCookies {
                existingKeys.insert("\(existing.name)\0\(existing.domain)\0\(existing.path)")
            }
            
            var cookiesToInject: [HTTPCookie] = []
            for (key, sCookie) in combinedCookies where !existingKeys.contains(key) {
                if let httpCookie = sCookie.toHTTPCookie() {
                    cookiesToInject.append(httpCookie)
                }
            }
            
            guard !cookiesToInject.isEmpty else {
                #if DEBUG
                print("[IsolatedCookieManager] All \(combinedCookies.count) stored cookies already present in dataStore for \(item.name); skipping injection.")
                #endif
                return
            }
            
            #if DEBUG
            print("[IsolatedCookieManager] Restoring \(cookiesToInject.count) missing cookies (of \(combinedCookies.count) stored) for \(item.name) (including group)...")
            #endif
            
            // 3. Inject missing cookies concurrently rather than sequentially
            await withTaskGroup(of: Void.self) { group in
                for cookie in cookiesToInject {
                    group.addTask { @MainActor in
                        await cookieStore.setCookie(cookie)
                    }
                }
            }
        }
        
        inFlightRestoreTasks[storeId] = restoreTask
        await restoreTask.value
        inFlightRestoreTasks.removeValue(forKey: storeId)
    }
    
    /// Schedules a coalesced, debounced cookie and URL metadata persistence after navigation settles.
    func schedulePersistCookies(
        for item: WebAppItem,
        from cookieStore: WKHTTPCookieStore,
        context: ModelContext,
        lastOpenedURL: String? = nil,
        delaySeconds: TimeInterval = 5.0
    ) {
        guard item.modelContext != nil, !item.deleteCookiesOnClose, clearingItemCounts[item.id] == nil else { return }
        if let url = lastOpenedURL, !url.isEmpty, url != "about:blank" {
            pendingURLByItem[item.id] = url
        }
        
        pendingPersistTasks[item.id]?.cancel()
        let itemId = item.id
        pendingFlushActions[itemId] = { @MainActor [weak self] in
            await self?.persistCookiesNow(for: item, from: cookieStore, context: context)
        }
        pendingPersistTasks[itemId] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.persistCookiesNow(for: item, from: cookieStore, context: context)
        }
    }
    
    /// Launches a tracked background flush for a closing/tearing-down WebView so idle purges can await it.
    func flushPendingSaveInBackground(
        for item: WebAppItem,
        from cookieStore: WKHTTPCookieStore,
        context: ModelContext,
        lastOpenedURL: String? = nil
    ) {
        guard item.modelContext != nil, !item.deleteCookiesOnClose, clearingItemCounts[item.id] == nil else { return }
        let itemId = item.id
        let previousTask = inFlightPersistTasks[itemId]?.task
        let token = UUID()
        let task = Task { @MainActor [weak self] in
            await previousTask?.value
            await self?.flushPendingSaveIfNeeded(
                for: item,
                from: cookieStore,
                context: context,
                lastOpenedURL: lastOpenedURL
            )
            if self?.inFlightPersistTasks[itemId]?.token == token {
                self?.inFlightPersistTasks.removeValue(forKey: itemId)
            }
        }
        inFlightPersistTasks[itemId] = (token: token, task: task)
    }
    
    /// Flushes all scheduled debounced saves and awaits any in-flight cookie persistence and data-clear tasks.
    func flushAllPendingSaves() async {
        for (_, task) in pendingPersistTasks {
            task.cancel()
        }
        pendingPersistTasks.removeAll()
        
        let actions = Array(pendingFlushActions.values)
        pendingFlushActions.removeAll()
        for action in actions {
            await action()
        }
        
        while !inFlightPersistTasks.isEmpty {
            let activeTasks = inFlightPersistTasks.values.map(\.task)
            for task in activeTasks {
                await task.value
            }
        }
        
        while !inFlightClearTasks.isEmpty {
            let clearTasks = inFlightClearTasks.values.map(\.task)
            for task in clearTasks {
                await task.value
            }
        }
    }
    
    /// Releases in-memory cookie diff caches after pending saves are flushed while preserving `restoredItemIDsByStore`.
    func releaseInMemoryCaches() {
        lastSavedCookiesByItem.removeAll(keepingCapacity: false)
        pendingURLByItem.removeAll(keepingCapacity: false)
    }
    
    /// Flushes pending cookies and URL metadata only if a debounced save is currently scheduled or the URL changed.
    func flushPendingSaveIfNeeded(
        for item: WebAppItem,
        from cookieStore: WKHTTPCookieStore,
        context: ModelContext,
        lastOpenedURL: String? = nil
    ) async {
        guard item.modelContext != nil, !item.deleteCookiesOnClose, clearingItemCounts[item.id] == nil else { return }
        let hasPendingTask = (pendingPersistTasks[item.id] != nil) || (pendingURLByItem[item.id] != nil)
        let hasChangedURL: Bool = {
            guard let url = lastOpenedURL, !url.isEmpty, url != "about:blank" else { return false }
            return item.lastOpenedURLString != url
        }()
        guard hasPendingTask || hasChangedURL else { return }
        await persistCookiesNow(for: item, from: cookieStore, context: context, lastOpenedURL: lastOpenedURL)
    }
    
    /// Immediately flushes active cookies and pending URL metadata into SwiftData (e.g. on capsule close or after idle debounce).
    func persistCookiesNow(
        for item: WebAppItem,
        from cookieStore: WKHTTPCookieStore,
        context: ModelContext,
        lastOpenedURL: String? = nil
    ) async {
        pendingPersistTasks[item.id]?.cancel()
        pendingPersistTasks.removeValue(forKey: item.id)
        pendingFlushActions.removeValue(forKey: item.id)
        
        guard item.modelContext != nil, !item.deleteCookiesOnClose, clearingItemCounts[item.id] == nil else {
            pendingURLByItem.removeValue(forKey: item.id)
            return
        }
        
        var didMutate = false
        let urlToSave = lastOpenedURL ?? pendingURLByItem.removeValue(forKey: item.id)
        if let url = urlToSave, !url.isEmpty, url != "about:blank" {
            if item.lastOpenedURLString != url {
                item.lastOpenedURLString = url
                didMutate = true
            }
            if item.lastVisited == nil || abs(Date().timeIntervalSince(item.lastVisited!)) > 30 {
                item.lastVisited = Date()
                didMutate = true
            }
        }
        
        let cookies = await cookieStore.allCookies()
        let sortedCookies = cookies.sorted { a, b in
            if a.domain != b.domain { return a.domain < b.domain }
            if a.path != b.path { return a.path < b.path }
            return a.name < b.name
        }
        let serializable = sortedCookies.map { SerializableCookie(from: $0) }
        
        if lastSavedCookiesByItem[item.id] != serializable || item.isolatedCookiesData == nil {
            if let encoded = try? Self.cookieEncoder.encode(serializable) {
                if item.isolatedCookiesData != encoded {
                    #if DEBUG
                    print("[IsolatedCookieManager] Persisting \(serializable.count) cookies for \(item.name)...")
                    #endif
                    item.isolatedCookiesData = encoded
                    didMutate = true
                }
                lastSavedCookiesByItem[item.id] = serializable
            }
        }
        
        if didMutate {
            try? context.save()
        }
    }
    
    /// Starts a tracked data-clear task synchronously on `@MainActor` so teardown and termination
    /// checks observe the pending operation immediately without async scheduling gaps.
    @discardableResult
    func clearDataInBackground(for item: WebAppItem, context: ModelContext) -> Task<Void, Never>? {
        startClearDataTask(for: item, context: context)
    }
    
    /// Selectively wipes all cookies, cache, local storage, and website data for a specific webapp
    func clearData(for item: WebAppItem, context: ModelContext) async {
        if let task = startClearDataTask(for: item, context: context) {
            await task.value
        }
    }
    
    private func startClearDataTask(for item: WebAppItem, context: ModelContext) -> Task<Void, Never>? {
        #if DEBUG
        print("[IsolatedCookieManager] Clearing all data for \(item.name)...")
        #endif
        
        let itemId = item.id
        pendingPersistTasks[itemId]?.cancel()
        pendingPersistTasks.removeValue(forKey: itemId)
        pendingFlushActions.removeValue(forKey: itemId)
        inFlightPersistTasks[itemId]?.task.cancel()
        inFlightPersistTasks.removeValue(forKey: itemId)
        pendingURLByItem.removeValue(forKey: itemId)
        lastSavedCookiesByItem.removeValue(forKey: itemId)
        let storeId = item.group?.id ?? itemId
        if item.group == nil {
            inFlightRestoreTasks[storeId]?.cancel()
            inFlightRestoreTasks.removeValue(forKey: storeId)
        }
        invalidateRestoreCache(for: storeId)
        
        // 1. Clear isolated SwiftData cookies and last-opened URL
        item.isolatedCookiesData = nil
        item.lastOpenedURLString = nil
        try? context.save()
        
        guard item.modelContext != nil else {
            // Ephemeral capsule uses nonPersistent data store; no disk store to remove
            return nil
        }
        
        let groupId = item.group?.id
        let itemURLString = item.urlString
        let previousClearTask = inFlightClearTasks[storeId]?.task
        let inFlightRestore = inFlightRestoreTasks[storeId]
        let token = UUID()
        clearingItemCounts[itemId, default: 0] += 1
        
        let task = Task { @MainActor [weak self] in
            await previousClearTask?.value
            await inFlightRestore?.value
            if let groupId {
                // Grouped capsule: Clean only this app's domain cookies and records from the shared group data store
                let groupStore = WKWebsiteDataStore(forIdentifier: groupId)
                await self?.clearGroupedWebsiteData(in: groupStore, forHostOf: itemURLString)
            } else {
                // Standalone capsule: remove the on-disk container directly when unused,
                // or wipe all cookies and website data if WebKit still has the store active (e.g. instant reopen).
                await self?.removeOrWipeDataStore(forIdentifier: itemId, label: "standalone app \(itemId)")
            }
            if let self {
                let nextCount = (self.clearingItemCounts[itemId] ?? 1) - 1
                if nextCount <= 0 {
                    self.clearingItemCounts.removeValue(forKey: itemId)
                } else {
                    self.clearingItemCounts[itemId] = nextCount
                }
                if self.inFlightClearTasks[storeId]?.token == token {
                    self.inFlightClearTasks.removeValue(forKey: storeId)
                }
            }
        }
        inFlightClearTasks[storeId] = (token: token, task: task)
        return task
    }
    
    /// Wipes all cookies, cache, local storage, and website data for all capsules in a group,
    /// and resets the shared group WKWebsiteDataStore.
    func clearData(for group: WebAppGroup, context: ModelContext) async {
        let task = startClearDataTask(for: group, context: context)
        await task.value
    }
    
    private func startClearDataTask(for group: WebAppGroup, context: ModelContext) -> Task<Void, Never> {
        #if DEBUG
        print("[IsolatedCookieManager] Clearing all data and cookies for group '\(group.name)' (\(group.id))...")
        #endif
        
        let groupId = group.id
        let items = group.items ?? []
        let itemIds = items.map(\.id)
        
        // 1. Cancel and remove any pending persist tasks and caches for member capsules
        for item in items {
            pendingPersistTasks[item.id]?.cancel()
            pendingPersistTasks.removeValue(forKey: item.id)
            pendingFlushActions.removeValue(forKey: item.id)
            inFlightPersistTasks[item.id]?.task.cancel()
            inFlightPersistTasks.removeValue(forKey: item.id)
            pendingURLByItem.removeValue(forKey: item.id)
            lastSavedCookiesByItem.removeValue(forKey: item.id)
            item.isolatedCookiesData = nil
            item.lastOpenedURLString = nil
            clearingItemCounts[item.id, default: 0] += 1
        }
        
        inFlightRestoreTasks[groupId]?.cancel()
        inFlightRestoreTasks.removeValue(forKey: groupId)
        invalidateRestoreCache(for: groupId)
        
        try? context.save()
        
        let previousClearTask = inFlightClearTasks[groupId]?.task
        let token = UUID()
        let task = Task { @MainActor [weak self] in
            await previousClearTask?.value
            await self?.removeOrWipeDataStore(forIdentifier: groupId, label: "group \(groupId)")
            if let self {
                for itemId in itemIds {
                    let nextCount = (self.clearingItemCounts[itemId] ?? 1) - 1
                    if nextCount <= 0 {
                        self.clearingItemCounts.removeValue(forKey: itemId)
                    } else {
                        self.clearingItemCounts[itemId] = nextCount
                    }
                }
                if self.inFlightClearTasks[groupId]?.token == token {
                    self.inFlightClearTasks.removeValue(forKey: groupId)
                }
            }
        }
        inFlightClearTasks[groupId] = (token: token, task: task)
        return task
    }
    
    private func removeOrWipeDataStore(forIdentifier identifier: UUID, label: String) async {
        do {
            try await WKWebsiteDataStore.remove(forIdentifier: identifier)
            #if DEBUG
            print("[IsolatedCookieManager] Successfully removed WKWebsiteDataStore for \(label)")
            #endif
        } catch {
            let store = WKWebsiteDataStore(forIdentifier: identifier)
            await clearAllCookiesAndStorage(in: store)
            #if DEBUG
            print("[IsolatedCookieManager] Wiped active WKWebsiteDataStore contents for \(label) (remove info: \(error.localizedDescription))")
            #endif
        }
    }
    
    private func clearGroupedWebsiteData(in groupStore: WKWebsiteDataStore, forHostOf urlString: String) async {
        if let host = Self.host(fromURLString: urlString) {
            let cookies = await groupStore.httpCookieStore.allCookies()
            let matchingCookies = cookies.filter { Self.host(host, matchesDomain: $0.domain) }
            if !matchingCookies.isEmpty {
                await withTaskGroup(of: Void.self) { group in
                    for cookie in matchingCookies {
                        group.addTask { @MainActor in
                            await groupStore.httpCookieStore.deleteCookie(cookie)
                        }
                    }
                }
            }
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            let records = await groupStore.dataRecords(ofTypes: dataTypes)
            let matchingRecords = records.filter { Self.host(host, matchesDomain: $0.displayName) }
            if !matchingRecords.isEmpty {
                await groupStore.removeData(ofTypes: dataTypes, for: matchingRecords)
            }
        } else {
            await clearAllCookiesAndStorage(in: groupStore)
        }
    }
    
    private func clearAllCookiesAndStorage(in store: WKWebsiteDataStore) async {
        let cookies = await store.httpCookieStore.allCookies()
        if !cookies.isEmpty {
            await withTaskGroup(of: Void.self) { group in
                for cookie in cookies {
                    group.addTask { @MainActor in
                        await store.httpCookieStore.deleteCookie(cookie)
                    }
                }
            }
        }
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        await store.removeData(ofTypes: dataTypes, modifiedSince: .distantPast)
    }
}
