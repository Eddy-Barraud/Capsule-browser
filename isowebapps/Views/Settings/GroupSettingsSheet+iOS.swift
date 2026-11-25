//
//  GroupSettingsSheet+iOS.swift
//  isowebapps
//
//  Description:
//  iOS layout for `GroupSettingsSheet`.
//

#if os(iOS)
import SwiftUI
import SwiftData

extension GroupSettingsSheet {
    var iOSLayout: some View {
        NavigationStack {
            Form {
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
                
                if !appsInOtherGroups.isEmpty {
                    Section(header: Text("Capsules in Other Groups"), footer: Text("Adding these will transfer them to this group.")) {
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
                
                Section(
                    header: Text("Data & Cookies"),
                    footer: Text("Permanently deletes all cookies, cache, local storage, and website sessions for all capsules in this group. You will be logged out of all accounts.")
                ) {
                    Button(role: .destructive) {
                        isShowingClearConfirmation = true
                    } label: {
                        HStack {
                            if isClearingData {
                                ProgressView()
                                Spacer().frame(width: 8)
                                Text("Clearing Data...")
                            } else if hasRecentlyClearedData {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("All Data & Cookies Cleared")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "trash")
                                Text("Clear All Data & Cookies")
                            }
                        }
                    }
                    .disabled(isClearingData || (group.items?.isEmpty ?? true))
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
}
#endif
