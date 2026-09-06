import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct AddGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \WebAppItem.displayOrder) private var allApps: [WebAppItem]
    
    @State private var groupName: String = ""
    @State private var selectedAppIDs: Set<UUID> = []
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Group Info")) {
                    TextField("Group Name", text: $groupName)
                }
                
                Section(header: Text("Select Apps for Group"), footer: Text("Apps already in a group are hidden.")) {
                    let availableApps = allApps.filter { $0.group == nil }
                    
                    if availableApps.isEmpty {
                        Text("No available apps to group.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableApps) { app in
                            Button {
                                if selectedAppIDs.contains(app.id) {
                                    selectedAppIDs.remove(app.id)
                                } else {
                                    selectedAppIDs.insert(app.id)
                                }
                            } label: {
                                HStack {
                                    if let iconData = app.iconData, let uiImage = _imageFrom(data: iconData) {
#if os(macOS)
                                        Image(nsImage: uiImage)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 30, height: 30)
                                            .cornerRadius(6)
#else
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 30, height: 30)
                                            .cornerRadius(6)
#endif
                                    }
                                    
                                    Text(app.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedAppIDs.contains(app.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Create App Group")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createGroup()
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty || selectedAppIDs.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 400)
        #endif
    }
    
    private func createGroup() {
        let newGroup = WebAppGroup(name: groupName.trimmingCharacters(in: .whitespaces))
        modelContext.insert(newGroup)
        
        let appsToGroup = allApps.filter { selectedAppIDs.contains($0.id) }
        for app in appsToGroup {
            app.group = newGroup
        }
        
        try? modelContext.save()
        dismiss()
    }
    
    #if os(iOS)
    private func _imageFrom(data: Data) -> UIImage? { UIImage(data: data) }
    #else
    private func _imageFrom(data: Data) -> NSImage? { NSImage(data: data) }
    #endif
}
