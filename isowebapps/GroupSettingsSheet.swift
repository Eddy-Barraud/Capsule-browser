//
//  GroupSettingsSheet.swift
//  isowebapps
//
//  Created on 06/10/2026.
//
//  Description:
//  Settings sheet for managing a WebAppGroup. Allows renaming the group,
//  removing existing capsules from the group, and adding available capsules into the group.
//

import SwiftUI
import SwiftData

struct GroupSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Bindable var group: WebAppGroup
    @Query(sort: \WebAppItem.displayOrder) private var allApps: [WebAppItem]
    
    @State private var groupName: String = ""
    @State private var searchText: String = ""
    
    private var groupItems: [WebAppItem] {
        let items = group.items ?? []
        let sorted = items.sorted { $0.displayOrder < $1.displayOrder }
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return sorted
        }
        return sorted.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.urlString.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var availableStandaloneApps: [WebAppItem] {
        let available = allApps.filter { $0.group == nil }
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return available
        }
        return available.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.urlString.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var appsInOtherGroups: [WebAppItem] {
        let others = allApps.filter { $0.group != nil && $0.group?.id != group.id }
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return others
        }
        return others.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.urlString.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
    }
    
    // MARK: - macOS Layout
    #if os(macOS)
    private var macOSLayout: some View {
        VStack(spacing: 0) {
            // Header
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
            
            // Search field
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
            
            // Scrollable Content
            ScrollView(.vertical) {
                VStack(spacing: 20) {
                    // Group Name Card
                    macOSSectionCard(title: "Group Name") {
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
                    
                    // Capsules in Group Card
                    macOSSectionCard(
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
                                    HStack(spacing: 12) {
                                        appIconView(for: app)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(app.name)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(.primary)
                                            
                                            if let domain = WebAppNamingHelper.domainName(from: app.urlString) {
                                                Text(domain)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Button {
                                            removeAppFromGroup(app)
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "minus.circle.fill")
                                                    .foregroundColor(.red)
                                                Text("Remove")
                                                    .font(.subheadline)
                                                    .foregroundColor(.red)
                                            }
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 10)
                                            .background(Color.red.opacity(0.12))
                                            .cornerRadius(6)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove from group")
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                    
                    // Available Standalone Capsules Card
                    macOSSectionCard(
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
                                    HStack(spacing: 12) {
                                        appIconView(for: app)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(app.name)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(.primary)
                                            
                                            if let domain = WebAppNamingHelper.domainName(from: app.urlString) {
                                                Text(domain)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Button {
                                            addAppToGroup(app)
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "plus.circle.fill")
                                                    .foregroundColor(.blue)
                                                Text("Add")
                                                    .font(.subheadline.bold())
                                                    .foregroundColor(.blue)
                                            }
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 10)
                                            .background(Color.blue.opacity(0.12))
                                            .cornerRadius(6)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Add to group")
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                    
                    // Capsules in Other Groups Card (if any)
                    if !appsInOtherGroups.isEmpty {
                        macOSSectionCard(
                            title: "Capsules in Other Groups",
                            badge: "\(appsInOtherGroups.count)",
                            footer: "Adding these will transfer them to this group."
                        ) {
                            VStack(spacing: 8) {
                                ForEach(appsInOtherGroups) { app in
                                    HStack(spacing: 12) {
                                        appIconView(for: app)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(app.name)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(.primary)
                                            
                                            if let otherGroupName = app.group?.name {
                                                Text("In: \(otherGroupName)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Button {
                                            addAppToGroup(app)
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.right.circle.fill")
                                                    .foregroundColor(.purple)
                                                Text("Transfer")
                                                    .font(.subheadline)
                                                    .foregroundColor(.purple)
                                            }
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 10)
                                            .background(Color.purple.opacity(0.12))
                                            .cornerRadius(6)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Transfer to this group")
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.visible)
            
            Divider()
            
            // Pinned Bottom Bar
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
    
    @ViewBuilder
    private func macOSSectionCard<Content: View>(
        title: String,
        badge: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let badge {
                    Spacer()
                    Text(badge)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            
            content()
            
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
    #endif
    
    // MARK: - iOS Layout
    #if os(iOS)
    private var iOSLayout: some View {
        NavigationStack {
            Form {
                // Section: Group Name
                Section(header: Text("Group Name")) {
                    TextField("Group Name", text: $groupName)
                        .onChange(of: groupName) { _, newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty {
                                group.name = trimmed
                                try? modelContext.save()
                            }
                        }
                }
                
                // Section: Capsules in this Group (Removal)
                Section(header: HStack {
                    Text("Capsules in Group")
                    Spacer()
                    Text("\(group.items?.count ?? 0)")
                        .foregroundStyle(.secondary)
                        .font(.caption.bold())
                }, footer: Text("Removing a capsule from the group returns it to the main capsules list.")) {
                    if groupItems.isEmpty {
                        Text(searchText.isEmpty ? "No capsules in this group yet." : "No matching capsules in group.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(groupItems) { app in
                            HStack(spacing: 12) {
                                appIconView(for: app)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    
                                    if let domain = WebAppNamingHelper.domainName(from: app.urlString) {
                                        Text(domain)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Button {
                                    removeAppFromGroup(app)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                        Text("Remove")
                                            .font(.subheadline)
                                            .foregroundColor(.red)
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .help("Remove from group")
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                
                // Section: Available Capsules to Add
                Section(header: HStack {
                    Text("Available Capsules to Add")
                    Spacer()
                    Text("\(availableStandaloneApps.count)")
                        .foregroundStyle(.secondary)
                        .font(.caption.bold())
                }, footer: Text("Capsules in a group share isolated cookies and login sessions.")) {
                    if availableStandaloneApps.isEmpty {
                        Text(searchText.isEmpty ? "No standalone capsules available." : "No matching available capsules.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(availableStandaloneApps) { app in
                            HStack(spacing: 12) {
                                appIconView(for: app)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    
                                    if let domain = WebAppNamingHelper.domainName(from: app.urlString) {
                                        Text(domain)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Button {
                                    addAppToGroup(app)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.blue)
                                        Text("Add")
                                            .font(.subheadline.bold())
                                            .foregroundColor(.blue)
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .help("Add to group")
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                
                // Section: Move from Other Groups (if any)
                if !appsInOtherGroups.isEmpty {
                    Section(header: Text("Capsules in Other Groups"), footer: Text("Adding these will transfer them to this group.")) {
                        ForEach(appsInOtherGroups) { app in
                            HStack(spacing: 12) {
                                appIconView(for: app)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    
                                    if let otherGroupName = app.group?.name {
                                        Text("In: \(otherGroupName)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Button {
                                    addAppToGroup(app)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .foregroundColor(.purple)
                                        Text("Transfer")
                                            .font(.subheadline)
                                            .foregroundColor(.purple)
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color.purple.opacity(0.1))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .help("Transfer to this group")
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search capsules...")
            .navigationTitle("Group Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                groupName = group.name
            }
        }
    }
    #endif
    
    // MARK: - Actions
    
    private func addAppToGroup(_ app: WebAppItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            app.group = group
            try? modelContext.save()
        }
    }
    
    private func removeAppFromGroup(_ app: WebAppItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            app.group = nil
            try? modelContext.save()
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private func appIconView(for app: WebAppItem) -> some View {
        if let iconData = app.iconData,
           let platformImage = PlatformImage(data: iconData) {
            Image(platformImage: platformImage)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Image(systemName: "globe")
                .font(.system(size: 18))
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
