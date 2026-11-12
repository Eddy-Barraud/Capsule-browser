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

#if os(macOS)
import AppKit

enum WindowPresentationMode: String, CaseIterable, Identifiable, Codable {
    case singleWindow = "singleWindow"
    case separateWindows = "separateWindows"
    case tabs = "tabs"
    
    var id: String { rawValue }
    
    var next: WindowPresentationMode {
        switch self {
        case .singleWindow:
            return .separateWindows
        case .separateWindows:
            return .tabs
        case .tabs:
            return .singleWindow
        }
    }
    
    var iconName: String {
        switch self {
        case .singleWindow:
            return "macwindow"
        case .separateWindows:
            return "macwindow.on.rectangle"
        case .tabs:
            return "macwindow.stack"
        }
    }
    
    var title: String {
        switch self {
        case .singleWindow:
            return "Single Window"
        case .separateWindows:
            return "Separate Windows"
        case .tabs:
            return "Tabs"
        }
    }
    
    var tooltip: String {
        switch self {
        case .singleWindow:
            return "Mode: Single Window (Click for Separate Windows)"
        case .separateWindows:
            return "Mode: Separate Windows (Click for Tabs)"
        case .tabs:
            return "Mode: Tabs (Click for Single Window)"
        }
    }
}

struct CapsuleWindowPayload: Codable, Hashable, Identifiable {
    var id: UUID { instanceId }
    let appId: UUID?
    let urlString: String?
    let name: String?
    let isSecondaryWindow: Bool
    let openAsTab: Bool
    let instanceId: UUID
    let sourceWindowNumber: Int?
    let sourceFrame: [Double]?
    
    init(
        appId: UUID?,
        urlString: String?,
        name: String?,
        isSecondaryWindow: Bool = true,
        openAsTab: Bool = false,
        instanceId: UUID = UUID(),
        sourceWindowNumber: Int? = nil,
        sourceFrame: [Double]? = nil
    ) {
        self.appId = appId
        self.urlString = urlString
        self.name = name
        self.isSecondaryWindow = isSecondaryWindow
        self.openAsTab = openAsTab
        self.instanceId = instanceId
        self.sourceWindowNumber = sourceWindowNumber
        self.sourceFrame = sourceFrame
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
    
    @objc func capsule_newWindowForTab(_ sender: Any?) {
        MainWindowTracker.shared.openNewTab(from: self)
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
        _ = MainWindowTracker.shared.handleNewWindowPresentation(self)
        capsule_order(place, relativeTo: otherWin)
    }
    
    @objc @MainActor func capsule_performClose(_ sender: Any?) {
        if !(self is NSPanel) && self.sheetParent == nil {
            MainWindowTracker.shared.closeTab(self)
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
    private var closeHookedWindows = NSHashTable<NSWindow>.weakObjects()
    
    private override init() {
        super.init()
    }
    
    func markWindowConfigured(_ window: NSWindow) {
        configuredWindows.add(window)
    }
    
    func isWindowConfigured(_ window: NSWindow) -> Bool {
        configuredWindows.contains(window)
    }
    
    func handleNewWindowPresentation(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel), window.sheetParent == nil else { return false }
        guard let target = pendingTabTargetWindow ?? targetWindowForNewTab,
              target !== window,
              window.tabGroup !== target.tabGroup else {
            return false
        }
        pendingTabTargetWindow = nil
        targetWindowForNewTab = nil
        
        #if DEBUG
        print("[WindowTabbing] Intercepted new window before presentation, merging into target tab group")
        #endif
        
        window.animationBehavior = .none
        target.animationBehavior = .none
        
        window.tabbingIdentifier = "CapsuleBrowserWindow"
        window.tabbingMode = .preferred
        target.tabbingIdentifier = "CapsuleBrowserWindow"
        target.tabbingMode = .preferred
        
        let targetFrame = target.frame
        window.setFrame(targetFrame, display: false)
        target.addTabbedWindow(window, ordered: .above)
        
        if let tg = target.tabGroup {
            for w in tg.windows {
                if w.frame != targetFrame {
                    w.setFrame(targetFrame, display: false)
                }
            }
            tg.selectedWindow = window
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
        
        let targetWin = sourceWindow
            ?? (NSApp.keyWindow != nil && !(NSApp.keyWindow is NSPanel) && !(NSApp.keyWindow?.isMiniaturized ?? true) ? NSApp.keyWindow : nil)
            ?? mainWindow
            ?? NSApp.windows.first(where: { !($0 is NSPanel) && $0.isVisible && !$0.isMiniaturized })
            
        if let win = targetWin {
            persistWindowSize(from: win)
            targetWindowForNewTab = win
            pendingTabTargetWindow = win
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
        openWindowAction?(finalPayload)
    }
    
    var savedWindowSize: CGSize {
        let width = UserDefaults.standard.double(forKey: Self.savedWindowWidthKey)
        let height = UserDefaults.standard.double(forKey: Self.savedWindowHeightKey)
        let resolvedWidth = width >= Self.minWindowWidth ? width : Self.minWindowWidth
        let resolvedHeight = height >= Self.minWindowHeight ? height : Self.minWindowHeight
        return CGSize(width: resolvedWidth, height: resolvedHeight)
    }
    
    func persistWindowSize(from window: NSWindow) {
        guard !window.isMiniaturized,
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
    
    func installCloseButtonHookIfNeeded(on window: NSWindow) {
        guard !closeHookedWindows.contains(window) else { return }
        closeHookedWindows.add(window)
        if let closeButton = window.standardWindowButton(.closeButton) {
            closeButton.target = self
            closeButton.action = #selector(handleTrafficLightCloseButton(_:))
        }
    }
    
    @objc private func handleTrafficLightCloseButton(_ sender: NSButton) {
        guard let clickedWindow = sender.window else { return }
        let currentEventType = NSApp.currentEvent?.type
        let isMouseEvent = (currentEventType == .leftMouseUp || currentEventType == .leftMouseDown)
        let isOptionPressed = NSEvent.modifierFlags.contains(.option)
        
        if isMouseEvent && isOptionPressed {
            closeAllTabsAndMainWindow(startingFrom: clickedWindow)
        } else if let tg = clickedWindow.tabGroup, tg.windows.count > 1 {
            closeTab(clickedWindow)
        } else {
            closeAllTabsAndMainWindow(startingFrom: clickedWindow)
        }
    }
    
    func closeTab(_ windowToClose: NSWindow) {
        #if DEBUG
        print("[CapsuleClose] closeTab called for window '\(windowToClose.title)' (isMainWindow: \(windowToClose === mainWindow))")
        #endif
        persistWindowSize(from: windowToClose)
        if windowToClose === mainWindow {
            if let dismissAction = mainWindowContentDismissAction {
                dismissAction()
                return
            }
            if let tabGroup = windowToClose.tabGroup, tabGroup.windows.count > 1 {
                windowToClose.delegate = nil
                windowToClose.close()
                return
            }
            windowToClose.delegate = nil
            windowToClose.close()
        } else {
            windowToClose.delegate = nil
            windowToClose.close()
        }
    }
    
    func closeActiveTab() {
        guard let keyWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? mainWindow else { return }
        let targetTab = keyWindow.tabGroup?.selectedWindow ?? keyWindow
        closeTab(targetTab)
    }
    
    func closeActiveWindow() {
        guard let keyWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? mainWindow else { return }
        closeAllTabsAndMainWindow(startingFrom: keyWindow)
    }
    
    func closeAllTabsAndMainWindow(startingFrom window: NSWindow) {
        guard !isClosingAllTabs else { return }
        isClosingAllTabs = true
        defer { isClosingAllTabs = false }
        
        persistWindowSize(from: window)
        
        let tabsToClose = window.tabGroup?.windows ?? [window]
        #if DEBUG
        print("[CapsuleClose] Closing all tabs and main window (\(tabsToClose.count) window(s))")
        #endif
        for tabWin in tabsToClose where tabWin !== window && tabWin !== mainWindow {
            tabWin.delegate = nil
            tabWin.close()
        }
        if let main = mainWindow, main !== window {
            mainWindow = nil
            NotificationCenter.default.post(name: Self.mainWindowDidCloseNotification, object: main)
            main.delegate = nil
            main.close()
        }
        if window === mainWindow {
            mainWindow = nil
            NotificationCenter.default.post(name: Self.mainWindowDidCloseNotification, object: window)
        }
        window.delegate = nil
        window.close()
    }
    
    func focusMainWindow() {
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
        if !flag {
            isReopeningFromDock = true
            // Close any hidden/lingering secondary capsule windows so reopening starts with only the main window
            for win in NSApp.windows where !(win is NSPanel) && win !== mainWindow {
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
        persistWindowSize(from: closingWindow)
        if closingWindow === mainWindow {
            mainWindow = nil
            NotificationCenter.default.post(name: Self.mainWindowDidCloseNotification, object: closingWindow)
        }
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

struct CapsuleWindowHostView: View {
    let payload: CapsuleWindowPayload
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @State private var cachedAppItem: WebAppItem?
    @State private var currentDomainTitle: String = ""
    @State private var hostingWindow: NSWindow?
    @State private var hasConfiguredWindow = false
    @State private var isWindowClosed = false
    @State private var windowCloseObserver: NSObjectProtocol?
    
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
                    if currentDomainTitle.isEmpty {
                        currentDomainTitle = initialDomainTitle
                    }
                    if cachedAppItem == nil {
                        cachedAppItem = lookupAppItem()
                    }
                    MainWindowTracker.shared.openWindowAction = { payload in
                        openWindow(id: "capsuleWindow", value: payload)
                    }
                    MainWindowTracker.shared.openMainWindowAction = {
                        openWindow(id: "mainWindow")
                    }
                }
                .onDisappear {
                    if let obs = windowCloseObserver {
                        NotificationCenter.default.removeObserver(obs)
                        windowCloseObserver = nil
                    }
                }
            }
        }
        .background(
            WindowAccessor(
                onWindowSync: { window in
                    if payload.openAsTab {
                        window.animationBehavior = .none
                        window.tabbingMode = .preferred
                        window.tabbingIdentifier = "CapsuleBrowserWindow"
                        
                        let titleToSet = currentDomainTitle.isEmpty ? initialDomainTitle : currentDomainTitle
                        window.title = titleToSet
                        window.tab.title = titleToSet
                        
                        let sourceWindowFromPayload = payload.sourceWindowNumber.flatMap { NSApp.window(withWindowNumber: $0) }
                        let keyWindow = NSApp.keyWindow
                        let targetWindow: NSWindow? = sourceWindowFromPayload
                            ?? MainWindowTracker.shared.targetWindowForNewTab
                            ?? (keyWindow !== window && !(keyWindow is NSPanel) && !(keyWindow?.isMiniaturized ?? true) ? keyWindow : nil)
                            ?? (MainWindowTracker.shared.mainWindow !== window ? MainWindowTracker.shared.mainWindow : nil)
                            ?? NSApp.windows.first(where: {
                                $0 !== window && $0.isVisible && !$0.isMiniaturized && !($0 is NSPanel) && $0.tabbingIdentifier == "CapsuleBrowserWindow"
                            }) ?? NSApp.windows.first(where: {
                                $0 !== window && $0.isVisible && !$0.isMiniaturized && !($0 is NSPanel)
                            })
                        
                        let targetFrame = payload.sourceFrameRect
                            ?? targetWindow?.frame
                            ?? (window.tabGroup?.windows.first(where: { $0 !== window })?.frame)
                            ?? MainWindowTracker.shared.savedWindowSizeRect(for: window)
                        
                        if let target = targetWindow, target !== window, window.tabGroup !== target.tabGroup {
                            window.setFrame(targetFrame, display: false)
                            target.setFrame(targetFrame, display: false)
                            target.addTabbedWindow(window, ordered: .above)
                            if let tg = target.tabGroup {
                                for w in tg.windows {
                                    if w.frame != targetFrame {
                                        w.setFrame(targetFrame, display: false)
                                    }
                                }
                                tg.selectedWindow = window
                            }
                        }
                    } else {
                        if let sourceRect = payload.sourceFrameRect {
                            var frame = window.frame
                            frame.size = sourceRect.size
                            window.setFrame(frame, display: false)
                        }
                    }
                },
                onWindow: { window in
                    if hostingWindow !== window {
                        hostingWindow = window
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
                    windowCloseObserver = NotificationCenter.default.addObserver(
                        forName: NSWindow.willCloseNotification,
                        object: window,
                        queue: .main
                    ) { _ in
                        #if DEBUG
                        print("[CapsuleClose] CapsuleWindowHostView closing window/tab for '\(appName)'")
                        #endif
                        if let obs = windowCloseObserver {
                            NotificationCenter.default.removeObserver(obs)
                            windowCloseObserver = nil
                        }
                        hostingWindow = nil
                        isWindowClosed = true
                    }
                    
                    if payload.openAsTab {
                        window.tabbingMode = .preferred
                        window.tabbingIdentifier = "CapsuleBrowserWindow"
                        window.delegate = MainWindowTracker.shared
                        
                        let sourceWindowFromPayload = payload.sourceWindowNumber.flatMap { NSApp.window(withWindowNumber: $0) }
                        let keyWindow = NSApp.keyWindow
                        let targetWindow: NSWindow? = sourceWindowFromPayload
                            ?? (keyWindow !== window && !(keyWindow is NSPanel) && !(keyWindow?.isMiniaturized ?? true) ? keyWindow : nil)
                            ?? (MainWindowTracker.shared.mainWindow !== window ? MainWindowTracker.shared.mainWindow : nil)
                            ?? NSApp.windows.first(where: {
                                $0 !== window && $0.isVisible && !$0.isMiniaturized && !($0 is NSPanel) && $0.tabbingIdentifier == "CapsuleBrowserWindow"
                            }) ?? NSApp.windows.first(where: {
                                $0 !== window && $0.isVisible && !$0.isMiniaturized && !($0 is NSPanel)
                            })
                        
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
                            window.setFrame(targetFrame, display: false)
                            target.setFrame(targetFrame, display: false)
                            target.addTabbedWindow(window, ordered: .above)
                            if let tg = target.tabGroup {
                                for w in tg.windows {
                                    if w.frame != targetFrame {
                                        w.setFrame(targetFrame, display: false)
                                    }
                                }
                                tg.selectedWindow = window
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
