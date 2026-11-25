//
//  CapsuleDownloadManager.swift
//  isowebapps
//
//  Description:
//  Coordinates WKDownload lifecycle, per-download user permission prompts,
//  custom folder selection vs. default Downloads directory, filename sanitization,
//  unique collision-safe destinations, progress tracking, and resource cleanup.
//

import Foundation
import WebKit
import Combine
#if os(macOS)
import AppKit
#else
import UIKit
import UniformTypeIdentifiers
#endif

/// Manages file downloads across isolated capsules, prompting for permission before saving.
@MainActor
public final class CapsuleDownloadManager: NSObject, ObservableObject, WKDownloadDelegate {
    public static let shared = CapsuleDownloadManager()
    
    @Published public internal(set) var items: [CapsuleDownloadItem] = []
    @Published public var activeBannerItemID: UUID? = nil
    
    public var hasActiveDownloads: Bool {
        items.contains { $0.isActive }
    }
    
    public func hasActiveDownload(for webView: WKWebView) -> Bool {
        contextsByDownloadID.values.contains { $0.originatingWebView === webView }
    }
    
    public var activeBannerItem: CapsuleDownloadItem? {
        guard let id = activeBannerItemID else { return nil }
        return items.first { $0.id == id }
    }
    
    var contextsByDownloadID: [ObjectIdentifier: DownloadContext] = [:]
    var downloadIDByItemID: [UUID: ObjectIdentifier] = [:]
    var pendingPrompts: [PendingDownloadPrompt] = []
    var activePrompt: PendingDownloadPrompt?
    var isPresentingPrompt = false
    private var autoDismissTask: Task<Void, Never>?
    
    #if !os(macOS)
    var activeFolderPickerCoordinator: IOSFolderPickerCoordinator?
    #endif
    
    private override init() {
        super.init()
    }
    
    // MARK: - Policy & Filename Pure Helpers
    
    /// Checks whether an HTTP `Content-Disposition` header specifies `attachment`.
    public static func isAttachmentContentDisposition(_ headerValue: String?) -> Bool {
        guard let raw = headerValue else { return false }
        let dispositionType = raw
            .split(separator: ";")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return dispositionType == "attachment"
    }
    
    /// Determines whether a `WKNavigationResponse` should trigger a file download rather than web rendering.
    public static func shouldDownloadResponse(
        _ response: URLResponse,
        canShowMIMEType: Bool,
        isForMainFrame: Bool
    ) -> Bool {
        let httpResponse = response as? HTTPURLResponse
        if let httpResponse, (httpResponse.statusCode == 204 || httpResponse.statusCode == 205) {
            return false
        }
        if isAttachmentContentDisposition(httpResponse?.value(forHTTPHeaderField: "Content-Disposition")) {
            return true
        }
        if !canShowMIMEType {
            if isForMainFrame {
                return true
            }
            let hasValidHTTPStatus = httpResponse.map { (200...299).contains($0.statusCode) } ?? true
            return response.expectedContentLength != 0 && hasValidHTTPStatus
        }
        return false
    }
    
    /// Sanitizes an untrusted server-provided filename to prevent path traversal, slashes, or hidden dotfiles.
    public static func sanitizedFilename(_ rawFilename: String, fallbackURL: URL? = nil) -> String {
        func cleanComponent(_ input: String) -> String {
            let base = (input as NSString).lastPathComponent
            let sanitizedChars = base.map { char -> Character in
                switch char {
                case ":", "\0", "\n", "\r", "\t":
                    return "_"
                default:
                    return char
                }
            }
            var result = String(sanitizedChars).trimmingCharacters(in: .whitespacesAndNewlines)
            while result.hasPrefix(".") {
                result.removeFirst()
            }
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.isEmpty || result == "." || result == ".." || result == "/" {
                return ""
            }
            return result
        }
        
        let primary = cleanComponent(rawFilename)
        if !primary.isEmpty {
            return primary
        }
        if let url = fallbackURL {
            let fallback = cleanComponent(url.lastPathComponent)
            if !fallback.isEmpty {
                return fallback
            }
        }
        return "download"
    }
    
    /// Returns a collision-free destination file URL inside `directory`, because `WKDownload` fails if the file already exists.
    public static func uniqueDestinationURL(
        in directory: URL,
        filename: String,
        fileManager: FileManager = .default
    ) -> URL {
        let cleanName = sanitizedFilename(filename)
        let initial = directory.appendingPathComponent(cleanName, isDirectory: false)
        if !fileManager.fileExists(atPath: initial.path) {
            return initial
        }
        
        let parsed = URL(fileURLWithPath: cleanName)
        let ext = parsed.pathExtension
        let stem = parsed.deletingPathExtension().lastPathComponent
        
        var counter = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName, isDirectory: false)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
    
    /// Returns the platform default Downloads directory.
    public static func defaultDownloadsDirectory(fileManager: FileManager = .default) -> URL? {
        #if os(macOS)
        return fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
        #else
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let downloads = docs.appendingPathComponent("Downloads", isDirectory: true)
        if !fileManager.fileExists(atPath: downloads.path) {
            try? fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        }
        return downloads
        #endif
    }
    
    // MARK: - Registration & User Controls
    
    /// Registers a `WKDownload` spawned by a `WKNavigationDelegate` callback and assigns `self` as delegate.
    public func registerDownload(_ download: WKDownload, originatingWebView: WKWebView?) {
        let downloadID = ObjectIdentifier(download)
        guard contextsByDownloadID[downloadID] == nil else {
            download.delegate = self
            return
        }
        
        let itemID = UUID()
        let rawName = download.originalRequest?.url?.lastPathComponent ?? ""
        let safeName = Self.sanitizedFilename(rawName, fallbackURL: download.originalRequest?.url)
        let host = download.originalRequest?.url?.host ?? "this website"
        
        let item = CapsuleDownloadItem(
            id: itemID,
            filename: safeName,
            sourceHost: host,
            destinationURL: nil,
            destinationFolderName: "Downloads",
            progress: 0,
            completedBytes: 0,
            totalBytes: 0,
            state: .awaitingPermission,
            createdAt: Date()
        )
        items.insert(item, at: 0)
        
        let context = DownloadContext(itemID: itemID, download: download, originatingWebView: originatingWebView)
        contextsByDownloadID[downloadID] = context
        downloadIDByItemID[itemID] = downloadID
        download.delegate = self
    }
    
    public func cancelDownload(id: UUID) {
        if let activePrompt, activePrompt.itemID == id {
            activePrompt.complete(with: nil)
        }
        if let idx = pendingPrompts.firstIndex(where: { $0.itemID == id }) {
            let removed = pendingPrompts.remove(at: idx)
            removed.complete(with: nil)
        }
        
        updateItem(id: id) { item in
            item.state = .cancelled
        }
        
        if let downloadID = downloadIDByItemID[id], let context = contextsByDownloadID[downloadID] {
            let dl = context.download
            context.releaseResources(removeTempFile: true)
            contextsByDownloadID.removeValue(forKey: downloadID)
            downloadIDByItemID.removeValue(forKey: id)
            dl?.cancel { _ in }
        }
        if activeBannerItemID == id {
            dismissBanner()
        }
    }
    
    #if os(macOS)
    public func revealInFinder(id: UUID) {
        guard let item = items.first(where: { $0.id == id }),
              let url = item.destinationURL else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    #endif
    
    public func clearFinishedDownloads() {
        let removedIDs = Set(items.filter { $0.isFinished }.map(\.id))
        items.removeAll { $0.isFinished }
        if let activeID = activeBannerItemID, removedIDs.contains(activeID) {
            dismissBanner()
        }
    }
    
    public func dismissBanner() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        activeBannerItemID = nil
    }
    
    // MARK: - WKDownloadDelegate
    
    public func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        let downloadID = ObjectIdentifier(download)
        let context: DownloadContext
        if let existing = contextsByDownloadID[downloadID] {
            context = existing
        } else {
            registerDownload(download, originatingWebView: download.webView)
            guard let created = contextsByDownloadID[downloadID] else {
                completionHandler(nil)
                return
            }
            context = created
        }
        
        let safeName = Self.sanitizedFilename(
            suggestedFilename,
            fallbackURL: response.url ?? download.originalRequest?.url
        )
        let sourceHost = response.url?.host
            ?? download.originalRequest?.url?.host
            ?? "this website"
        let expectedLength = response.expectedContentLength
        
        updateItem(id: context.itemID) { item in
            item.filename = safeName
            item.sourceHost = sourceHost
            item.totalBytes = expectedLength > 0 ? expectedLength : 0
            item.state = .awaitingPermission
        }
        
        let prompt = PendingDownloadPrompt(
            itemID: context.itemID,
            downloadID: downloadID,
            filename: safeName,
            sourceHost: sourceHost,
            expectedContentLength: expectedLength,
            originatingWebView: context.originatingWebView ?? download.webView,
            completion: completionHandler
        )
        pendingPrompts.append(prompt)
        processNextPromptIfIdle()
    }
    
    public func downloadDidFinish(_ download: WKDownload) {
        let downloadID = ObjectIdentifier(download)
        guard let context = contextsByDownloadID[downloadID] else { return }
        
        var finalURL = items.first(where: { $0.id == context.itemID })?.destinationURL
        var transferError: Error? = nil
        
        #if !os(macOS)
        if let tempURL = context.tempStagingURL, let targetURL = context.finalDestinationURL {
            do {
                let targetFolder = context.securityScopedFolderURL ?? targetURL.deletingLastPathComponent()
                let resolvedTarget = Self.uniqueDestinationURL(in: targetFolder, filename: targetURL.lastPathComponent)
                if FileManager.default.fileExists(atPath: resolvedTarget.path) {
                    try FileManager.default.removeItem(at: resolvedTarget)
                }
                try FileManager.default.copyItem(at: tempURL, to: resolvedTarget)
                finalURL = resolvedTarget
            } catch {
                transferError = error
            }
        }
        #endif
        
        context.releaseResources(removeTempFile: true)
        contextsByDownloadID.removeValue(forKey: downloadID)
        downloadIDByItemID.removeValue(forKey: context.itemID)
        
        if let transferError {
            updateItem(id: context.itemID) { item in
                item.state = .failed(transferError.localizedDescription)
            }
            setBannerItem(context.itemID, autoDismissAfter: nil)
            return
        }
        
        updateItem(id: context.itemID) { item in
            if let finalURL {
                item.destinationURL = finalURL
                item.destinationFolderName = finalURL.deletingLastPathComponent().lastPathComponent
            }
            item.progress = 1.0
            if item.totalBytes > 0 {
                item.completedBytes = max(item.completedBytes, item.totalBytes)
            }
            item.state = .completed
        }
        setBannerItem(context.itemID, autoDismissAfter: 6.0)
    }
    
    public func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let downloadID = ObjectIdentifier(download)
        guard let context = contextsByDownloadID[downloadID] else { return }
        
        context.releaseResources(removeTempFile: true)
        contextsByDownloadID.removeValue(forKey: downloadID)
        downloadIDByItemID.removeValue(forKey: context.itemID)
        
        let currentState = items.first(where: { $0.id == context.itemID })?.state
        guard currentState != .cancelled else { return }
        
        updateItem(id: context.itemID) { item in
            item.state = .failed(error.localizedDescription)
        }
        setBannerItem(context.itemID, autoDismissAfter: nil)
    }
    
    func updateItem(id: UUID, mutate: (inout CapsuleDownloadItem) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[idx])
    }
    
    func setBannerItem(_ id: UUID, autoDismissAfter delay: TimeInterval?) {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        activeBannerItemID = id
        if let delay {
            autoDismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                if self.activeBannerItemID == id {
                    self.activeBannerItemID = nil
                }
            }
        }
    }
}
