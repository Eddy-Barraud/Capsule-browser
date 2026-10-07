import SwiftUI

struct WebAppGroupTileView: View {
    let group: WebAppGroup
    let onStartApp: (WebAppItem) -> Void
    let onResumeApp: (WebAppItem) -> Void
    let onClearDataApp: (WebAppItem) -> Void
    let onDeleteApp: (WebAppItem) -> Void
    let onEditGroup: () -> Void
    let onDeleteGroup: () -> Void
    
    #if os(iOS)
    let columns = [
        GridItem(.flexible(), spacing: 20, alignment: .top)
    ]
    #else
    let columns = [
        GridItem(.flexible(), spacing: 20, alignment: .top)
    ]
    #endif
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(group.name)
                    .font(.title2.bold())
                Spacer()
                
                Button(action: onEditGroup) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Group Settings")
                
                Button(role: .destructive, action: onDeleteGroup) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Delete Group")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            if let items = group.items, !items.isEmpty {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items.sorted(by: { $0.displayOrder < $1.displayOrder })) { app in
                        WebAppTileView(
                            app: app,
                            onStart: { onStartApp(app) },
                            onResume: { onResumeApp(app) },
                            onClearData: { onClearDataApp(app) },
                            onDelete: { onDeleteApp(app) }
                        )
                    }
                }
                .padding(16)
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text("No capsules in this group yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button(action: onEditGroup) {
                            Label("Add Capsules", systemImage: "plus.circle")
                                .font(.footnote.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .compositingGroup()
    }
}

