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
    
    init(
        appId: UUID?,
        urlString: String?,
        name: String?,
        isSecondaryWindow: Bool = true,
        openAsTab: Bool = false,
        instanceId: UUID = UUID()
    ) {
        self.appId = appId
        self.urlString = urlString
        self.name = name
        self.isSecondaryWindow = isSecondaryWindow
        self.openAsTab = openAsTab
        self.instanceId = instanceId
    }
    
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
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowTracker.shared.handleDockReopen(hasVisibleWindows: flag)
        return true
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
    private(set) var isReopeningFromDock: Bool = false
    private(set) var isClosingAllTabs: Bool = false
    private var configuredWindows = NSHashTable<NSWindow>.weakObjects()
    private var closeHookedWindows = NSHashTable<NSWindow>.weakObjects()
    
    private override init() {
        super.init()
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
        closeAllTabsAndMainWindow(startingFrom: clickedWindow)
    }
    
    func closeAllTabsAndMainWindow(startingFrom window: NSWindow) {
        guard !isClosingAllTabs else { return }
        isClosingAllTabs = true
        defer { isClosingAllTabs = false }
        
        persistWindowSize(from: window)
        
        let tabsToClose = window.tabGroup?.windows ?? [window]
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
        guard let window = mainWindow ?? NSApp.windows.first(where: {
            !($0 is NSPanel) && $0.isVisible && $0.tabbingIdentifier == "CapsuleBrowserWindow"
        }) ?? NSApp.windows.first(where: { !($0 is NSPanel) }) else { return }
        
        if let tabGroup = window.tabGroup, tabGroup.windows.count > 1 {
            tabGroup.selectedWindow = window
            window.makeKeyAndOrderFront(nil)
        } else {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
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
        persistWindowSize(from: resizedWindow)
    }
    
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let resizedWindow = notification.object as? NSWindow else { return }
        persistWindowSize(from: resizedWindow)
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isClosingAllTabs {
            return true
        }
        if sender === mainWindow {
            closeAllTabsAndMainWindow(startingFrom: sender)
            return false
        }
        return true
    }
    
    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        persistWindowSize(from: closingWindow)
        if closingWindow === mainWindow {
            mainWindow = nil
            NotificationCenter.default.post(name: Self.mainWindowDidCloseNotification, object: closingWindow)
        }
    }
}

final class WindowAccessorView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = self.window {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window = window else { return }
                self?.onWindow?(window)
            }
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    
    func makeNSView(context: Context) -> WindowAccessorView {
        let view = WindowAccessorView()
        view.onWindow = onWindow
        if let window = view.window {
            DispatchQueue.main.async { [weak window] in
                guard let window = window else { return }
                onWindow(window)
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: WindowAccessorView, context: Context) {
        nsView.onWindow = onWindow
        if let window = nsView.window {
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
    @Query private var allApps: [WebAppItem]
    @State private var cachedAppItem: WebAppItem?
    @State private var currentDomainTitle: String = ""
    @State private var hostingWindow: NSWindow?
    @State private var hasConfiguredWindow = false
    
    private var resolvedAppItem: WebAppItem {
        if let cached = cachedAppItem {
            return cached
        }
        if let appId = payload.appId, let found = allApps.first(where: { $0.id == appId }) {
            return found
        }
        return WebAppItem(name: payload.name ?? "Capsule", urlString: payload.urlString ?? "about:blank")
    }
    
    private var initialDomainTitle: String {
        let rawURL = payload.urlString ?? resolvedAppItem.lastOpenedURLString ?? resolvedAppItem.urlString
        return WebAppNamingHelper.domainName(from: rawURL) ?? resolvedAppItem.name
    }
    
    var body: some View {
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
                if let appId = payload.appId, let found = allApps.first(where: { $0.id == appId }) {
                    cachedAppItem = found
                } else {
                    cachedAppItem = WebAppItem(name: payload.name ?? "Capsule", urlString: payload.urlString ?? "about:blank")
                }
            }
        }
        .background(
            WindowAccessor { window in
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
                guard !hasConfiguredWindow else { return }
                hasConfiguredWindow = true
                window.isRestorable = false
                MainWindowTracker.shared.installCloseButtonHookIfNeeded(on: window)
                
                if payload.openAsTab {
                    window.tabbingMode = .preferred
                    window.tabbingIdentifier = "CapsuleBrowserWindow"
                    
                    if let tg = window.tabGroup, tg.windows.count > 1 {
                        tg.selectedWindow = window
                        window.makeKeyAndOrderFront(nil)
                    } else {
                        let keyWindow = NSApp.keyWindow
                        let targetWindow: NSWindow?
                        if let kw = keyWindow, kw !== window, !kw.isMiniaturized, !(kw is NSPanel), kw.tabbingIdentifier == "CapsuleBrowserWindow" {
                            targetWindow = kw
                        } else if let main = MainWindowTracker.shared.mainWindow, main !== window, !main.isMiniaturized, !(main is NSPanel) {
                            targetWindow = main
                        } else {
                            targetWindow = NSApp.windows.first(where: {
                                $0 !== window && $0.isVisible && !$0.isMiniaturized && !($0 is NSPanel) && $0.tabbingIdentifier == "CapsuleBrowserWindow"
                            }) ?? NSApp.windows.first(where: {
                                $0 !== window && $0.isVisible && !$0.isMiniaturized && !($0 is NSPanel)
                            })
                        }
                        
                        if let target = targetWindow {
                            let targetFrame = target.frame
                            window.setFrame(targetFrame, display: false)
                            target.addTabbedWindow(window, ordered: .above)
                            target.tabGroup?.selectedWindow = window
                            window.makeKeyAndOrderFront(nil)
                            DispatchQueue.main.async {
                                target.setFrame(targetFrame, display: true)
                                window.setFrame(targetFrame, display: true)
                                target.tabGroup?.selectedWindow = window
                                window.makeKeyAndOrderFront(nil)
                            }
                        } else {
                            window.makeKeyAndOrderFront(nil)
                        }
                    }
                } else {
                    window.tabbingMode = .disallowed
                    window.delegate = MainWindowTracker.shared
                    MainWindowTracker.shared.applySavedSizeIfNeeded(to: window)
                    window.cascadeTopLeft(from: NSZeroPoint)
                    window.makeKeyAndOrderFront(nil)
                }
                NSApp.activate(ignoringOtherApps: true)
            }
        )
    }
}
#endif
