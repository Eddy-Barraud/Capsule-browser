//
//  CapsuleDownloadModels.swift
//  isowebapps
//
//  Description:
//  Data models and internal tracking context types for `CapsuleDownloadManager`.
//

import Foundation
import WebKit

/// Snapshot of a single file download tracked by `CapsuleDownloadManager`.
public struct CapsuleDownloadItem: Identifiable, Equatable {
    public enum State: Equatable {
        case awaitingPermission
        case downloading
        case completed
        case failed(String)
        case cancelled
    }
    
    public let id: UUID
    public var filename: String
    public var sourceHost: String
    public var destinationURL: URL?
    public var destinationFolderName: String
    public var progress: Double
    public var completedBytes: Int64
    public var totalBytes: Int64
    public var state: State
    public let createdAt: Date
    
    public var isActive: Bool {
        state == .awaitingPermission || state == .downloading
    }
    
    public var isFinished: Bool {
        switch state {
        case .completed, .failed, .cancelled:
            return true
        case .awaitingPermission, .downloading:
            return false
        }
    }
}

@MainActor
final class DownloadContext {
    let itemID: UUID
    var download: WKDownload?
    weak var originatingWebView: WKWebView?
    var progressObservations: [NSKeyValueObservation] = []
    var securityScopedFolderURL: URL?
    var didStartSecurityScopedAccess: Bool = false
    var finalDestinationURL: URL?
    var tempStagingURL: URL?
    
    init(itemID: UUID, download: WKDownload, originatingWebView: WKWebView?) {
        self.itemID = itemID
        self.download = download
        self.originatingWebView = originatingWebView
    }
    
    func releaseResources(removeTempFile: Bool) {
        progressObservations.forEach { $0.invalidate() }
        progressObservations.removeAll()
        if removeTempFile, let tempURL = tempStagingURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        tempStagingURL = nil
        if didStartSecurityScopedAccess, let folder = securityScopedFolderURL {
            folder.stopAccessingSecurityScopedResource()
        }
        didStartSecurityScopedAccess = false
        securityScopedFolderURL = nil
        download = nil
        originatingWebView = nil
    }
}

@MainActor
final class PendingDownloadPrompt {
    let itemID: UUID
    let downloadID: ObjectIdentifier
    let filename: String
    let sourceHost: String
    let expectedContentLength: Int64
    weak var originatingWebView: WKWebView?
    private var completion: (@MainActor @Sendable (URL?) -> Void)?
    
    init(
        itemID: UUID,
        downloadID: ObjectIdentifier,
        filename: String,
        sourceHost: String,
        expectedContentLength: Int64,
        originatingWebView: WKWebView?,
        completion: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        self.itemID = itemID
        self.downloadID = downloadID
        self.filename = filename
        self.sourceHost = sourceHost
        self.expectedContentLength = expectedContentLength
        self.originatingWebView = originatingWebView
        self.completion = completion
    }
    
    func complete(with url: URL?) {
        guard let handler = completion else { return }
        completion = nil
        handler(url)
    }
}
