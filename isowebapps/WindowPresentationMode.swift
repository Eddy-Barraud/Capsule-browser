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
}

@MainActor
final class MainWindowTracker {
    static let shared = MainWindowTracker()
    weak var mainWindow: NSWindow?
    
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
}

final class WindowAccessorView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = self.window {
            onWindow?(window)
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    
    func makeNSView(context: Context) -> WindowAccessorView {
        let view = WindowAccessorView()
        view.onWindow = onWindow
        if let window = view.window {
            onWindow(window)
        }
        return view
    }
    
    func updateNSView(_ nsView: WindowAccessorView, context: Context) {
        nsView.onWindow = onWindow
        if let window = nsView.window {
            onWindow(window)
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
                hostingWindow = window
                let titleToSet = currentDomainTitle.isEmpty ? initialDomainTitle : currentDomainTitle
                window.title = titleToSet
                window.tab.title = titleToSet
                guard !hasConfiguredWindow else { return }
                hasConfiguredWindow = true
                
                if payload.openAsTab {
                    window.tabbingMode = .preferred
                    window.tabbingIdentifier = "CapsuleBrowserWindow"
                    
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
                } else {
                    window.tabbingMode = .disallowed
                    window.cascadeTopLeft(from: NSZeroPoint)
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        )
    }
}
#endif
