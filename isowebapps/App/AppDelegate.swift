//
//  AppDelegate.swift
//  isowebapps
//
//  Description:
//  macOS NSApplicationDelegate handling window tabbing setup, swizzling,
//  remote notifications, active CloudKit refresh, and Dock reopen behavior.
//

#if os(macOS)
import AppKit

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
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let memoryManager = WebKitMemoryManager.shared
        let cookieManager = IsolatedCookieManager.shared
        let needsAsyncCleanup = memoryManager.liveWebViewCount > 0
            || cookieManager.hasPendingOperations
            || memoryManager.hasOpenDeleteOnCloseCapsules
        
        guard needsAsyncCleanup else {
            return .terminateNow
        }
        
        MainWindowTracker.shared.cancelIdleMemoryPurge()
        var hasReplied = false
        let finishTermination: @MainActor () -> Void = {
            guard !hasReplied else { return }
            hasReplied = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        
        Task { @MainActor in
            await memoryManager.prepareForApplicationTermination(
                modelContainer: CloudSyncManager.shared.activeContainer
            )
            finishTermination()
        }
        
        // Safety deadline so app termination never hangs indefinitely on XPC/WebKit callbacks.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            finishTermination()
        }
        return .terminateLater
    }
}
#endif
