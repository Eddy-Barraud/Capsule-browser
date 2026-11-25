//
//  WindowPresentationMode.swift
//  isowebapps
//
//  Description:
//  macOS window presentation modes (Single Window, Separate Windows, Tabs)
//  and supporting payload, tracker, and secondary window host.
//

import SwiftUI
import SwiftData
import Combine

#if os(macOS)
import AppKit

final class WeakWindowBox {
    weak var window: NSWindow?
}

struct CapsuleWindowPayload: Codable, Hashable, Identifiable {
    var id: UUID { instanceId }
    let appId: UUID?
    let urlString: String?
    let name: String?
    let isSecondaryWindow: Bool
    let openAsTab: Bool
    let startInReaderMode: Bool
    let instanceId: UUID
    let sourceWindowNumber: Int?
    let sourceFrame: [Double]?
    
    enum CodingKeys: String, CodingKey {
        case appId
        case urlString
        case name
        case isSecondaryWindow
        case openAsTab
        case startInReaderMode
        case instanceId
        case sourceWindowNumber
        case sourceFrame
    }
    
    init(
        appId: UUID?,
        urlString: String?,
        name: String?,
        isSecondaryWindow: Bool = true,
        openAsTab: Bool = false,
        startInReaderMode: Bool = false,
        instanceId: UUID = UUID(),
        sourceWindowNumber: Int? = nil,
        sourceFrame: [Double]? = nil
    ) {
        self.appId = appId
        self.urlString = urlString
        self.name = name
        self.isSecondaryWindow = isSecondaryWindow
        self.openAsTab = openAsTab
        self.startInReaderMode = startInReaderMode
        self.instanceId = instanceId
        self.sourceWindowNumber = sourceWindowNumber
        self.sourceFrame = sourceFrame
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.appId = try container.decodeIfPresent(UUID.self, forKey: .appId)
        self.urlString = try container.decodeIfPresent(String.self, forKey: .urlString)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.isSecondaryWindow = try container.decodeIfPresent(Bool.self, forKey: .isSecondaryWindow) ?? true
        self.openAsTab = try container.decodeIfPresent(Bool.self, forKey: .openAsTab) ?? false
        self.startInReaderMode = try container.decodeIfPresent(Bool.self, forKey: .startInReaderMode) ?? false
        self.instanceId = try container.decodeIfPresent(UUID.self, forKey: .instanceId) ?? UUID()
        self.sourceWindowNumber = try container.decodeIfPresent(Int.self, forKey: .sourceWindowNumber)
        self.sourceFrame = try container.decodeIfPresent([Double].self, forKey: .sourceFrame)
    }
    
    #if os(macOS)
    var sourceFrameRect: NSRect? {
        guard let sf = sourceFrame, sf.count == 4 else { return nil }
        return NSRect(x: sf[0], y: sf[1], width: sf[2], height: sf[3])
    }
    #endif
    
    static var defaultNewTabPayload: CapsuleWindowPayload {
        let modeRaw = UserDefaults.standard.string(forKey: "windowPresentationMode") ?? "singleWindow"
        let mode = WindowPresentationMode(rawValue: modeRaw) ?? .singleWindow
        let rawEngine = UserDefaults.standard.string(forKey: SearchEngine.storageKey) ?? SearchEngine.duckDuckGo.rawValue
        let engine = SearchEngine(rawValue: rawEngine) ?? .duckDuckGo
        let customURL = UserDefaults.standard.string(forKey: SearchEngine.customURLStorageKey) ?? ""
        return CapsuleWindowPayload(
            appId: nil,
            urlString: engine.homeURLString(customTemplate: customURL),
            name: engine.displayName,
            isSecondaryWindow: true,
            openAsTab: (mode == .tabs)
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
        NSWindow.allowsAutomaticWindowTabbing = false
        _ = NSWindow.swizzleNewWindowForTabOnce
        _ = NSWindow.swizzlePresentationMethodsOnce
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        CloudSyncManager.shared.handleAppDidBecomeActive()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowTracker.shared.handleDockReopen(hasVisibleWindows: flag)
        return true
    }
}

extension NSWindow {
    static let swizzleNewWindowForTabOnce: Void = {
        let originalSelector = #selector(NSResponder.newWindowForTab(_:))
        let swizzledSelector = #selector(NSWindow.capsule_newWindowForTab(_:))
        
        guard let swizzledMethod = class_getInstanceMethod(NSWindow.self, swizzledSelector) else { return }
        
        if class_addMethod(
            NSWindow.self,
            originalSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        ) {
            #if DEBUG
            print("[WindowTabbing] Successfully added newWindowForTab: to NSWindow")
            #endif
        } else if let originalMethod = class_getInstanceMethod(NSWindow.self, originalSelector) {
            method_exchangeImplementations(originalMethod, swizzledMethod)
            #if DEBUG
            print("[WindowTabbing] Successfully swizzled newWindowForTab: on NSWindow")
            #endif
        }
    }()
    
    static let swizzlePresentationMethodsOnce: Void = {
        let pairs: [(Selector, Selector)] = [
            (#selector(NSWindow.makeKeyAndOrderFront(_:)), #selector(NSWindow.capsule_makeKeyAndOrderFront(_:))),
            (#selector(NSWindow.orderFront(_:)), #selector(NSWindow.capsule_orderFront(_:))),
            (#selector(NSWindow.order(_:relativeTo:)), #selector(NSWindow.capsule_order(_:relativeTo:))),
            (#selector(NSWindow.performClose(_:)), #selector(NSWindow.capsule_performClose(_:)))
        ]
        
        for (origSel, swizSel) in pairs {
            guard let origMethod = class_getInstanceMethod(NSWindow.self, origSel),
                  let swizMethod = class_getInstanceMethod(NSWindow.self, swizSel) else { continue }
            method_exchangeImplementations(origMethod, swizMethod)
        }
    }()
    
    @objc @MainActor func capsule_newWindowForTab(_ sender: Any?) {
        let source = MainWindowTracker.shared.isManagedCapsuleWindow(self) ? self : nil
        MainWindowTracker.shared.openNewTab(from: source)
    }
    
    @objc @MainActor func capsule_makeKeyAndOrderFront(_ sender: Any?) {
        _ = MainWindowTracker.shared.handleNewWindowPresentation(self)
        capsule_makeKeyAndOrderFront(sender)
    }
    
    @objc @MainActor func capsule_orderFront(_ sender: Any?) {
        _ = MainWindowTracker.shared.handleNewWindowPresentation(self)
        capsule_orderFront(sender)
    }
    
    @objc @MainActor func capsule_order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        if place != .out {
            _ = MainWindowTracker.shared.handleNewWindowPresentation(self)
        }
        capsule_order(place, relativeTo: otherWin)
    }
    
    @objc @MainActor func capsule_performClose(_ sender: Any?) {
        if MainWindowTracker.shared.isManagedCapsuleWindow(self) {
            if let button = sender as? NSButton, button === self.standardWindowButton(.closeButton) {
                MainWindowTracker.shared.handleTrafficLightClose(for: self)
            } else {
                MainWindowTracker.shared.closeTab(self)
            }
            return
        }
        capsule_performClose(sender)
    }
    
    var serializedFrame: [Double] {
        let f = self.frame
        return [Double(f.origin.x), Double(f.origin.y), Double(f.size.width), Double(f.size.height)]
    }
}

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
    private(set) var isReopeningFromDock: Bool = false
    private(set) var isClosingAllTabs: Bool = false
    private var configuredWindows = NSHashTable<NSWindow>.weakObjects()
    private var knownCapsuleWindows = NSHashTable<NSWindow>.weakObjects()
    private var closeHookedWindows = NSHashTable<NSWindow>.weakObjects()
    private var pendingTabRequestID: UInt64 = 0
    private var idlePurgeTask: Task<Void, Never>?
    
    private override init() {
        super.init()
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
    
    func isWindowConfigured(_ window: NSWindow) -> Bool {
        configuredWindows.contains(window)
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
    
    func savedWindowSizeRect(for window: NSWindow) -> NSRect {
        let size = savedWindowSize
        var frame = window.frame
        let newFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        frame.origin.y += (frame.size.height - newFrameSize.height)
        frame.size = newFrameSize
        if let screenVisibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame {
            frame.size.width = min(frame.size.width, screenVisibleFrame.width)
            frame.size.height = min(frame.size.height, screenVisibleFrame.height)
            frame.origin.x = max(screenVisibleFrame.minX, min(frame.origin.x, screenVisibleFrame.maxX - frame.size.width))
            frame.origin.y = max(screenVisibleFrame.minY, min(frame.origin.y, screenVisibleFrame.maxY - frame.size.height))
        }
        return frame
    }
    
    func openNewTab(with payload: CapsuleWindowPayload? = nil, from sourceWindow: NSWindow? = nil) {
        let modeRaw = UserDefaults.standard.string(forKey: "windowPresentationMode") ?? "singleWindow"
        let mode = WindowPresentationMode(rawValue: modeRaw) ?? .singleWindow
        guard mode == .tabs else { return }
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
    
    var savedWindowSize: CGSize {
        let width = UserDefaults.standard.double(forKey: Self.savedWindowWidthKey)
        let height = UserDefaults.standard.double(forKey: Self.savedWindowHeightKey)
        let resolvedWidth = width >= Self.minWindowWidth ? width : Self.minWindowWidth
        let resolvedHeight = height >= Self.minWindowHeight ? height : Self.minWindowHeight
        return CGSize(width: resolvedWidth, height: resolvedHeight)
    }
    
    func persistWindowSize(from window: NSWindow) {
        guard Self.supportsNativeTabbing(window),
              !window.isMiniaturized,
              !window.styleMask.contains(.fullScreen) else {
            return
        }
        let contentSize = window.contentLayoutRect.size.width >= Self.minWindowWidth
            ? window.contentLayoutRect.size
            : window.frame.size
        let width = max(Self.minWindowWidth, contentSize.width)
        let height = max(Self.minWindowHeight, contentSize.height)
        UserDefaults.standard.set(Double(width), forKey: Self.savedWindowWidthKey)
        UserDefaults.standard.set(Double(height), forKey: Self.savedWindowHeightKey)
    }
    
    func applySavedSizeIfNeeded(to window: NSWindow) {
        window.isRestorable = false
        installCloseButtonHookIfNeeded(on: window)
        guard !configuredWindows.contains(window) else { return }
        configuredWindows.add(window)
        
        let targetSize = savedWindowSize
        let currentSize = window.contentLayoutRect.size
        guard abs(currentSize.width - targetSize.width) > 1 || abs(currentSize.height - targetSize.height) > 1 else {
            return
        }
        
        var frame = window.frame
        let newFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetSize)).size
        // Keep the top-left corner anchored (macOS coordinate system has origin at bottom-left)
        frame.origin.y += (frame.size.height - newFrameSize.height)
        frame.size = newFrameSize
        
        if let screenVisibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame {
            frame.size.width = min(frame.size.width, screenVisibleFrame.width)
            frame.size.height = min(frame.size.height, screenVisibleFrame.height)
            frame.origin.x = max(screenVisibleFrame.minX, min(frame.origin.x, screenVisibleFrame.maxX - frame.size.width))
            frame.origin.y = max(screenVisibleFrame.minY, min(frame.origin.y, screenVisibleFrame.maxY - frame.size.height))
        }
        
        window.setFrame(frame, display: true)
    }
    
    var currentPresentationMode: WindowPresentationMode {
        let modeRaw = UserDefaults.standard.string(forKey: "windowPresentationMode") ?? "singleWindow"
        return WindowPresentationMode(rawValue: modeRaw) ?? .singleWindow
    }
    
    func installCloseButtonHookIfNeeded(on window: NSWindow) {
        guard Self.supportsNativeTabbing(window),
              let closeButton = window.standardWindowButton(.closeButton) else {
            return
        }
        closeHookedWindows.add(window)
        if closeButton.target !== self || closeButton.action != #selector(handleTrafficLightCloseButton(_:)) {
            closeButton.target = self
            closeButton.action = #selector(handleTrafficLightCloseButton(_:))
        }
    }
    
    @objc private func handleTrafficLightCloseButton(_ sender: NSButton) {
        guard let clickedWindow = sender.window else { return }
        let currentEventType = NSApp.currentEvent?.type
        let isMouseEvent = (currentEventType == .leftMouseUp || currentEventType == .leftMouseDown)
        let isOptionPressed = isMouseEvent && NSEvent.modifierFlags.contains(.option)
        handleTrafficLightClose(for: clickedWindow, isOptionClick: isOptionPressed)
    }
    
    func handleTrafficLightClose(for clickedWindow: NSWindow, isOptionClick: Bool = false) {
        let isInMainTG: Bool = {
            guard let tg = clickedWindow.tabGroup, let mainTG = mainWindow?.tabGroup else { return false }
            return tg === mainTG
        }()
        let action = CapsuleWindowClosePolicy.trafficLightCloseAction(
            isMainWindow: clickedWindow === mainWindow,
            presentationMode: currentPresentationMode,
            isInMainWindowTabGroup: isInMainTG,
            tabGroupWindowCount: clickedWindow.tabGroup?.windows.count ?? 1,
            isOptionClick: isOptionClick
        )
        #if DEBUG
        print("[CapsuleClose] Traffic-light close on '\(clickedWindow.title)' (isMain: \(clickedWindow === mainWindow), mode: \(currentPresentationMode.rawValue), action: \(action))")
        #endif
        switch action {
        case .closeAllAppWindows:
            closeAllTabsAndMainWindow(startingFrom: clickedWindow)
        case .closeWindowTabGroup:
            closeTabGroupOnly(startingFrom: clickedWindow)
        case .closeSingleWindow:
            closeTab(clickedWindow)
        }
    }
    
    func closeTab(_ windowToClose: NSWindow) {
        #if DEBUG
        print("[CapsuleClose] closeTab called for window '\(windowToClose.title)' (isMainWindow: \(windowToClose === mainWindow))")
        #endif
        if windowToClose === mainWindow {
            if let dismissAction = mainWindowContentDismissAction {
                dismissAction()
                return
            }
            closeAllTabsAndMainWindow(startingFrom: windowToClose)
            return
        }
        cleanupAndCloseSecondaryWindow(windowToClose)
        scheduleIdleMemoryPurgeIfNoVisibleWindows()
    }
    
    private func cleanupAndCloseSecondaryWindow(_ windowToClose: NSWindow) {
        if windowToClose === pendingTabTargetWindow {
            clearPendingTabTarget()
        }
        if windowToClose === targetWindowForNewTab {
            targetWindowForNewTab = nil
        }
        configuredWindows.remove(windowToClose)
        knownCapsuleWindows.remove(windowToClose)
        closeHookedWindows.remove(windowToClose)
        persistWindowSize(from: windowToClose)
        windowToClose.makeFirstResponder(nil)
        windowToClose.delegate = nil
        windowToClose.close()
    }
    
    private func closeTabGroupOnly(startingFrom window: NSWindow) {
        guard !isClosingAllTabs else { return }
        isClosingAllTabs = true
        defer { isClosingAllTabs = false }
        
        persistWindowSize(from: window)
        let windowsInGroup = window.tabGroup?.windows ?? [window]
        for tabWin in windowsInGroup where tabWin !== mainWindow {
            cleanupAndCloseSecondaryWindow(tabWin)
        }
        scheduleIdleMemoryPurgeIfNoVisibleWindows()
    }
    
    private func activeManagedWindow() -> NSWindow? {
        if let key = NSApp.keyWindow, isManagedCapsuleWindow(key) {
            return key
        }
        if let main = NSApp.mainWindow, isManagedCapsuleWindow(main) {
            return main
        }
        return mainWindow
    }
    
    func closeActiveTab() {
        if let key = NSApp.keyWindow,
           !isManagedCapsuleWindow(key),
           (key.sheetParent != nil || key is NSPanel) {
            key.performClose(nil)
            return
        }
        guard let active = activeManagedWindow() else { return }
        let targetTab = active.tabGroup?.selectedWindow ?? active
        closeTab(targetTab)
    }
    
    func closeActiveWindow() {
        guard let active = activeManagedWindow() else { return }
        handleTrafficLightClose(for: active, isOptionClick: false)
    }
    
    private func allManagedWindows(startingFrom window: NSWindow) -> [NSWindow] {
        var seen = Set<ObjectIdentifier>()
        var result: [NSWindow] = []
        
        func appendIfNeeded(_ candidate: NSWindow?) {
            guard let w = candidate else { return }
            let id = ObjectIdentifier(w)
            if seen.insert(id).inserted {
                result.append(w)
            }
        }
        
        appendIfNeeded(window)
        window.tabGroup?.windows.forEach { appendIfNeeded($0) }
        appendIfNeeded(mainWindow)
        mainWindow?.tabGroup?.windows.forEach { appendIfNeeded($0) }
        for known in knownCapsuleWindows.allObjects {
            appendIfNeeded(known)
            known.tabGroup?.windows.forEach { appendIfNeeded($0) }
        }
        for configured in configuredWindows.allObjects {
            appendIfNeeded(configured)
            configured.tabGroup?.windows.forEach { appendIfNeeded($0) }
        }
        for appWin in NSApp.windows where isManagedCapsuleWindow(appWin) {
            appendIfNeeded(appWin)
        }
        return result
    }
    
    func closeAllTabsAndMainWindow(startingFrom window: NSWindow) {
        guard !isClosingAllTabs else { return }
        isClosingAllTabs = true
        defer { isClosingAllTabs = false }
        
        clearPendingTabTarget()
        targetWindowForNewTab = nil
        persistWindowSize(from: window)
        
        let windowsToClose = allManagedWindows(startingFrom: window)
        #if DEBUG
        print("[CapsuleClose] Closing all app windows and tabs (\(windowsToClose.count) window(s))")
        #endif
        
        for win in windowsToClose where win !== mainWindow {
            cleanupAndCloseSecondaryWindow(win)
        }
        
        if let main = mainWindow {
            mainWindow = nil
            mainWindowContentDismissAction = nil
            configuredWindows.remove(main)
            knownCapsuleWindows.remove(main)
            closeHookedWindows.remove(main)
            NotificationCenter.default.post(name: Self.mainWindowDidCloseNotification, object: main)
            main.makeFirstResponder(nil)
            main.delegate = nil
            main.close()
        }
        scheduleIdleMemoryPurgeIfNoVisibleWindows()
    }
    
    func focusMainWindow() {
        cancelIdleMemoryPurge()
        if let window = mainWindow, window.isVisible {
            if let tabGroup = window.tabGroup, tabGroup.windows.count > 1 {
                if tabGroup.selectedWindow !== window {
                    tabGroup.selectedWindow = window
                    window.makeKeyAndOrderFront(nil)
                }
            } else {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        } else {
            openMainWindowAction?()
        }
    }
    
    func handleDockReopen(hasVisibleWindows flag: Bool) {
        cancelIdleMemoryPurge()
        if !UBlockOriginExtensionManager.shared.isLoaded {
            Task {
                await UBlockOriginExtensionManager.shared.prepare()
            }
        }
        if !flag {
            isReopeningFromDock = true
            // Close any hidden/lingering secondary capsule windows so reopening starts with only the main window
            for win in NSApp.windows where isManagedCapsuleWindow(win) && win !== mainWindow {
                win.delegate = nil
                win.close()
            }
            if let currentMain = mainWindow, !currentMain.isVisible {
                mainWindow = nil
            }
            NotificationCenter.default.post(name: Self.mainWindowDidCloseNotification, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.isReopeningFromDock = false
            }
        }
    }
    
    // MARK: - NSWindowDelegate
    
    func windowDidResize(_ notification: Notification) {
        guard let resizedWindow = notification.object as? NSWindow else { return }
        guard configuredWindows.contains(resizedWindow) else { return }
        persistWindowSize(from: resizedWindow)
    }
    
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let resizedWindow = notification.object as? NSWindow else { return }
        guard configuredWindows.contains(resizedWindow) else { return }
        persistWindowSize(from: resizedWindow)
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isClosingAllTabs {
            return true
        }
        if let tabGroup = sender.tabGroup, tabGroup.windows.count > 1 {
            return true
        }
        return true
    }
    
    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        #if DEBUG
        print("[CapsuleClose] MainWindowTracker windowWillClose: '\(closingWindow.title)' (isMainWindow: \(closingWindow === mainWindow))")
        #endif
        if closingWindow === pendingTabTargetWindow {
            clearPendingTabTarget()
        }
        if closingWindow === targetWindowForNewTab {
            targetWindowForNewTab = nil
        }
        let wasMainWindow = (closingWindow === mainWindow)
        configuredWindows.remove(closingWindow)
        knownCapsuleWindows.remove(closingWindow)
        closeHookedWindows.remove(closingWindow)
        persistWindowSize(from: closingWindow)
        if wasMainWindow {
            mainWindow = nil
            mainWindowContentDismissAction = nil
            NotificationCenter.default.post(name: Self.mainWindowDidCloseNotification, object: closingWindow)
            if !isClosingAllTabs {
                isClosingAllTabs = true
                defer { isClosingAllTabs = false }
                let secondaryWindows = allManagedWindows(startingFrom: closingWindow).filter { $0 !== closingWindow }
                for sec in secondaryWindows {
                    cleanupAndCloseSecondaryWindow(sec)
                }
            }
        }
        scheduleIdleMemoryPurgeIfNoVisibleWindows()
    }
}

final class WindowAccessorView: NSView {
    var onWindowSync: ((NSWindow) -> Void)?
    var onWindow: ((NSWindow) -> Void)?
    weak var lastNotifiedWindow: NSWindow?
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = self.window, window !== lastNotifiedWindow {
            lastNotifiedWindow = window
            onWindowSync?(window)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window = window else { return }
                self?.onWindow?(window)
            }
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    var onWindowSync: ((NSWindow) -> Void)? = nil
    let onWindow: (NSWindow) -> Void
    
    func makeNSView(context: Context) -> WindowAccessorView {
        let view = WindowAccessorView()
        view.onWindowSync = onWindowSync
        view.onWindow = onWindow
        if let window = view.window, window !== view.lastNotifiedWindow {
            view.lastNotifiedWindow = window
            onWindowSync?(window)
            DispatchQueue.main.async { [weak window] in
                guard let window = window else { return }
                onWindow(window)
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: WindowAccessorView, context: Context) {
        nsView.onWindowSync = onWindowSync
        nsView.onWindow = onWindow
        if let window = nsView.window, window !== nsView.lastNotifiedWindow {
            nsView.lastNotifiedWindow = window
            onWindowSync?(window)
            DispatchQueue.main.async { [weak window] in
                guard let window = window else { return }
                onWindow(window)
            }
        }
    }
}

@MainActor
final class CapsuleWindowCloseObserver: ObservableObject {
    nonisolated(unsafe) private var observer: NSObjectProtocol?
    private weak var observedWindow: NSWindow?
    
    func attach(to window: NSWindow, onClose: @escaping @MainActor () -> Void) {
        if observedWindow === window, observer != nil {
            return
        }
        removeObserver()
        observedWindow = window
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.removeObserver()
                onClose()
            }
        }
    }
    
    private func removeObserver() {
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
            observer = nil
        }
        observedWindow = nil
    }
    
    deinit {
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}

struct CapsuleWindowHostView: View {
    let payload: CapsuleWindowPayload
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @State private var cachedAppItem: WebAppItem?
    @State private var currentDomainTitle: String = ""
    @State private var hostingWindowBox = WeakWindowBox()
    @State private var hasConfiguredWindow = false
    @State private var isWindowClosed = false
    @StateObject private var closeObserver = CapsuleWindowCloseObserver()
    
    private var hostingWindow: NSWindow? {
        hostingWindowBox.window
    }
    
    private func lookupAppItem() -> WebAppItem {
        if let appId = payload.appId {
            let descriptor = FetchDescriptor<WebAppItem>(predicate: #Predicate { $0.id == appId })
            if let found = (try? modelContext.fetch(descriptor))?.first {
                return found
            }
        }
        return WebAppItem(name: payload.name ?? "Capsule", urlString: payload.urlString ?? "about:blank")
    }
    
    private var resolvedAppItem: WebAppItem {
        if let cached = cachedAppItem {
            return cached
        }
        return lookupAppItem()
    }
    
    private var initialDomainTitle: String {
        let rawURL = payload.urlString ?? resolvedAppItem.lastOpenedURLString ?? resolvedAppItem.urlString
        return WebAppNamingHelper.domainName(from: rawURL) ?? resolvedAppItem.name
    }
    
    var body: some View {
        Group {
            if isWindowClosed {
                EmptyView()
            } else {
                WebAppContainerView(
                    appItem: resolvedAppItem,
                    initialURLString: payload.urlString,
                    isSecondaryWindow: payload.isSecondaryWindow,
                    startInReaderMode: payload.startInReaderMode,
                    onActiveDomainChange: { newDomain in
                        currentDomainTitle = newDomain
                        hostingWindow?.title = newDomain
                        hostingWindow?.tab.title = newDomain
                    },
                    onDismiss: {
                        MainWindowTracker.shared.focusMainWindow()
                    }
                )
                .frame(minWidth: 800, minHeight: 600)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(currentDomainTitle.isEmpty ? initialDomainTitle : currentDomainTitle)
                .onAppear {
                    MainWindowTracker.shared.cancelIdleMemoryPurge()
                    if !UBlockOriginExtensionManager.shared.isLoaded {
                        Task {
                            await UBlockOriginExtensionManager.shared.prepare()
                        }
                    }
                    if currentDomainTitle.isEmpty {
                        currentDomainTitle = initialDomainTitle
                    }
                    if cachedAppItem == nil {
                        cachedAppItem = lookupAppItem()
                    }
                    if MainWindowTracker.shared.openWindowAction == nil {
                        MainWindowTracker.shared.openWindowAction = { payload in
                            openWindow(id: "capsuleWindow", value: payload)
                        }
                    }
                    if MainWindowTracker.shared.openMainWindowAction == nil {
                        MainWindowTracker.shared.openMainWindowAction = {
                            openWindow(id: "mainWindow")
                        }
                    }
                }
            }
        }
        .background(
            WindowAccessor(
                onWindowSync: { window in
                    MainWindowTracker.shared.registerCapsuleWindow(window)
                    if payload.openAsTab {
                        window.animationBehavior = .none
                        window.tabbingMode = .preferred
                        window.tabbingIdentifier = "CapsuleBrowserWindow"
                        
                        let titleToSet = currentDomainTitle.isEmpty ? initialDomainTitle : currentDomainTitle
                        window.title = titleToSet
                        window.tab.title = titleToSet
                        
                        let targetWindow = MainWindowTracker.shared.resolveSourceWindow(
                            sourceWindowNumber: payload.sourceWindowNumber,
                            excluding: window,
                            includeFallbackTarget: true
                        )
                        
                        let targetFrame = payload.sourceFrameRect
                            ?? targetWindow?.frame
                            ?? (window.tabGroup?.windows.first(where: { $0 !== window })?.frame)
                            ?? MainWindowTracker.shared.savedWindowSizeRect(for: window)
                        
                        if let target = targetWindow, target !== window {
                            let merged = MainWindowTracker.shared.mergeWindowIntoTabGroup(
                                window,
                                target: target,
                                targetFrame: targetFrame
                            )
                            if merged || (target.tabGroup != nil && window.tabGroup === target.tabGroup) {
                                MainWindowTracker.shared.clearPendingTabTarget()
                            }
                        }
                    } else {
                        window.tabbingMode = .disallowed
                        if let sourceRect = payload.sourceFrameRect {
                            var frame = window.frame
                            frame.size = sourceRect.size
                            window.setFrame(frame, display: false)
                        }
                    }
                },
                onWindow: { window in
                    MainWindowTracker.shared.registerCapsuleWindow(window)
                    if hostingWindowBox.window !== window {
                        hostingWindowBox.window = window
                    }
                    let titleToSet = currentDomainTitle.isEmpty ? initialDomainTitle : currentDomainTitle
                    if window.title != titleToSet {
                        window.title = titleToSet
                    }
                    if window.tab.title != titleToSet {
                        window.tab.title = titleToSet
                    }
                    guard !hasConfiguredWindow else {
                        return
                    }
                    hasConfiguredWindow = true
                    window.isRestorable = false
                    MainWindowTracker.shared.installCloseButtonHookIfNeeded(on: window)
                    
                    let appName = resolvedAppItem.name
                    closeObserver.attach(to: window) { [weak window] in
                        #if DEBUG
                        print("[CapsuleClose] CapsuleWindowHostView closing window/tab for '\(appName)'")
                        #endif
                        hostingWindowBox.window = nil
                        cachedAppItem = nil
                        isWindowClosed = true
                        window?.contentView?.layoutSubtreeIfNeeded()
                    }
                    
                    if payload.openAsTab {
                        MainWindowTracker.shared.clearPendingTabTarget()
                        window.tabbingMode = .preferred
                        window.tabbingIdentifier = "CapsuleBrowserWindow"
                        window.delegate = MainWindowTracker.shared
                        
                        let targetWindow = MainWindowTracker.shared.resolveSourceWindow(
                            sourceWindowNumber: payload.sourceWindowNumber,
                            excluding: window,
                            includeFallbackTarget: false
                        )
                        
                        let targetFrame = payload.sourceFrameRect
                            ?? targetWindow?.frame
                            ?? (window.tabGroup?.windows.first(where: { $0 !== window })?.frame)
                            ?? MainWindowTracker.shared.savedWindowSizeRect(for: window)
                        
                        if let tg = window.tabGroup, tg.windows.count > 1 {
                            for w in tg.windows {
                                if w.frame != targetFrame {
                                    w.setFrame(targetFrame, display: false)
                                }
                            }
                            tg.selectedWindow = window
                            window.makeKeyAndOrderFront(nil)
                            window.makeFirstResponder(window.contentView)
                        } else if let target = targetWindow, target !== window {
                            if !MainWindowTracker.shared.mergeWindowIntoTabGroup(
                                window,
                                target: target,
                                targetFrame: targetFrame
                            ) {
                                window.setFrame(targetFrame, display: false)
                            }
                            window.makeKeyAndOrderFront(nil)
                            window.makeFirstResponder(window.contentView)
                        } else {
                            window.setFrame(targetFrame, display: false)
                            window.makeKeyAndOrderFront(nil)
                            window.makeFirstResponder(window.contentView)
                        }
                        MainWindowTracker.shared.markWindowConfigured(window)
                        MainWindowTracker.shared.persistWindowSize(from: window)
                    } else {
                        window.tabbingMode = .disallowed
                        window.delegate = MainWindowTracker.shared
                        if let sourceRect = payload.sourceFrameRect {
                            var frame = window.frame
                            frame.size = sourceRect.size
                            window.setFrame(frame, display: false)
                        } else {
                            MainWindowTracker.shared.applySavedSizeIfNeeded(to: window)
                        }
                        MainWindowTracker.shared.markWindowConfigured(window)
                        window.cascadeTopLeft(from: NSZeroPoint)
                        window.makeKeyAndOrderFront(nil)
                    }
                    NSApp.activate(ignoringOtherApps: true)
                }
            )
        )
    }
}
#endif
