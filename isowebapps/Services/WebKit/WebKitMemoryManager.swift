//
//  WebKitMemoryManager.swift
//  isowebapps
//
//  Description:
//  Tracks active `WKWebView` instances, open capsule reference counts,
//  WebKit teardown (`_close`, delegate clearing, script removal),
//  and idle memory/cache purging.
//

import Foundation
import WebKit
import SwiftData

@MainActor
final class WebKitMemoryManager {
    private final class WeakWebAppItemBox {
        weak var item: WebAppItem?
        init(_ item: WebAppItem) {
            self.item = item
        }
    }
    
    static let shared = WebKitMemoryManager()
    
    private var activeWebViews = NSHashTable<WKWebView>.weakObjects()
    private var tornDownWebViews = NSHashTable<WKWebView>.weakObjects()
    private var activeDataStores = NSHashTable<WKWebsiteDataStore>.weakObjects()
    private var activeCoordinators = NSHashTable<WebViewCoordinator>.weakObjects()
    private var openCapsuleCounts: [UUID: Int] = [:]
    private var openCapsuleItems: [UUID: WeakWebAppItemBox] = [:]
    
    private init() {}
    
    var liveWebViewCount: Int {
        activeWebViews.allObjects.count
    }
    
    var hasOpenDeleteOnCloseCapsules: Bool {
        openCapsuleItems.values.contains { box in
            guard let item = box.item, item.modelContext != nil else { return false }
            return item.deleteCookiesOnClose
        }
    }
    
    func registerOpenCapsule(appItem: WebAppItem) {
        let appId = appItem.id
        openCapsuleCounts[appId, default: 0] += 1
        openCapsuleItems[appId] = WeakWebAppItemBox(appItem)
    }
    
    @discardableResult
    func unregisterOpenCapsule(appId: UUID) -> Int {
        guard let current = openCapsuleCounts[appId] else { return 0 }
        let next = current - 1
        if next <= 0 {
            openCapsuleCounts.removeValue(forKey: appId)
            openCapsuleItems.removeValue(forKey: appId)
            return 0
        }
        openCapsuleCounts[appId] = next
        return next
    }
    
    func register(coordinator: WebViewCoordinator) {
        activeCoordinators.add(coordinator)
    }
    
    func prepareForApplicationTermination(modelContainer: ModelContainer) async {
        let itemsToClear: [WebAppItem] = openCapsuleItems.values.compactMap { box in
            guard let item = box.item, item.modelContext != nil, item.deleteCookiesOnClose else {
                return nil
            }
            return item
        }
        
        for coordinator in activeCoordinators.allObjects {
            if coordinator.appItem.deleteCookiesOnClose {
                coordinator.cleanupWithoutFlushing()
            } else {
                coordinator.cleanup()
            }
        }
        activeCoordinators.removeAllObjects()
        
        for webView in activeWebViews.allObjects {
            teardownWebView(webView, purgeMemoryCache: false)
        }
        activeWebViews.removeAllObjects()
        
        await IsolatedCookieManager.shared.flushAllPendingSaves()
        
        for item in itemsToClear {
            await IsolatedCookieManager.shared.clearData(for: item, context: modelContainer.mainContext)
        }
        openCapsuleCounts.removeAll()
        openCapsuleItems.removeAll()
    }
    
    func register(webView: WKWebView) {
        activeWebViews.add(webView)
        activeDataStores.add(webView.configuration.websiteDataStore)
    }
    
    func isTornDown(_ webView: WKWebView) -> Bool {
        tornDownWebViews.contains(webView)
    }
    
    func teardownWebView(_ webView: WKWebView, purgeMemoryCache: Bool = true) {
        guard !tornDownWebViews.contains(webView) else { return }
        tornDownWebViews.add(webView)
        activeWebViews.remove(webView)
        
        webView.stopLoading()
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.closeAllMediaPresentations(completionHandler: nil)
        
        #if os(macOS)
        webView.setAllMediaPlaybackSuspended(true)
        if let isolatedWV = webView as? IsolatedWKWebView {
            isolatedWV.cleanup()
        }
        if let window = webView.window,
           let responderView = window.firstResponder as? NSView,
           responderView === webView || responderView.isDescendant(of: webView) {
            window.makeFirstResponder(nil)
        }
        #endif
        
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        controller.removeAllUserScripts()
        controller.removeAllScriptMessageHandlers()
        
        let dataStore = webView.configuration.websiteDataStore
        activeDataStores.add(dataStore)
        webView.removeFromSuperview()
        
        #if os(macOS)
        let closeSelector = NSSelectorFromString("_close")
        if webView.responds(to: closeSelector) {
            webView.perform(closeSelector)
        }
        #endif
        
        if purgeMemoryCache {
            dataStore.removeData(ofTypes: [WKWebsiteDataTypeMemoryCache], modifiedSince: .distantPast) {}
        }
    }
    
    func purgeIdleResources(teardownAllWebViews: Bool) async {
        await IsolatedCookieManager.shared.flushAllPendingSaves()
        
        if teardownAllWebViews {
            for webView in activeWebViews.allObjects {
                teardownWebView(webView, purgeMemoryCache: false)
            }
            activeWebViews.removeAllObjects()
        }
        
        var seenStores = Set<ObjectIdentifier>()
        var storesToPurge: [WKWebsiteDataStore] = []
        for store in activeDataStores.allObjects {
            let id = ObjectIdentifier(store)
            if seenStores.insert(id).inserted {
                storesToPurge.append(store)
            }
        }
        let defaultStore = WKWebsiteDataStore.default()
        if seenStores.insert(ObjectIdentifier(defaultStore)).inserted {
            storesToPurge.append(defaultStore)
        }
        
        for store in storesToPurge {
            await store.removeData(ofTypes: [WKWebsiteDataTypeMemoryCache], modifiedSince: .distantPast)
        }
        if teardownAllWebViews {
            activeDataStores.removeAllObjects()
        }
        
        UBlockOriginExtensionManager.shared.releaseInMemoryCaches()
        URLCache.shared.removeAllCachedResponses()
        IsolatedCookieManager.shared.releaseInMemoryCaches()
        IconImageCache.clear()
        #if os(macOS)
        ReaderImageCache.shared.clear()
        #endif
        
        #if DEBUG
        print("[Memory] Purged idle WebKit caches (teardownAllWebViews: \(teardownAllWebViews), stores: \(storesToPurge.count), remainingLiveWebViews: \(liveWebViewCount))")
        #endif
    }
}
