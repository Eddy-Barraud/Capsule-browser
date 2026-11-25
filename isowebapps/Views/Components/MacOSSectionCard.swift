//
//  MacOSSectionCard.swift
//  isowebapps
//
//  Description:
//  Reusable macOS settings section card container with optional icon, badge, and footer.
//

#if os(macOS)
import SwiftUI
import AppKit

struct MacOSSectionCard<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    var badge: String? = nil
    var footer: String? = nil
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.blue)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                if let badge {
                    Spacer()
                    Text(badge)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}
#endif
