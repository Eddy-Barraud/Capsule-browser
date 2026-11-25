//
//  GroupSettingsSheet.swift
//  isowebapps
//
//  Created on 06/10/2026.
//
//  Description:
//  Settings sheet for managing a `WebAppGroup`: renaming the group,
//  adding/removing/transferring capsules, and clearing group data/cookies.
//

import SwiftUI
import SwiftData

struct GroupSettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    
    @Bindable var group: WebAppGroup
    @Query(sort: \WebAppItem.displayOrder) var allApps: [WebAppItem]
    
    @State var groupName: String = ""
    @State var searchText: String = ""
    @State var isShowingClearConfirmation = false
    @State var isClearingData = false
    @State var hasRecentlyClearedData = false
    
    var groupItems: [WebAppItem] {
        let items = group.items ?? []
        let sorted = items.sorted { $0.displayOrder < $1.displayOrder }
        return filteredApps(sorted)
    }
    
    var availableStandaloneApps: [WebAppItem] {
        filteredApps(allApps.filter { $0.group == nil })
    }
    
    var appsInOtherGroups: [WebAppItem] {
        filteredApps(allApps.filter { $0.group != nil && $0.group?.id != group.id })
    }
    
    private func filteredApps(_ apps: [WebAppItem]) -> [WebAppItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.urlString.localizedCaseInsensitiveContains(query)
        }
    }
    
    var body: some View {
        Group {
            #if os(macOS)
            macOSLayout
            #else
            iOSLayout
            #endif
        }
        .confirmationDialog(
            "Clear All Data & Cookies for '\(group.name)'?",
            isPresented: $isShowingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Data & Cookies", role: .destructive) {
                clearGroupData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all cookies, local storage, cache, and active sessions for all \(group.items?.count ?? 0) capsules in this group. This cannot be undone.")
        }
    }
    
    func addAppToGroup(_ app: WebAppItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            app.group = group
            try? modelContext.save()
        }
    }
    
    func removeAppFromGroup(_ app: WebAppItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            app.group = nil
            try? modelContext.save()
        }
    }
    
    private func clearGroupData() {
        isClearingData = true
        Task {
            await IsolatedCookieManager.shared.clearData(for: group, context: modelContext)
            isClearingData = false
            hasRecentlyClearedData = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                hasRecentlyClearedData = false
            }
        }
    }
}
