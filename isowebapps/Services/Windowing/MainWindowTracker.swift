//
//  MainWindowTracker.swift
//  isowebapps
//
//  Description:
//  Coordinates macOS window presentation modes (Single Window, Separate Windows, Tabs),
//  window sizing, tab-group merging, close semantics, Dock reopen, and idle RAM purging.
//

#if os(macOS)
import Foundation
import AppKit

@MainActor
final class MainWindowTracker: NSObject, NSWindowDelegate {
    static let shared = MainWindowTracker()
    static let mainWindowDidCloseNotification = Notification.Name("MainWindowTrackerMainWindowDidClose")
    static let savedWindowWidthKey = "savedWindowWidth"
    static let savedWindowHeightKey = "savedWindowHeight"
    static let minWindowWidth: CGFloat = 800
    static let minWindowHeight: CGFloat = 600
    
    weak var mainWindow: NSWindow?
    weak var targetWindowForNewTab: NSWindow?
    weak var pendingTabTargetWindow: NSWindow?
    var openWindowAction: ((CapsuleWindowPayload) -> Void)?
    var openMainWindowAction: (() -> Void)?
    var mainWindowContentDismissAction: (() -> Void)?
    var isReopeningFromDock: Bool = false
    var isClosingAllTabs: Bool = false
    var configuredWindows = NSHashTable<NSWindow>.weakObjects()
    var knownCapsuleWindows = NSHashTable<NSWindow>.weakObjects()
    var closeHookedWindows = NSHashTable<NSWindow>.weakObjects()
    private var pendingTabRequestID: UInt64 = 0
    private var idlePurgeTask: Task<Void, Never>?
    
    private override init() {
        super.init()
    }
    
    var currentPresentationMode: WindowPresentationMode {
        let modeRaw = UserDefaults.standard.string(forKey: "windowPresentationMode") ?? "singleWindow"
        return WindowPresentationMode(rawValue: modeRaw) ?? .singleWindow
    }
    
    static func supportsNativeTabbing(_ window: NSWindow) -> Bool {
        !(window is NSPanel)
            && !window.isSheet
            && window.sheetParent == nil
            && window.parent == nil
            && window.level == .normal
            && window.styleMask.contains(.titled)
            && window.styleMask.contains(.closable)
            && window.styleMask.contains(.resizable)
            && !window.styleMask.contains(.utilityWindow)
            && !window.styleMask.contains(.hudWindow)
            && !window.styleMask.contains(.nonactivatingPanel)
            && !window.styleMask.contains(.docModalWindow)
    }
    
    static func isSwiftUIHostedWindow(_ window: NSWindow) -> Bool {
        if let rawID = window.identifier?.rawValue,
           rawID.hasPrefix("capsuleWindow") || rawID.hasPrefix("mainWindow") {
            return true
        }
        if let vc = window.contentViewController,
           NSStringFromClass(type(of: vc)).contains("Hosting") {
            return true
        }
        if let cv = window.contentView,
           NSStringFromClass(type(of: cv)).contains("Hosting") {
            return true
        }
        return false
    }
    
    func registerCapsuleWindow(_ window: NSWindow) {
        guard Self.supportsNativeTabbing(window) else { return }
        cancelIdleMemoryPurge()
        knownCapsuleWindows.add(window)
    }
    
    func cancelIdleMemoryPurge() {
        idlePurgeTask?.cancel()
        idlePurgeTask = nil
    }
    
    func hasAnyVisibleCapsuleWindow() -> Bool {
        NSApp.windows.contains { win in
            isManagedCapsuleWindow(win) && (win.isVisible || win.isMiniaturized)
        }
    }
    
    func scheduleIdleMemoryPurgeIfNoVisibleWindows(delaySeconds: TimeInterval = 0.35) {
        idlePurgeTask?.cancel()
        idlePurgeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.idlePurgeTask = nil
            guard !self.hasAnyVisibleCapsuleWindow() else { return }
            await WebKitMemoryManager.shared.purgeIdleResources(teardownAllWebViews: true)
        }
    }
    
    func isManagedCapsuleWindow(_ window: NSWindow) -> Bool {
        guard Self.supportsNativeTabbing(window) else { return false }
        return window === mainWindow
            || knownCapsuleWindows.contains(window)
            || configuredWindows.contains(window)
            || window.tabbingIdentifier == "CapsuleBrowserWindow"
    }
    
    func armPendingTabTarget(_ target: NSWindow) {
        guard Self.supportsNativeTabbing(target) else { return }
        targetWindowForNewTab = target
        pendingTabTargetWindow = target
        pendingTabRequestID &+= 1
        let requestID = pendingTabRequestID
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, self.pendingTabRequestID == requestID else { return }
            self.pendingTabTargetWindow = nil
        }
    }
    
    func clearPendingTabTarget() {
        pendingTabRequestID &+= 1
        pendingTabTargetWindow = nil
    }
    
    func resolveSourceWindow(
        preferred: NSWindow? = nil,
        sourceWindowNumber: Int? = nil,
        excluding excludedWindow: NSWindow? = nil,
        includeFallbackTarget: Bool = true
    ) -> NSWindow? {
        func isValidCandidate(_ candidate: NSWindow?) -> Bool {
            guard let w = candidate,
                  w !== excludedWindow,
                  Self.supportsNativeTabbing(w),
                  !w.isMiniaturized else {
                return false
            }
            return isManagedCapsuleWindow(w) || Self.isSwiftUIHostedWindow(w)
        }
        
        if isValidCandidate(preferred) {
            return preferred
        }
        if let num = sourceWindowNumber,
           let win = NSApp.window(withWindowNumber: num),
           isValidCandidate(win) {
            return win
        }
        if includeFallbackTarget, isValidCandidate(targetWindowForNewTab) {
            return targetWindowForNewTab
        }
        if isValidCandidate(NSApp.keyWindow) {
            return NSApp.keyWindow
        }
        if isValidCandidate(mainWindow) {
            return mainWindow
        }
        if let tagged = NSApp.windows.first(where: {
            isValidCandidate($0) && $0.isVisible && $0.tabbingIdentifier == "CapsuleBrowserWindow"
        }) {
            return tagged
        }
        return NSApp.windows.first(where: { isValidCandidate($0) && $0.isVisible })
    }
    
    /// Unified capsule window/tab launcher used across Home Screen and active capsule views.
    func presentCapsuleWindow(
        appId: UUID?,
        urlString: String,
        name: String,
        startInReaderMode: Bool = false,
        preferredSourceWindow: NSWindow? = nil,
        openAsTab: Bool,
        openWindowFallback: ((CapsuleWindowPayload) -> Void)? = nil
    ) {
        let sourceWin = resolveSourceWindow(
            preferred: preferredSourceWindow,
            includeFallbackTarget: openAsTab
        )
        if let win = sourceWin {
            persistWindowSize(from: win)
        }
        let payload = CapsuleWindowPayload(
            appId: appId,
            urlString: urlString,
            name: name,
            isSecondaryWindow: true,
            openAsTab: openAsTab,
            startInReaderMode: startInReaderMode,
            sourceWindowNumber: sourceWin?.windowNumber,
            sourceFrame: sourceWin?.serializedFrame
        )
        if openAsTab {
            if openWindowAction != nil {
                openNewTab(with: payload, from: sourceWin)
            } else {
                if let win = sourceWin {
                    armPendingTabTarget(win)
                }
                openWindowFallback?(payload)
            }
        } else if let fallback = openWindowFallback ?? openWindowAction {
            fallback(payload)
        }
    }
    
    @discardableResult
    func mergeWindowIntoTabGroup(_ window: NSWindow, target: NSWindow, targetFrame: NSRect? = nil) -> Bool {
        guard target !== window,
              Self.supportsNativeTabbing(window),
              Self.supportsNativeTabbing(target),
              window.tabbingMode != .disallowed else {
            return false
        }
        if let targetGroup = target.tabGroup, window.tabGroup === targetGroup {
            return false
        }
        
        window.animationBehavior = .none
        target.animationBehavior = .none
        
        window.tabbingIdentifier = "CapsuleBrowserWindow"
        window.tabbingMode = .preferred
        target.tabbingIdentifier = "CapsuleBrowserWindow"
        target.tabbingMode = .preferred
        
        let resolvedFrame = targetFrame ?? target.frame
        window.setFrame(resolvedFrame, display: false)
        if target.frame != resolvedFrame {
            target.setFrame(resolvedFrame, display: false)
        }
        target.addTabbedWindow(window, ordered: .above)
        
        if let tg = target.tabGroup {
            for w in tg.windows where w.frame != resolvedFrame {
                w.setFrame(resolvedFrame, display: false)
            }
            tg.selectedWindow = window
        }
        registerCapsuleWindow(window)
        registerCapsuleWindow(target)
        installCloseButtonHookIfNeeded(on: window)
        installCloseButtonHookIfNeeded(on: target)
        return true
    }
    
    func markWindowConfigured(_ window: NSWindow) {
        configuredWindows.add(window)
    }
    
    func handleNewWindowPresentation(_ window: NSWindow) -> Bool {
        guard let target = pendingTabTargetWindow else { return false }
        if window === target {
            return false
        }
        if let targetGroup = target.tabGroup, window.tabGroup === targetGroup {
            clearPendingTabTarget()
            return false
        }
        guard Self.supportsNativeTabbing(window),
              window.tabbingMode != .disallowed,
              Self.isSwiftUIHostedWindow(window),
              window !== mainWindow,
              !(window.identifier?.rawValue.hasPrefix("mainWindow") ?? false),
              !configuredWindows.contains(window),
              Self.supportsNativeTabbing(target) else {
            return false
        }
        
        clearPendingTabTarget()
        
        #if DEBUG
        print("[WindowTabbing] Intercepted new window before presentation, merging into target tab group")
        #endif
        
        guard mergeWindowIntoTabGroup(window, target: target, targetFrame: target.frame) else {
            return false
        }
        markWindowConfigured(window)
        return true
    }
    
    func openNewTab(with payload: CapsuleWindowPayload? = nil, from sourceWindow: NSWindow? = nil) {
        guard currentPresentationMode == .tabs else { return }
        guard let openWindowAction = openWindowAction else { return }
        cancelIdleMemoryPurge()
        
        let targetWin = resolveSourceWindow(preferred: sourceWindow, includeFallbackTarget: false)
        
        if let win = targetWin {
            persistWindowSize(from: win)
            armPendingTabTarget(win)
        }
        
        let finalPayload: CapsuleWindowPayload
        if let payload = payload {
            if payload.sourceWindowNumber == nil || payload.sourceFrame == nil {
                finalPayload = CapsuleWindowPayload(
                    appId: payload.appId,
                    urlString: payload.urlString,
                    name: payload.name,
                    isSecondaryWindow: payload.isSecondaryWindow,
                    openAsTab: payload.openAsTab,
                    startInReaderMode: payload.startInReaderMode,
                    instanceId: payload.instanceId,
                    sourceWindowNumber: payload.sourceWindowNumber ?? targetWin?.windowNumber,
                    sourceFrame: payload.sourceFrame ?? targetWin?.serializedFrame
                )
            } else {
                finalPayload = payload
            }
        } else {
            let defaultPayload = CapsuleWindowPayload.defaultNewTabPayload
            finalPayload = CapsuleWindowPayload(
                appId: defaultPayload.appId,
                urlString: defaultPayload.urlString,
                name: defaultPayload.name,
                isSecondaryWindow: defaultPayload.isSecondaryWindow,
                openAsTab: defaultPayload.openAsTab,
                sourceWindowNumber: targetWin?.windowNumber,
                sourceFrame: targetWin?.serializedFrame
            )
        }
        openWindowAction(finalPayload)
    }
}
#endif
