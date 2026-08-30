//
//  IsolatedWebView.swift
//  isowebapps
//
//  Created on 23/08/2026.
//
//  Description:
//  UIKit/AppKit representable wrapping a dedicated `WKWebView` instance per app.
//  Configures non-persistent cookie stores, desktop/media settings, HTML5 fullscreen,
//  and attaches live KVO / delegate observers to track history and URL mutations.
//

import SwiftUI
import WebKit
import SwiftData
import PDFKit
#if os(iOS)
import SafariServices
#endif
#if os(iOS)

struct IsolatedWebViewRepresentable: UIViewRepresentable {
    let appItem: WebAppItem
    @ObservedObject var navigationState: WebViewNavigationState
    let modelContext: ModelContext
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = createConfiguredWebView(context: context)
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Sync states if required
    }
    
    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(appItem: appItem, navigationState: navigationState, modelContext: modelContext)
    }
    
    static func dismantleUIView(_ uiView: WKWebView, coordinator: WebViewCoordinator) {
        #if DEBUG
        print("[IsolatedWebView] Dismantling UIView and stopping webView loading")
        #endif
        uiView.stopLoading()
        uiView.loadHTMLString("", baseURL: nil)
        coordinator.cleanup()
    }
}
#else
struct IsolatedWebViewRepresentable: NSViewRepresentable {
    let appItem: WebAppItem
    @ObservedObject var navigationState: WebViewNavigationState
    let modelContext: ModelContext
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = createConfiguredWebView(context: context)
        webView.autoresizingMask = [.width, .height]
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Sync states if required
    }
    
    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(appItem: appItem, navigationState: navigationState, modelContext: modelContext)
    }
    
    static func dismantleNSView(_ nsView: WKWebView, coordinator: WebViewCoordinator) {
        #if DEBUG
        print("[IsolatedWebView] Dismantling NSView and stopping webView loading")
        #endif
        nsView.stopLoading()
        nsView.loadHTMLString("", baseURL: nil)
        coordinator.cleanup()
    }
}
#endif

extension IsolatedWebViewRepresentable {
    func createConfiguredWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // 1. Isolate website data store per app instance
        let dataStore = WKWebsiteDataStore.nonPersistent()
        configuration.websiteDataStore = dataStore
        
        // 2. Enable HTML5 Fullscreen & Media Playback Capabilities
        let preferences = WKPreferences()
        preferences.isElementFullscreenEnabled = true
        #if os(macOS)
        preferences.setValue(true, forKey: "fullScreenEnabled")
        #endif
        configuration.preferences = preferences
        
        let webpagePreferences = WKWebpagePreferences()
        webpagePreferences.allowsContentJavaScript = true
        #if os(macOS)
        webpagePreferences.preferredContentMode = .desktop
        #else
        webpagePreferences.preferredContentMode = .mobile
        #endif
        configuration.defaultWebpagePreferences = webpagePreferences
        
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        #else
        configuration.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        #endif
        
        // 3. Conditional Content Blocking & YouTube Scripts
        let isYouTube = appItem.urlString.lowercased().contains("youtube.com")
        
        if isYouTube {
            // For YouTube: use dedicated lightweight script & native player controls instead of uBlock
            let ytPlaceholderScript = WKUserScript(
                source: YouTubeScripts.ytPlaceholderAndAdBlockScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            configuration.userContentController.addUserScript(ytPlaceholderScript)

            #if os(macOS)
            let ytNativeControlsUserScript = WKUserScript(
                source: YouTubeScripts.ytNativeControlsScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            configuration.userContentController.addUserScript(ytNativeControlsUserScript)
            #endif
        } else if appItem.isUBlockEnabled {
            // For other websites: load standard uBlock Origin rules and cosmetic scripts if enabled
            UBlockOriginExtensionManager.shared.applyToConfiguration(configuration)
        }
        
        // 4. Configure Application User Agent
        if isYouTube {
            let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
            configuration.applicationNameForUserAgent = "isowebapps/\(appVersion)"
        }
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        
        if !isYouTube {
            #if os(macOS)
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6.2 Safari/605.1.15"
            #else
            webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.4 Mobile/15E148 Safari/604.1"
            #endif
        }
        
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        #if os(iOS)
        webView.allowsBackForwardNavigationGestures = true
        #endif
        
        
        context.coordinator.setup(webView: webView)
        
        // Connect navigation actions
        navigationState.onGoBack = { [weak webView] in
            #if DEBUG
            print("[IsolatedWebView] Navigating Back")
            #endif
            webView?.goBack()
        }
        navigationState.onGoForward = { [weak webView] in
            #if DEBUG
            print("[IsolatedWebView] Navigating Forward")
            #endif
            webView?.goForward()
        }
        navigationState.onReload = { [weak webView] in
            #if DEBUG
            print("[IsolatedWebView] Reloading")
            #endif
            webView?.reload()
        }
        navigationState.onLoadURL = { [weak webView] url in
            #if DEBUG
            print("[IsolatedWebView] Loading custom URL: \(url)")
            #endif
            webView?.load(URLRequest(url: url))
        }
        navigationState.onStopLoading = { [weak webView] in
            #if DEBUG
            print("[IsolatedWebView] Stopping webView & clearing page")
            #endif
            webView?.stopLoading()
            webView?.loadHTMLString("", baseURL: nil)
        }
        navigationState.onToggleUBlock = { [weak webView, weak contextCoordinator = context.coordinator] isEnabled in
            guard let webView = webView, let coordinator = contextCoordinator else { return }
            let config = webView.configuration
            let isYT = coordinator.appItem.urlString.lowercased().contains("youtube.com")
            guard !isYT else { return }
            
            if isEnabled {
                UBlockOriginExtensionManager.shared.applyToConfiguration(config)
            } else {
                UBlockOriginExtensionManager.shared.removeFromConfiguration(config)
            }
            webView.reload()
        }
        navigationState.onCaptureFirstPagePDFText = { [weak webView] in
            guard let webView = webView else {
                throw WebPageSummaryError.webViewUnavailable
            }
            
            let title = webView.title ?? ""
            let urlString = webView.url?.absoluteString ?? ""
            
            // 1. Generate PDF of the rendered web page
            let pdfConfig = WKPDFConfiguration()
            let pdfData: Data = try await withCheckedThrowingContinuation { continuation in
                webView.createPDF(configuration: pdfConfig) { result in
                    continuation.resume(with: result)
                }
            }
            
            // 2. Extract content from the first page only
            guard let document = PDFDocument(data: pdfData),
                  let firstPage = document.page(at: 0) else {
                throw WebPageSummaryError.pdfExtractionFailed
            }
            
            var pageText = firstPage.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if pageText.isEmpty {
                // Fallback: If PDF text layer is empty or rasterized, extract DOM innerText
                let evaluated = try? await webView.evaluateJavaScript("document.body.innerText") as? String
                pageText = evaluated?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            
            return (title: title, url: urlString, text: pageText)
        }
        
        // 3. Restore isolated cookies and load start page (last opened URL or configured home URL)
        Task { @MainActor in
            await IsolatedCookieManager.shared.restoreCookies(for: appItem, into: dataStore.httpCookieStore)
            let startURLString = appItem.lastOpenedURLString ?? appItem.urlString
            if let url = URL(string: startURLString) {
                #if DEBUG
                print("[IsolatedWebView] Starting initial load for: \(url) (configured home: \(appItem.urlString))")
                #endif
                let request = URLRequest(url: url)
                webView.load(request)
            }
        }
        
        return webView
    }
}

class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    let appItem: WebAppItem
    let navigationState: WebViewNavigationState
    let modelContext: ModelContext
    weak var webView: WKWebView?
    private var backForwardObserver: NSKeyValueObservation?
    private var canGoForwardObserver: NSKeyValueObservation?
    private var urlObserver: NSKeyValueObservation?
    private var loadingObserver: NSKeyValueObservation?
    private weak var observedCookieStore: WKHTTPCookieStore?
    
    init(appItem: WebAppItem, navigationState: WebViewNavigationState, modelContext: ModelContext) {
        self.appItem = appItem
        self.navigationState = navigationState
        self.modelContext = modelContext
        super.init()
    }
    
    func setup(webView: WKWebView) {
        self.webView = webView
        
        DispatchQueue.main.async { [weak self, weak webView] in
            guard let self = self, let webView = webView else { return }
            
            // Observe canGoBack KVO asynchronously to prevent layout recursion during view initialization
            self.backForwardObserver = webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.navigationState.canGoBack = wv.canGoBack
                    #if DEBUG
                    print("[IsolatedWebView KVO] canGoBack: \(wv.canGoBack)")
                    #endif
                }
            }
            
            // Observe canGoForward KVO directly
            self.canGoForwardObserver = webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.navigationState.canGoForward = wv.canGoForward
                    #if DEBUG
                    print("[IsolatedWebView KVO] canGoForward: \(wv.canGoForward)")
                    #endif
                }
            }
            
            // Observe current URL
            self.urlObserver = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    if let urlStr = wv.url?.absoluteString, !urlStr.isEmpty, urlStr != "about:blank" {
                        self?.navigationState.currentURLString = urlStr
                    }
                }
            }
            
            // Observe isLoading
            self.loadingObserver = webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.navigationState.isLoading = wv.isLoading
                }
            }
            
            // Observe Cookie Store changes live (consent cookies, session tokens, etc.)
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            self.observedCookieStore = cookieStore
            cookieStore.add(self)
        }
    }
    
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in
            await IsolatedCookieManager.shared.persistCookies(
                for: appItem,
                from: cookieStore,
                context: modelContext
            )
        }
    }
    
    func cleanup() {
        backForwardObserver?.invalidate()
        canGoForwardObserver?.invalidate()
        urlObserver?.invalidate()
        loadingObserver?.invalidate()
        observedCookieStore?.remove(self)
        observedCookieStore = nil
        webView = nil
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navigationState.isLoading = true
        if let urlString = webView.url?.absoluteString, !urlString.isEmpty, urlString != "about:blank" {
            navigationState.currentURLString = urlString
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Defer handling of target="_blank" (new window) links to createWebViewWith
        // to prevent the WKWebView from going blank when we cancel the navigation.
        if navigationAction.targetFrame == nil {
            decisionHandler(.allow)
            return
        }
        
        if appItem.openLinksInSafariReaderMode, navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            // If the link is on the same root domain (e.g. accounts.google.com from news.google.com),
            // keep the navigation inside the WKWebView so session, cookies, and authentication flows work.
            if !isInternalNavigation(to: url, currentWebViewURL: webView.url) {
                decisionHandler(.cancel)
                openInSafariReader(url: url)
                return
            }
        }
        decisionHandler(.allow)
    }
    
    private func isInternalNavigation(to targetURL: URL, currentWebViewURL: URL?) -> Bool {
        // Allow non-HTTP(S) schemes, about:blank, or local navigation to proceed in WKWebView
        guard let targetHost = targetURL.host?.lowercased(), !targetHost.isEmpty else {
            return true
        }
        
        let targetRoot = targetURL.rootDomain
        
        // Compare with configured WebApp starting URL (e.g. news.google.com -> google.com)
        if let appRoot = URL(string: appItem.urlString)?.rootDomain, targetRoot == appRoot {
            return true
        }
        
        // Compare with current active page URL in the WebView
        if let currentRoot = currentWebViewURL?.rootDomain, targetRoot == currentRoot {
            return true
        }
        
        return false
    }
    
    private func openInSafariReader(url: URL) {
        // Dispatch to main queue asynchronously to allow the WKNavigationDelegate callback
        // to finish returning .cancel, avoiding WebKit state inconsistencies that cause blank pages.
        DispatchQueue.main.async {
            self.navigationState.onOpenSafari?(url)
        }
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let urlString = webView.url?.absoluteString, !urlString.isEmpty, urlString != "about:blank" {
            navigationState.currentURLString = urlString
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationState.isLoading = false
        navigationState.canGoBack = webView.canGoBack
        navigationState.canGoForward = webView.canGoForward
        if let urlString = webView.url?.absoluteString, !urlString.isEmpty, urlString != "about:blank" {
            navigationState.currentURLString = urlString
            // Persist the last opened URL for this web app
            appItem.lastOpenedURLString = urlString
            appItem.lastVisited = Date()
            try? modelContext.save()
        }
        
        // Persist cookies after navigation completes
        Task { @MainActor in
            await IsolatedCookieManager.shared.persistCookies(
                for: appItem,
                from: webView.configuration.websiteDataStore.httpCookieStore,
                context: modelContext
            )
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationState.isLoading = false
        navigationState.canGoBack = webView.canGoBack
        navigationState.canGoForward = webView.canGoForward
    }
    
    // Handle target="_blank" and popup windows inside the same isolated webview
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            if let url = navigationAction.request.url {
                if appItem.openLinksInSafariReaderMode && !isInternalNavigation(to: url, currentWebViewURL: webView.url) {
                    openInSafariReader(url: url)
                } else {
                    webView.load(navigationAction.request)
                }
            }
        }
        return nil
    }
}

// MARK: - URL Root Domain Helper

private extension URL {
    /// Extracts the root/registrable domain (e.g. "google.com" from "accounts.google.com" or "news.google.com")
    var rootDomain: String? {
        guard let host = self.host?.lowercased() else { return nil }
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count > 1 else { return host }
        
        // Multi-part second-level domains (e.g. .co.uk, .com.au, .gouv.fr, .asso.fr, .org.uk)
        let multiPartTLDs: Set<String> = ["co", "com", "net", "org", "gov", "edu", "gouv", "asso"]
        if parts.count >= 3, let secondToLast = parts.dropLast().last, multiPartTLDs.contains(secondToLast) {
            return parts.suffix(3).joined(separator: ".")
        }
        
        return parts.suffix(2).joined(separator: ".")
    }
}
