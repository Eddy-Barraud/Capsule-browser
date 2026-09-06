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
    @AppStorage("hasSeededDefaults") private var hasSeededDefaults = false
    
    @State private var isSeedingDefaults = false
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
    @State private var isInitializing = true
    
    #if os(iOS)
    let columns = [
        GridItem(.flexible(), spacing: 20, alignment: .top)
    ]
    #else
    let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 350), spacing: 20, alignment: .top)
    ]
    #endif
    
    var body: some View {
        Group {
            if let activeApp = selectedWebApp {
                // Active Isolated Web App Container View
                WebAppContainerView(
                    appItem: activeApp,
                    onDismiss: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedWebApp = nil
                        }
                    }
                )
                .id(activeApp.id)
                .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
            } else {
                // Home Screen Grid
                homeScreenView
                    .transition(.opacity)
            }
        }
        .task {
            await UBlockOriginExtensionManager.shared.prepare()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation {
                    isInitializing = false
                }
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            AddWebAppSheet()
        }
        .sheet(isPresented: $isShowingAddGroupSheet) {
            AddGroupSheet()
        }
        .sheet(isPresented: $isShowingUBlockSettings) {
            UBlockSettingsView()
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
                        
                        if selectedWebApp != nil {
                            selectedWebApp = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    selectedWebApp = app
                                }
                            }
                        } else {
                            withAnimation {
                                selectedWebApp = app
                            }
                        }
                    },
                    onSelectEphemeral: {
                        guard let host = URL(string: targetURLString)?.host else { return }
                        let ephemeralApp = WebAppItem(name: host, urlString: targetURLString)
                        isShowingOpenURLSheet = false
                        pendingOpenURL = nil
                        
                        if selectedWebApp != nil {
                            selectedWebApp = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    selectedWebApp = ephemeralApp
                                }
                            }
                        } else {
                            withAnimation {
                                selectedWebApp = ephemeralApp
                            }
                        }
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
            "Clear Data for \(itemToClearData?.name ?? "Web App")?",
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
            Text("This will permanently remove all cached files, cookies, and local storage isolated for this app.")
        }
        .confirmationDialog(
            "Delete \(itemToDelete?.name ?? "Web App")?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete App", role: .destructive) {
                if let item = itemToDelete {
                    deleteApp(item)
                    itemToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this web app? This action will remove it from all synced devices.")
        }
        .confirmationDialog(
            "Delete \(groupToDelete?.name ?? "Group")?",
            isPresented: $isShowingDeleteGroupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Ungroup Apps", role: .destructive) {
                if let group = groupToDelete {
                    deleteGroup(group)
                    groupToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                groupToDelete = nil
            }
        } message: {
            Text("The group will be removed, but the apps inside it will be kept.")
        }
    }
    
    private var allHomeItems: [HomeGridItem] {
        let apps = webApps.filter { $0.group == nil }.map { HomeGridItem.app($0) }
        let groups = webAppGroups.map { HomeGridItem.group($0) }
        return (apps + groups).sorted { $0.displayOrder < $1.displayOrder }
    }
    
    // Liquid Glass Home Screen
    private var homeScreenView: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                    if isInitializing && webApps.isEmpty && webAppGroups.isEmpty {
                        VStack(spacing: 24) {
                            Spacer(minLength: 120)
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Loading your apps...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else if webApps.isEmpty && webAppGroups.isEmpty {
                        if !hasSeededDefaults {
                            VStack(spacing: 24) {
                                Spacer(minLength: 60)
                                
                                if isSeedingDefaults {
                                    ProgressView("Downloading Icons & Preparing Apps...")
                                        .padding()
                                } else {
                                    VStack(spacing: 16) {
                                        Image(systemName: "sparkles.rectangle.stack.fill")
                                            .font(.system(size: 56))
                                            .foregroundStyle(.purple.gradient)
                                            .padding(24)
                                            .liquidGlassCard(cornerRadius: 28)
                                        
                                        Text("Welcome to Capsule Browser")
                                            .font(.title2.bold())
                                        
                                        Text("Would you like to start with a blank slate, or try our default list of apps?\n(YouTube, Google News, DuckDuckGo, Reddit, Instagram, Gemini)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 36)
                                        
                                        HStack(spacing: 16) {
                                            Button("Start Empty") {
                                                startEmpty()
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.large)
                                            
                                            Button("Load Defaults") {
                                                loadDefaultApps()
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.large)
                                        }
                                        .padding(.top, 16)
                                    }
                                }
                                
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            emptyStateView
                        }
                    } else {
                        AdaptiveMasonryLayout(minColumnWidth: 300, spacing: 24) {
                            ForEach(allHomeItems) { item in
                                switch item {
                                case .group(let group):
                                    WebAppGroupTileView(
                                        group: group,
                                        onStartApp: { app in
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                app.lastOpenedURLString = nil
                                                try? modelContext.save()
                                                selectedWebApp = app
                                            }
                                        },
                                        onResumeApp: { app in
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                selectedWebApp = app
                                            }
                                        },
                                        onClearDataApp: { app in
                                            itemToClearData = app
                                            isShowingClearConfirmation = true
                                        },
                                        onDeleteApp: { app in
                                            itemToDelete = app
                                            isShowingDeleteConfirmation = true
                                        },
                                        onDeleteGroup: {
                                            groupToDelete = group
                                            isShowingDeleteGroupConfirmation = true
                                        }
                                    )
                                    .onDrag {
                                        self.draggingItem = item
                                        return NSItemProvider(object: item.id as NSString)
                                    }
                                    .onDrop(of: [.plainText], delegate: HomeItemDropDelegate(item: item, items: allHomeItems, draggingItem: $draggingItem, modelContext: modelContext))
                                    
                                case .app(let app):
                                    WebAppTileView(
                                        app: app,
                                        onStart: {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                app.lastOpenedURLString = nil
                                                try? modelContext.save()
                                                selectedWebApp = app
                                            }
                                        },
                                        onResume: {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                selectedWebApp = app
                                            }
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
                                    .onDrag {
                                        self.draggingItem = item
                                        return NSItemProvider(object: item.id as NSString)
                                    } 
                                    .onDrop(of: [.plainText], delegate: HomeItemDropDelegate(item: item, items: allHomeItems, draggingItem: $draggingItem, modelContext: modelContext))
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
                        prompt: Text("Search DuckDuckGo or enter URL...")
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
                    Button {
                        isShowingUBlockSettings = true
                    } label: {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 15, weight: .semibold))
                            #if os(macOS)
                            .padding(8)
                            .liquidGlassButton(cornerRadius: 12)
                            #endif
                    }
                    .buttonStyle(.plain)
                    .help("uBlock Origin Lite Settings")
                    
                    Menu {
                        Button {
                            isShowingAddSheet = true
                        } label: {
                            Label("Add New App", systemImage: "plus.app")
                        }
                        Button {
                            isShowingAddGroupSheet = true
                        } label: {
                            Label("Create a Group", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            #if os(macOS)
                            .padding(8)
                            .liquidGlassButton(cornerRadius: 12)
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
            
            Text("No Isolated Web Apps Yet")
                .font(.title3.bold())
            
            Text("Add your favorite web applications to run in isolated containers with uBlock Origin ad-blocking.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            
            Button {
                isShowingAddSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Add Web App")
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
            let dataStore = WKWebsiteDataStore.nonPersistent()
            await IsolatedCookieManager.shared.clearData(for: item, dataStore: dataStore, context: modelContext)
        }
    }
    
    private func deleteApp(_ item: WebAppItem) {
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
    }
    
    private func deleteGroup(_ group: WebAppGroup) {
        withAnimation {
            if let items = group.items {
                for app in items {
                    app.group = nil
                }
            }
            modelContext.delete(group)
            try? modelContext.save()
        }
    }
    
    private func startEmpty() {
        withAnimation {
            hasSeededDefaults = true
        }
    }
    
    private func loadDefaultApps() {
        isSeedingDefaults = true
        
        let defaults = [
            ("Google News", "https://news.google.com"),
            ("YouTube", "https://www.youtube.com"),
            ("Reddit", "https://www.reddit.com"),
            ("Instagram", "https://www.instagram.com"),
            ("DuckDuckGo", "https://start.duckduckgo.com"),
            ("Gemini", "https://gemini.google.com")
        ]
        
        Task {
            for app in defaults {
                guard let url = URL(string: app.1) else { continue }
                let iconData = await FaviconFetcher.fetchIcon(for: url)
                await MainActor.run {
                    let use_reader: Bool = (app.1 == "https://news.google.com") ? true : false

                    let newApp = WebAppItem(name: app.0, urlString: app.1, iconData: iconData, openLinksInSafariReaderMode: use_reader)
                    modelContext.insert(newApp)
                }
            }
            await MainActor.run {
                try? modelContext.save()
                withAnimation {
                    hasSeededDefaults = true
                    isSeedingDefaults = false
                }
            }
        }
    }
    
    private func performQuickSearch() {
        let query = quickSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        
        let urlString: String
        if query.lowercased().hasPrefix("http://") || query.lowercased().hasPrefix("https://") {
            urlString = query
        } else if query.contains(".") && !query.contains(" ") {
            urlString = "https://\(query)"
        } else {
            guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
            urlString = "https://duckduckgo.com/?q=\(encodedQuery)"
        }
        
        let ephemeralApp = WebAppItem(name: "Search", urlString: urlString)
        withAnimation {
            selectedWebApp = ephemeralApp
            quickSearchText = ""
        }
    }
}

// Tile View for Each Web App with Liquid Glass Design
struct WebAppTileView: View {
    @Bindable var app: WebAppItem
    let onStart: () -> Void
    let onResume: () -> Void
    let onClearData: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Left Column: App Logo (Clickable for Start)
            Button(action: onStart) {
                ZStack {
                    if let iconData = app.iconData,
                       let platformImage = PlatformImage(data: iconData) {
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
                .liquidGlassCard(cornerRadius: 20)
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
                    
                    Menu {
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
                            Label("Delete Web App", systemImage: "trash.fill")
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
                
                HStack(spacing: 12) {
                    Button(action: onStart) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text("Start")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 44) // iOS accessibility size
                        .liquidGlassButton(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onResume) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.uturn.forward")
                            Text("Resume")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 44) // iOS accessibility size
                        .liquidGlassButton(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 24)
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
                        Text("Recommended Apps")
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
                        Text("Other Apps")
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
            if let iconData = app.iconData,
               let platformImage = PlatformImage(data: iconData) {
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
