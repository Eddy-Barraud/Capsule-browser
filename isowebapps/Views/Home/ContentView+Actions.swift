//
//  ContentView+Actions.swift
//  isowebapps
//
//  Description:
//  Capsule launching, deletion, cookie wiping, deep-link routing, and CloudKit sync
//  reconciliation helpers for `ContentView`.
//

import SwiftUI
import SwiftData
import WebKit

extension ContentView {
    func dismissSelectedWebApp() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedWebApp = nil
            activeDomainTitle = ""
            #if os(macOS)
            hostingWindow?.title = "Capsule Browser"
            hostingWindow?.tab.title = "Capsule Browser"
            #endif
        }
    }
    
    #if DEBUG
    func logHomeLayoutMetrics(containerSize: CGSize, reason: String, includeSnapshotCounts: Bool = true) {
        let horizontalPadding: CGFloat = 40
        let availableWidth = max(0, containerSize.width - horizontalPadding)
        #if os(macOS)
        let minColWidth: CGFloat = 360
        let spacing: CGFloat = 24
        #else
        let minColWidth: CGFloat = availableWidth
        let spacing: CGFloat = 20
        #endif
        let colCount = max(1, Int((availableWidth + spacing) / (minColWidth + spacing)))
        if includeSnapshotCounts {
            let snapshot = computeHomeLayoutSnapshot()
            print("[LayoutDebug] Home Screen (\(reason)): \(Int(containerSize.width))x\(Int(containerSize.height))pt, cols=\(colCount), groups=\(snapshot.uniqueGroups.count), standalone=\(snapshot.standaloneApps.count)")
        } else {
            print("[LayoutDebug] Home Screen (\(reason)): \(Int(containerSize.width))x\(Int(containerSize.height))pt, cols=\(colCount)")
        }
    }
    #endif
    
    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "capsulebrowser",
              url.host?.lowercased() == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItem = components.queryItems?.first(where: { $0.name == "url" }),
              let targetURLString = queryItem.value else {
            return
        }
        
        guard let parsedURL = URL(string: targetURLString),
              let scheme = parsedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return
        }
        
        pendingOpenURL = targetURLString
        isShowingOpenURLSheet = true
    }
    
    func clearAppData(_ item: WebAppItem) {
        IsolatedCookieManager.shared.clearDataInBackground(for: item, context: modelContext)
    }
    
    func deleteApp(_ item: WebAppItem) {
        let itemId = item.id
        let isStandalone = (item.group == nil)
        withAnimation {
            modelContext.delete(item)
            try? modelContext.save()
        }
        if isStandalone {
            Task {
                try? await WKWebsiteDataStore.remove(forIdentifier: itemId)
            }
        }
    }
    
    func deleteGroup(_ group: WebAppGroup) {
        let groupId = group.id
        withAnimation {
            if let items = group.items {
                for app in items {
                    app.group = nil
                }
            }
            modelContext.delete(group)
            try? modelContext.save()
        }
        Task {
            try? await WKWebsiteDataStore.remove(forIdentifier: groupId)
        }
    }
    
    func performQuickSearch(_ rawInput: String) {
        guard let urlString = SearchEngine.resolveInput(rawInput) else { return }
        openEphemeralCapsule(name: "Search", urlString: urlString)
    }
    
    // MARK: - Capsule Launching
    
    func openCapsule(_ app: WebAppItem, clearLastOpenedURL: Bool = false) {
        if clearLastOpenedURL {
            app.lastOpenedURLString = nil
            try? modelContext.save()
        }
        
        #if os(macOS)
        hostingWindow?.makeFirstResponder(nil)
        if windowPresentationMode == .singleWindow {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selectedWebApp = app
            }
            return
        }
        MainWindowTracker.shared.presentCapsuleWindow(
            appId: app.id,
            urlString: app.lastOpenedURLString ?? app.urlString,
            name: app.name,
            preferredSourceWindow: hostingWindow,
            openAsTab: (windowPresentationMode == .tabs),
            openWindowFallback: { payload in
                openWindow(id: "capsuleWindow", value: payload)
            }
        )
        #else
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedWebApp = app
        }
        #endif
    }
    
    func openEphemeralCapsule(name: String, urlString: String) {
        #if os(macOS)
        hostingWindow?.makeFirstResponder(nil)
        if windowPresentationMode == .singleWindow {
            let ephemeralApp = WebAppItem(name: name, urlString: urlString)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selectedWebApp = ephemeralApp
            }
            return
        }
        MainWindowTracker.shared.presentCapsuleWindow(
            appId: nil,
            urlString: urlString,
            name: name,
            preferredSourceWindow: hostingWindow,
            openAsTab: (windowPresentationMode == .tabs),
            openWindowFallback: { payload in
                openWindow(id: "capsuleWindow", value: payload)
            }
        )
        #else
        let ephemeralApp = WebAppItem(name: name, urlString: urlString)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedWebApp = ephemeralApp
        }
        #endif
    }

    func reconcileSelectedWebAppAfterSync() {
        guard let active = selectedWebApp,
              active.modelContext != nil || active.persistentModelID.storeIdentifier != nil,
              !webApps.contains(where: { ObjectIdentifier($0) == ObjectIdentifier(active) }) else {
            return
        }
        let activeName = CloudSyncManager.normalizedName(active.name)
        if let byID = webApps.first(where: { $0.id == active.id }) {
            selectedWebApp = byID
        } else if !activeName.isEmpty,
                  let byName = webApps.first(where: { CloudSyncManager.normalizedName($0.name) == activeName }) {
            selectedWebApp = byName
        } else {
            dismissSelectedWebApp()
        }
    }
}
