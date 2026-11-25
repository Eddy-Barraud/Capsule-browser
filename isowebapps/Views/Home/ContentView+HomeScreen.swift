//
//  ContentView+HomeScreen.swift
//  isowebapps
//
//  Description:
//  Home Screen grid, empty state, and layout snapshot computation for `ContentView`.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct HomeScreenLayoutSnapshot {
    let uniqueGroups: [WebAppGroup]
    let itemsByGroupID: [UUID: [WebAppItem]]
    let standaloneApps: [WebAppItem]
}

extension ContentView {
    var isDragDropEnabled: Bool {
        #if os(macOS)
        return true
        #else
        return isReordering
        #endif
    }
    
    /// Computes deduplicated groups, per-group items, and standalone apps in a single linear pass.
    func computeHomeLayoutSnapshot() -> HomeScreenLayoutSnapshot {
        let sortedByRichness = webAppGroups.sorted {
            let count0 = ($0.items ?? []).count
            let count1 = ($1.items ?? []).count
            if count0 != count1 { return count0 > count1 }
            return $0.createdAt < $1.createdAt
        }
        var seenGroupIDs = Set<UUID>()
        var seenGroupNames = Set<String>()
        var keptGroupObjects = Set<ObjectIdentifier>()
        var canonicalGroupIDByNormName: [String: UUID] = [:]
        for group in sortedByRichness {
            let normName = CloudSyncManager.normalizedName(group.name)
            if !seenGroupIDs.contains(group.id) && (normName.isEmpty || !seenGroupNames.contains(normName)) {
                seenGroupIDs.insert(group.id)
                if !normName.isEmpty {
                    seenGroupNames.insert(normName)
                    canonicalGroupIDByNormName[normName] = group.id
                }
                keptGroupObjects.insert(ObjectIdentifier(group))
            }
        }
        let uniqueGroups = webAppGroups.filter { keptGroupObjects.contains(ObjectIdentifier($0)) }
        
        var groupedAppIDs = Set<UUID>()
        var groupedAppNames = Set<String>()
        var bucketsByGroupID: [UUID: [WebAppItem]] = [:]
        var rawStandalone: [WebAppItem] = []
        
        for app in webApps {
            if let g = app.group {
                groupedAppIDs.insert(app.id)
                let normApp = CloudSyncManager.normalizedName(app.name)
                if !normApp.isEmpty { groupedAppNames.insert(normApp) }
                let normGroup = CloudSyncManager.normalizedName(g.name)
                let targetGroupID = seenGroupIDs.contains(g.id) ? g.id : (canonicalGroupIDByNormName[normGroup] ?? g.id)
                bucketsByGroupID[targetGroupID, default: []].append(app)
            } else {
                rawStandalone.append(app)
            }
        }
        
        var itemsByGroupID: [UUID: [WebAppItem]] = [:]
        for (groupID, bucket) in bucketsByGroupID {
            var seenIDs = Set<UUID>()
            var seenNames = Set<String>()
            var deduped: [WebAppItem] = []
            for app in bucket.sorted(by: { $0.displayOrder < $1.displayOrder }) {
                let norm = CloudSyncManager.normalizedName(app.name)
                if !seenIDs.contains(app.id) && (norm.isEmpty || !seenNames.contains(norm)) {
                    seenIDs.insert(app.id)
                    if !norm.isEmpty { seenNames.insert(norm) }
                    deduped.append(app)
                }
            }
            itemsByGroupID[groupID] = deduped
        }
        
        var seenStandaloneIDs = Set<UUID>()
        var seenStandaloneNames = Set<String>()
        var standaloneApps: [WebAppItem] = []
        for app in rawStandalone {
            let norm = CloudSyncManager.normalizedName(app.name)
            guard !groupedAppIDs.contains(app.id),
                  (norm.isEmpty || !groupedAppNames.contains(norm)),
                  !seenStandaloneIDs.contains(app.id),
                  (norm.isEmpty || !seenStandaloneNames.contains(norm)) else {
                continue
            }
            seenStandaloneIDs.insert(app.id)
            if !norm.isEmpty { seenStandaloneNames.insert(norm) }
            standaloneApps.append(app)
        }
        
        return HomeScreenLayoutSnapshot(
            uniqueGroups: uniqueGroups,
            itemsByGroupID: itemsByGroupID,
            standaloneApps: standaloneApps
        )
    }
    
    var homeScreenView: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    let snapshot = computeHomeLayoutSnapshot()
                    let uniqueGroups = snapshot.uniqueGroups
                    let standaloneApps = snapshot.standaloneApps
                    VStack(alignment: .leading, spacing: 24) {
                        if isInitializing && webApps.isEmpty && webAppGroups.isEmpty {
                            VStack(spacing: 24) {
                                Spacer(minLength: 120)
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text("Loading your capsules...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        } else if uniqueGroups.isEmpty && standaloneApps.isEmpty {
                            emptyStateView
                        } else {
                            VStack(alignment: .leading, spacing: 24) {
                                if !uniqueGroups.isEmpty {
                                    let groupItems = uniqueGroups.map { HomeGridItem.group($0) }
                                    LazyVGrid(columns: columns, spacing: 24) {
                                        ForEach(uniqueGroups) { group in
                                            let item = HomeGridItem.group(group)
                                            WebAppGroupTileView(
                                                group: group,
                                                resolvedItems: snapshot.itemsByGroupID[group.id] ?? [],
                                                onStartApp: { app in
                                                    openCapsule(app, clearLastOpenedURL: true)
                                                },
                                                onResumeApp: { app in
                                                    openCapsule(app, clearLastOpenedURL: false)
                                                },
                                                onClearDataApp: { app in
                                                    itemToClearData = app
                                                    isShowingClearConfirmation = true
                                                },
                                                onDeleteApp: { app in
                                                    itemToDelete = app
                                                    isShowingDeleteConfirmation = true
                                                },
                                                onEditGroup: {
                                                    groupToEdit = group
                                                },
                                                onDeleteGroup: {
                                                    groupToDelete = group
                                                    isShowingDeleteGroupConfirmation = true
                                                }
                                            )
                                            .reorderable(
                                                item: item,
                                                items: groupItems,
                                                isEnabled: isDragDropEnabled,
                                                draggingItem: $draggingItem,
                                                modelContext: modelContext
                                            )
                                            #if os(iOS)
                                            .onLongPressGesture {
                                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                                impact.impactOccurred()
                                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                    isReordering = true
                                                }
                                            }
                                            #endif
                                        }
                                    }
                                }
                                
                                if !standaloneApps.isEmpty {
                                    let appItems = standaloneApps.map { HomeGridItem.app($0) }
                                    LazyVGrid(columns: columns, spacing: 24) {
                                        ForEach(standaloneApps) { app in
                                            let item = HomeGridItem.app(app)
                                            WebAppTileView(
                                                app: app,
                                                onStart: {
                                                    openCapsule(app, clearLastOpenedURL: true)
                                                },
                                                onResume: {
                                                    openCapsule(app, clearLastOpenedURL: false)
                                                },
                                                onClearData: {
                                                    itemToClearData = app
                                                    isShowingClearConfirmation = true
                                                },
                                                onDelete: {
                                                    itemToDelete = app
                                                    isShowingDeleteConfirmation = true
                                                }
                                            )
                                            .reorderable(
                                                item: item,
                                                items: appItems,
                                                isEnabled: isDragDropEnabled,
                                                draggingItem: $draggingItem,
                                                modelContext: modelContext
                                            )
                                            #if os(iOS)
                                            .onLongPressGesture {
                                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                                impact.impactOccurred()
                                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                    isReordering = true
                                                }
                                            }
                                            #endif
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                        }
                    }
                    .padding(.bottom, 140)
                }
                #if DEBUG
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                lastLoggedContainerSize = proxy.size
                                logHomeLayoutMetrics(containerSize: proxy.size, reason: "initial appear")
                            }
                            .onChange(of: proxy.size) { _, newSize in
                                if abs(newSize.width - lastLoggedContainerSize.width) >= 1 || abs(newSize.height - lastLoggedContainerSize.height) >= 1 {
                                    lastLoggedContainerSize = newSize
                                    logHomeLayoutMetrics(containerSize: newSize, reason: "window resized", includeSnapshotCounts: false)
                                }
                            }
                    }
                )
                #endif
                .scrollDismissesKeyboard(.interactively)
                .onDrop(of: [.plainText], isTargeted: nil) { _ in
                    self.draggingItem = nil
                    return false
                }
                
                HomeSearchBarView(
                    defaultSearchEngineDisplayName: defaultSearchEngine.displayName,
                    onSubmitInput: { query in
                        performQuickSearch(query)
                    }
                )
            }
            .navigationTitle("Capsule Browser")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    #if os(iOS)
                    if isReordering {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isReordering = false
                            }
                        } label: {
                            Text("Done")
                                .fontWeight(.bold)
                        }
                    }
                    #endif
                    
                    #if os(macOS)
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            windowPresentationMode = windowPresentationMode.next
                            MainWindowTracker.shared.mainWindow?.tabbingMode = (windowPresentationMode == .tabs) ? .preferred : .disallowed
                        }
                    } label: {
                        Image(systemName: windowPresentationMode.iconName)
                            .font(.system(size: 15, weight: .semibold))
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    .help(windowPresentationMode.tooltip)
                    #endif
                    
                    Button {
                        cloudSyncManager.isSettingsSheetPresented = true
                    } label: {
                        Image(systemName: "gearshape.2.fill")
                            .font(.system(size: 15, weight: .semibold))
                            #if os(macOS)
                            .padding(8)
                            #endif
                    }
                    .buttonStyle(.plain)
                    .help("General Settings & Content Blocker")
                    
                    Menu {
                        Button {
                            isShowingAddSheet = true
                        } label: {
                            Label("New Capsule", systemImage: "plus.rectangle.on.rectangle")
                        }
                        Button {
                            isShowingAddGroupSheet = true
                        } label: {
                            Label("Create a Group", systemImage: "folder.badge.plus")
                        }
                        #if os(iOS)
                        Divider()
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isReordering.toggle()
                            }
                        } label: {
                            Label(isReordering ? "Done Reordering" : "Reorder Capsules", systemImage: isReordering ? "checkmark" : "arrow.up.arrow.down")
                        }
                        #endif
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            #if os(macOS)
                            .padding(8)
                            #endif
                    }
                    .buttonStyle(.plain)
                    .help("Add Options")
                }
            }
            .background(
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.12),
                        Color.purple.opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            #if os(macOS)
            .background(
                WindowAccessor(
                    onWindowSync: { window in
                        MainWindowTracker.shared.registerCapsuleWindow(window)
                    },
                    onWindow: { window in
                        MainWindowTracker.shared.registerCapsuleWindow(window)
                        if hostingWindowBox.window !== window {
                            hostingWindowBox.window = window
                        }
                        guard !hasConfiguredMainWindow else {
                            if selectedWebApp == nil {
                                if window.title != "Capsule Browser" {
                                    window.title = "Capsule Browser"
                                }
                                if window.tab.title != "Capsule Browser" {
                                    window.tab.title = "Capsule Browser"
                                }
                            }
                            return
                        }
                        hasConfiguredMainWindow = true
                        let tracker = MainWindowTracker.shared
                        let currentMain = tracker.mainWindow
                        if currentMain == nil || currentMain === window || !(currentMain?.isVisible ?? false) || tracker.isReopeningFromDock {
                            tracker.mainWindow = window
                            tracker.registerCapsuleWindow(window)
                            window.delegate = tracker
                            tracker.applySavedSizeIfNeeded(to: window)
                            tracker.persistWindowSize(from: window)
                        } else if currentMain !== window {
                            window.delegate = nil
                            window.close()
                            return
                        }
                        window.tabbingIdentifier = "CapsuleBrowserWindow"
                        window.tabbingMode = (windowPresentationMode == .tabs) ? .preferred : .disallowed
                        if selectedWebApp == nil {
                            if window.title != "Capsule Browser" {
                                window.title = "Capsule Browser"
                            }
                            if window.tab.title != "Capsule Browser" {
                                window.tab.title = "Capsule Browser"
                            }
                        }
                    }
                )
            )
            #endif
        }
    }
    
    var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 80)
            
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(.blue.gradient)
                .padding(24)
                .liquidGlassCard(cornerRadius: 28)
            
            Text("No Capsules Yet")
                .font(.title3.bold())
            
            Text("Save your favorite websites to browse in isolated capsules with tracker protection and uBlock Origin ad-blocking.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            
            Button {
                isShowingAddSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("New Capsule")
                }
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .liquidGlassButton(cornerRadius: 14)
            .buttonStyle(.plain)
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
