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
    var initialURLString: String? = nil
    @ObservedObject var navigationState: WebViewNavigationState
    let modelContext: ModelContext
    var onOpenNewWindowOrTab: ((URL) -> Void)? = nil
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = createConfiguredWebView(context: context)
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onOpenNewWindowOrTab = onOpenNewWindowOrTab
    }
    
    func makeCoordinator() -> WebViewCoordinator {
        let coordinator = WebViewCoordinator(appItem: appItem, navigationState: navigationState, modelContext: modelContext)
        coordinator.onOpenNewWindowOrTab = onOpenNewWindowOrTab
        return coordinator
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
import AppKit

class IsolatedWKWebView: WKWebView {
    private(set) var isSleeping: Bool = false
    private var activityAssertionToken: NSObjectProtocol?
    private var notificationObservers: [NSObjectProtocol] = []
    private var tabGroupObservation: NSKeyValueObservation?
    private var windowTabGroupObservation: NSKeyValueObservation?
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupWindowTracking()
    }
    
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        let modeRaw = UserDefaults.standard.string(forKey: "windowPresentationMode") ?? "singleWindow"
        #if DEBUG
        print("[IsolatedWKWebView] willOpenMenu called! mode: \(modeRaw), menu items count: \(menu.items.count)")
        #endif
        for item in menu.items {
            if modeRaw == "tabs" {
                if item.identifier?.rawValue == "WKMenuItemIdentifierOpenLinkInNewWindow" || item.title.contains("New Window") {
                    item.title = item.title.replacingOccurrences(of: "New Window", with: "New Tab")
                }
            }
        }
    }
    
    // MARK: - Window & Tab Group Lifecycle Tracking
    
    private func setupWindowTracking() {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()
        tabGroupObservation?.invalidate()
        tabGroupObservation = nil
        windowTabGroupObservation?.invalidate()
        windowTabGroupObservation = nil
        
        guard let window = self.window else {
            putToSleep()
            return
        }
        
        let nc = NotificationCenter.default
        let notifications: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didResignMainNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeOcclusionStateNotification
        ]
        
        for name in notifications {
            let obs = nc.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.evaluateSleepWakeStatus()
            }
            notificationObservers.append(obs)
        }
        
        // Observe preference changes so toggling Sleeping Tabs in settings takes effect immediately
        let userDefaultsObs = nc.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.evaluateSleepWakeStatus()
        }
        notificationObservers.append(userDefaultsObs)
        
        // Observe tabGroup changes on the window
        windowTabGroupObservation = window.observe(\.tabGroup, options: [.initial, .new]) { [weak self] win, _ in
            self?.setupTabGroupObservation(for: win)
        }
        
        setupTabGroupObservation(for: window)
        evaluateSleepWakeStatus()
    }
    
    private func setupTabGroupObservation(for window: NSWindow) {
        tabGroupObservation?.invalidate()
        tabGroupObservation = window.tabGroup?.observe(\.selectedWindow, options: [.initial, .new]) { [weak self] _, _ in
            self?.evaluateSleepWakeStatus()
        }
    }
    
    // MARK: - Sleep & Wake Evaluation
    
    func evaluateSleepWakeStatus() {
        guard let window = self.window else {
            putToSleep()
            return
        }
        
        let isSleepingTabsEnabled = UserDefaults.standard.object(forKey: "sleepingTabsEnabled") as? Bool ?? true
        if !isSleepingTabsEnabled {
            wakeUp()
            return
        }
        
        // If window is miniaturized or occluded (completely covered/invisible), put it to sleep
        if window.isMiniaturized || !window.occlusionState.contains(.visible) {
            putToSleep()
            return
        }
        
        // If part of a tab group:
        if let tabGroup = window.tabGroup, let selected = tabGroup.selectedWindow {
            if selected == window {
                wakeUp()
            } else {
                putToSleep()
            }
            return
        }
        
        // Standalone or separate window mode
        wakeUp()
    }
    
    // MARK: - State Transitions
    
    func putToSleep() {
        guard !isSleeping else { return }
        isSleeping = true
        #if DEBUG
        print("[IsolatedWKWebView] Tab sleeping: \(self.url?.host ?? "untitled")")
        #endif
        
        releaseForegroundActivityToken()
        
        // Suspend media playback unless active audio/music is playing
        if !hasActiveAudioPlayback {
            setAllMediaPlaybackSuspended(true)
        }
        
        // Dispatch Page Visibility API 'hidden' event to suspend rAF, intervals, and DOM animation loops
        evaluateJavaScript("""
        if (document.hidden !== true) {
            Object.defineProperty(document, 'hidden', { value: true, configurable: true });
            Object.defineProperty(document, 'visibilityState', { value: 'hidden', configurable: true });
            document.dispatchEvent(new Event('visibilitychange'));
        }
        """, completionHandler: nil)
    }
    
    func wakeUp() {
        let wasSleeping = isSleeping
        isSleeping = false
        
        if wasSleeping {
            #if DEBUG
            print("[IsolatedWKWebView] Tab waking up: \(self.url?.host ?? "untitled")")
            #endif
            
            // Resume media playback
            setAllMediaPlaybackSuspended(false)
            
            // Dispatch Page Visibility API 'visible' event to resume page loops
            evaluateJavaScript("""
            if (document.hidden !== false) {
                Object.defineProperty(document, 'hidden', { value: false, configurable: true });
                Object.defineProperty(document, 'visibilityState', { value: 'visible', configurable: true });
                document.dispatchEvent(new Event('visibilitychange'));
            }
            """, completionHandler: nil)
        }
        
        // If foreground key window, prioritize threads and CPU scheduling
        if window?.isKeyWindow == true {
            claimForegroundActivityToken()
        } else {
            releaseForegroundActivityToken()
        }
    }
    
    func reapplySleepingStateIfNeeded() {
        guard isSleeping else { return }
        if !hasActiveAudioPlayback {
            setAllMediaPlaybackSuspended(true)
        }
        evaluateJavaScript("""
        if (document.hidden !== true) {
            Object.defineProperty(document, 'hidden', { value: true, configurable: true });
            Object.defineProperty(document, 'visibilityState', { value: 'hidden', configurable: true });
            document.dispatchEvent(new Event('visibilitychange'));
        }
        """, completionHandler: nil)
    }
    
    // MARK: - Resource & Priority Management
    
    private func claimForegroundActivityToken() {
        guard activityAssertionToken == nil else { return }
        activityAssertionToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Active Capsule Foreground Web Tab"
        )
    }
    
    private func releaseForegroundActivityToken() {
        if let token = activityAssertionToken {
            ProcessInfo.processInfo.endActivity(token)
            activityAssertionToken = nil
        }
    }
    
    private var hasActiveAudioPlayback: Bool {
        let isPlayingAudioSel = NSSelectorFromString("_isPlayingAudio")
        if responds(to: isPlayingAudioSel) {
            typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
            if let method = class_getMethodImplementation(type(of: self), isPlayingAudioSel) {
                let fn = unsafeBitCast(method, to: Getter.self)
                if fn(self, isPlayingAudioSel) {
                    return true
                }
            }
        }
        
        let nowPlayingSel = NSSelectorFromString("_hasActiveNowPlayingSession")
        if responds(to: nowPlayingSel) {
            typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
            if let method = class_getMethodImplementation(type(of: self), nowPlayingSel) {
                let fn = unsafeBitCast(method, to: Getter.self)
                if fn(self, nowPlayingSel) {
                    return true
                }
            }
        }
        return false
    }
    
    func cleanup() {
        releaseForegroundActivityToken()
        tabGroupObservation?.invalidate()
        tabGroupObservation = nil
        windowTabGroupObservation?.invalidate()
        windowTabGroupObservation = nil
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()
    }
    
    deinit {
        cleanup()
    }
}

struct IsolatedWebViewRepresentable: NSViewRepresentable {
    let appItem: WebAppItem
    var initialURLString: String? = nil
    @ObservedObject var navigationState: WebViewNavigationState
    let modelContext: ModelContext
    var onOpenNewWindowOrTab: ((URL) -> Void)? = nil
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = createConfiguredWebView(context: context)
        webView.autoresizingMask = [.width, .height]
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onOpenNewWindowOrTab = onOpenNewWindowOrTab
    }
    
    func makeCoordinator() -> WebViewCoordinator {
        let coordinator = WebViewCoordinator(appItem: appItem, navigationState: navigationState, modelContext: modelContext)
        coordinator.onOpenNewWindowOrTab = onOpenNewWindowOrTab
        return coordinator
    }
    
    static func dismantleNSView(_ nsView: WKWebView, coordinator: WebViewCoordinator) {
        #if DEBUG
        print("[IsolatedWebView] Dismantling NSView and stopping webView loading")
        #endif
        if let isolatedWV = nsView as? IsolatedWKWebView {
            isolatedWV.cleanup()
        }
        nsView.stopLoading()
        coordinator.cleanup()
    }
}
#endif

extension IsolatedWebViewRepresentable {
    func createConfiguredWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // 1. Configure website data store:
        // Ephemeral capsules (e.g. launched from search bar) have no modelContext -> use nonPersistent().
        // Persistent capsules use WKWebsiteDataStore(forIdentifier:) with the group ID if grouped,
        // or the app item ID if standalone, guaranteeing on-disk isolation and persistence of
        // cookies, localStorage, and IndexedDB across app relaunches.
        let dataStore: WKWebsiteDataStore
        if appItem.modelContext == nil {
            dataStore = WKWebsiteDataStore.nonPersistent()
        } else {
            let storeId = appItem.group?.id ?? appItem.id
            dataStore = WKWebsiteDataStore(forIdentifier: storeId)
        }
        configuration.websiteDataStore = dataStore
        
        // 2. Enable HTML5 Fullscreen & Media Playback Capabilities
        let preferences = WKPreferences()
        preferences.isElementFullscreenEnabled = true
        #if os(macOS)
        preferences.setValue(true, forKey: "fullScreenEnabled")
        // Automatic WebKit DOM timer throttling for hidden/occluded background pages
        preferences.setValue(true, forKey: "hiddenPageDOMTimerThrottlingEnabled")
        preferences.setValue(true, forKey: "hiddenPageDOMTimerThrottlingAutoIncreases")
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
        
        #if os(macOS)
        let webView = IsolatedWKWebView(frame: .zero, configuration: configuration)
        #else
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.keyboardDismissMode = .interactive
        #endif
        
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
        
        // 3. Restore isolated cookies (including grouped apps if applicable) and load start page
        Task { @MainActor in
            let groupedItems = appItem.group?.items ?? []
            await IsolatedCookieManager.shared.restoreCookies(for: appItem, groupedItems: groupedItems, into: dataStore.httpCookieStore)
            let startURLString = initialURLString ?? appItem.lastOpenedURLString ?? appItem.urlString
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
    var onOpenNewWindowOrTab: ((URL) -> Void)?
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
        guard appItem.modelContext != nil else { return }
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
        #if DEBUG
        print("[IsolatedWebView] decidePolicyFor: targetFrame nil: \(navigationAction.targetFrame == nil), url: \(String(describing: navigationAction.request.url)), navType: \(navigationAction.navigationType.rawValue)")
        #endif
        // Defer handling of target="_blank" (new window) links to createWebViewWith
        // to prevent the WKWebView from going blank when we cancel the navigation.
        if navigationAction.targetFrame == nil {
            #if DEBUG
            print("[IsolatedWebView] decidePolicyFor: targetFrame is nil, returning .allow to let createWebViewWith handle it")
            #endif
            decisionHandler(.allow)
            return
        }
        
        if appItem.openLinksInSafariReaderMode, let url = navigationAction.request.url {
            let isUserClick = navigationAction.navigationType == .linkActivated
            let isExternalRedirect = navigationAction.navigationType == .other && webView.url != nil && webView.url?.absoluteString != "about:blank"
            
            // If the link is on an external domain or is a known article redirector (like Google News /read/...),
            // open it in Safari Reader mode and cancel navigation inside the isolated WKWebView.
            if (isUserClick || isExternalRedirect) && !isInternalNavigation(to: url, currentWebViewURL: webView.url) {
                #if DEBUG
                print("[IsolatedWebView] decidePolicyFor: external domain, canceling and opening in Safari Reader")
                #endif
                decisionHandler(.cancel)
                openInSafariReader(url: url)
                return
            }
        }
        #if DEBUG
        print("[IsolatedWebView] decidePolicyFor: allowing navigation in current webview to \(String(describing: navigationAction.request.url))")
        #endif
        decisionHandler(.allow)
    }
    
    /// Checks whether a URL is a known intermediary article redirector (e.g. Google News /read/... or /articles/...)
    /// that leads to an external publication.
    private func isExternalArticleOrRedirect(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        
        // Google News & Google Search redirect patterns
        if host.contains("news.google.") || host == "google.com" || host.hasSuffix(".google.com") {
            let path = url.path.lowercased()
            if path.hasPrefix("/read/") || path.hasPrefix("/articles/") || path.hasPrefix("/rss/articles/") || path.hasPrefix("/stories/") {
                return true
            }
            if path == "/url" || path.hasPrefix("/url/") {
                return true
            }
        }
        
        // Common external link aggregators & shorteners
        if host == "out.reddit.com" || host == "t.co" {
            return true
        }
        
        return false
    }
    
    private func isInternalNavigation(to targetURL: URL, currentWebViewURL: URL?) -> Bool {
        // Allow non-HTTP(S) schemes, about:blank, or local navigation to proceed in WKWebView
        guard let targetHost = targetURL.host?.lowercased(), !targetHost.isEmpty else {
            return true
        }
        
        // Known article redirectors (like Google News /read/... or /articles/...) always lead to external content
        if isExternalArticleOrRedirect(url: targetURL) {
            return false
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
            self.navigationState.onOpenSafariReader?(url)
        }
    }
    
    private func openInSafari(url: URL) {
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
            // Persist the last opened URL for this web app if persistent
            if appItem.modelContext != nil {
                appItem.lastOpenedURLString = urlString
                appItem.lastVisited = Date()
                try? modelContext.save()
            }
        }
        
        // Persist cookies after navigation completes
        guard appItem.modelContext != nil else { return }
        Task { @MainActor in
            await IsolatedCookieManager.shared.persistCookies(
                for: appItem,
                from: webView.configuration.websiteDataStore.httpCookieStore,
                context: modelContext
            )
        }
        
        #if os(macOS)
        if let isolatedWV = webView as? IsolatedWKWebView {
            isolatedWV.reapplySleepingStateIfNeeded()
        }
        #endif
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationState.isLoading = false
        navigationState.canGoBack = webView.canGoBack
        navigationState.canGoForward = webView.canGoForward
    }
    
    // Handle target="_blank", popup windows, and "Open Link in New Window" context menu actions
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        #if DEBUG
        print("[IsolatedWebView] createWebViewWith called! targetFrame is nil: \(navigationAction.targetFrame == nil), url: \(String(describing: navigationAction.request.url))")
        #endif
        if navigationAction.targetFrame == nil {
            if let url = navigationAction.request.url {
                #if os(macOS)
                let modeRaw = UserDefaults.standard.string(forKey: "windowPresentationMode") ?? "singleWindow"
                let mode = WindowPresentationMode(rawValue: modeRaw) ?? .singleWindow
                let handler = onOpenNewWindowOrTab ?? navigationState.onOpenNewWindowOrTab
                
                if mode != .singleWindow {
                    #if DEBUG
                    print("[IsolatedWebView] Mode is \(mode), invoking new window/tab handler for: \(url)")
                    #endif
                    if let handler = handler {
                        DispatchQueue.main.async {
                            handler(url)
                        }
                    } else {
                        #if DEBUG
                        print("[IsolatedWebView] Warning: onOpenNewWindowOrTab handler is nil in mode \(mode)")
                        #endif
                    }
                    return nil
                }
                
                // In single window mode on macOS:
                if appItem.openLinksInSafariReaderMode && !isInternalNavigation(to: url, currentWebViewURL: webView.url) {
                    #if DEBUG
                    print("[IsolatedWebView] Single window mode: opening in Safari Reader")
                    #endif
                    openInSafariReader(url: url)
                } else {
                    #if DEBUG
                    print("[IsolatedWebView] Single window mode: loading in current webview")
                    #endif
                    webView.load(navigationAction.request)
                }
                #else
                if appItem.openLinksInSafariReaderMode && !isInternalNavigation(to: url, currentWebViewURL: webView.url) {
                    openInSafariReader(url: url)
                } else {
                    webView.load(navigationAction.request)
                }
                #endif
            } else {
                #if DEBUG
                print("[IsolatedWebView] navigationAction.request.url is NIL!")
                #endif
            }
        }
        return nil
    }
    
    // MARK: - WKUIDelegate: Media Capture Permissions (Camera & Microphone)
    
    @available(macOS 12.0, iOS 15.0, *)
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        #if DEBUG
        let typeDescription: String
        switch type {
        case .camera:
            typeDescription = "camera"
        case .microphone:
            typeDescription = "microphone"
        case .cameraAndMicrophone:
            typeDescription = "camera & microphone"
        @unknown default:
            typeDescription = "unknown media type"
        }
        print("[IsolatedWebView] Granting media capture permission for origin: \(origin.host), type: \(typeDescription)")
        #endif
        decisionHandler(.grant)
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
