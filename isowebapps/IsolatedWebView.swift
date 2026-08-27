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


// MARK: - YouTube Ad Blocking & Native Player Enhancement Scripts

/// Injected on YouTube pages.
/// Hides ads, attaches a tap-to-play placeholder overlay on video pages (/watch),
/// and starts the video directly in native full-screen player when tapped.
/// Does nothing on Shorts (/shorts/) pages or non-YouTube domains.
private let ytPlaceholderAndAdBlockScript = """
(function() {
    var hostname = window.location.hostname;
    if (!hostname.includes('youtube.com')) return;

    function injectStyles() {
        if (document.getElementById('yt-free-styles')) return;
        var style = document.createElement('style');
        style.id = 'yt-free-styles';
        style.textContent = [
            /* Ad blocking CSS rules */
            '.video-ads, .ytp-ad-module, .ytp-ad-overlay-container,',
            '.ytp-ad-player-overlay, .ytp-ad-text, .ytp-ad-image-overlay,',
            '.ad-showing .ytp-ad-action-interstitial, .ad-container,',
            '.ytp-ad-preview-container, .ytp-ad-skip-button-slot,',
            '.ytp-ad-message-container, ytd-ad-slot-renderer,',
            '#player-ads, ytm-promoted-sparkles-web-renderer,',
            '.ytp-pause-overlay, .ytp-ce-element, .ytp-endscreen-content {',
            '    display: none !important;',
            '}',
            /* Native player placeholder overlay */
            '.yt-free-placeholder {',
            '    position: absolute !important;',
            '    top: 0 !important;',
            '    left: 0 !important;',
            '    width: 100% !important;',
            '    height: 100% !important;',
            '    z-index: 99999 !important;',
            '    background: rgba(12, 12, 12, 0.90) !important;',
            '    backdrop-filter: blur(10px) !important;',
            '    -webkit-backdrop-filter: blur(10px) !important;',
            '    display: flex !important;',
            '    flex-direction: column !important;',
            '    align-items: center !important;',
            '    justify-content: center !important;',
            '    cursor: pointer !important;',
            '    user-select: none !important;',
            '    -webkit-user-select: none !important;',
            '    -webkit-tap-highlight-color: transparent !important;',
            '    transition: opacity 0.2s ease;',
            '}',
            '.yt-free-placeholder:active {',
            '    background: rgba(25, 25, 25, 0.96) !important;',
            '}',
            '.yt-free-btn {',
            '    width: 64px !important;',
            '    height: 64px !important;',
            '    background: #ff0000 !important;',
            '    border-radius: 50% !important;',
            '    display: flex !important;',
            '    align-items: center !important;',
            '    justify-content: center !important;',
            '    box-shadow: 0 4px 20px rgba(255, 0, 0, 0.5), 0 2px 10px rgba(0, 0, 0, 0.5) !important;',
            '    margin-bottom: 12px !important;',
            '    transition: transform 0.15s ease !important;',
            '    pointer-events: none !important;',
            '}',
            '.yt-free-placeholder:active .yt-free-btn {',
            '    transform: scale(0.92) !important;',
            '}',
            '.yt-free-btn svg {',
            '    width: 26px !important;',
            '    height: 26px !important;',
            '    fill: #ffffff !important;',
            '    margin-left: 3px !important;',
            '    pointer-events: none !important;',
            '}',
            '.yt-free-label {',
            '    color: #ffffff !important;',
            '    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif !important;',
            '    font-size: 15px !important;',
            '    font-weight: 600 !important;',
            '    letter-spacing: -0.2px !important;',
            '    text-shadow: 0 1px 4px rgba(0,0,0,0.8) !important;',
            '    pointer-events: none !important;',
            '}',
            '.yt-free-badge {',
            '    color: rgba(255, 255, 255, 0.7) !important;',
            '    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif !important;',
            '    font-size: 11px !important;',
            '    margin-top: 4px !important;',
            '    text-shadow: 0 1px 3px rgba(0,0,0,0.8) !important;',
            '    pointer-events: none !important;',
            '}'
        ].join('\\n');
        (document.head || document.documentElement).appendChild(style);
    }

    function isShorts() {
        var path = window.location.pathname || '';
        return path.startsWith('/shorts') || window.location.href.includes('/shorts/');
    }

    function isWatchPage() {
        if (isShorts()) return false;
        var path = window.location.pathname || '';
        return path.startsWith('/watch') || window.location.search.includes('v=');
    }

    function skipAds() {
        var video = document.querySelector('video');
        var adShowing = document.querySelector('.ad-showing, .ad-interrupting, .ytp-ad-player-overlay, ytm-promoted-sparkles-web-renderer');
        if (adShowing && video) {
            video.muted = true;
            video.playbackRate = 16;
            if (isFinite(video.duration) && video.duration > 0) {
                video.currentTime = video.duration;
            }
            var skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, .ytp-ad-overlay-close-button');
            if (skipBtn) skipBtn.click();
        }
    }

    function findPlayerContainer() {
        return document.getElementById('player-container-id') ||
               document.getElementById('player') ||
               document.getElementById('movie_player') ||
               document.getElementById('ytd-player') ||
               document.querySelector('.player-container') ||
               document.querySelector('.html5-video-player') ||
               (document.querySelector('video') && document.querySelector('video').parentElement);
    }

    function launchNativePlayer(placeholder) {
        skipAds();

        var video = document.querySelector('video');
        var player = document.getElementById('movie_player');

        if (video) {
            video.muted = false;
            video.playbackRate = 1.0;
            video.removeAttribute('playsinline');
            video.removeAttribute('webkit-playsinline');

            function enterFS() {
                if (typeof video.webkitEnterFullscreen === 'function') {
                    video.webkitEnterFullscreen();
                } else if (typeof video.requestFullscreen === 'function') {
                    video.requestFullscreen().catch(function(){});
                } else if (typeof video.webkitRequestFullscreen === 'function') {
                    video.webkitRequestFullscreen();
                }
            }

            var p = video.play();
            if (p !== undefined) {
                p.then(enterFS).catch(enterFS);
            } else {
                enterFS();
            }

            function onExitFS() {
                video.removeEventListener('webkitendfullscreen', onExitFS);
                video.removeEventListener('fullscreenchange', onExitFS);
                if (placeholder) {
                    placeholder.style.display = 'flex';
                }
                video.pause();
            }
            video.addEventListener('webkitendfullscreen', onExitFS);
            video.addEventListener('fullscreenchange', onExitFS);
        } else if (player && typeof player.playVideo === 'function') {
            player.playVideo();
        }

        if (placeholder) {
            placeholder.style.display = 'none';
        }
    }

    function setupPlaceholder() {
        injectStyles();

        // For Shorts: do nothing and remove any placeholder
        if (isShorts()) {
            var existing = document.querySelector('.yt-free-placeholder');
            if (existing) existing.remove();
            return;
        }

        if (!isWatchPage()) {
            var existing = document.querySelector('.yt-free-placeholder');
            if (existing) existing.remove();
            return;
        }

        var container = findPlayerContainer();
        if (!container) return;

        var pos = window.getComputedStyle(container).position;
        if (pos === 'static' || !pos) {
            container.style.position = 'relative';
        }

        var placeholder = container.querySelector(':scope > .yt-free-placeholder');
        if (!placeholder) {
            var strays = document.querySelectorAll('.yt-free-placeholder');
            strays.forEach(function(s) { s.remove(); });

            placeholder = document.createElement('div');
            placeholder.className = 'yt-free-placeholder';
            placeholder.innerHTML = [
                '<div class="yt-free-btn">',
                '  <svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>',
                '</div>',
                '<div class="yt-free-label">Play Video</div>',
                '<div class="yt-free-badge">Ad-Free Player</div>'
            ].join('');

            placeholder.addEventListener('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                launchNativePlayer(placeholder);
            });

            container.appendChild(placeholder);
        }

        // Before user interaction, pause/mute video to prevent background ad audio
        var video = document.querySelector('video');
        if (video && placeholder.style.display !== 'none') {
            if (!video.paused && !document.fullscreenElement && !document.webkitFullscreenElement) {
                video.muted = true;
                video.pause();
            }
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', setupPlaceholder);
    } else {
        setupPlaceholder();
    }

    window.addEventListener('yt-navigate-finish', setupPlaceholder);
    window.addEventListener('yt-page-data-updated', setupPlaceholder);
    window.addEventListener('popstate', setupPlaceholder);

    var obs = new MutationObserver(function() {
        setupPlaceholder();
    });
    obs.observe(document.documentElement, { childList: true, subtree: true });

    setInterval(function() {
        setupPlaceholder();
        if (isWatchPage()) {
            skipAds();
        }
    }, 500);
})();
"""

/// macOS only — forces native <video controls> on top of the YouTube player.
/// The native controls bar, including PiP and AirPlay, overlays the bottom
/// of the player.
private let ytNativeControlsScript = """
(function() {
    var hostname = window.location.hostname;
    if (!hostname.includes('youtube.com')) return;

    var style = document.createElement('style');
    style.textContent = [
        '.ytp-pause-overlay { display: none !important; }',
        '.ytp-ce-element { display: none !important; }',
        '.ytp-endscreen-content { display: none !important; }'
    ].join(' ');
    document.documentElement.appendChild(style);

    var guardedVideos = new WeakSet();

    function guardVideo(video) {
        if (guardedVideos.has(video)) return;
        guardedVideos.add(video);

        function applyAttrs() {
            video.setAttribute('controls', '');
            video.removeAttribute('controlslist');
            video.removeAttribute('disablepictureinpicture');
            video.removeAttribute('playsinline');
            video.removeAttribute('webkit-playsinline');
        }
        applyAttrs();

        var obs = new MutationObserver(function(mutations) {
            mutations.forEach(function(m) {
                if (m.attributeName === 'controls' && !video.hasAttribute('controls')) {
                    video.setAttribute('controls', '');
                }
                if (m.attributeName === 'controlslist') video.removeAttribute('controlslist');
                if (m.attributeName === 'disablepictureinpicture') video.removeAttribute('disablepictureinpicture');
                if (m.attributeName === 'playsinline') video.removeAttribute('playsinline');
                if (m.attributeName === 'webkit-playsinline') video.removeAttribute('webkit-playsinline');
            });
        });
        obs.observe(video, {
            attributes: true,
            attributeFilter: ['controls', 'controlslist', 'disablepictureinpicture', 'playsinline', 'webkit-playsinline']
        });
    }

    document.querySelectorAll('video').forEach(guardVideo);

    var docObs = new MutationObserver(function(mutations) {
        mutations.forEach(function(m) {
            m.addedNodes.forEach(function(node) {
                if (node.nodeType !== 1) return;
                if (node.tagName === 'VIDEO') guardVideo(node);
                else node.querySelectorAll && node.querySelectorAll('video').forEach(guardVideo);
            });
        });
    });
    docObs.observe(document.documentElement, { childList: true, subtree: true });

    try {
        Object.defineProperty(HTMLVideoElement.prototype, 'disablePictureInPicture', {
            get: function() { return false; },
            set: function() {},
            configurable: true
        });
    } catch(e) {}

    document.addEventListener('contextmenu', function(e) {
        var el = e.target;
        while (el) {
            if (el.tagName === 'VIDEO') {
                e.stopImmediatePropagation();
                return;
            }
            el = el.parentElement;
        }
    }, true);
})();
"""

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
                source: ytPlaceholderAndAdBlockScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            configuration.userContentController.addUserScript(ytPlaceholderScript)

            #if os(macOS)
            let ytNativeControlsUserScript = WKUserScript(
                source: ytNativeControlsScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            configuration.userContentController.addUserScript(ytNativeControlsUserScript)
            #endif
        } else if appItem.isUBlockEnabled {
            // For other websites: load standard uBlock Origin rules and cosmetic scripts if enabled
            UBlockOriginExtensionManager.shared.applyToConfiguration(configuration)
        }
        
        // 4. Configure Application User Agent with Name and Version
        // Setting applicationNameForUserAgent appends 'isowebapps/<version>' to the authentic
        // Safari/Mobile Safari User-Agent without overriding mobile/desktop platform tokens.
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let appUserAgent = "isowebapps/\(appVersion)"
        configuration.applicationNameForUserAgent = appUserAgent
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
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
            decisionHandler(.cancel)
            openInSafariReader(url: url)
            return
        }
        decisionHandler(.allow)
    }
    
    private func openInSafariReader(url: URL) {
        #if os(iOS)
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        let svc = SFSafariViewController(url: url, configuration: config)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            rootVC.present(svc, animated: true)
        }
        #else
        NSWorkspace.shared.open(url)
        #endif
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
            if appItem.openLinksInSafariReaderMode, let url = navigationAction.request.url {
                openInSafariReader(url: url)
            } else {
                webView.load(navigationAction.request)
            }
        }
        return nil
    }
}
