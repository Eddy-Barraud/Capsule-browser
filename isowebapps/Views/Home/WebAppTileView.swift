//
//  WebAppTileView.swift
//  isowebapps
//
//  Description:
//  Home Screen tile view and isolated per-capsule settings menu for a `WebAppItem`.
//

import SwiftUI
import SwiftData

struct WebAppTileView: View {
    let app: WebAppItem
    let onStart: () -> Void
    let onResume: () -> Void
    let onClearData: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
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
                .liquidGlassButton(cornerRadius: 20)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(app.name)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
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
                        .frame(maxWidth: .infinity, minHeight: 44)
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
                        .frame(maxWidth: .infinity, minHeight: 44)
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

struct WebAppTileSettingsMenu: View {
    @AppStorage("ublock_master_enabled") private var ublockMasterEnabled = true
    @Bindable var app: WebAppItem
    let onClearData: () -> Void
    let onDelete: () -> Void
    
    private var readerLinksToggleTitle: String {
        #if os(macOS)
        return "Open links in Reader"
        #else
        return "Open links in Safari Reader"
        #endif
    }
    
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
            Toggle(readerLinksToggleTitle, isOn: $app.openLinksInSafariReaderMode)
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
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.1))
                .clipShape(Circle())
        }
        .menuStyle(.borderlessButton)
    }
}
