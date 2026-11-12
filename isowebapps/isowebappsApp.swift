//
//  isowebappsApp.swift
//  isowebapps
//
//  Created by Eddy Barraud on 23/08/2026.
//
//  Description:
//  The main application entry point for both macOS and iOS platforms.
//  Initializes SwiftData with CloudKit synchronization for `WebAppItem` models,
//  and presents the root `ContentView`.
//

import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

@main
struct isowebappsApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @AppStorage(MainWindowTracker.savedWindowWidthKey) private var savedWindowWidth: Double = Double(MainWindowTracker.minWindowWidth)
    @AppStorage(MainWindowTracker.savedWindowHeightKey) private var savedWindowHeight: Double = Double(MainWindowTracker.minWindowHeight)
    #endif

    @StateObject private var cloudSyncManager = CloudSyncManager.shared

    var body: some Scene {
        WindowGroup(id: "mainWindow") {
            ContentView()
                .id(cloudSyncManager.containerRefreshID)
                .environmentObject(cloudSyncManager)
                .iCloudSyncConflictAlert(syncManager: cloudSyncManager)
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    MainWindowTracker.shared.openWindowAction = { payload in
                        openWindow(id: "capsuleWindow", value: payload)
                    }
                    MainWindowTracker.shared.openMainWindowAction = {
                        openWindow(id: "mainWindow")
                    }
                }
                #elseif os(iOS)
                .onAppear {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                #endif
        }
        #if os(macOS)
        .defaultSize(
            width: max(MainWindowTracker.minWindowWidth, CGFloat(savedWindowWidth)),
            height: max(MainWindowTracker.minWindowHeight, CGFloat(savedWindowHeight))
        )
        #endif
        .modelContainer(cloudSyncManager.activeContainer)
        
        #if os(macOS)
        WindowGroup(id: "capsuleWindow", for: CapsuleWindowPayload.self) { $payload in
            CapsuleWindowHostView(payload: payload ?? .defaultNewTabPayload)
                .id(cloudSyncManager.containerRefreshID)
                .environmentObject(cloudSyncManager)
                .frame(minWidth: 800, minHeight: 600)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .defaultSize(
            width: max(MainWindowTracker.minWindowWidth, CGFloat(savedWindowWidth)),
            height: max(MainWindowTracker.minWindowHeight, CGFloat(savedWindowHeight))
        )
        .modelContainer(cloudSyncManager.activeContainer)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    MainWindowTracker.shared.openNewTab()
                }
                .keyboardShortcut("t", modifiers: .command)
                
                Button("New Window") {
                    let defaultPayload = CapsuleWindowPayload.defaultNewTabPayload
                    let payload = CapsuleWindowPayload(
                        appId: nil,
                        urlString: defaultPayload.urlString,
                        name: defaultPayload.name,
                        isSecondaryWindow: true,
                        openAsTab: false
                    )
                    openWindow(id: "capsuleWindow", value: payload)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            CommandGroup(replacing: .saveItem) {
                Button("Close Tab") {
                    MainWindowTracker.shared.closeActiveTab()
                }
                .keyboardShortcut("w", modifiers: .command)
                
                Button("Close Window") {
                    MainWindowTracker.shared.closeActiveWindow()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            }
        }
        #endif
    }
}
