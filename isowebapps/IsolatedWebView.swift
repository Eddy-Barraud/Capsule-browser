//
//  IsolatedWebView.swift
//  isowebapps
//
//  Created on 23/08/2026.
//

import SwiftUI
import WebKit
import SwiftData

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
        webpagePreferences.preferredContentMode = .recommended
        #endif
        configuration.defaultWebpagePreferences = webpagePreferences
        
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        #endif
        
        // 3. Load uBlock Origin rules and cosmetic scripts
        UBlockOriginExtensionManager.shared.applyToConfiguration(configuration)
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        // Set standard Safari User-Agent so YouTube & media sites enable Full HD / 4K DASH MSE streaming
        #if os(macOS)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
        #else
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"
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
        
        // 3. Restore isolated cookies asynchronously
        Task { @MainActor in
            await IsolatedCookieManager.shared.restoreCookies(for: appItem, into: dataStore.httpCookieStore)
            if let url = URL(string: appItem.urlString) {
                #if DEBUG
                print("[IsolatedWebView] Starting initial load for: \(url)")
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
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationState.isLoading = false
        navigationState.canGoBack = webView.canGoBack
        navigationState.canGoForward = webView.canGoForward
        if let urlString = webView.url?.absoluteString, !urlString.isEmpty, urlString != "about:blank" {
            navigationState.currentURLString = urlString
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
            webView.load(navigationAction.request)
        }
        return nil
    }
}
