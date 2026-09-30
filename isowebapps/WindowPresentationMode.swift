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
        
        if let tabGroup = window.tabGroup, let current = NSApp.keyWindow, tabGroup.windows.contains(current) {
            tabGroup.selectedWindow = window
        } else {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindow(window)
            }
        }
    }
}

struct CapsuleWindowHostView: View {
    let payload: CapsuleWindowPayload
    @Environment(\.modelContext) private var modelContext
    @Query private var allApps: [WebAppItem]
    @State private var hasConfiguredWindow = false
    
    private var resolvedAppItem: WebAppItem {
        if let appId = payload.appId, let found = allApps.first(where: { $0.id == appId }) {
            return found
        }
        return WebAppItem(name: payload.name ?? "Capsule", urlString: payload.urlString ?? "about:blank")
    }
    
    var body: some View {
        WebAppContainerView(
            appItem: resolvedAppItem,
            isSecondaryWindow: payload.isSecondaryWindow,
            onDismiss: {
                MainWindowTracker.shared.focusMainWindow()
            }
        )
        .navigationTitle(resolvedAppItem.name)
        .background(
            WindowAccessor { window in
                guard !hasConfiguredWindow else { return }
                hasConfiguredWindow = true
                
                if payload.openAsTab {
                    window.tabbingMode = .preferred
                    window.tabbingIdentifier = "CapsuleBrowserWindow"
                    if let targetWindow = NSApp.windows.first(where: {
                        $0 !== window && $0.isVisible && !$0.isMiniaturized && !($0 is NSPanel)
                    }) {
                        targetWindow.addTabbedWindow(window, ordered: .above)
                    }
                } else {
                    window.tabbingMode = .disallowed
                }
            }
        )
    }
}
#endif
