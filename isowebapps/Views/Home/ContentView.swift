//
//  ContentView.swift
//  isowebapps
//
//  Created by Eddy Barraud on 23/08/2026.
//
//  Description:
//  The Home Screen view of the application. Displays the grid of pinned capsules and groups,
//  hosts quick search, incoming URL routing, and settings/creation sheets.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var cloudSyncManager: CloudSyncManager
    @Query(sort: [SortDescriptor(\WebAppItem.displayOrder, order: .forward), SortDescriptor(\WebAppItem.createdAt, order: .forward)]) var webApps: [WebAppItem]
    @Query(sort: [SortDescriptor(\WebAppGroup.displayOrder, order: .forward), SortDescriptor(\WebAppGroup.createdAt, order: .forward)]) var webAppGroups: [WebAppGroup]
    
    @State var draggingItem: HomeGridItem?
    @State var selectedWebApp: WebAppItem?
    @State var isShowingOpenURLSheet = false
    @State var pendingOpenURL: String? = nil
    @State var isShowingAddSheet = false
    @State var isShowingAddGroupSheet = false
    @State var itemToClearData: WebAppItem?
    @State var isShowingClearConfirmation = false
    @State var itemToDelete: WebAppItem?
    @State var isShowingDeleteConfirmation = false
    @State var groupToDelete: WebAppGroup?
    @State var isShowingDeleteGroupConfirmation = false
    @State var groupToEdit: WebAppGroup?
    @State var isInitializing = true
    @State var isReordering = false
    
    @AppStorage(SearchEngine.storageKey) var defaultSearchEngine: SearchEngine = .duckDuckGo
    @AppStorage(SearchEngine.customURLStorageKey) var customSearchEngineURL: String = ""
    #if os(macOS)
    @AppStorage("windowPresentationMode") var windowPresentationMode: WindowPresentationMode = .singleWindow
    @Environment(\.openWindow) var openWindow
    @State var hostingWindowBox = WeakWindowBox()
    @State var hasConfiguredMainWindow = false
    var hostingWindow: NSWindow? { hostingWindowBox.window }
    #endif
    @State var activeDomainTitle: String = ""
    #if DEBUG
    @State var lastLoggedContainerSize: CGSize = .zero
    #endif
    
    #if os(iOS)
    let columns = [
        GridItem(.flexible(), spacing: 20, alignment: .top)
    ]
    #else
    let columns = [
        GridItem(.adaptive(minimum: 360), spacing: 24, alignment: .top)
    ]
    #endif
    
    var body: some View {
        Group {
            if let activeApp = selectedWebApp {
                #if os(macOS)
                let isSecondary = (hostingWindow != nil && MainWindowTracker.shared.mainWindow != nil && hostingWindow !== MainWindowTracker.shared.mainWindow)
                #else
                let isSecondary = false
                #endif
                
                WebAppContainerView(
                    appItem: activeApp,
                    isSecondaryWindow: isSecondary,
                    onActiveDomainChange: { newDomain in
                        activeDomainTitle = newDomain
                        #if os(macOS)
                        hostingWindow?.title = newDomain
                        hostingWindow?.tab.title = newDomain
                        #endif
                    },
                    onDismiss: {
                        #if os(macOS)
                        if isSecondary {
                            MainWindowTracker.shared.focusMainWindow()
                            return
                        }
                        #endif
                        dismissSelectedWebApp()
                    }
                )
                .id(activeApp.id)
                .navigationTitle(activeDomainTitle.isEmpty ? (WebAppNamingHelper.domainName(from: activeApp.urlString) ?? activeApp.name) : activeDomainTitle)
                .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
            } else {
                homeScreenView
                    .navigationTitle("Capsule Browser")
                    .transition(.opacity)
            }
        }
        .task {
            await UBlockOriginExtensionManager.shared.prepare()
        }
        .onAppear {
            if !UBlockOriginExtensionManager.shared.isLoaded {
                Task {
                    await UBlockOriginExtensionManager.shared.prepare()
                }
            }
            _ = CloudSyncManager.shared.deduplicateStore(in: modelContext)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation {
                    isInitializing = false
                }
            }
            #if os(macOS)
            MainWindowTracker.shared.cancelIdleMemoryPurge()
            MainWindowTracker.shared.openWindowAction = { payload in
                openWindow(id: "capsuleWindow", value: payload)
            }
            MainWindowTracker.shared.openMainWindowAction = {
                openWindow(id: "mainWindow")
            }
            if MainWindowTracker.shared.mainWindowContentDismissAction == nil {
                MainWindowTracker.shared.mainWindowContentDismissAction = selectedWebApp != nil ? {
                    dismissSelectedWebApp()
                } : nil
            }
            #endif
        }
        .onChange(of: draggingItem) { _, newValue in
            if newValue == nil && modelContext.hasChanges {
                try? modelContext.save()
            }
        }
        .onChange(of: webAppGroups.count) { _, _ in
            let uniqueGroupIDs = Set(webAppGroups.map(\.id))
            if webAppGroups.count > uniqueGroupIDs.count {
                _ = CloudSyncManager.shared.deduplicateStore(in: modelContext)
            }
            #if DEBUG
            if lastLoggedContainerSize != .zero {
                logHomeLayoutMetrics(containerSize: lastLoggedContainerSize, reason: "webAppGroups.count changed")
            }
            #endif
        }
        .onChange(of: webApps.count) { _, _ in
            let uniqueTotal = Set(webApps.map(\.id)).count
            if webApps.count > uniqueTotal {
                _ = CloudSyncManager.shared.deduplicateStore(in: modelContext)
            }
            if selectedWebApp != nil {
                reconcileSelectedWebAppAfterSync()
            }
            #if DEBUG
            if lastLoggedContainerSize != .zero {
                logHomeLayoutMetrics(containerSize: lastLoggedContainerSize, reason: "webApps.count changed")
            }
            #endif
        }
        .onChange(of: cloudSyncManager.lastKnownStoreSignature) { _, _ in
            if selectedWebApp != nil {
                reconcileSelectedWebAppAfterSync()
            }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: MainWindowTracker.mainWindowDidCloseNotification)) { notification in
            let closedWindow = notification.object as? NSWindow
            if closedWindow == nil || closedWindow === hostingWindow || hostingWindow === MainWindowTracker.shared.mainWindow {
                selectedWebApp = nil
                activeDomainTitle = ""
                hostingWindow?.title = "Capsule Browser"
                hostingWindow?.tab.title = "Capsule Browser"
            }
            if let closedWindow, closedWindow === hostingWindow {
                hostingWindowBox.window = nil
                hasConfiguredMainWindow = false
            }
        }
        .onChange(of: selectedWebApp) { _, newApp in
            if newApp == nil {
                MainWindowTracker.shared.mainWindowContentDismissAction = nil
            } else if MainWindowTracker.shared.mainWindowContentDismissAction == nil {
                MainWindowTracker.shared.mainWindowContentDismissAction = {
                    dismissSelectedWebApp()
                }
            }
        }
        .onChange(of: windowPresentationMode) { _, newMode in
            MainWindowTracker.shared.mainWindow?.tabbingMode = (newMode == .tabs) ? .preferred : .disallowed
        }
        #else
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            Task {
                await WebKitMemoryManager.shared.purgeIdleResources(teardownAllWebViews: false)
            }
        }
        #endif
        .sheet(isPresented: $isShowingAddSheet) {
            AddWebAppSheet()
        }
        .sheet(isPresented: $isShowingAddGroupSheet) {
            AddGroupSheet()
        }
        .sheet(item: $groupToEdit) { group in
            GroupSettingsSheet(group: group)
        }
        .sheet(isPresented: $cloudSyncManager.isSettingsSheetPresented) {
            GeneralSettingsView()
        }
        .sheet(isPresented: $isShowingOpenURLSheet) {
            if let targetURLString = pendingOpenURL {
                OpenURLSheet(
                    targetURLString: targetURLString,
                    webApps: webApps,
                    onSelectApp: { app in
                        app.lastOpenedURLString = targetURLString
                        try? modelContext.save()
                        isShowingOpenURLSheet = false
                        pendingOpenURL = nil
                        openCapsule(app, clearLastOpenedURL: false)
                    },
                    onSelectEphemeral: {
                        isShowingOpenURLSheet = false
                        pendingOpenURL = nil
                        let resolvedHost = URL(string: targetURLString)?.host
                        let capsuleName = (resolvedHost != nil && !resolvedHost!.isEmpty) ? resolvedHost! : "Web Capsule"
                        openEphemeralCapsule(name: capsuleName, urlString: targetURLString)
                    },
                    onCancel: {
                        isShowingOpenURLSheet = false
                        pendingOpenURL = nil
                    }
                )
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .confirmationDialog(
            "Clear Data for \(itemToClearData?.name ?? "Capsule")?",
            isPresented: $isShowingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Cookies & Storage", role: .destructive) {
                if let item = itemToClearData {
                    clearAppData(item)
                    itemToClearData = nil
                }
            }
            Button("Cancel", role: .cancel) {
                itemToClearData = nil
            }
        } message: {
            Text("This will permanently remove all cached files, cookies, and local storage isolated for this capsule.")
        }
        .confirmationDialog(
            "Delete \(itemToDelete?.name ?? "Capsule")?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Capsule", role: .destructive) {
                if let item = itemToDelete {
                    deleteApp(item)
                    itemToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this capsule? This action will remove it from all synced devices.")
        }
        .confirmationDialog(
            "Delete \(groupToDelete?.name ?? "Group")?",
            isPresented: $isShowingDeleteGroupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Ungroup Capsules", role: .destructive) {
                if let group = groupToDelete {
                    deleteGroup(group)
                    groupToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                groupToDelete = nil
            }
        } message: {
            Text("The group will be removed, but the capsules inside it will be kept.")
        }
    }
}

extension View {
    @ViewBuilder
    func reorderable(
        item: HomeGridItem,
        items: [HomeGridItem],
        isEnabled: Bool,
        draggingItem: Binding<HomeGridItem?>,
        modelContext: ModelContext
    ) -> some View {
        if isEnabled {
            self
                .onDrag {
                    draggingItem.wrappedValue = item
                    return NSItemProvider(object: item.id as NSString)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: HomeItemDropDelegate(
                        item: item,
                        items: items,
                        draggingItem: draggingItem,
                        modelContext: modelContext
                    )
                )
        } else {
            self
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(CloudSyncManager.shared)
        .modelContainer(for: WebAppItem.self, inMemory: true)
}
