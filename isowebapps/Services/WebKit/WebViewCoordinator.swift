//
//  WebViewCoordinator.swift
//  isowebapps
//
//  Description:
//  `WKNavigationDelegate` and `WKUIDelegate` coordinator managing KVO state,
//  cookie persistence, scheme validation, reader redirection, downloads,
//  and uBlock configuration updates for an isolated `WKWebView`.
//

import Foundation
import WebKit
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    let appItem: WebAppItem
    let navigationState: WebViewNavigationState
    let modelContext: ModelContext
    weak var webView: WKWebView?
    var webViewToken: UUID?
    var onOpenNewWindowOrTab: ((URL) -> Void)?
    private var hasCommittedAnyPage: Bool = false
    private var hasFlushedOnCleanup: Bool = false
    private var backForwardObserver: NSKeyValueObservation?
    private var canGoForwardObserver: NSKeyValueObservation?
    private var urlObserver: NSKeyValueObservation?
    private var loadingObserver: NSKeyValueObservation?
    private weak var observedCookieStore: WKHTTPCookieStore?
    private var uBlockUpdateObserver: Any?
    private var capsuleUBlockSettingObserver: Any?
    private var appLifecycleObservers: [Any] = []
    
    init(appItem: WebAppItem, navigationState: WebViewNavigationState, modelContext: ModelContext) {
        self.appItem = appItem
        self.navigationState = navigationState
        self.modelContext = modelContext
        super.init()
    }
    
    deinit {
        #if DEBUG
        print("[Memory] WebViewCoordinator deinit: '\(appItem.name)'")
        #endif
        cleanup()
    }
    
    func setup(webView: WKWebView) {
        self.webView = webView
        self.observedCookieStore = webView.configuration.websiteDataStore.httpCookieStore
        WebKitMemoryManager.shared.register(coordinator: self)
        
        DispatchQueue.main.async { [weak self, weak webView] in
            guard let self = self, !self.hasFlushedOnCleanup, let webView = webView else { return }
            
            self.backForwardObserver = webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.navigationState.canGoBack = wv.canGoBack
                }
            }
            
            self.canGoForwardObserver = webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.navigationState.canGoForward = wv.canGoForward
                }
            }
            
            self.urlObserver = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    #if os(macOS)
                    self?.navigationState.currentBackgroundWebViewURL = wv.url
                    if self?.navigationState.isReaderModeActive == true { return }
                    #endif
                    if let urlStr = wv.url?.absoluteString, !urlStr.isEmpty, urlStr != "about:blank" {
                        self?.navigationState.currentURLString = urlStr
                    }
                }
            }
            
            self.loadingObserver = webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    #if os(macOS)
                    if self?.navigationState.isReaderModeActive == true { return }
                    #endif
                    self?.navigationState.isLoading = wv.isLoading
                }
            }
            
            #if os(iOS)
            let lifecycleNames: [Notification.Name] = [
                UIApplication.willResignActiveNotification,
                UIApplication.willTerminateNotification
            ]
            #else
            let lifecycleNames: [Notification.Name] = [
                NSApplication.willTerminateNotification
            ]
            #endif
            for name in lifecycleNames {
                let obs = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.flushCookiesNow()
                }
                self.appLifecycleObservers.append(obs)
            }
            
            self.uBlockUpdateObserver = NotificationCenter.default.addObserver(
                forName: UBlockOriginExtensionManager.didUpdateRulesNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let webView = self.webView else { return }
                    Self.applyUBlockSetting(isEnabled: self.appItem.isUBlockEnabled, to: webView, reload: true)
                }
            }
            
            self.capsuleUBlockSettingObserver = NotificationCenter.default.addObserver(
                forName: UBlockOriginExtensionManager.capsuleUBlockSettingChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let targetId = notification.object as? UUID
                let overrideEnabled = notification.userInfo?["isUBlockEnabled"] as? Bool
                MainActor.assumeIsolated {
                    guard let self,
                          let webView = self.webView,
                          let targetId,
                          targetId == self.appItem.id else { return }
                    
                    let isEnabled = overrideEnabled ?? self.appItem.isUBlockEnabled
                    self.navigationState.isUBlockEnabled = isEnabled
                    Self.applyUBlockSetting(isEnabled: isEnabled, to: webView, reload: true)
                }
            }
        }
    }
    
    @MainActor
    static func applyUBlockSetting(isEnabled: Bool, to webView: WKWebView, reload: Bool) {
        let config = webView.configuration
        if isEnabled {
            UBlockOriginExtensionManager.shared.applyToConfiguration(config)
        } else {
            UBlockOriginExtensionManager.shared.removeFromConfiguration(config)
        }
        if reload {
            webView.reloadFromOrigin()
        }
    }
    
    func flushCookiesNow() {
        guard appItem.modelContext != nil,
              !appItem.deleteCookiesOnClose,
              let cookieStore = observedCookieStore else { return }
        IsolatedCookieManager.shared.flushPendingSaveInBackground(
            for: appItem,
            from: cookieStore,
            context: modelContext,
            lastOpenedURL: navigationState.currentURLString
        )
    }
    
    func cleanupForSleep() {
        cleanupInternal(reason: "deep sleep", flushCookies: true)
    }
    
    func cleanup() {
        cleanupInternal(reason: "close/dismantle", flushCookies: true)
    }
    
    func cleanupWithoutFlushing() {
        cleanupInternal(reason: "termination wipe", flushCookies: false)
    }
    
    private func cleanupInternal(reason: String, flushCookies: Bool) {
        guard !hasFlushedOnCleanup else { return }
        hasFlushedOnCleanup = true
        #if DEBUG
        print("[CapsuleClose] WebViewCoordinator cleanup (\(reason)) for '\(appItem.name)'")
        #endif
        if flushCookies {
            flushCookiesNow()
        }
        navigationState.clearWebViewCallbacks(matching: webViewToken)
        backForwardObserver?.invalidate()
        backForwardObserver = nil
        canGoForwardObserver?.invalidate()
        canGoForwardObserver = nil
        urlObserver?.invalidate()
        urlObserver = nil
        loadingObserver?.invalidate()
        loadingObserver = nil
        observedCookieStore = nil
        if let obs = uBlockUpdateObserver {
            NotificationCenter.default.removeObserver(obs)
            uBlockUpdateObserver = nil
        }
        if let obs = capsuleUBlockSettingObserver {
            NotificationCenter.default.removeObserver(obs)
            capsuleUBlockSettingObserver = nil
        }
        for obs in appLifecycleObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        appLifecycleObservers.removeAll()
        webView = nil
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        #if os(macOS)
        navigationState.lastBackgroundLoadError = nil
        navigationState.currentBackgroundWebViewURL = webView.url
        guard !navigationState.isReaderModeActive else { return }
        #endif
        navigationState.isLoading = true
        if let urlString = webView.url?.absoluteString, !urlString.isEmpty, urlString != "about:blank" {
            navigationState.currentURLString = urlString
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let targetURL = navigationAction.request.url,
           let scheme = targetURL.scheme?.lowercased() {
            if scheme == "mailto" || scheme == "tel" {
                #if os(macOS)
                NSWorkspace.shared.open(targetURL)
                #else
                UIApplication.shared.open(targetURL, options: [:], completionHandler: nil)
                #endif
                decisionHandler(.cancel)
                return
            }
            
            let allowedSchemes: Set<String> = ["http", "https", "about", "data", "blob"]
            if !allowedSchemes.contains(scheme) {
                decisionHandler(.cancel)
                return
            }
            
            IsolatedWebViewRepresentable.updateUserAgent(for: webView, targetURL: targetURL)
        }
        
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        
        if navigationAction.targetFrame == nil {
            decisionHandler(.allow)
            return
        }
        
        #if os(macOS)
        let shouldInterceptReaderLinks = appItem.openLinksInSafariReaderMode && !navigationState.isReaderModeActive
        #else
        let shouldInterceptReaderLinks = appItem.openLinksInSafariReaderMode
        #endif
        
        if shouldInterceptReaderLinks, let url = navigationAction.request.url {
            let isUserClick = navigationAction.navigationType == .linkActivated
            let isExternalRedirect = navigationAction.navigationType == .other && (
                !hasCommittedAnyPage || (webView.url != nil && webView.url?.absoluteString != "about:blank")
            )
            
            if (isUserClick || isExternalRedirect) && !isInternalNavigation(to: url, currentWebViewURL: webView.url) {
                decisionHandler(.cancel)
                openInSafariReader(url: url)
                #if os(macOS)
                if !hasCommittedAnyPage {
                    DispatchQueue.main.async { [weak webView] in
                        if let window = webView?.window, window !== MainWindowTracker.shared.mainWindow {
                            window.close()
                        }
                    }
                }
                #endif
                return
            }
        }
        decisionHandler(.allow)
    }
    
    private func isExternalArticleOrRedirect(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host.contains("news.google.") || host == "google.com" || host.hasSuffix(".google.com") {
            let path = url.path.lowercased()
            if path.hasPrefix("/read/") || path.hasPrefix("/articles/") || path.hasPrefix("/rss/articles/") || path.hasPrefix("/stories/") {
                return true
            }
            if path == "/url" || path.hasPrefix("/url/") {
                return true
            }
        }
        if host == "out.reddit.com" || host == "t.co" {
            return true
        }
        return false
    }
    
    private func isInternalNavigation(to targetURL: URL, currentWebViewURL: URL?) -> Bool {
        guard let targetHost = targetURL.host?.lowercased(), !targetHost.isEmpty else {
            return true
        }
        if isExternalArticleOrRedirect(url: targetURL) {
            return false
        }
        let targetRoot = targetURL.rootDomain
        if let appRoot = URL(string: appItem.urlString)?.rootDomain, targetRoot == appRoot {
            return true
        }
        if let currentRoot = currentWebViewURL?.rootDomain, targetRoot == currentRoot {
            return true
        }
        return false
    }
    
    private func openInSafariReader(url: URL) {
        DispatchQueue.main.async {
            self.navigationState.onOpenSafariReader?(url)
        }
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let urlString = webView.url?.absoluteString, !urlString.isEmpty, urlString != "about:blank" {
            hasCommittedAnyPage = true
            #if os(macOS)
            navigationState.currentBackgroundWebViewURL = webView.url
            navigationState.webViewCommitGeneration += 1
            if !navigationState.isReaderModeActive {
                navigationState.currentURLString = urlString
            }
            #else
            navigationState.currentURLString = urlString
            #endif
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        #if os(macOS)
        let readerActive = navigationState.isReaderModeActive
        navigationState.currentBackgroundWebViewURL = webView.url
        if let urlString = webView.url?.absoluteString, !urlString.isEmpty, urlString != "about:blank" {
            navigationState.webViewFinishGeneration += 1
        }
        if readerActive {
            webView.pauseAllMediaPlayback(completionHandler: nil)
            webView.setAllMediaPlaybackSuspended(true)
        }
        #else
        let readerActive = false
        #endif
        if !readerActive {
            navigationState.isLoading = false
        }
        navigationState.canGoBack = webView.canGoBack
        navigationState.canGoForward = webView.canGoForward
        let activeURLString: String?
        if let urlString = webView.url?.absoluteString, !urlString.isEmpty, urlString != "about:blank" {
            if !readerActive {
                navigationState.currentURLString = urlString
            }
            activeURLString = urlString
        } else {
            activeURLString = nil
        }
        
        if appItem.modelContext != nil {
            IsolatedCookieManager.shared.schedulePersistCookies(
                for: appItem,
                from: webView.configuration.websiteDataStore.httpCookieStore,
                context: modelContext,
                lastOpenedURL: activeURLString
            )
        }
        
        #if os(macOS)
        if let isolatedWV = webView as? IsolatedWKWebView {
            isolatedWV.reapplySleepingStateIfNeeded()
        }
        #endif
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(webView, error: error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(webView, error: error)
    }
    
    private func handleLoadFailure(_ webView: WKWebView, error: Error) {
        #if os(macOS)
        if navigationState.isReaderModeActive {
            let nsErr = error as NSError
            if !ReaderHTMLUtilities.shouldIgnoreBackgroundNavigationError(domain: nsErr.domain, code: nsErr.code) {
                navigationState.lastBackgroundLoadError = error.localizedDescription
            }
        } else {
            navigationState.isLoading = false
        }
        #else
        navigationState.isLoading = false
        #endif
        navigationState.canGoBack = webView.canGoBack
        navigationState.canGoForward = webView.canGoForward
    }
    
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if let httpResponse = navigationResponse.response as? HTTPURLResponse,
           (httpResponse.statusCode == 204 || httpResponse.statusCode == 205) {
            decisionHandler(.cancel)
            return
        }
        
        if CapsuleDownloadManager.shouldDownloadResponse(
            navigationResponse.response,
            canShowMIMEType: navigationResponse.canShowMIMEType,
            isForMainFrame: navigationResponse.isForMainFrame
        ) {
            let allowedSchemes: Set<String> = ["http", "https", "data", "blob"]
            let scheme = navigationResponse.response.url?.scheme?.lowercased()
            if scheme == nil || allowedSchemes.contains(scheme!) {
                decisionHandler(.download)
                return
            }
        }
        
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        navigationState.isLoading = false
        CapsuleDownloadManager.shared.registerDownload(download, originatingWebView: webView)
    }
    
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        navigationState.isLoading = false
        CapsuleDownloadManager.shared.registerDownload(download, originatingWebView: webView)
    }
    
    // MARK: - WKUIDelegate
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            #if os(macOS)
            let shouldOpenNewTabInReader = appItem.openLinksInSafariReaderMode && !navigationState.isReaderModeActive
            #else
            let shouldOpenNewTabInReader = appItem.openLinksInSafariReaderMode
            #endif
            if shouldOpenNewTabInReader && !isInternalNavigation(to: url, currentWebViewURL: webView.url) {
                openInSafariReader(url: url)
                return nil
            }
            
            #if os(macOS)
            let mode = MainWindowTracker.shared.currentPresentationMode
            let handler = onOpenNewWindowOrTab ?? navigationState.onOpenNewWindowOrTab
            if mode != .singleWindow {
                if let win = webView.window {
                    MainWindowTracker.shared.persistWindowSize(from: win)
                    MainWindowTracker.shared.targetWindowForNewTab = win
                }
                if let handler = handler {
                    DispatchQueue.main.async {
                        handler(url)
                    }
                }
                return nil
            }
            #endif
            
            IsolatedWebViewRepresentable.updateUserAgent(for: webView, targetURL: url)
            webView.load(navigationAction.request)
        }
        return nil
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.prompt)
    }
}

private extension URL {
    var rootDomain: String? {
        guard let host = self.host?.lowercased() else { return nil }
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count > 1 else { return host }
        
        let multiPartTLDs: Set<String> = ["co", "com", "net", "org", "gov", "edu", "gouv", "asso"]
        if parts.count >= 3, let secondToLast = parts.dropLast().last, multiPartTLDs.contains(secondToLast) {
            return parts.suffix(3).joined(separator: ".")
        }
        return parts.suffix(2).joined(separator: ".")
    }
}
