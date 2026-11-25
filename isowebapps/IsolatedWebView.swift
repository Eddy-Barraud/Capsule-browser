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
#if os(iOS)
import SafariServices
#endif

@MainActor
final class WebKitMemoryManager {
    static let shared = WebKitMemoryManager()
    
    private var activeWebViews = NSHashTable<WKWebView>.weakObjects()
    private var tornDownWebViews = NSHashTable<WKWebView>.weakObjects()
    private var activeDataStores = NSHashTable<WKWebsiteDataStore>.weakObjects()
    private var openCapsuleCounts: [UUID: Int] = [:]
    
    private init() {}
    
    var liveWebViewCount: Int {
        activeWebViews.allObjects.count
    }
    
    func registerOpenCapsule(appId: UUID) {
        openCapsuleCounts[appId, default: 0] += 1
    }
    
    @discardableResult
    func unregisterOpenCapsule(appId: UUID) -> Int {
        guard let current = openCapsuleCounts[appId] else { return 0 }
        let next = current - 1
        if next <= 0 {
            openCapsuleCounts.removeValue(forKey: appId)
            return 0
        }
        openCapsuleCounts[appId] = next
        return next
    }
    
    func purgeMemoryCache(for dataStore: WKWebsiteDataStore) {
        activeDataStores.add(dataStore)
        dataStore.removeData(ofTypes: [WKWebsiteDataTypeMemoryCache], modifiedSince: .distantPast) {}
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
        #if os(macOS)
        ReaderImageCache.shared.clear()
        #endif
        
        #if DEBUG
        print("[Memory] Purged idle WebKit caches (teardownAllWebViews: \(teardownAllWebViews), stores: \(storesToPurge.count), remainingLiveWebViews: \(liveWebViewCount))")
        #endif
    }
}

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
        print("[CapsuleClose] Dismantling UIView for capsule '\(coordinator.appItem.name)' and tearing down webView")
        #endif
        coordinator.cleanup()
        WebKitMemoryManager.shared.teardownWebView(uiView)
    }
}
#else
import AppKit
import Combine

@MainActor
final class CapsuleLifecycleController: ObservableObject {
    @Published private(set) var sleepState: CapsuleSleepState = .awake
    @Published private(set) var webViewGeneration: Int = 0
    
    var isDeepSleeping: Bool { sleepState == .deepSleeping }
    var isClosed: Bool { sleepState == .closed }
    
    private(set) var savedInteractionState: Any?
    private(set) var savedURLString: String?
    private(set) var preservedNonPersistentDataStore: WKWebsiteDataStore?
    
    private weak var window: NSWindow?
    private weak var webView: IsolatedWKWebView?
    private weak var coordinator: WebViewCoordinator?
    
    var capsuleName: String = ""
    var isEphemeral: Bool = false
    var softSleepDelay: TimeInterval = 0.15
    var deepSleepDelay: TimeInterval = 5.0
    var audioRecheckInterval: TimeInterval = 10.0
    var canDeepSleepProvider: (() -> Bool)?
    var onBeforeDeepSleep: (() -> Void)?
    var onWindowWillClose: (() -> Void)?
    
    nonisolated(unsafe) private var notificationObservers: [NSObjectProtocol] = []
    nonisolated(unsafe) private var tabGroupObservation: NSKeyValueObservation?
    nonisolated(unsafe) private var windowTabGroupObservation: NSKeyValueObservation?
    nonisolated(unsafe) private var sleepWakeWorkItem: DispatchWorkItem?
    nonisolated(unsafe) private var deepSleepWorkItem: DispatchWorkItem?
    nonisolated(unsafe) private var audioRecheckWorkItem: DispatchWorkItem?
    nonisolated(unsafe) private var activityAssertionToken: NSObjectProtocol?
    private var hasBeenPresented: Bool = false
    private var lastSleepingTabsEnabled: Bool = UserDefaults.standard.object(forKey: "sleepingTabsEnabled") as? Bool ?? true
    
    func consumeSavedInteractionState() -> Any? {
        let state = savedInteractionState
        savedInteractionState = nil
        return state
    }
    
    func attachWindow(_ window: NSWindow) {
        guard !isClosed else { return }
        if self.window === window {
            if window.isVisible || window.isKeyWindow || window.isMainWindow || window.tabGroup != nil {
                hasBeenPresented = true
            }
            scheduleSleepWakeEvaluation(delay: 0.05)
            return
        }
        
        teardownObservers()
        self.window = window
        hasBeenPresented = window.isVisible || window.isKeyWindow || window.isMainWindow || window.tabGroup != nil
        
        let nc = NotificationCenter.default
        let windowNotificationNames: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didResignMainNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeOcclusionStateNotification
        ]
        for name in windowNotificationNames {
            let obs = nc.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.isClosed else { return }
                    if name == NSWindow.didBecomeKeyNotification || name == NSWindow.didBecomeMainNotification {
                        self.hasBeenPresented = true
                    }
                    self.scheduleSleepWakeEvaluation()
                }
            }
            notificationObservers.append(obs)
        }
        
        let closeObs = nc.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleClose()
            }
        }
        notificationObservers.append(closeObs)
        
        let appNotificationNames: [Notification.Name] = [
            NSApplication.didHideNotification,
            NSApplication.didUnhideNotification,
            NSApplication.didBecomeActiveNotification
        ]
        for name in appNotificationNames {
            let obs = nc.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleSleepWakeEvaluation()
                }
            }
            notificationObservers.append(obs)
        }
        
        let defaultsObs = nc.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isClosed else { return }
                let current = UserDefaults.standard.object(forKey: "sleepingTabsEnabled") as? Bool ?? true
                guard current != self.lastSleepingTabsEnabled else { return }
                self.lastSleepingTabsEnabled = current
                if let prefs = self.webView?.configuration.preferences {
                    prefs.setValue(current, forKey: "hiddenPageDOMTimerThrottlingEnabled")
                    prefs.setValue(current, forKey: "hiddenPageDOMTimerThrottlingAutoIncreases")
                }
                self.scheduleSleepWakeEvaluation(delay: 0.05)
            }
        }
        notificationObservers.append(defaultsObs)
        
        windowTabGroupObservation = window.observe(\.tabGroup, options: [.new]) { [weak self] win, _ in
            Task { @MainActor [weak self, weak win] in
                guard let self, let win, !self.isClosed else { return }
                self.setupTabGroupObservation(for: win)
                self.scheduleSleepWakeEvaluation()
            }
        }
        
        setupTabGroupObservation(for: window)
        scheduleSleepWakeEvaluation(delay: 0.05)
    }
    
    func attachWebView(_ webView: IsolatedWKWebView, coordinator: WebViewCoordinator) {
        guard !isClosed else { return }
        self.webView = webView
        self.coordinator = coordinator
        let sleepingEnabled = UserDefaults.standard.object(forKey: "sleepingTabsEnabled") as? Bool ?? true
        webView.configuration.preferences.setValue(sleepingEnabled, forKey: "hiddenPageDOMTimerThrottlingEnabled")
        webView.configuration.preferences.setValue(sleepingEnabled, forKey: "hiddenPageDOMTimerThrottlingAutoIncreases")
        scheduleSleepWakeEvaluation(delay: 0.05)
    }
    
    private func setupTabGroupObservation(for window: NSWindow) {
        tabGroupObservation?.invalidate()
        tabGroupObservation = window.tabGroup?.observe(\.selectedWindow, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.scheduleSleepWakeEvaluation()
            }
        }
    }
    
    func scheduleSleepWakeEvaluation(delay: TimeInterval? = nil) {
        sleepWakeWorkItem?.cancel()
        sleepWakeWorkItem = nil
        guard !isClosed else { return }
        let resolvedDelay = delay ?? softSleepDelay
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.sleepWakeWorkItem = nil
                self?.evaluateSleepWakeStatus()
            }
        }
        sleepWakeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + resolvedDelay, execute: work)
    }
    
    private func isSubstantiallyCoveredByFrontAppWindow(for window: NSWindow) -> Bool {
        var frontFrames: [CGRect] = []
        var foundTarget = false
        for candidate in NSApp.orderedWindows {
            if candidate === window {
                foundTarget = true
                break
            }
            guard candidate.isVisible,
                  !candidate.isMiniaturized,
                  candidate.level == .normal,
                  !candidate.isSheet,
                  candidate.sheetParent == nil,
                  !(candidate is NSPanel) else {
                continue
            }
            frontFrames.append(candidate.frame)
        }
        guard foundTarget, !frontFrames.isEmpty else { return false }
        return CapsuleSleepPolicy.coverageFraction(of: window.frame, coveredBy: frontFrames) >= CapsuleSleepPolicy.substantialCoverageThreshold
    }
    
    private func currentSnapshot() -> CapsuleWindowSleepSnapshot? {
        guard let window else { return nil }
        if window.isVisible || window.isKeyWindow || window.isMainWindow || window.tabGroup != nil {
            hasBeenPresented = true
        }
        let sleepingTabsEnabled = UserDefaults.standard.object(forKey: "sleepingTabsEnabled") as? Bool ?? true
        let tabGroup = window.tabGroup
        let isInMultiTabGroup = (tabGroup?.windows.count ?? 0) > 1
        let isSelectedTabInGroup = !isInMultiTabGroup || (tabGroup?.selectedWindow === window)
        return CapsuleWindowSleepSnapshot(
            sleepingTabsEnabled: sleepingTabsEnabled,
            isClosed: isClosed,
            hasBeenPresented: hasBeenPresented,
            isMiniaturized: window.isMiniaturized,
            isVisible: window.isVisible,
            isOcclusionVisible: window.occlusionState.contains(.visible),
            isSubstantiallyCoveredByFrontAppWindow: isSubstantiallyCoveredByFrontAppWindow(for: window),
            isAppHidden: NSApp.isHidden,
            isKeyWindow: window.isKeyWindow,
            isInMultiTabGroup: isInMultiTabGroup,
            isSelectedTabInGroup: isSelectedTabInGroup
        )
    }
    
    func evaluateSleepWakeStatus() {
        guard !isClosed, let snapshot = currentSnapshot() else {
            releaseForegroundActivityToken()
            return
        }
        
        switch CapsuleSleepPolicy.evaluate(snapshot) {
        case .ignoreNotYetPresented:
            releaseForegroundActivityToken()
        case .awake(let claimForegroundActivity):
            wakeUp(forceImmediate: false, claimForegroundActivity: claimForegroundActivity)
        case .sleep:
            enterSoftSleepAndScheduleDeepSleep()
        }
    }
    
    func wakeUp(forceImmediate: Bool = false, claimForegroundActivity: Bool? = nil) {
        guard !isClosed else { return }
        sleepWakeWorkItem?.cancel()
        sleepWakeWorkItem = nil
        deepSleepWorkItem?.cancel()
        deepSleepWorkItem = nil
        audioRecheckWorkItem?.cancel()
        audioRecheckWorkItem = nil
        
        let shouldClaim = claimForegroundActivity ?? (window?.isKeyWindow == true && window?.isVisible == true && !(window?.isMiniaturized ?? false) && !NSApp.isHidden)
        
        if sleepState == .deepSleeping {
            #if DEBUG
            print("[CapsuleLifecycle] Waking up from deep sleep: '\(capsuleName)'")
            #endif
            sleepState = .awake
            webViewGeneration &+= 1
            window?.contentView?.layoutSubtreeIfNeeded()
        } else if sleepState == .softSleeping {
            sleepState = .awake
            webView?.applyWakeFromSoftSleep()
        }
        
        if shouldClaim || forceImmediate {
            if window?.isKeyWindow == true {
                claimForegroundActivityToken()
            }
        } else {
            releaseForegroundActivityToken()
        }
    }
    
    private func enterSoftSleepAndScheduleDeepSleep() {
        guard !isClosed else { return }
        releaseForegroundActivityToken()
        if sleepState == .deepSleeping {
            return
        }
        
        if let webView, webView.hasActiveAudioPlayback {
            sleepState = .softSleeping
            deepSleepWorkItem?.cancel()
            deepSleepWorkItem = nil
            scheduleAudioOrBlockerRecheck()
            return
        }
        
        if sleepState != .softSleeping {
            sleepState = .softSleeping
            webView?.applySoftSleep()
            if let dataStore = webView?.configuration.websiteDataStore {
                WebKitMemoryManager.shared.purgeMemoryCache(for: dataStore)
            }
        }
        
        if deepSleepWorkItem == nil {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.deepSleepWorkItem = nil
                    self?.enterDeepSleepIfEligible()
                }
            }
            deepSleepWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + deepSleepDelay, execute: work)
        }
    }
    
    private func scheduleAudioOrBlockerRecheck() {
        audioRecheckWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.audioRecheckWorkItem = nil
                self?.evaluateSleepWakeStatus()
            }
        }
        audioRecheckWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + audioRecheckInterval, execute: work)
    }
    
    private func enterDeepSleepIfEligible() {
        guard !isClosed else { return }
        guard let snapshot = currentSnapshot(), CapsuleSleepPolicy.evaluate(snapshot) == .sleep else {
            evaluateSleepWakeStatus()
            return
        }
        
        let hasAudio = webView?.hasActiveAudioPlayback ?? false
        let hasDownload = webView.map { CapsuleDownloadManager.shared.hasActiveDownload(for: $0) } ?? false
        let containerAllowsSleep = canDeepSleepProvider?() ?? true
        if hasAudio || hasDownload || !containerAllowsSleep {
            scheduleAudioOrBlockerRecheck()
            return
        }
        
        guard let webView = self.webView else {
            sleepState = .deepSleeping
            return
        }
        
        savedInteractionState = webView.interactionState
        if let currentURL = webView.url?.absoluteString, !currentURL.isEmpty, currentURL != "about:blank" {
            savedURLString = currentURL
        }
        if isEphemeral {
            preservedNonPersistentDataStore = webView.configuration.websiteDataStore
        }
        
        let currentCoordinator = self.coordinator
        currentCoordinator?.flushCookiesNow()
        onBeforeDeepSleep?()
        
        sleepState = .deepSleeping
        self.webView = nil
        self.coordinator = nil
        
        currentCoordinator?.cleanupForSleep()
        WebKitMemoryManager.shared.teardownWebView(webView, purgeMemoryCache: true)
        window?.contentView?.layoutSubtreeIfNeeded()
        
        #if DEBUG
        print("[CapsuleLifecycle] Deep sleep (RAM freed) for '\(capsuleName)'")
        #endif
    }
    
    func handleClose() {
        guard sleepState != .closed else { return }
        sleepState = .closed
        cancelAllTimers()
        teardownObservers()
        releaseForegroundActivityToken()
        
        savedInteractionState = nil
        savedURLString = nil
        preservedNonPersistentDataStore = nil
        
        let closeHandler = onWindowWillClose
        canDeepSleepProvider = nil
        onBeforeDeepSleep = nil
        onWindowWillClose = nil
        closeHandler?()
        
        let currentCoordinator = self.coordinator
        let currentWebView = self.webView
        self.coordinator = nil
        self.webView = nil
        self.window = nil
        
        currentCoordinator?.cleanup()
        if let currentWebView {
            WebKitMemoryManager.shared.teardownWebView(currentWebView)
        }
        
        #if DEBUG
        print("[CapsuleLifecycle] Closed and released all capsule objects for '\(capsuleName)'")
        #endif
    }
    
    private func cancelAllTimers() {
        sleepWakeWorkItem?.cancel()
        sleepWakeWorkItem = nil
        deepSleepWorkItem?.cancel()
        deepSleepWorkItem = nil
        audioRecheckWorkItem?.cancel()
        audioRecheckWorkItem = nil
    }
    
    private func teardownObservers() {
        tabGroupObservation?.invalidate()
        tabGroupObservation = nil
        windowTabGroupObservation?.invalidate()
        windowTabGroupObservation = nil
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()
    }
    
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
    
    deinit {
        sleepWakeWorkItem?.cancel()
        deepSleepWorkItem?.cancel()
        audioRecheckWorkItem?.cancel()
        tabGroupObservation?.invalidate()
        windowTabGroupObservation?.invalidate()
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        if let token = activityAssertionToken {
            ProcessInfo.processInfo.endActivity(token)
        }
    }
}

class IsolatedWKWebView: WKWebView {
    var capsuleName: String = ""
    private(set) var isSleeping: Bool = false
    private(set) var isClosedOrDismantled: Bool = false
    var onSearchInNewEphemeralCapsule: ((URL) -> Void)?
    private var cachedContextMenuSelection: String?
    
    static func isSearchWebMenuItem(_ item: NSMenuItem) -> Bool {
        if item.identifier?.rawValue == "WKMenuItemIdentifierSearchWeb" {
            return true
        }
        if let action = item.action, NSStringFromSelector(action) == "_searchWithGoogleFromMenu:" {
            return true
        }
        return false
    }
    
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        cachedContextMenuSelection = nil
        let modeRaw = UserDefaults.standard.string(forKey: "windowPresentationMode") ?? "singleWindow"
        #if DEBUG
        print("[IsolatedWKWebView] willOpenMenu called! mode: \(modeRaw), menu items count: \(menu.items.count)")
        #endif
        var didMatchSearchItem = false
        for item in menu.items {
            if modeRaw == "tabs" {
                if item.identifier?.rawValue == "WKMenuItemIdentifierOpenLinkInNewWindow" || item.title.contains("New Window") {
                    item.title = item.title.replacingOccurrences(of: "New Window", with: "New Tab")
                }
            }
            if Self.isSearchWebMenuItem(item) {
                item.title = SearchEngine.current().contextMenuSearchTitle()
                item.target = self
                item.action = #selector(searchSelectionInNewEphemeralCapsule(_:))
                item.isEnabled = true
                didMatchSearchItem = true
            }
        }
        if didMatchSearchItem {
            extractSelectedText { [weak self] text in
                guard let self, !self.isClosedOrDismantled else { return }
                if let text, !text.isEmpty {
                    self.cachedContextMenuSelection = text
                }
            }
        }
    }
    
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(searchSelectionInNewEphemeralCapsule(_:)) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }
    
    @objc private func searchSelectionInNewEphemeralCapsule(_ sender: Any?) {
        let cached = cachedContextMenuSelection
        cachedContextMenuSelection = nil
        extractSelectedText { [weak self] liveText in
            guard let self, !self.isClosedOrDismantled else { return }
            let liveTrimmed = liveText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cachedTrimmed = cached?.trimmingCharacters(in: .whitespacesAndNewlines)
            let query = (liveTrimmed?.isEmpty == false) ? liveTrimmed! : (cachedTrimmed ?? "")
            guard !query.isEmpty,
                  let searchURL = SearchEngine.searchURL(for: query) else {
                return
            }
            self.onSearchInNewEphemeralCapsule?(searchURL)
        }
    }
    
    private func extractSelectedText(completion: @escaping @MainActor (String?) -> Void) {
        let script = """
        (function() {
            function selectionInDocument(doc, win) {
                if (!doc) return '';
                var active = doc.activeElement;
                while (active) {
                    var tag = active.tagName;
                    if (tag === 'INPUT' || tag === 'TEXTAREA') {
                        var start = active.selectionStart;
                        var end = active.selectionEnd;
                        if (typeof start === 'number' && typeof end === 'number' && end > start) {
                            var val = active.value.slice(start, end);
                            if (val && val.trim().length > 0) return val;
                        }
                    }
                    if (active.shadowRoot) {
                        if (typeof active.shadowRoot.getSelection === 'function') {
                            var srSel = active.shadowRoot.getSelection();
                            var srText = srSel ? srSel.toString() : '';
                            if (srText && srText.trim().length > 0) return srText;
                        }
                        if (active.shadowRoot.activeElement) {
                            active = active.shadowRoot.activeElement;
                            continue;
                        }
                    }
                    break;
                }
                var sel = (win && typeof win.getSelection === 'function') ? win.getSelection() : (typeof doc.getSelection === 'function' ? doc.getSelection() : null);
                var text = sel ? sel.toString() : '';
                if (text && text.trim().length > 0) return text;
                var frames = doc.querySelectorAll('iframe, frame');
                for (var i = 0; i < frames.length; i++) {
                    try {
                        var childDoc = frames[i].contentDocument;
                        var childWin = frames[i].contentWindow;
                        if (childDoc) {
                            var childText = selectionInDocument(childDoc, childWin);
                            if (childText && childText.trim().length > 0) return childText;
                        }
                    } catch (e) {}
                }
                return '';
            }
            return selectionInDocument(document, window);
        })();
        """
        evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self] result in
            let rawText: String?
            if case .success(let value) = result {
                rawText = value as? String
            } else {
                rawText = nil
            }
            MainActor.assumeIsolated {
                let trimmed = rawText?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let trimmed, !trimmed.isEmpty {
                    completion(trimmed)
                } else {
                    completion(self?.extractSelectedTextViaServicesPasteboard())
                }
            }
        }
    }
    
    private func extractSelectedTextViaServicesPasteboard() -> String? {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let selector = #selector(NSServicesMenuRequestor.writeSelection(to:types:))
        let types: NSArray = [NSPasteboard.PasteboardType.string]
        typealias WriteSelectionFn = @convention(c) (AnyObject, Selector, NSPasteboard, NSArray) -> Bool
        
        let candidates: [AnyObject?] = [
            validRequestor(forSendType: .string, returnType: nil) as AnyObject?,
            self
        ]
        for case let candidate? in candidates {
            if candidate.responds(to: selector),
               let method = class_getMethodImplementation(type(of: candidate), selector) {
                let fn = unsafeBitCast(method, to: WriteSelectionFn.self)
                if fn(candidate, selector, pasteboard, types),
                   let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }
    
    // MARK: - Sleep & Wake State Transitions
    
    func applySoftSleep() {
        guard !isClosedOrDismantled, !isSleeping else { return }
        isSleeping = true
        #if DEBUG
        print("[IsolatedWKWebView] Tab soft sleeping: \(self.url?.host ?? "untitled")")
        #endif
        
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
    
    func applyWakeFromSoftSleep() {
        guard !isClosedOrDismantled, isSleeping else { return }
        isSleeping = false
        #if DEBUG
        print("[IsolatedWKWebView] Tab waking from soft sleep: \(self.url?.host ?? "untitled")")
        #endif
        
        setAllMediaPlaybackSuspended(false)
        
        evaluateJavaScript("""
        if (document.hidden !== false) {
            Object.defineProperty(document, 'hidden', { value: false, configurable: true });
            Object.defineProperty(document, 'visibilityState', { value: 'visible', configurable: true });
            document.dispatchEvent(new Event('visibilitychange'));
        }
        """, completionHandler: nil)
    }
    
    func reapplySleepingStateIfNeeded() {
        guard !isClosedOrDismantled, isSleeping else { return }
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
    
    var hasActiveAudioPlayback: Bool {
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
        isClosedOrDismantled = true
        onSearchInNewEphemeralCapsule = nil
        cachedContextMenuSelection = nil
    }
    
    deinit {
        #if DEBUG
        print("[Memory] IsolatedWKWebView deinit: '\(capsuleName)'")
        #endif
        cleanup()
    }
}

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
    /// Standard default Safari User-Agent string used for regular browsing.
    static let defaultUserAgent: String = {
        #if os(macOS)
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6.2 Safari/605.1.15"
        #else
        return "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.4 Mobile/15E148 Safari/604.1"
        #endif
    }()

    /// Generates a randomized User-Agent for YouTube capsules in the format:
    /// 6 random lowercase letters + space + (XX.X)
    /// Example: "kepsse (31.4)"
    static func generateRandomYouTubeUserAgent() -> String {
        let letters = "abcdefghijklmnopqrstuvwxyz"
        let randomLetters = String((0..<6).compactMap { _ in letters.randomElement() })
        let major = Int.random(in: 10...99)
        let minor = Int.random(in: 0...9)
        return "\(randomLetters) (\(major).\(minor))"
    }
    
    /// Dynamically applies the YouTube-specific random User-Agent when browsing YouTube,
    /// or restores the clean standard Safari User-Agent when navigating to other sites.
    static func updateUserAgent(for webView: WKWebView?, targetURL: URL) {
        let isYouTube = targetURL.absoluteString.localizedCaseInsensitiveContains("youtube.com")
        if isYouTube {
            let youtubeUA = generateRandomYouTubeUserAgent()
            webView?.customUserAgent = youtubeUA
            #if DEBUG
            print("[IsolatedWebView] Assigned YouTube spoofed User-Agent: \(youtubeUA)")
            #endif
        } else {
            webView?.customUserAgent = defaultUserAgent
        }
    }
    
    /// Non-mutating DOM extraction script capturing article HTML and page metadata from a live WKWebView.
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
        
        // 1. Configure website data store:
        // Ephemeral capsules (e.g. launched from search bar) have no modelContext -> use nonPersistent().
        // Persistent capsules use WKWebsiteDataStore(forIdentifier:) with the group ID if grouped,
        // or the app item ID if standalone, guaranteeing on-disk isolation and persistence of
        // cookies, localStorage, and IndexedDB across app relaunches.
        let dataStore: WKWebsiteDataStore
        if appItem.modelContext == nil {
            #if os(macOS)
            dataStore = lifecycleController?.preservedNonPersistentDataStore ?? WKWebsiteDataStore.nonPersistent()
            #else
            dataStore = WKWebsiteDataStore.nonPersistent()
            #endif
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
        // Automatic WebKit DOM timer throttling for hidden/occluded background pages when Sleeping Tabs is active
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
        
        // 3. Conditional Content Blocking (applied synchronously if already loaded; otherwise prepared asynchronously before load)
        let needsUBlockLoad = appItem.isUBlockEnabled && !UBlockOriginExtensionManager.shared.isLoaded
        if appItem.isUBlockEnabled && !needsUBlockLoad {
            UBlockOriginExtensionManager.shared.applyToConfiguration(configuration)
        }
        
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
            Self.updateUserAgent(for: webView, targetURL: url)
            webView?.load(URLRequest(url: url))
        }
        let coordinator = context.coordinator
        navigationState.onStopLoading = { [weak webView, weak coordinator] in
            #if DEBUG
            print("[CapsuleClose] Stopping webView & tearing down page for '\(coordinator?.appItem.name ?? "Capsule")'")
            #endif
            coordinator?.flushCookiesNow()
            if let webView {
                WebKitMemoryManager.shared.teardownWebView(webView)
            }
        }
        navigationState.onToggleUBlock = { [weak webView] isEnabled in
            guard let webView = webView else { return }
            let config = webView.configuration
            
            if isEnabled {
                UBlockOriginExtensionManager.shared.applyToConfiguration(config)
            } else {
                UBlockOriginExtensionManager.shared.removeFromConfiguration(config)
            }
            webView.reloadFromOrigin()
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
                let isSleeping = webView.isSleeping
                if !isSleeping {
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
            guard let webView = webView else {
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
        
        // 3. Ensure uBlock rules are prepared, restore isolated cookies (including grouped apps if applicable), and load/restore page
        let groupedItems = appItem.group?.items ?? []
        let startURLString = initialURLString ?? lifecycleSavedURL ?? appItem.lastOpenedURLString ?? appItem.urlString
        let needsCookieRestore = IsolatedCookieManager.shared.needsRestore(for: appItem, groupedItems: groupedItems)
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
            if let url = URL(string: startURLString) {
                #if DEBUG
                print("[IsolatedWebView] Starting initial load for: \(url) (configured home: \(appItem.urlString))")
                #endif
                wv.load(URLRequest(url: url))
            }
        }
        if needsUBlockLoad || needsCookieRestore {
            Task { @MainActor [weak webView] in
                if needsUBlockLoad {
                    await UBlockOriginExtensionManager.shared.prepare()
                    guard let webView, !WebKitMemoryManager.shared.isTornDown(webView) else { return }
                    if appItem.isUBlockEnabled {
                        UBlockOriginExtensionManager.shared.applyToConfiguration(webView.configuration)
                    }
                }
                if needsCookieRestore {
                    await IsolatedCookieManager.shared.restoreCookies(for: appItem, groupedItems: groupedItems, into: dataStore.httpCookieStore)
                }
                guard let webView, !WebKitMemoryManager.shared.isTornDown(webView) else { return }
                startOrRestoreLoad(webView)
            }
        } else {
            startOrRestoreLoad(webView)
        }
        
        return webView
    }
}

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
        
        DispatchQueue.main.async { [weak self, weak webView] in
            guard let self = self, !self.hasFlushedOnCleanup, let webView = webView else { return }
            
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
                    #if os(macOS)
                    self?.navigationState.currentBackgroundWebViewURL = wv.url
                    if self?.navigationState.isReaderModeActive == true { return }
                    #endif
                    if let urlStr = wv.url?.absoluteString, !urlStr.isEmpty, urlStr != "about:blank" {
                        self?.navigationState.currentURLString = urlStr
                    }
                }
            }
            
            // Observe isLoading
            self.loadingObserver = webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    #if os(macOS)
                    if self?.navigationState.isReaderModeActive == true { return }
                    #endif
                    self?.navigationState.isLoading = wv.isLoading
                }
            }
            
            // Flush pending cookies when app terminates (or resigns active on iOS)
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
            
            // Observe global uBlock rules recompiled in GeneralSettingsView
            self.uBlockUpdateObserver = NotificationCenter.default.addObserver(
                forName: UBlockOriginExtensionManager.didUpdateRulesNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self = self, let webView = self.webView else { return }
                    let config = webView.configuration
                    if self.appItem.isUBlockEnabled {
                        UBlockOriginExtensionManager.shared.applyToConfiguration(config)
                    } else {
                        UBlockOriginExtensionManager.shared.removeFromConfiguration(config)
                    }
                    webView.reloadFromOrigin()
                }
            }
            
            // Observe per-capsule uBlock toggle from settings
            self.capsuleUBlockSettingObserver = NotificationCenter.default.addObserver(
                forName: UBlockOriginExtensionManager.capsuleUBlockSettingChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let targetId = notification.object as? UUID
                let overrideEnabled = notification.userInfo?["isUBlockEnabled"] as? Bool
                MainActor.assumeIsolated {
                    guard let self = self,
                          let webView = self.webView,
                          let targetId,
                          targetId == self.appItem.id else { return }
                    
                    let isEnabled = overrideEnabled ?? self.appItem.isUBlockEnabled
                    self.navigationState.isUBlockEnabled = isEnabled
                    let config = webView.configuration
                    if isEnabled {
                        UBlockOriginExtensionManager.shared.applyToConfiguration(config)
                    } else {
                        UBlockOriginExtensionManager.shared.removeFromConfiguration(config)
                    }
                    webView.reloadFromOrigin()
                }
            }
        }
    }
    
    func flushCookiesNow() {
        guard appItem.modelContext != nil, let cookieStore = observedCookieStore else { return }
        IsolatedCookieManager.shared.flushPendingSaveInBackground(
            for: appItem,
            from: cookieStore,
            context: modelContext,
            lastOpenedURL: navigationState.currentURLString
        )
    }
    
    func cleanupForSleep() {
        cleanupInternal(reason: "deep sleep")
    }
    
    func cleanup() {
        cleanupInternal(reason: "close/dismantle")
    }
    
    private func cleanupInternal(reason: String) {
        guard !hasFlushedOnCleanup else { return }
        hasFlushedOnCleanup = true
        #if DEBUG
        print("[CapsuleClose] WebViewCoordinator cleanup (\(reason)) for '\(appItem.name)'")
        #endif
        flushCookiesNow()
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
        #if DEBUG
        print("[IsolatedWebView] decidePolicyFor: targetFrame nil: \(navigationAction.targetFrame == nil), url: \(String(describing: navigationAction.request.url)), navType: \(navigationAction.navigationType.rawValue)")
        #endif
        
        // Security: Block navigation to disallowed or dangerous URL schemes (e.g. file://)
        // and delegate external communication schemes (mailto:, tel:) to the operating system.
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
                #if DEBUG
                print("[IsolatedWebView] decidePolicyFor: blocked navigation to disallowed scheme: \(scheme)")
                #endif
                decisionHandler(.cancel)
                return
            }
            
            // Dynamically synchronize the User-Agent (YouTube spoof vs standard Safari)
            // for every in-page or external navigation.
            IsolatedWebViewRepresentable.updateUserAgent(for: webView, targetURL: targetURL)
        }
        
        // Handle links/actions explicitly flagged as downloads (e.g. <a download>)
        if navigationAction.shouldPerformDownload {
            #if DEBUG
            print("[IsolatedWebView] decidePolicyFor navigationAction: shouldPerformDownload -> .download (\(String(describing: navigationAction.request.url)))")
            #endif
            decisionHandler(.download)
            return
        }
        
        // Defer handling of target="_blank" (new window) links to createWebViewWith
        // to prevent the WKWebView from going blank when we cancel the navigation.
        if navigationAction.targetFrame == nil {
            #if DEBUG
            print("[IsolatedWebView] decidePolicyFor: targetFrame is nil, returning .allow to let createWebViewWith handle it")
            #endif
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
            
            // If the link is on an external domain or is a known article redirector (like Google News /read/...),
            // open it in Safari Reader mode and cancel navigation inside the isolated WKWebView.
            if (isUserClick || isExternalRedirect) && !isInternalNavigation(to: url, currentWebViewURL: webView.url) {
                #if DEBUG
                print("[IsolatedWebView] decidePolicyFor: external domain, canceling and opening in Reader")
                #endif
                decisionHandler(.cancel)
                openInSafariReader(url: url)
                #if os(macOS)
                // If this secondary tab/window was just spawned for a redirect link and hasn't rendered any page yet,
                // close the empty redirect tab/window automatically.
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
        
        // Schedule coalesced, debounced cookie and URL metadata persistence after navigation settles
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
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
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
                #if DEBUG
                print("[IsolatedWebView] decidePolicyFor navigationResponse: triggering .download for \(String(describing: navigationResponse.response.url)) (canShowMIME: \(navigationResponse.canShowMIMEType))")
                #endif
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
    
    // Handle target="_blank", popup windows, and "Open Link in New Window" context menu actions
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        #if DEBUG
        print("[IsolatedWebView] createWebViewWith called! targetFrame is nil: \(navigationAction.targetFrame == nil), url: \(String(describing: navigationAction.request.url))")
        #endif
        if navigationAction.targetFrame == nil {
            if let url = navigationAction.request.url {
                // If "Open Links in Reader" is enabled and the target URL is external (or a known redirector),
                // open it directly in Reader without spawning an empty tab or window first.
                #if os(macOS)
                let shouldOpenNewTabInReader = appItem.openLinksInSafariReaderMode && !navigationState.isReaderModeActive
                #else
                let shouldOpenNewTabInReader = appItem.openLinksInSafariReaderMode
                #endif
                if shouldOpenNewTabInReader && !isInternalNavigation(to: url, currentWebViewURL: webView.url) {
                    #if DEBUG
                    print("[IsolatedWebView] createWebViewWith: external/redirect URL with Reader enabled, opening in Reader: \(url)")
                    #endif
                    openInSafariReader(url: url)
                    return nil
                }
                
                #if os(macOS)
                let modeRaw = UserDefaults.standard.string(forKey: "windowPresentationMode") ?? "singleWindow"
                let mode = WindowPresentationMode(rawValue: modeRaw) ?? .singleWindow
                let handler = onOpenNewWindowOrTab ?? navigationState.onOpenNewWindowOrTab
                
                if mode != .singleWindow {
                    #if DEBUG
                    print("[IsolatedWebView] Mode is \(mode), invoking new window/tab handler for: \(url)")
                    #endif
                    if let win = webView.window {
                        MainWindowTracker.shared.persistWindowSize(from: win)
                        MainWindowTracker.shared.targetWindowForNewTab = win
                    }
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
                #endif
                
                #if DEBUG
                print("[IsolatedWebView] Single window mode: loading in current webview")
                #endif
                IsolatedWebViewRepresentable.updateUserAgent(for: webView, targetURL: url)
                webView.load(navigationAction.request)
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
        print("[IsolatedWebView] Requesting media capture permission for origin: \(origin.host), type: \(typeDescription)")
        #endif
        // Security: Always delegate permission decisions to the native prompt (.prompt)
        // rather than auto-granting (.grant), protecting user privacy against silent recording.
        decisionHandler(.prompt)
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
