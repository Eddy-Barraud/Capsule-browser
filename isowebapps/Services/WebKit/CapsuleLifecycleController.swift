//
//  CapsuleLifecycleController.swift
//  isowebapps
//
//  Description:
//  macOS capsule sleep/wake/close lifecycle controller: applies immediate soft-sleep
//  throttling when backgrounded, frees WebKit RAM after the 5-minute deep-sleep timer
//  (preserving active audio and downloads), and tears down resources on close.
//

#if os(macOS)
import Foundation
import AppKit
import WebKit
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
    var evaluationDebounceDelay: TimeInterval = 0.15
    var sleepDelay: TimeInterval = CapsuleSleepPolicy.defaultSleepTimeoutSeconds
    var audioRecheckInterval: TimeInterval = 30.0
    var canDeepSleepProvider: (() -> Bool)?
    var onBeforeDeepSleep: (() -> Void)?
    var onWindowWillClose: (() -> Void)?
    var snapshotTransformForTesting: ((CapsuleWindowSleepSnapshot) -> CapsuleWindowSleepSnapshot)?
    
    nonisolated(unsafe) private var notificationObservers: [NSObjectProtocol] = []
    nonisolated(unsafe) private var tabGroupObservation: NSKeyValueObservation?
    nonisolated(unsafe) private var windowTabGroupObservation: NSKeyValueObservation?
    nonisolated(unsafe) private var sleepWakeWorkItem: DispatchWorkItem?
    nonisolated(unsafe) private var sleepWorkItem: DispatchWorkItem?
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
                    if name == NSWindow.didBecomeMainNotification {
                        self.hasBeenPresented = true
                    }
                    self.scheduleSleepWakeEvaluation()
                }
            }
            notificationObservers.append(obs)
        }
        
        // Observe key window changes globally so covering/uncovering sibling windows re-evaluate sleep/wake.
        let keyObs = nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] notification in
            let becameKeyWin = notification.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, !self.isClosed else { return }
                if becameKeyWin === self.window {
                    self.hasBeenPresented = true
                }
                self.scheduleSleepWakeEvaluation()
            }
        }
        notificationObservers.append(keyObs)
        
        let closeObs = nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] notification in
            let closingWin = notification.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, !self.isClosed else { return }
                if closingWin === self.window {
                    self.handleClose()
                } else {
                    self.scheduleSleepWakeEvaluation()
                }
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
        if sleepState == .softSleeping {
            webView.applySoftSleep()
        }
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
        let resolvedDelay = delay ?? evaluationDebounceDelay
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
        let snapshot = CapsuleWindowSleepSnapshot(
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
        return snapshotTransformForTesting?(snapshot) ?? snapshot
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
            scheduleSleepAfterTimeout()
        }
    }
    
    func wakeUp(forceImmediate: Bool = false, claimForegroundActivity: Bool? = nil) {
        guard !isClosed else { return }
        sleepWakeWorkItem?.cancel()
        sleepWakeWorkItem = nil
        sleepWorkItem?.cancel()
        sleepWorkItem = nil
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
    
    private func scheduleSleepAfterTimeout() {
        guard !isClosed else { return }
        releaseForegroundActivityToken()
        if sleepState == .deepSleeping {
            return
        }
        
        // Apply soft sleep immediately when backgrounded (throttling DOM/rAF while preserving active audio)
        if sleepState == .awake {
            sleepState = .softSleeping
            webView?.applySoftSleep()
        } else if sleepState == .softSleeping, let webView, !webView.isSleeping {
            webView.applySoftSleep()
        }
        
        if sleepWorkItem == nil && audioRecheckWorkItem == nil {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.sleepWorkItem = nil
                    self?.enterSleepIfEligible()
                }
            }
            sleepWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + sleepDelay, execute: work)
        }
    }
    
    private func scheduleAudioOrBlockerRecheck() {
        audioRecheckWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.audioRecheckWorkItem = nil
                self?.enterSleepIfEligible()
            }
        }
        audioRecheckWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + audioRecheckInterval, execute: work)
    }
    
    private func enterSleepIfEligible() {
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
        
        webView.applySoftSleep()
        sleepState = .deepSleeping
        self.webView = nil
        self.coordinator = nil
        
        currentCoordinator?.cleanupForSleep()
        WebKitMemoryManager.shared.teardownWebView(webView, purgeMemoryCache: true)
        window?.contentView?.layoutSubtreeIfNeeded()
        
        #if DEBUG
        print("[CapsuleLifecycle] Slept capsule after \(Int(sleepDelay))s timer (RAM freed) for '\(capsuleName)'")
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
        snapshotTransformForTesting = nil
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
        sleepWorkItem?.cancel()
        sleepWorkItem = nil
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
        sleepWorkItem?.cancel()
        audioRecheckWorkItem?.cancel()
        tabGroupObservation?.invalidate()
        windowTabGroupObservation?.invalidate()
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        if let token = activityAssertionToken {
            ProcessInfo.processInfo.endActivity(token)
        }
    }
}
#endif
