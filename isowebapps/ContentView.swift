//
//  ContentView.swift
//  isowebapps
//
//  Created by Eddy Barraud on 23/08/2026.
//
//  Description:
//  The Home Screen view of the application. Displays the grid of pinned web applications
//  with high-resolution icons, titles, and context menus for per-app data clearing.
//  Hosts toolbar buttons for adding new web apps and accessing uBlock Origin Lite settings.
//

import SwiftUI
import SwiftData
import WebKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\WebAppItem.displayOrder, order: .forward), SortDescriptor(\WebAppItem.createdAt, order: .forward)]) private var webApps: [WebAppItem]
    @Query(sort: [SortDescriptor(\WebAppGroup.displayOrder, order: .forward), SortDescriptor(\WebAppGroup.createdAt, order: .forward)]) private var webAppGroups: [WebAppGroup]
    
    @State private var draggingItem: HomeGridItem?
    @State private var selectedWebApp: WebAppItem?
    @State private var quickSearchText = ""
    @State private var isShowingOpenURLSheet = false
    @State private var pendingOpenURL: String? = nil
    @FocusState private var isSearchFocused: Bool
    @State private var isShowingAddSheet = false
    @State private var isShowingAddGroupSheet = false
    @State private var isShowingUBlockSettings = false
    @State private var itemToClearData: WebAppItem?
    @State private var isShowingClearConfirmation = false
    @State private var itemToDelete: WebAppItem?
    @State private var isShowingDeleteConfirmation = false
    @State private var groupToDelete: WebAppGroup?
    @State private var isShowingDeleteGroupConfirmation = false
    @State private var groupToEdit: WebAppGroup?
    @State private var isInitializing = true
    @State private var isReordering = false
    
    @AppStorage(SearchEngine.storageKey) private var defaultSearchEngine: SearchEngine = .duckDuckGo
    @AppStorage(SearchEngine.customURLStorageKey) private var customSearchEngineURL: String = ""
    #if os(macOS)
    @AppStorage("windowPresentationMode") private var windowPresentationMode: WindowPresentationMode = .singleWindow
    @Environment(\.openWindow) private var openWindow
    @State private var hostingWindow: NSWindow?
    @State private var hasConfiguredMainWindow = false
    #endif
    @State private var activeDomainTitle: String = ""
    #if DEBUG
    @State private var lastLoggedContainerSize: CGSize = .zero
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
                
                // Active Isolated Web App Container View
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
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedWebApp = nil
                            activeDomainTitle = ""
                            #if os(macOS)
                            hostingWindow?.title = "Capsule Browser"
                            hostingWindow?.tab.title = "Capsule Browser"
                            #endif
                        }
                    }
                )
                .id(activeApp.id)
                .navigationTitle(activeDomainTitle.isEmpty ? (WebAppNamingHelper.domainName(from: activeApp.urlString) ?? activeApp.name) : activeDomainTitle)
                .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
            } else {
                // Home Screen Grid
                homeScreenView
                    .navigationTitle("Capsule Browser")
                    .transition(.opacity)
            }
        }
        .task {
            await UBlockOriginExtensionManager.shared.prepare()
        }
        .onAppear {
            _ = CloudSyncManager.shared.deduplicateStore(in: modelContext)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation {
                    isInitializing = false
                }
            }
        }
        .onChange(of: webAppGroups.count) { _, _ in
            if webAppGroups.count > deduplicatedGroups.count {
                _ = CloudSyncManager.shared.deduplicateStore(in: modelContext)
            }
            #if DEBUG
            if lastLoggedContainerSize != .zero {
                logHomeLayoutMetrics(containerSize: lastLoggedContainerSize, reason: "webAppGroups.count changed")
            }
            #endif
        }
        .onChange(of: webApps.count) { _, _ in
            let uniqueTotal = Set(webApps.map { $0.id }).count
            if webApps.count > uniqueTotal {
                _ = CloudSyncManager.shared.deduplicateStore(in: modelContext)
            }
            #if DEBUG
            if lastLoggedContainerSize != .zero {
                logHomeLayoutMetrics(containerSize: lastLoggedContainerSize, reason: "webApps.count changed")
            }
            #endif
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
        .sheet(isPresented: $isShowingUBlockSettings) {
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
                        guard let host = URL(string: targetURLString)?.host else { return }
                        isShowingOpenURLSheet = false
                        pendingOpenURL = nil
                        openEphemeralCapsule(name: host, urlString: targetURLString)
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
    
    private var isDragDropEnabled: Bool {
        #if os(macOS)
        return true
        #else
        return isReordering
        #endif
    }

    private var deduplicatedGroups: [WebAppGroup] {
        // Prefer keeping the group instance with the most items when duplicate IDs/names exist
        let sortedByRichness = webAppGroups.sorted {
            let count0 = ($0.items ?? []).count
            let count1 = ($1.items ?? []).count
            if count0 != count1 { return count0 > count1 }
            return $0.createdAt < $1.createdAt
        }
        var seenIDs = Set<UUID>()
        var seenNames = Set<String>()
        var keptObjects = Set<ObjectIdentifier>()
        for group in sortedByRichness {
            let normName = group.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !seenIDs.contains(group.id) && (normName.isEmpty || !seenNames.contains(normName)) {
                seenIDs.insert(group.id)
                if !normName.isEmpty { seenNames.insert(normName) }
                keptObjects.insert(ObjectIdentifier(group))
            }
        }
        return webAppGroups.filter { keptObjects.contains(ObjectIdentifier($0)) }
    }
    
    private func deduplicatedItems(for group: WebAppGroup) -> [WebAppItem] {
        let normGroupName = group.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matchingItems = webApps.filter { app in
            guard let g = app.group else { return false }
            if g.id == group.id { return true }
            let gName = g.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !normGroupName.isEmpty && gName == normGroupName
        }
        var seenIDs = Set<UUID>()
        var seenNames = Set<String>()
        var result: [WebAppItem] = []
        for app in matchingItems.sorted(by: { $0.displayOrder < $1.displayOrder }) {
            let normAppName = app.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !seenIDs.contains(app.id) && (normAppName.isEmpty || !seenNames.contains(normAppName)) {
                seenIDs.insert(app.id)
                if !normAppName.isEmpty { seenNames.insert(normAppName) }
                result.append(app)
            }
        }
        return result
    }
    
    private var deduplicatedStandaloneApps: [WebAppItem] {
        var groupedIDs = Set<UUID>()
        var groupedNames = Set<String>()
        for app in webApps where app.group != nil {
            groupedIDs.insert(app.id)
            let norm = app.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !norm.isEmpty { groupedNames.insert(norm) }
        }
        
        var seenIDs = Set<UUID>()
        var seenNames = Set<String>()
        var result: [WebAppItem] = []
        for app in webApps where app.group == nil {
            let norm = app.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !groupedIDs.contains(app.id),
                  (norm.isEmpty || !groupedNames.contains(norm)),
                  !seenIDs.contains(app.id),
                  (norm.isEmpty || !seenNames.contains(norm)) else {
                continue
            }
            seenIDs.insert(app.id)
            if !norm.isEmpty { seenNames.insert(norm) }
            result.append(app)
        }
        return result
    }

    private var allHomeItems: [HomeGridItem] {
        let apps = deduplicatedStandaloneApps.map { HomeGridItem.app($0) }
        let groups = deduplicatedGroups.map { HomeGridItem.group($0) }
        return (apps + groups).sorted { $0.displayOrder < $1.displayOrder }
    }
    
    #if DEBUG
    private func logHomeLayoutMetrics(containerSize: CGSize, reason: String) {
        let horizontalPadding: CGFloat = 40 // .padding(.horizontal, 20) * 2
        let availableWidth = max(0, containerSize.width - horizontalPadding)
        #if os(macOS)
        let minColWidth: CGFloat = 360
        let maxColWidth: CGFloat = .infinity
        let maxColDesc = "infinity"
        let spacing: CGFloat = 24
        #else
        let minColWidth: CGFloat = availableWidth
        let maxColWidth: CGFloat = availableWidth
        let maxColDesc = String(format: "%.0f", maxColWidth)
        let spacing: CGFloat = 20
        #endif
        
        let rawColCount = Int((availableWidth + spacing) / (minColWidth + spacing))
        let colCount = max(1, rawColCount)
        let totalSpacing = CGFloat(colCount - 1) * spacing
        let rawColWidth = (availableWidth - totalSpacing) / CGFloat(colCount)
        let actualColWidth = min(maxColWidth, max(minColWidth, rawColWidth))
        let unusedHorizontalSpace = max(0, availableWidth - (CGFloat(colCount) * actualColWidth + totalSpacing))
        // Inside a group tile: 32pt group padding + 32pt tile padding + 80pt icon + 16pt icon spacing + 10pt button spacing = 170pt
        let buttonWidthInGroup = max(0, (actualColWidth - 170) / 2.0)
        
        let uniqueGroups = deduplicatedGroups
        let uniqueApps = deduplicatedStandaloneApps
        
        let groupIDCounts = Dictionary(grouping: webAppGroups, by: { $0.id }).filter { $0.value.count > 1 }
        let appIDCounts = Dictionary(grouping: webApps, by: { $0.id }).filter { $0.value.count > 1 }
        
        print("""
        ============================================================
        [LayoutDebug] Home Screen Layout (\(reason))
        - Container Size: \(Int(containerSize.width)) x \(Int(containerSize.height)) pt (available grid width: \(Int(availableWidth)) pt)
        - Grid Config: adaptive(min: \(Int(minColWidth)), max: \(maxColDesc)), spacing: \(Int(spacing)) pt
        - Computed Columns: \(colCount) column(s) x \(String(format: "%.1f", actualColWidth)) pt each (unused horizontal space: \(String(format: "%.1f", unusedHorizontalSpace)) pt)
        - Est. Button Width in Group: \(String(format: "%.1f", buttonWidthInGroup)) pt per button (needs ~88 pt to avoid truncation)
        - Groups in @Query: \(webAppGroups.count) raw -> \(uniqueGroups.count) deduplicated (duplicate group UUIDs: \(groupIDCounts.count))
        - Apps in @Query: \(webApps.count) raw -> \(uniqueApps.count) standalone deduplicated (duplicate app UUIDs: \(appIDCounts.count))
        """)
        for (idx, group) in uniqueGroups.enumerated() {
            let row = idx / colCount
            let col = idx % colCount
            let xOffset = 20 + CGFloat(col) * (actualColWidth + spacing)
            let itemsCount = deduplicatedItems(for: group).count
            print("  • Group[\(idx)] '\(group.name)' (id: \(group.id)) -> slot [row \(row), col \(col)], x=\(Int(xOffset))pt, width=\(Int(actualColWidth))pt, items=\(itemsCount)")
        }
        if !uniqueApps.isEmpty {
            print("  • Standalone Capsules (\(uniqueApps.count)): \(uniqueApps.map { $0.name }.joined(separator: ", "))")
        }
        print("============================================================")
    }
    #endif
    
    // Liquid Glass Home Screen
    private var homeScreenView: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    let uniqueGroups = deduplicatedGroups
                    let standaloneApps = deduplicatedStandaloneApps
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
                                            resolvedItems: deduplicatedItems(for: group),
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
                .padding(.bottom, 40)
                .padding(.bottom, 100)
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
                                logHomeLayoutMetrics(containerSize: newSize, reason: "window resized")
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
            
            // Bottom Search Bar
            HStack(spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 20))
                    
                    TextField(
                        "",
                        text: $quickSearchText,
                        prompt: Text("Search \(defaultSearchEngine.displayName) or enter URL...")
                            .foregroundColor(.primary.opacity(0.6))
                    )
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .onSubmit {
                            performQuickSearch()
                            isSearchFocused = false
                        }
                    
                    #if os(macOS)
                    if isSearchFocused || !quickSearchText.isEmpty {
                        HStack(spacing: 8) {
                            Button(action: {
                                quickSearchText = ""
                                isSearchFocused = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 20))
                            }
                            .buttonStyle(.plain)
                            .transition(.scale.combined(with: .opacity))
                            
                            Button(action: {
                                performQuickSearch()
                                isSearchFocused = false
                            }) {
                                Image(systemName: "paperplane.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 20))
                            }
                            .buttonStyle(.plain)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    isSearchFocused = true
                }
                
                #if os(iOS)
                if isSearchFocused || !quickSearchText.isEmpty {
                    Button(action: {
                        performQuickSearch()
                        isSearchFocused = false
                    }) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                            .frame(width: 48, height: 48)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity).combined(with: .move(edge: .trailing)))

                    Button(action: {
                        quickSearchText = ""
                        isSearchFocused = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 48, height: 48)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity).combined(with: .move(edge: .trailing)))
                }
                #endif
            }
            .padding(.horizontal, 20)
            #if os(macOS)
            .padding(.bottom, 20)
            #else
            .padding(.bottom, 4)
            #endif
            #if os(iOS)
            .frame(width: isSearchFocused ? UIScreen.main.bounds.width : UIScreen.main.bounds.width * 0.7)
            #endif
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSearchFocused)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: quickSearchText.isEmpty)
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
                            if windowPresentationMode == .tabs {
                                MainWindowTracker.shared.mainWindow?.tabbingMode = .preferred
                            } else {
                                MainWindowTracker.shared.mainWindow?.tabbingMode = .disallowed
                            }
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
                        isShowingUBlockSettings = true
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
                WindowAccessor { window in
                    if hostingWindow !== window {
                        hostingWindow = window
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
                        window.delegate = tracker
                        tracker.applySavedSizeIfNeeded(to: window)
                    } else if currentMain !== window {
                        // Prevent duplicate main ContentView windows restored or spawned by macOS on reopen
                        window.delegate = nil
                        window.close()
                        return
                    }
                    window.tabbingIdentifier = "CapsuleBrowserWindow"
                    if windowPresentationMode == .tabs {
                        window.tabbingMode = .preferred
                    } else {
                        window.tabbingMode = .disallowed
                    }
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
            #endif
        }
    }
    
    private func handleIncomingURL(_ url: URL) {
        // Expected format: capsulebrowser://open?url=https%3A%2F%2Fwww.youtube.com
        guard url.scheme == "capsulebrowser",
              url.host == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItem = components.queryItems?.first(where: { $0.name == "url" }),
              let targetURLString = queryItem.value else {
            return
        }
        
        pendingOpenURL = targetURLString
        isShowingOpenURLSheet = true
    }
    
    private var emptyStateView: some View {
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
    
    private func clearAppData(_ item: WebAppItem) {
        Task {
            await IsolatedCookieManager.shared.clearData(for: item, context: modelContext)
        }
    }
    
    private func deleteApp(_ item: WebAppItem) {
        let itemId = item.id
        let isStandalone = (item.group == nil)
        withAnimation {
            modelContext.delete(item)
            do {
                try modelContext.save()
            } catch {
                #if DEBUG
                print("[ContentView] Failed to save context after delete: \(error)")
                #endif
            }
        }
        if isStandalone {
            Task {
                try? await WKWebsiteDataStore.remove(forIdentifier: itemId)
            }
        }
    }
    
    private func deleteGroup(_ group: WebAppGroup) {
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
    
    private func performQuickSearch() {
        guard let urlString = SearchEngine.resolveInput(quickSearchText) else { return }
        quickSearchText = ""
        openEphemeralCapsule(name: "Search", urlString: urlString)
    }
    
    // MARK: - Capsule Launching
    
    private func openCapsule(_ app: WebAppItem, clearLastOpenedURL: Bool = false) {
        if clearLastOpenedURL {
            app.lastOpenedURLString = nil
            try? modelContext.save()
        }
        
        #if os(macOS)
        isSearchFocused = false
        hostingWindow?.makeFirstResponder(nil)
        switch windowPresentationMode {
        case .singleWindow:
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selectedWebApp = app
            }
        case .separateWindows:
            let payload = CapsuleWindowPayload(
                appId: app.id,
                urlString: app.lastOpenedURLString ?? app.urlString,
                name: app.name,
                isSecondaryWindow: true,
                openAsTab: false
            )
            openWindow(id: "capsuleWindow", value: payload)
        case .tabs:
            let payload = CapsuleWindowPayload(
                appId: app.id,
                urlString: app.lastOpenedURLString ?? app.urlString,
                name: app.name,
                isSecondaryWindow: true,
                openAsTab: true
            )
            openWindow(id: "capsuleWindow", value: payload)
        }
        #else
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedWebApp = app
        }
        #endif
    }
    
    private func openEphemeralCapsule(name: String, urlString: String) {
        #if os(macOS)
        isSearchFocused = false
        hostingWindow?.makeFirstResponder(nil)
        switch windowPresentationMode {
        case .singleWindow:
            let ephemeralApp = WebAppItem(name: name, urlString: urlString)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selectedWebApp = ephemeralApp
            }
        case .separateWindows:
            let payload = CapsuleWindowPayload(
                appId: nil,
                urlString: urlString,
                name: name,
                isSecondaryWindow: true,
                openAsTab: false
            )
            openWindow(id: "capsuleWindow", value: payload)
        case .tabs:
            let payload = CapsuleWindowPayload(
                appId: nil,
                urlString: urlString,
                name: name,
                isSecondaryWindow: true,
                openAsTab: true
            )
            openWindow(id: "capsuleWindow", value: payload)
        }
        #else
        let ephemeralApp = WebAppItem(name: name, urlString: urlString)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedWebApp = ephemeralApp
        }
        #endif
    }
}

// In-memory cache of decoded PlatformImages keyed by capsule UUID + icon byte count
// so scrolling the Home Screen never decodes PNG/ICO Data on the main thread.
enum IconImageCache {
    private static let cache: NSCache<NSString, PlatformImage> = {
        let c = NSCache<NSString, PlatformImage>()
        c.countLimit = 256
        return c
    }()
    
    static func image(for id: UUID, data: Data?) -> PlatformImage? {
        guard let data = data, !data.isEmpty else { return nil }
        let key = "\(id.uuidString)-\(data.count)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let decoded = PlatformImage(data: data) else { return nil }
        cache.setObject(decoded, forKey: key)
        return decoded
    }
}

// Tile View for Each Web App with Liquid Glass Design
struct WebAppTileView: View {
    @Environment(\.colorScheme) var colorScheme
    let app: WebAppItem
    let onStart: () -> Void
    let onResume: () -> Void
    let onClearData: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Left Column: App Logo (Clickable for Start)
            Button(action: onStart) {
                ZStack {
                    if let platformImage = IconImageCache.image(for: app.id, data: app.iconData) {
                        Image(platformImage: platformImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 34))
                            .foregroundStyle(.primary)
                    }
                }
                .frame(width: 80, height: 80)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            colorScheme == .dark
                            ? Color(white: 0.28).opacity(0.85)
                            : Color.white.opacity(0.95)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.45 : 1.0),
                                    Color.white.opacity(colorScheme == .dark ? 0.1 : 0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.1),
                    radius: 5,
                    x: 0,
                    y: 2.5
                )
            }
            .buttonStyle(.plain)
            
            // Right Column: Title, Gear, and Buttons
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(app.name)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Settings menu in separate subview to isolate @Bindable observation
                    WebAppTileSettingsMenu(
                        app: app,
                        onClearData: onClearData,
                        onDelete: onDelete
                    )
                }
                
                HStack(spacing: 10) {
                    Button(action: onStart) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                            Text("Start")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 44) // iOS accessibility size
                        .liquidGlassButton(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onResume) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.forward")
                            Text("Resume")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 44) // iOS accessibility size
                        .liquidGlassButton(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .liquidGlassCard(cornerRadius: 24)
    }
}

// Extracted Settings Menu to isolate @Bindable observation and avoid re-evaluating the parent tile
struct WebAppTileSettingsMenu: View {
    @AppStorage("ublock_master_enabled") private var ublockMasterEnabled = true
    @Bindable var app: WebAppItem
    let onClearData: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Menu {
            if ublockMasterEnabled {
                Toggle("uBlock Origin protection", isOn: $app.isUBlockEnabled)
                    .onChange(of: app.isUBlockEnabled) { _, newValue in
                        try? app.modelContext?.save()
                        NotificationCenter.default.post(
                            name: UBlockOriginExtensionManager.capsuleUBlockSettingChangedNotification,
                            object: app.id,
                            userInfo: ["isUBlockEnabled": newValue]
                        )
                    }
            }
            Toggle("Open links in Safari Reader", isOn: $app.openLinksInSafariReaderMode)
                .onChange(of: app.openLinksInSafariReaderMode) { _, _ in
                    try? app.modelContext?.save()
                }
            Toggle("Delete cookies on close", isOn: $app.deleteCookiesOnClose)
                .onChange(of: app.deleteCookiesOnClose) { _, _ in
                    try? app.modelContext?.save()
                }
                
            Divider()
            
            Button(action: onClearData) {
                Label("Clear Cookies & Cache...", systemImage: "arrow.clockwise.circle")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete Capsule", systemImage: "trash.fill")
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 30, height: 30) // Ensure large enough tappable area
                .background(Color.primary.opacity(0.1))
                .clipShape(Circle())
        }
        .menuStyle(.borderlessButton)
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
        .modelContainer(for: WebAppItem.self, inMemory: true)
}

struct WebAppDropDelegate: DropDelegate {
    let item: WebAppItem
    let items: [WebAppItem]
    @Binding var draggingItem: WebAppItem?
    var modelContext: ModelContext
    
    func dropEntered(info: DropInfo) {
        guard let draggingItem = draggingItem, draggingItem.id != item.id else { return }
        
        guard let fromIndex = items.firstIndex(where: { $0.id == draggingItem.id }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else { return }
        
        if fromIndex != toIndex {
            withAnimation(.default) {
                var sortedItems = items
                let movedItem = sortedItems.remove(at: fromIndex)
                sortedItems.insert(movedItem, at: toIndex)
                
                for (index, app) in sortedItems.enumerated() {
                    app.displayOrder = index
                }
                
                try? modelContext.save()
            }
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        self.draggingItem = nil
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}


struct OpenURLSheet: View {
    let targetURLString: String
    let webApps: [WebAppItem]
    let onSelectApp: (WebAppItem) -> Void
    let onSelectEphemeral: () -> Void
    let onCancel: () -> Void
    
    var matchingApps: [WebAppItem] {
        guard let host = URL(string: targetURLString)?.host else { return [] }
        return webApps.filter { app in
            guard let existingHost = URL(string: app.urlString)?.host else { return false }
            return existingHost == host || existingHost.hasSuffix("." + host) || host.hasSuffix("." + existingHost)
        }
    }
    
    var otherApps: [WebAppItem] {
        let matched = Set(matchingApps.map { $0.id })
        return webApps.filter { !matched.contains($0.id) }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: onSelectEphemeral) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.purple)
                            Text("Ephemeral Capsule")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("No cookies saved")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Quick Open")
                }
                
                if !matchingApps.isEmpty {
                    Section {
                        ForEach(matchingApps) { app in
                            Button {
                                onSelectApp(app)
                            } label: {
                                appRow(app)
                            }
                        }
                    } header: {
                        Text("Recommended Capsules")
                    }
                }
                
                if !otherApps.isEmpty {
                    Section {
                        ForEach(otherApps) { app in
                            Button {
                                onSelectApp(app)
                            } label: {
                                appRow(app)
                            }
                        }
                    } header: {
                        Text("Other Capsules")
                    }
                }
            }
            .navigationTitle("Open Link")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 500)
        #endif
    }
    
    private func appRow(_ app: WebAppItem) -> some View {
        HStack {
            if let platformImage = IconImageCache.image(for: app.id, data: app.iconData) {
                Image(platformImage: platformImage)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text(String(app.name.prefix(1)).uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.primary)
                    )
            }
            
            Text(app.name)
                .foregroundColor(.primary)
            Spacer()
        }
    }
}
