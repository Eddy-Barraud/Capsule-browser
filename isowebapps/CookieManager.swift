//
//  CookieManager.swift
//  isowebapps
//
//  Created on 23/08/2026.
//

import Foundation
import WebKit
import SwiftData

/// Manages per-webapp cookie isolation and synchronization with SwiftData/CloudKit.
@MainActor
final class IsolatedCookieManager {
    static let shared = IsolatedCookieManager()
    
    private init() {}
    
    /// Restores cookies from SwiftData item into the WKHTTPCookieStore
    func restoreCookies(for item: WebAppItem, into cookieStore: WKHTTPCookieStore) async {
        guard let data = item.isolatedCookiesData,
              let serializableCookies = try? JSONDecoder().decode([SerializableCookie].self, from: data) else {
            #if DEBUG
            print("[IsolatedCookieManager] No stored cookies found for \(item.name)")
            #endif
            return
        }
        
        #if DEBUG
        print("[IsolatedCookieManager] Restoring \(serializableCookies.count) cookies for \(item.name)...")
        #endif
        
        for sCookie in serializableCookies {
            if let cookie = sCookie.toHTTPCookie() {
                await cookieStore.setCookie(cookie)
            }
        }
    }
    
    /// Saves current cookies from WKHTTPCookieStore back into SwiftData item for CloudKit sync
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
    
    /// Clears cookies, cache, local storage, and website data for a specific webapp
    func clearData(for item: WebAppItem, dataStore: WKWebsiteDataStore, context: ModelContext) async {
        #if DEBUG
        print("[IsolatedCookieManager] Clearing all data for \(item.name)...")
        #endif
        
        // Clear isolated SwiftData cookies
        item.isolatedCookiesData = nil
        try? context.save()
        
        // Remove from WKWebsiteDataStore
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
