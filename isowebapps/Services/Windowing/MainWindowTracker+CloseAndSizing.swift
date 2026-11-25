//
//  MainWindowTracker+CloseAndSizing.swift
//  isowebapps
//
//  Description:
//  Window sizing persistence, traffic-light close policy routing, multi-tab
//  teardown, Dock reopen cleanup, and `NSWindowDelegate` callbacks for `MainWindowTracker`.
//

#if os(macOS)
import Foundation
import AppKit

extension MainWindowTracker {
    // MARK: - Window Sizing
    
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
    
    // MARK: - Close Routing & Focus
    
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
        if let window = mainWindow, (window.isVisible || window.isMiniaturized) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            if let tabGroup = window.tabGroup, tabGroup.windows.count > 1 {
                if tabGroup.selectedWindow !== window {
                    tabGroup.selectedWindow = window
                }
            }
            window.makeKeyAndOrderFront(nil)
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
        true
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
#endif
