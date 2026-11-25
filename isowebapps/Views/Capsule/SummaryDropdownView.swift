//
//  SummaryDropdownView.swift
//  isowebapps
//
//  Description:
//  Dropdown/sidebar panel displaying the on-device AI-generated web page summary.
//

import SwiftUI

struct SummaryDropdownView: View {
    let isGenerating: Bool
    let summaryText: String
    let errorMessage: String?
    let onClose: () -> Void
    let onRegenerate: () -> Void
    
    @State private var hasCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.purple.gradient)
                
                Text("Page Summary")
                    .font(.system(size: 13, weight: .bold))
                
                Spacer()
                
                if !summaryText.isEmpty && !isGenerating {
                    Button {
                        copyToClipboard(summaryText)
                        hasCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            hasCopied = false
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .liquidGlassButton(cornerRadius: 8)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onRegenerate) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .padding(6)
                            .liquidGlassButton(cornerRadius: 8)
                    }
                    .buttonStyle(.plain)
                    .help("Regenerate Summary")
                }
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            if let error = errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else if isGenerating && summaryText.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Generating AI summary...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                ScrollView {
                    Text(summaryText)
                        .font(.system(size: 16, weight: .regular))
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                #if os(macOS)
                .frame(maxHeight: .infinity)
                #else
                .frame(maxHeight: 250)
                #endif
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(uiOrNsWindowBackgroundColor.opacity(0.95))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.4), Color.blue.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
    
    private var uiOrNsWindowBackgroundColor: Color {
        #if os(iOS)
        return Color(uiColor: .secondarySystemBackground)
        #else
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }
}
