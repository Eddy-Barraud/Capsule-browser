//
//  TopControlsBar.swift
//  isowebapps
//
//  Description:
//  Top controls bar for capsules (AI Summarize, uBlock toggle, Ephemeral Add,
//  Downloads popover, Reader mode toggle, Home/Capsules button) plus the
//  macOS Sleeping Capsule placeholder view.
//

import SwiftUI
import SwiftData

struct TopControlsBar: View {
    @AppStorage("ublock_master_enabled") private var ublockMasterEnabled = true
    let appItem: WebAppItem
    @ObservedObject var navigationState: WebViewNavigationState
    @ObservedObject var downloadManager: CapsuleDownloadManager
    @Binding var isShowingDownloadsPopover: Bool
    var isGeneratingSummary: Bool = false
    var isSummarizationAvailable: Bool = false
    var isSecondaryWindow: Bool = false
    var isReaderModeActive: Bool = false
    let onDismiss: () -> Void
    let onToggleShield: () -> Void
    let onSummarize: () -> Void
    let onOpenInReader: () -> Void
    var onAddCapsule: (() -> Void)? = nil
    
    private var isYouTube: Bool {
        YouTubeFreeSupport.isYouTubeURLString(appItem.urlString) ||
        YouTubeFreeSupport.isYouTubeURLString(navigationState.currentURLString)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            if isSummarizationAvailable {
                Button(action: onSummarize) {
                    HStack(spacing: 4) {
                        if isGeneratingSummary {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.purple.gradient)
                        }
                        Text("Summarize")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 32)
                    .liquidGlassButton(cornerRadius: 10)
                }
                .buttonStyle(.plain)
                .help("Summarize the currently shown web page using Foundation Models")
            }
            
            if ublockMasterEnabled {
                Button(action: onToggleShield) {
                    HStack(spacing: 5) {
                        Image(systemName: isYouTube
                              ? (navigationState.isUBlockEnabled ? "play.rectangle.fill" : "play.slash.fill")
                              : (navigationState.isUBlockEnabled ? "shield.fill" : "shield.slash.fill"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isYouTube
                                             ? (navigationState.isUBlockEnabled ? .red : .secondary)
                                             : (navigationState.isUBlockEnabled ? .blue : .secondary))
                        
                        Text(isYouTube
                             ? (navigationState.isUBlockEnabled ? "Ad-Free" : "Ad-Free OFF")
                             : (navigationState.isUBlockEnabled ? "uBlock ON" : "uBlock OFF"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(navigationState.isUBlockEnabled ? .primary : .secondary)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 32)
                    .liquidGlassButton(cornerRadius: 10)
                }
                .buttonStyle(.plain)
                .help(isYouTube ? "Toggle YouTube ad-blocking and script injection" : "Toggle uBlock Origin protection")
            }
            
            Spacer()
            
            if appItem.modelContext == nil, let onAddCapsule = onAddCapsule {
                Button(action: onAddCapsule) {
                    HStack(spacing: 5) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.blue)
                        
                        Text("Add")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 32)
                    .liquidGlassButton(cornerRadius: 10)
                }
                .buttonStyle(.plain)
                .help("Add current page as a new capsule")
                
                Spacer()
            }
            
            if !downloadManager.items.isEmpty {
                Button {
                    isShowingDownloadsPopover.toggle()
                } label: {
                    HStack(spacing: 4) {
                        if downloadManager.hasActiveDownloads {
                            ProgressView()
                                .scaleEffect(0.55)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                        
                        Text("Downloads")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 32)
                    .liquidGlassButton(cornerRadius: 10)
                }
                .buttonStyle(.plain)
                .help("View active and recent file downloads")
                #if os(macOS)
                .popover(isPresented: $isShowingDownloadsPopover, arrowEdge: .bottom) {
                    DownloadsListView(downloadManager: downloadManager)
                        .frame(width: 340)
                        .frame(maxHeight: 380)
                }
                #endif
            }
            
            #if os(macOS)
            Button(action: onOpenInReader) {
                HStack(spacing: 4) {
                    Image(systemName: isReaderModeActive ? "doc.plaintext.fill" : "doc.plaintext")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isReaderModeActive ? .white : .blue)
                    
                    Text("Reader")
                        .font(.system(size: 11, weight: isReaderModeActive ? .semibold : .medium))
                        .foregroundColor(isReaderModeActive ? .white : .primary)
                }
                .padding(.horizontal, 9)
                .frame(height: 32)
                .modifier(ReaderToggleButtonStyleModifier(isActive: isReaderModeActive, cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help(isReaderModeActive ? "Switch back to full webpage" : "Open current page in Reader view")
            #else
            if !appItem.openLinksInSafariReaderMode {
                Button(action: onOpenInReader) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.plaintext")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.blue)
                        
                        Text("Reader")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 32)
                    .liquidGlassButton(cornerRadius: 10)
                }
                .buttonStyle(.plain)
                .help("Open current web page in Safari Reader view")
            }
            #endif
            
            Button(action: onDismiss) {
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Capsules")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 9)
                .frame(height: 32)
                .liquidGlassButton(cornerRadius: 10)
            }
            .buttonStyle(.plain)
            .help(isSecondaryWindow ? "Focus Capsules home window" : "Back to Capsules")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        #if os(iOS)
        .background(Color(uiColor: .systemBackground))
        #else
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
    }
}

#if os(macOS)
struct SleepingCapsulePlaceholderView: View {
    let capsuleName: String
    let urlString: String
    let onWakeNow: () -> Void
    
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            
            Text(capsuleName.isEmpty ? "Sleeping Capsule" : capsuleName)
                .font(.headline)
            
            Text("Sleeping to save memory")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if !urlString.isEmpty && urlString != "about:blank" {
                Text(urlString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 420)
            }
            
            Button("Wake Capsule", action: onWakeNow)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ReaderToggleButtonStyleModifier: ViewModifier {
    let isActive: Bool
    var cornerRadius: CGFloat = 10
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.accentColor)
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .liquidGlassButton(cornerRadius: cornerRadius)
        }
    }
}
#endif
