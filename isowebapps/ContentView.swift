//
//  ContentView.swift
//  isowebapps
//
//  Created by Eddy Barraud on 23/08/2026.
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
    
    let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 20)
    ]
    
    var body: some View {
        Group {
            if let activeApp = selectedWebApp {
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
                homeScreenView
                    .transition(.opacity)
            }
        }
        .task {
            await UBlockOriginExtensionManager.shared.prepare()
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
            Button("Clear Cookies, Cache & Storage", role: .destructive) {
                if let item = itemToClearData {
                    clearAppData(item)
                }
            }
            Button("Delete Web App", role: .destructive) {
                if let item = itemToClearData {
                    withAnimation {
                        modelContext.delete(item)
                        try? modelContext.save()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will wipe all locally stored cache, isolated cookies, and website storage for this web application.")
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
                                WebAppTileView(app: app) {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        selectedWebApp = app
                                    }
                                } onOptionMenu: {
                                    itemToClearData = app
                                    isShowingClearConfirmation = true
                                }
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
                            .padding(8)
                            .liquidGlassButton(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                    .help("uBlock Origin Lite Settings")
                    
                    Button {
                        isShowingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .padding(8)
                            .liquidGlassButton(cornerRadius: 12)
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
}

// Tile View for Each Web App with Liquid Glass Design
struct WebAppTileView: View {
    let app: WebAppItem
    let onOpen: () -> Void
    let onOptionMenu: () -> Void
    
    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 10) {
                ZStack {
                    if let iconData = app.iconData,
                       let platformImage = PlatformImage(data: iconData) {
                        Image(platformImage: platformImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 30))
                            .foregroundStyle(.primary)
                    }
                }
                .frame(width: 76, height: 76)
                .liquidGlassCard(cornerRadius: 20)
                
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
            }
            .frame(width: 96)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onOptionMenu) {
                Label("Clear Cookies & Cache...", systemImage: "trash")
            }
            Button(role: .destructive, action: onOptionMenu) {
                Label("Delete Web App", systemImage: "trash.fill")
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: WebAppItem.self, inMemory: true)
}
