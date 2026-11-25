//
//  CapsuleActionRow.swift
//  isowebapps
//
//  Description:
//  Reusable capsule row with icon, title, optional subtitle, and action pill button
//  shared across macOS and iOS group management views.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct CapsuleActionRow: View {
    let app: WebAppItem
    let subtitle: String?
    let buttonTitle: String
    let buttonIcon: String
    let buttonColor: Color
    let helpText: String
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            CapsuleIconView(app: app)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: action) {
                HStack(spacing: 4) {
                    Image(systemName: buttonIcon)
                        .foregroundColor(buttonColor)
                    Text(buttonTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(buttonColor)
                }
                #if os(macOS)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(buttonColor.opacity(0.12))
                .cornerRadius(6)
                #else
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(buttonColor.opacity(0.1))
                .cornerRadius(8)
                #endif
            }
            .buttonStyle(.plain)
            .help(helpText)
        }
        #if os(macOS)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
        #else
        .padding(.vertical, 2)
        #endif
    }
}
