//
//  IsolatedWebViewRepresentable.swift
//  isowebapps
//
//  Description:
//  UIKit/AppKit representable wrapping a dedicated `WKWebView` instance per capsule.
//  Configures isolated `WKWebsiteDataStore` containers, desktop/media settings,
//  HTML5 fullscreen, uBlock rule application, cookie restoration, and DOM extraction.
//

import SwiftUI
import WebKit
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(iOS)
struct IsolatedWebViewRepresentable: UIViewRepresentable {
    let appItem: WebAppItem
    var initialURLString: String? = nil
    @ObservedObject var navigationState: WebViewNavigationState
    let modelContext: ModelContext
    var onOpenNewWindowOrTab: ((URL) -> Void)? = nil
    
    func makeUIView(context: Context) -> WKWebView {
        createConfiguredWebView(context: context)
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
        print("[CapsuleClose] Dismantling UIView for capsule '\(coordinator.appItem.name)' and tearing down webView")
        #endif
        coordinator.cleanup()
        WebKitMemoryManager.shared.teardownWebView(uiView)
    }
}
#else
struct IsolatedWebViewRepresentable: NSViewRepresentable {
    let appItem: WebAppItem
    var initialURLString: String? = nil
    @ObservedObject var navigationState: WebViewNavigationState
    let modelContext: ModelContext
    var lifecycleController: CapsuleLifecycleController? = nil
    var onOpenNewWindowOrTab: ((URL) -> Void)? = nil
    var onSearchInNewEphemeralCapsule: ((URL) -> Void)? = nil
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = createConfiguredWebView(context: context)
        webView.autoresizingMask = [.width, .height]
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onOpenNewWindowOrTab = onOpenNewWindowOrTab
        if let isolatedWV = nsView as? IsolatedWKWebView {
            isolatedWV.onSearchInNewEphemeralCapsule = onSearchInNewEphemeralCapsule
        }
    }
    
    func makeCoordinator() -> WebViewCoordinator {
        let coordinator = WebViewCoordinator(appItem: appItem, navigationState: navigationState, modelContext: modelContext)
        coordinator.onOpenNewWindowOrTab = onOpenNewWindowOrTab
        return coordinator
    }
    
    static func dismantleNSView(_ nsView: WKWebView, coordinator: WebViewCoordinator) {
        #if DEBUG
        print("[CapsuleClose] Dismantling NSView for capsule '\(coordinator.appItem.name)' and tearing down webView")
        #endif
        coordinator.cleanup()
        WebKitMemoryManager.shared.teardownWebView(nsView)
    }
}
#endif

extension IsolatedWebViewRepresentable {
    static let defaultUserAgent: String = {
        #if os(macOS)
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6.2 Safari/605.1.15"
        #else
        return "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.4 Mobile/15E148 Safari/604.1"
        #endif
    }()

    // YouTube uses the genuine native WebKit User-Agent (customUserAgent == nil), like Youtube-Free.
    
    static func updateUserAgent(for webView: WKWebView?, targetURL: URL) {
        guard let scheme = targetURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        if YouTubeFreeSupport.isYouTubeURL(targetURL) {
            if webView?.customUserAgent != nil {
                webView?.customUserAgent = nil
            }
        } else if webView?.customUserAgent != defaultUserAgent {
            webView?.customUserAgent = defaultUserAgent
        }
    }
    
    static let readerDOMExtractionScript: String = #"""
    (function() {
        var getMeta = function(selector) {
            var el = document.querySelector(selector);
            return el ? (el.getAttribute('content') || '').trim() : '';
        };
        var title = (document.title || '').trim();
        var siteName = getMeta('meta[property="og:site_name"]') || getMeta('meta[name="application-name"]');
        var author = getMeta('meta[name="author"]') || getMeta('meta[property="article:author"]');
        var hasRobotCheckWidget = Boolean(
            document.querySelector(
                '#captcha-form, form[action*="/sorry"], .g-recaptcha, #recaptcha, iframe[src*="recaptcha"], iframe[src*="hcaptcha"], iframe[src*="challenges.cloudflare.com"], .cf-turnstile, iframe[src*="captcha-delivery.com"], #px-captcha'
            )
        );

        var pickBestContainer = function() {
            var selectorGroups = [
                'article',
                'main, [role="main"]',
                '#mw-content-text, .article-content, .post-content, .entry-content, .story-body, [itemprop="articleBody"]'
            ];
            for (var i = 0; i < selectorGroups.length; i++) {
                var nodes = document.querySelectorAll(selectorGroups[i]);
                var best = null;
                var bestLen = 0;
                for (var j = 0; j < nodes.length; j++) {
                    var textLen = (nodes[j].innerText || nodes[j].textContent || '').trim().length;
                    if (textLen > bestLen) {
                        bestLen = textLen;
                        best = nodes[j];
                    }
                }
                if (best && bestLen >= 250) {
                    return { node: best, matchedPrimary: true };
                }
            }
            return { node: document.body || document.documentElement, matchedPrimary: false };
        };

        var selection = pickBestContainer();
        var target = selection.node;
        var matchedPrimary = selection.matchedPrimary;
        var html = '';
        var plainTextLength = 0;
        if (target) {
            var clone = target.cloneNode(true);
            var pickFromSrcset = function(srcset) {
                if (!srcset) return '';
                var parts = srcset.trim().split(/,\s+|,(?=(?:https?:\/\/|\/\/|\/))/i);
                var bestURL = '';
                var bestScore = -1;
                for (var idx = 0; idx < parts.length; idx++) {
                    var tokens = parts[idx].trim().split(/\s+/);
                    var candidate = tokens[0] || '';
                    if (!candidate) continue;
                    var lower = candidate.toLowerCase();
                    if (!(lower.indexOf('https://') === 0 || lower.indexOf('http://') === 0 || lower.indexOf('//') === 0 || lower.indexOf('/') === 0)) {
                        continue;
                    }
                    var score = 0;
                    if (tokens.length > 1) {
                        var desc = tokens[1].toLowerCase();
                        if (desc.slice(-1) === 'w') score = parseFloat(desc) || 0;
                        else if (desc.slice(-1) === 'x') score = (parseFloat(desc) || 0) * 1000;
                    }
                    if (!bestURL || score > bestScore) {
                        bestURL = candidate;
                        bestScore = score;
                    }
                }
                return bestURL;
            };
            var imgs = clone.querySelectorAll('img');
            for (var k = 0; k < imgs.length; k++) {
                var img = imgs[k];
                var src = (img.getAttribute('src') || '').trim().toLowerCase();
                var needsPromotion = !src || src.indexOf('data:image/svg+xml') === 0 || src.indexOf('data:image/gif;base64,r0lgodlh') === 0 || src.indexOf('about:') === 0;
                if (needsPromotion) {
                    var lazy = img.getAttribute('data-src')
                        || img.getAttribute('data-original')
                        || img.getAttribute('data-lazy-src')
                        || img.getAttribute('data-actualsrc')
                        || pickFromSrcset(img.getAttribute('data-srcset') || img.getAttribute('srcset'));
                    if (!lazy && img.parentElement && img.parentElement.tagName && img.parentElement.tagName.toLowerCase() === 'picture') {
                        var sources = img.parentElement.querySelectorAll('source');
                        for (var sIdx = 0; sIdx < sources.length; sIdx++) {
                            lazy = pickFromSrcset(sources[sIdx].getAttribute('data-srcset') || sources[sIdx].getAttribute('srcset'));
                            if (lazy) break;
                        }
                    }
                    if (lazy) {
                        img.setAttribute('src', lazy);
                    }
                }
            }
            var junk = clone.querySelectorAll('script, style, noscript, iframe, nav, footer, aside, form, button, dialog, svg, canvas, template, [hidden], [aria-hidden="true"]');
            for (var m = junk.length - 1; m >= 0; m--) {
                if (junk[m].parentNode) {
                    junk[m].parentNode.removeChild(junk[m]);
                }
            }
            var styled = clone.querySelectorAll('[style]');
            for (var n = styled.length - 1; n >= 0; n--) {
                var st = (styled[n].getAttribute('style') || '').toLowerCase().replace(/\s+/g, '');
                if (st.indexOf('display:none') !== -1 || st.indexOf('visibility:hidden') !== -1) {
                    if (styled[n].parentNode) {
                        styled[n].parentNode.removeChild(styled[n]);
                    }
                }
            }
            html = clone.innerHTML || '';
            plainTextLength = (clone.textContent || '').replace(/\s+/g, ' ').trim().length;
        }
        if (!html.trim() && document.body) {
            html = document.body.innerHTML || '';
            plainTextLength = (document.body.innerText || document.body.textContent || '').replace(/\s+/g, ' ').trim().length;
        }
        return {
            title: title,
            url: window.location.href || '',
            siteName: siteName,
            author: author,
            html: html,
            readyState: document.readyState || '',
            textLength: plainTextLength,
            matchedPrimaryContainer: matchedPrimary,
            hasRobotCheckWidget: hasRobotCheckWidget
        };
    })();
    """#
    
    func createConfiguredWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        let dataStore: WKWebsiteDataStore
        let targetStoreId: UUID?
        if appItem.modelContext == nil {
            targetStoreId = nil
            #if os(macOS)
            dataStore = lifecycleController?.preservedNonPersistentDataStore ?? WKWebsiteDataStore.nonPersistent()
            #else
            dataStore = WKWebsiteDataStore.nonPersistent()
            #endif
        } else {
            let storeId = appItem.group?.id ?? appItem.id
            targetStoreId = storeId
            dataStore = WKWebsiteDataStore(forIdentifier: storeId)
        }
        configuration.websiteDataStore = dataStore
        
        let preferences = WKPreferences()
        preferences.isElementFullscreenEnabled = true
        preferences.setValue(true, forKey: "fullScreenEnabled")
        #if os(macOS)
        let sleepingTabsEnabled = UserDefaults.standard.object(forKey: "sleepingTabsEnabled") as? Bool ?? true
        preferences.setValue(sleepingTabsEnabled, forKey: "hiddenPageDOMTimerThrottlingEnabled")
        preferences.setValue(sleepingTabsEnabled, forKey: "hiddenPageDOMTimerThrottlingAutoIncreases")
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
        
        #if os(macOS)
        let savedURLForProtection = lifecycleController?.savedURLString
        #else
        let savedURLForProtection: String? = nil
        #endif
        let rawProtectionStartString = initialURLString ?? savedURLForProtection ?? appItem.lastOpenedURLString ?? appItem.urlString
        let resolvedStartURL: URL? = URL(string: rawProtectionStartString).map {
            YouTubeFreeSupport.isYouTubeURL($0) ? YouTubeFreeSupport.normalizedInitialYouTubeURL($0) : $0
        }
        if YouTubeFreeSupport.isYouTubeURL(resolvedStartURL) {
            YouTubeFreeSupport.activateIOSPlaybackAudioSessionIfNeeded()
        }
        let initialProtectionMode = YouTubeFreeSupport.desiredProtectionMode(
            isCapsuleProtectionEnabled: appItem.isUBlockEnabled,
            targetURL: resolvedStartURL,
            fallbackURLString: appItem.urlString
        )
        context.coordinator.activeProtectionMode = initialProtectionMode
        let needsUBlockLoad = initialProtectionMode == .uBlock && !UBlockOriginExtensionManager.shared.isLoaded
        let needsYouTubeLoad = initialProtectionMode == .youTubeAdFree && !YouTubeContentBlocker.shared.isLoaded
        switch initialProtectionMode {
        case .uBlock:
            if !needsUBlockLoad {
                UBlockOriginExtensionManager.shared.applyToConfiguration(configuration)
            }
        case .youTubeAdFree:
            if !needsYouTubeLoad {
                YouTubeContentBlocker.shared.applyToConfiguration(configuration)
            }
        case .none:
            break
        }
        configuration.userContentController.add(WeakScriptMessageHandler(context.coordinator), name: "avkitVideoURL")
        
        #if os(macOS)
        let webView = IsolatedWKWebView(frame: .zero, configuration: configuration)
        webView.capsuleName = appItem.name
        webView.onSearchInNewEphemeralCapsule = onSearchInNewEphemeralCapsule
        #else
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.keyboardDismissMode = .interactive
        #endif
        
        let targetURLString = initialURLString ?? appItem.lastOpenedURLString ?? appItem.urlString
        if let targetURL = URL(string: targetURLString) {
            Self.updateUserAgent(for: webView, targetURL: targetURL)
        } else {
            webView.customUserAgent = Self.defaultUserAgent
        }
        
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        #if os(iOS)
        webView.allowsBackForwardNavigationGestures = true
        #endif
        
        let webViewToken = UUID()
        navigationState.activeWebViewToken = webViewToken
        context.coordinator.webViewToken = webViewToken
        context.coordinator.setup(webView: webView)
        WebKitMemoryManager.shared.register(webView: webView)
        #if os(macOS)
        lifecycleController?.attachWebView(webView, coordinator: context.coordinator)
        let restoredInteractionState = lifecycleController?.consumeSavedInteractionState()
        let lifecycleSavedURL = lifecycleController?.savedURLString
        #else
        let restoredInteractionState: Any? = nil
        let lifecycleSavedURL: String? = nil
        #endif
        
        navigationState.onGoBack = { [weak webView] in
            webView?.goBack()
        }
        navigationState.onGoForward = { [weak webView] in
            webView?.goForward()
        }
        navigationState.onReload = { [weak webView] in
            webView?.reload()
        }
        let coordinator = context.coordinator
        navigationState.onLoadURL = { [weak webView, weak coordinator, weak navigationState] url in
            navigationState?.avkitHLSURL = nil
            Self.updateUserAgent(for: webView, targetURL: url)
            guard let webView else { return }
            let request = URLRequest(url: url)
            let ready = coordinator?.ensureProtection(for: url, webView: webView, onReady: { [weak webView] in
                webView?.load(request)
            }) ?? true
            if ready {
                webView.load(request)
            }
        }
        navigationState.onCloseAVKitOverlay = { [weak webView, weak navigationState] in
            guard let navigationState else { return }
            navigationState.avkitHLSURL = nil
            if let last = navigationState.lastVideoPageURL {
                navigationState.lastVideoPageURL = nil
                webView?.load(URLRequest(url: last))
            }
        }
        navigationState.onStopLoading = { [weak webView, weak coordinator] in
            coordinator?.cleanup()
            if let webView {
                WebKitMemoryManager.shared.teardownWebView(webView)
            }
        }
        navigationState.onToggleUBlock = { [weak coordinator] isEnabled in
            coordinator?.applyContentProtection(isEnabled: isEnabled, targetURL: nil, reload: true)
        }
        #if os(macOS)
        if navigationState.isReaderModeActive {
            webView.setAllMediaPlaybackSuspended(true)
        }
        navigationState.onSetReaderMediaSuspended = { [weak webView, weak navigationState] suspended in
            guard let webView else { return }
            if suspended {
                webView.pauseAllMediaPlayback(completionHandler: nil)
                webView.setAllMediaPlaybackSuspended(true)
            } else {
                if !webView.isSleeping {
                    webView.setAllMediaPlaybackSuspended(false)
                }
                if let navigationState {
                    navigationState.isLoading = webView.isLoading
                    navigationState.canGoBack = webView.canGoBack
                    navigationState.canGoForward = webView.canGoForward
                    if let liveURL = webView.url?.absoluteString, !liveURL.isEmpty, liveURL != "about:blank" {
                        navigationState.currentURLString = liveURL
                    }
                }
            }
        }
        #endif
        navigationState.onCaptureLiveHTML = { [weak webView] in
            guard let webView else {
                throw WebPageSummaryError.webViewUnavailable
            }
            
            let result = try await webView.evaluateJavaScript(Self.readerDOMExtractionScript)
            if let dict = result as? [String: Any],
               let extractedHTML = dict["html"] as? String {
                let rawTitle = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedTitle = (rawTitle?.isEmpty == false) ? rawTitle! : (webView.title ?? "")
                let rawURL = (dict["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedURL = (rawURL?.isEmpty == false) ? rawURL! : (webView.url?.absoluteString ?? "")
                let rawSite = (dict["siteName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let rawAuthor = (dict["author"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let readyState = (dict["readyState"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let textLength = dict["textLength"] as? Int
                let matchedPrimary = (dict["matchedPrimaryContainer"] as? Bool) ?? false
                let hasRobotCheckWidget = (dict["hasRobotCheckWidget"] as? Bool) ?? false
                
                return ReaderHTMLCapture(
                    title: resolvedTitle,
                    urlString: resolvedURL,
                    siteName: rawSite?.isEmpty == false ? rawSite : nil,
                    author: rawAuthor?.isEmpty == false ? rawAuthor : nil,
                    html: extractedHTML,
                    readyState: readyState?.isEmpty == false ? readyState : nil,
                    textLength: textLength,
                    matchedPrimaryContainer: matchedPrimary,
                    hasRobotCheckWidget: hasRobotCheckWidget
                )
            }
            
            let fallbackHTML = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String ?? ""
            return ReaderHTMLCapture(
                title: webView.title ?? "",
                urlString: webView.url?.absoluteString ?? "",
                siteName: nil,
                author: nil,
                html: fallbackHTML,
                readyState: nil,
                textLength: nil,
                matchedPrimaryContainer: false,
                hasRobotCheckWidget: false
            )
        }
        
        let groupedItems = appItem.group?.items ?? []
        let startURLString = initialURLString ?? lifecycleSavedURL ?? appItem.lastOpenedURLString ?? appItem.urlString
        let needsCookieRestore = IsolatedCookieManager.shared.needsRestore(for: appItem, groupedItems: groupedItems)
        let needsPendingClearWait = targetStoreId.map { IsolatedCookieManager.shared.hasPendingClear(for: $0) } ?? false
        let startOrRestoreLoad: @MainActor (WKWebView) -> Void = { wv in
            if let restoredInteractionState {
                wv.interactionState = restoredInteractionState
                if wv.backForwardList.currentItem == nil && !wv.isLoading {
                    let fallbackURLString = initialURLString
                        ?? lifecycleSavedURL
                        ?? appItem.lastOpenedURLString
                        ?? appItem.urlString
                    if let url = URL(string: fallbackURLString) {
                        Self.updateUserAgent(for: wv, targetURL: url)
                        wv.load(URLRequest(url: url))
                    }
                }
                return
            }
            if let rawURL = URL(string: startURLString) {
                let url = YouTubeFreeSupport.isYouTubeURL(rawURL) ? YouTubeFreeSupport.normalizedInitialYouTubeURL(rawURL) : rawURL
                Self.updateUserAgent(for: wv, targetURL: url)
                wv.load(URLRequest(url: url))
            }
        }
        if needsUBlockLoad || needsYouTubeLoad || needsCookieRestore || needsPendingClearWait {
            Task { @MainActor [weak webView] in
                if let targetStoreId, IsolatedCookieManager.shared.hasPendingClear(for: targetStoreId) {
                    await IsolatedCookieManager.shared.awaitPendingClear(for: targetStoreId)
                }
                if needsUBlockLoad {
                    await UBlockOriginExtensionManager.shared.prepare()
                    guard let webView, !WebKitMemoryManager.shared.isTornDown(webView) else { return }
                    if appItem.isUBlockEnabled {
                        UBlockOriginExtensionManager.shared.applyToConfiguration(webView.configuration)
                    }
                }
                if needsYouTubeLoad {
                    await YouTubeContentBlocker.shared.prepare()
                    guard let webView, !WebKitMemoryManager.shared.isTornDown(webView) else { return }
                    YouTubeContentBlocker.shared.applyToConfiguration(webView.configuration)
                }
                guard let webView, !WebKitMemoryManager.shared.isTornDown(webView) else { return }
                let latestGroupedItems = appItem.group?.items ?? groupedItems
                if needsCookieRestore || IsolatedCookieManager.shared.needsRestore(for: appItem, groupedItems: latestGroupedItems) {
                    await IsolatedCookieManager.shared.restoreCookies(for: appItem, groupedItems: latestGroupedItems, into: dataStore.httpCookieStore)
                }
                guard !WebKitMemoryManager.shared.isTornDown(webView) else { return }
                startOrRestoreLoad(webView)
            }
        } else {
            startOrRestoreLoad(webView)
        }
        
        return webView
    }
}
