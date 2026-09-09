import SwiftUI

struct WebAppGroupTileView: View {
    let group: WebAppGroup
    let onStartApp: (WebAppItem) -> Void
    let onResumeApp: (WebAppItem) -> Void
    let onClearDataApp: (WebAppItem) -> Void
    let onDeleteApp: (WebAppItem) -> Void
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
            HStack {
                Text(group.name)
                    .font(.title2.bold())
                Spacer()
                Button(role: .destructive, action: onDeleteGroup) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            LazyVGrid(columns: columns, spacing: 16) {
                if let items = group.items {
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
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .compositingGroup()
    }
}

