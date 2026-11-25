//
//  GroupSettingsSheet+MacOS.swift
//  isowebapps
//
//  Description:
//  macOS layout for `GroupSettingsSheet`.
//

#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

extension GroupSettingsSheet {
    var macOSLayout: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Group Settings")
                        .font(.title2.bold())
                    Text("Configure group name and managed capsules")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)
            
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search capsules...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            
            Divider()
            
            ScrollView(.vertical) {
                VStack(spacing: 20) {
                    MacOSSectionCard(title: "Group Name") {
                        TextField("Group Name", text: $groupName)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: groupName) { _, newValue in
                                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty {
                                    group.name = trimmed
                                    try? modelContext.save()
                                }
                            }
                    }
                    
                    MacOSSectionCard(
                        title: "Capsules in Group",
                        badge: "\(group.items?.count ?? 0)",
                        footer: "Removing a capsule from the group returns it to the main capsules list."
                    ) {
                        if groupItems.isEmpty {
                            Text(searchText.isEmpty ? "No capsules in this group yet." : "No matching capsules in group.")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(groupItems) { app in
                                    CapsuleActionRow(
                                        app: app,
                                        subtitle: WebAppNamingHelper.domainName(from: app.urlString),
                                        buttonTitle: "Remove",
                                        buttonIcon: "minus.circle.fill",
                                        buttonColor: .red,
                                        helpText: "Remove from group"
                                    ) {
                                        removeAppFromGroup(app)
                                    }
                                }
                            }
                        }
                    }
                    
                    MacOSSectionCard(
                        title: "Available Capsules to Add",
                        badge: "\(availableStandaloneApps.count)",
                        footer: "Capsules in a group share isolated cookies and login sessions."
                    ) {
                        if availableStandaloneApps.isEmpty {
                            Text(searchText.isEmpty ? "No standalone capsules available." : "No matching available capsules.")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(availableStandaloneApps) { app in
                                    CapsuleActionRow(
                                        app: app,
                                        subtitle: WebAppNamingHelper.domainName(from: app.urlString),
                                        buttonTitle: "Add",
                                        buttonIcon: "plus.circle.fill",
                                        buttonColor: .blue,
                                        helpText: "Add to group"
                                    ) {
                                        addAppToGroup(app)
                                    }
                                }
                            }
                        }
                    }
                    
                    if !appsInOtherGroups.isEmpty {
                        MacOSSectionCard(
                            title: "Capsules in Other Groups",
                            badge: "\(appsInOtherGroups.count)",
                            footer: "Adding these will transfer them to this group."
                        ) {
                            VStack(spacing: 8) {
                                ForEach(appsInOtherGroups) { app in
                                    CapsuleActionRow(
                                        app: app,
                                        subtitle: app.group.map { "In: \($0.name)" },
                                        buttonTitle: "Transfer",
                                        buttonIcon: "arrow.right.circle.fill",
                                        buttonColor: .purple,
                                        helpText: "Transfer to this group"
                                    ) {
                                        addAppToGroup(app)
                                    }
                                }
                            }
                        }
                    }
                    
                    MacOSSectionCard(
                        title: "Data & Cookies",
                        badge: (group.items?.isEmpty ?? true) ? nil : "\(group.items?.count ?? 0) capsules",
                        footer: "Permanently deletes all cookies, cache, local storage, and website sessions for all capsules in this group."
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Clearing group data logs you out of all accounts and services across every capsule in this group.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            HStack {
                                Button(role: .destructive) {
                                    isShowingClearConfirmation = true
                                } label: {
                                    HStack(spacing: 6) {
                                        if isClearingData {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Clearing Data...")
                                        } else if hasRecentlyClearedData {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                            Text("Data Cleared")
                                                .foregroundColor(.green)
                                        } else {
                                            Image(systemName: "trash")
                                            Text("Clear All Data & Cookies")
                                        }
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(hasRecentlyClearedData ? .green : .red)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background((hasRecentlyClearedData ? Color.green : Color.red).opacity(0.12))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .disabled(isClearingData || (group.items?.isEmpty ?? true))
                                .help("Delete all cookies, storage, and website data for all capsules in this group")
                                
                                Spacer()
                            }
                        }
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.visible)
            
            Divider()
            
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 520, idealWidth: 560, maxWidth: 640, minHeight: 450, idealHeight: 560, maxHeight: 720)
        .onAppear {
            groupName = group.name
        }
    }
}
#endif
