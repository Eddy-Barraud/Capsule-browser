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
    
    private init() {}
    
    /// Restores cookies from a SwiftData `WebAppItem` and its group into the target `WKHTTPCookieStore`
    func restoreCookies(for item: WebAppItem, groupedItems: [WebAppItem] = [], into cookieStore: WKHTTPCookieStore) async {
        // 1. Combine cookies. Deduplicate using a unique key per cookie.
        var combinedCookies: [String: SerializableCookie] = [:]
        
        // Load grouped items first (so they can be overridden by the item's own cookies)
        for groupItem in groupedItems where groupItem.id != item.id {
            if let data = groupItem.isolatedCookiesData,
               let serializableCookies = try? JSONDecoder().decode([SerializableCookie].self, from: data) {
                for cookie in serializableCookies {
                    let key = "\(cookie.name)-\(cookie.domain)-\(cookie.path)"
                    combinedCookies[key] = cookie
                }
            }
        }
        
        // Load the item's own cookies (these take precedence)
        if let data = item.isolatedCookiesData,
           let serializableCookies = try? JSONDecoder().decode([SerializableCookie].self, from: data) {
            for cookie in serializableCookies {
                let key = "\(cookie.name)-\(cookie.domain)-\(cookie.path)"
                combinedCookies[key] = cookie
            }
        }
        
        guard !combinedCookies.isEmpty else {
            #if DEBUG
            print("[IsolatedCookieManager] No stored cookies found for \(item.name) or its group")
            #endif
            return
        }
        
        #if DEBUG
        print("[IsolatedCookieManager] Restoring \(combinedCookies.count) cookies for \(item.name) (including group)...")
        #endif
        
        for sCookie in combinedCookies.values {
            if let cookie = sCookie.toHTTPCookie() {
                await cookieStore.setCookie(cookie)
            }
        }
    }
    
    /// Extracts active cookies from `WKHTTPCookieStore` and persists them into SwiftData for CloudKit sync
    func persistCookies(for item: WebAppItem, from cookieStore: WKHTTPCookieStore, context: ModelContext) async {
        let cookies = await cookieStore.allCookies()
        let serializable = cookies.map { SerializableCookie(from: $0) }
        
        #if DEBUG
        print("[IsolatedCookieManager] Persisting \(cookies.count) cookies for \(item.name)...")
        #endif
        
        if let encoded = try? JSONEncoder().encode(serializable) {
            item.isolatedCookiesData = encoded
            try? context.save()
        }
    }
    
    /// Selectively wipes all cookies, cache, local storage, and website data for a specific webapp
    static func saveCookies(for appItem: WebAppItem, from dataStore: WKWebsiteDataStore) {
        guard appItem.modelContext != nil else { return } // Ephemeral apps don't persist cookies
        
        dataStore.httpCookieStore.getAllCookies { cookies in
            let serializable = cookies.map { SerializableCookie(from: $0) }
            if let encoded = try? JSONEncoder().encode(serializable) {
                appItem.isolatedCookiesData = encoded
                try? appItem.modelContext?.save()
            }
        }
    }
    
    func clearData(for item: WebAppItem, dataStore: WKWebsiteDataStore, context: ModelContext) async {
        #if DEBUG
        print("[IsolatedCookieManager] Clearing all data for \(item.name)...")
        #endif
        
        // 1. Clear isolated SwiftData cookies
        item.isolatedCookiesData = nil
        try? context.save()
        
        // 2. Remove all related records from WKWebsiteDataStore
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: dataTypes)
        
        if let host = URL(string: item.urlString)?.host {
            let matchingRecords = records.filter { $0.displayName.contains(host) }
            await dataStore.removeData(ofTypes: dataTypes, for: matchingRecords)
        } else {
            let dateFrom = Date(timeIntervalSince1970: 0)
            await dataStore.removeData(ofTypes: dataTypes, modifiedSince: dateFrom)
        }
    }
}
