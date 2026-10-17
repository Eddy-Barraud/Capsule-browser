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

@main
struct isowebappsApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    #endif

    @StateObject private var cloudSyncManager = CloudSyncManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(cloudSyncManager.containerRefreshID)
                .environmentObject(cloudSyncManager)
                .iCloudSyncConflictAlert(syncManager: cloudSyncManager)
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 800, height: 600)
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
        .defaultSize(width: 800, height: 600)
        .modelContainer(cloudSyncManager.activeContainer)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    openWindow(id: "capsuleWindow", value: CapsuleWindowPayload.defaultNewTabPayload)
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
        }
        #endif
    }
}
