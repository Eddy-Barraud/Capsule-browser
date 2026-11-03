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
    
    /// Latest pending URL string to persist for a `WebAppItem.id`.
    private var pendingURLByItem: [UUID: String] = [:]
    
    /// Cached last-saved cookie array per `WebAppItem.id` to avoid redundant SwiftData writes.
    private var lastSavedCookiesByItem: [UUID: [SerializableCookie]] = [:]
    
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
            let decoder = JSONDecoder()
            
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
        guard item.modelContext != nil else { return }
        if let url = lastOpenedURL, !url.isEmpty, url != "about:blank" {
            pendingURLByItem[item.id] = url
        }
        
        pendingPersistTasks[item.id]?.cancel()
        let itemId = item.id
        pendingPersistTasks[itemId] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.persistCookiesNow(for: item, from: cookieStore, context: context)
        }
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
        
        guard item.modelContext != nil else { return }
        
        var didMutate = false
        let urlToSave = lastOpenedURL ?? pendingURLByItem.removeValue(forKey: item.id)
        if let url = urlToSave, !url.isEmpty, url != "about:blank" {
            if item.lastOpenedURLString != url {
                item.lastOpenedURLString = url
                didMutate = true
            }
            if item.lastVisited == nil || Date().timeIntervalSince(item.lastVisited!) > 30 {
                item.lastVisited = Date()
                didMutate = true
            }
        }
        
        if !item.deleteCookiesOnClose {
            let cookies = await cookieStore.allCookies()
            let sortedCookies = cookies.sorted { a, b in
                if a.domain != b.domain { return a.domain < b.domain }
                if a.path != b.path { return a.path < b.path }
                return a.name < b.name
            }
            let serializable = sortedCookies.map { SerializableCookie(from: $0) }
            
            if lastSavedCookiesByItem[item.id] != serializable {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                if let encoded = try? encoder.encode(serializable) {
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
        }
        
        if didMutate {
            try? context.save()
        }
    }
    
    /// Extracts active cookies from `WKHTTPCookieStore` and persists them into SwiftData for CloudKit sync
    func persistCookies(for item: WebAppItem, from cookieStore: WKHTTPCookieStore, context: ModelContext) async {
        await persistCookiesNow(for: item, from: cookieStore, context: context)
    }
    
    /// Selectively wipes all cookies, cache, local storage, and website data for a specific webapp
    static func saveCookies(for appItem: WebAppItem, from dataStore: WKWebsiteDataStore) {
        guard appItem.modelContext != nil, !appItem.deleteCookiesOnClose else { return } // Ephemeral apps don't persist cookies
        guard let context = appItem.modelContext else { return }
        Task { @MainActor in
            await IsolatedCookieManager.shared.persistCookiesNow(
                for: appItem,
                from: dataStore.httpCookieStore,
                context: context
            )
        }
    }
    
    /// Selectively wipes all cookies, cache, local storage, and website data for a specific webapp
    func clearData(for item: WebAppItem, context: ModelContext) async {
        #if DEBUG
        print("[IsolatedCookieManager] Clearing all data for \(item.name)...")
        #endif
        
        pendingPersistTasks[item.id]?.cancel()
        pendingPersistTasks.removeValue(forKey: item.id)
        pendingURLByItem.removeValue(forKey: item.id)
        lastSavedCookiesByItem.removeValue(forKey: item.id)
        let storeId = item.group?.id ?? item.id
        invalidateRestoreCache(for: storeId)
        
        // 1. Clear isolated SwiftData cookies
        item.isolatedCookiesData = nil
        try? context.save()
        
        guard item.modelContext != nil else {
            // Ephemeral capsule uses nonPersistent data store; no disk store to remove
            return
        }
        
        if let group = item.group {
            // Grouped capsule: Clean only this app's domain records from the shared group data store
            let groupStore = WKWebsiteDataStore(forIdentifier: group.id)
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            let records = await groupStore.dataRecords(ofTypes: dataTypes)
            
            if let host = URL(string: item.urlString)?.host {
                let matchingRecords = records.filter { $0.displayName.contains(host) }
                await groupStore.removeData(ofTypes: dataTypes, for: matchingRecords)
            } else {
                let dateFrom = Date(timeIntervalSince1970: 0)
                await groupStore.removeData(ofTypes: dataTypes, modifiedSince: dateFrom)
            }
        } else {
            // Standalone capsule: completely remove the dedicated on-disk website data store
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: item.id)
                #if DEBUG
                print("[IsolatedCookieManager] Successfully removed WKWebsiteDataStore for standalone app \(item.id)")
                #endif
            } catch {
                #if DEBUG
                print("[IsolatedCookieManager] Error removing WKWebsiteDataStore for \(item.id): \(error)")
                #endif
            }
        }
    }
}
