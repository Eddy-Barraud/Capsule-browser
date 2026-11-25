//
//  CapsuleDownloadViews.swift
//  isowebapps
//
//  Description:
//  Download status banner and popover/sheet download queue list views.
//

import SwiftUI

struct DownloadBannerView: View {
    let item: CapsuleDownloadItem
    let onCancel: () -> Void
    let onReveal: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            statusIcon
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.filename)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer(minLength: 4)
                    
                    Text(subtitleText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                if item.state == .downloading {
                    if item.totalBytes > 0 {
                        ProgressView(value: item.progress)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                }
            }
            
            if item.state == .downloading {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else if item.state == .completed {
                #if os(macOS)
                Button("Show in Finder", action: onReveal)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                #endif
            }
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        #if os(iOS)
        .background(Color(uiColor: .secondarySystemBackground))
        #else
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch item.state {
        case .awaitingPermission, .downloading:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.blue)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.orange)
        case .cancelled:
            Image(systemName: "xmark.circle")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }
    
    private var subtitleText: String {
        switch item.state {
        case .awaitingPermission:
            return "Waiting for permission…"
        case .downloading:
            let done = ByteCountFormatter.string(fromByteCount: item.completedBytes, countStyle: .file)
            if item.totalBytes > 0 {
                let total = ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file)
                return "\(done) / \(total)"
            }
            return done
        case .completed:
            return "Saved to \(item.destinationFolderName)"
        case .failed(let message):
            return message
        case .cancelled:
            return "Cancelled"
        }
    }
}

struct DownloadsListView: View {
    @ObservedObject var downloadManager: CapsuleDownloadManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Downloads")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                if downloadManager.items.contains(where: \.isFinished) {
                    Button("Clear") {
                        downloadManager.clearFinishedDownloads()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .medium))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            Divider()
            
            if downloadManager.items.isEmpty {
                Text("No downloads yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(downloadManager.items) { item in
                            downloadRow(item)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }
    
    private func downloadRow(_ item: CapsuleDownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.filename)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Text("\(item.sourceHost) • \(rowStatusText(item))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 4)
                
                if item.isActive {
                    Button {
                        downloadManager.cancelDownload(id: item.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel Download")
                } else if item.state == .completed {
                    #if os(macOS)
                    Button {
                        downloadManager.revealInFinder(id: item.id)
                    } label: {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                    #endif
                }
            }
            
            if item.state == .downloading {
                if item.totalBytes > 0 {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
    
    private func rowStatusText(_ item: CapsuleDownloadItem) -> String {
        switch item.state {
        case .awaitingPermission:
            return "Awaiting permission"
        case .downloading:
            let done = ByteCountFormatter.string(fromByteCount: item.completedBytes, countStyle: .file)
            if item.totalBytes > 0 {
                let total = ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file)
                return "\(done) of \(total)"
            }
            return done
        case .completed:
            return "Saved to \(item.destinationFolderName)"
        case .failed(let reason):
            return "Failed: \(reason)"
        case .cancelled:
            return "Cancelled"
        }
    }
}
