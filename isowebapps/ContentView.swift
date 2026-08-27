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

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WebAppItem.createdAt, order: .forward) private var webApps: [WebAppItem]
    
    @State private var selectedWebApp: WebAppItem?
    @State private var isShowingAddSheet = false
    @State private var isShowingUBlockSettings = false
    @State private var itemToClearData: WebAppItem?
    @State private var isShowingClearConfirmation = false
    @State private var itemToDelete: WebAppItem?
    @State private var isShowingDeleteConfirmation = false
    
    #if os(iOS)
    let columns = [
        GridItem(.flexible(), spacing: 20)
    ]
    #else
    let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 350), spacing: 20)
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
                .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
            } else {
                // Home Screen Grid
                homeScreenView
                    .transition(.opacity)
            }
        }
        .task {
            await UBlockOriginExtensionManager.shared.prepare()
            seedDefaultAppsIfNeeded()
        }
        .sheet(isPresented: $isShowingAddSheet) {
            AddWebAppSheet()
        }
        .sheet(isPresented: $isShowingUBlockSettings) {
            UBlockSettingsView()
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
            Text("This will wipe all locally stored cookies, session cache, and website storage for this web application.")
        }
        .confirmationDialog(
            "Delete \(itemToDelete?.name ?? "Web App")?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Web App", role: .destructive) {
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
    }
    
    // Liquid Glass Home Screen
    private var homeScreenView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if webApps.isEmpty {
                        emptyStateView
                    } else {
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(webApps) { app in
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
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("Isolated Web Apps")
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
                    
                    Button {
                        isShowingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            #if os(macOS)
                            .padding(8)
                            .liquidGlassButton(cornerRadius: 12)
                            #endif
                    }
                    .buttonStyle(.plain)
                    .help("Add Web App")
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
    
    private func seedDefaultAppsIfNeeded() {
        if webApps.isEmpty && !UserDefaults.standard.bool(forKey: "hasSeededDefaults") {
            let defaults = [
                ("YouTube", "https://www.youtube.com"),
                ("Google News", "https://news.google.com"),
                ("DuckDuckGo", "https://duckduckgo.com"),
                ("Reddit", "https://www.reddit.com"),
                ("Gemini", "https://gemini.google.com")
            ]
            
            Task {
                for app in defaults {
                    guard let url = URL(string: app.1) else { continue }
                    let iconData = await FaviconFetcher.fetchIcon(for: url)
                    await MainActor.run {
                        let newApp = WebAppItem(name: app.0, urlString: app.1, iconData: iconData)
                        modelContext.insert(newApp)
                    }
                }
                await MainActor.run {
                    try? modelContext.save()
                    UserDefaults.standard.set(true, forKey: "hasSeededDefaults")
                }
            }
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
        .contextMenu {
            Button(action: onClearData) {
                Label("Clear Cookies & Cache...", systemImage: "arrow.clockwise.circle")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete Web App", systemImage: "trash.fill")
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: WebAppItem.self, inMemory: true)
}
