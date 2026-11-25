//
//  OpenURLSheet.swift
//  isowebapps
//
//  Description:
//  Modal sheet allowing users to route an incoming Share Extension / deep-link URL
//  into an existing matching capsule or a fresh ephemeral capsule.
//

import SwiftUI

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
        let matched = Set(matchingApps.lazy.map(\.id))
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
            if app.iconData != nil {
                CapsuleIconView(app: app, size: 24, cornerRadius: 6, fallbackSymbolSize: 12)
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
