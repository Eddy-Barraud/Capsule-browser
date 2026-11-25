//
//  CapsuleWindowHostView.swift
//  isowebapps
//
//  Description:
//  SwiftUI host view for secondary macOS capsule windows/tabs, plus AppKit
//  `WindowAccessor` and `CapsuleWindowCloseObserver` helpers.
//

#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import Combine

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
        notifyIfNeeded(view)
        return view
    }
    
    func updateNSView(_ nsView: WindowAccessorView, context: Context) {
        nsView.onWindowSync = onWindowSync
        nsView.onWindow = onWindow
        notifyIfNeeded(nsView)
    }
    
    private func notifyIfNeeded(_ view: WindowAccessorView) {
        if let window = view.window, window !== view.lastNotifiedWindow {
            view.lastNotifiedWindow = window
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
        cachedAppItem ?? lookupAppItem()
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
                            for w in tg.windows where w.frame != targetFrame {
                                w.setFrame(targetFrame, display: false)
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
