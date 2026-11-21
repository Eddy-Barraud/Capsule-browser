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

/// Manages file downloads across isolated capsules, prompting for permission before saving.
@MainActor
public final class CapsuleDownloadManager: NSObject, ObservableObject, WKDownloadDelegate {
    public static let shared = CapsuleDownloadManager()
    
    @Published public private(set) var items: [CapsuleDownloadItem] = []
    @Published public var activeBannerItemID: UUID? = nil
    
    public var hasActiveDownloads: Bool {
        items.contains { $0.isActive }
    }
    
    public var activeBannerItem: CapsuleDownloadItem? {
        guard let id = activeBannerItemID else { return nil }
        return items.first { $0.id == id }
    }
    
    @MainActor
    private final class DownloadContext {
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
    private final class PendingPrompt {
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
    
    private var contextsByDownloadID: [ObjectIdentifier: DownloadContext] = [:]
    private var downloadIDByItemID: [UUID: ObjectIdentifier] = [:]
    private var pendingPrompts: [PendingPrompt] = []
    private var activePrompt: PendingPrompt?
    private var isPresentingPrompt = false
    private var autoDismissTask: Task<Void, Never>?
    
    #if !os(macOS)
    private var activeFolderPickerCoordinator: IOSFolderPickerCoordinator?
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
        
        let prompt = PendingPrompt(
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
    
    // MARK: - Permission Prompt Queue & Platform Pickers
    
    private func processNextPromptIfIdle() {
        guard !isPresentingPrompt, !pendingPrompts.isEmpty else { return }
        let next = pendingPrompts.removeFirst()
        isPresentingPrompt = true
        activePrompt = next
        presentPermissionPrompt(for: next)
    }
    
    private func finishPrompt(_ prompt: PendingPrompt, destinationURL: URL?) {
        prompt.complete(with: destinationURL)
        if activePrompt === prompt {
            activePrompt = nil
        }
        isPresentingPrompt = false
        processNextPromptIfIdle()
    }
    
    private func cancelPrompt(_ prompt: PendingPrompt) {
        updateItem(id: prompt.itemID) { item in
            item.state = .cancelled
        }
        if let context = contextsByDownloadID[prompt.downloadID] {
            context.releaseResources(removeTempFile: true)
            contextsByDownloadID.removeValue(forKey: prompt.downloadID)
            downloadIDByItemID.removeValue(forKey: prompt.itemID)
        }
        items.removeAll { $0.id == prompt.itemID }
        finishPrompt(prompt, destinationURL: nil)
    }
    
    private func startDownload(for prompt: PendingPrompt, in folderURL: URL, startedSecurityScope: Bool) {
        guard let context = contextsByDownloadID[prompt.downloadID],
              let download = context.download else {
            if startedSecurityScope {
                folderURL.stopAccessingSecurityScopedResource()
            }
            cancelPrompt(prompt)
            return
        }
        
        #if os(macOS)
        let destURL = Self.uniqueDestinationURL(in: folderURL, filename: prompt.filename)
        context.securityScopedFolderURL = folderURL
        context.didStartSecurityScopedAccess = startedSecurityScope
        context.finalDestinationURL = destURL
        let folderName = folderURL.lastPathComponent.isEmpty ? "Downloads" : folderURL.lastPathComponent
        updateItem(id: prompt.itemID) { item in
            item.destinationURL = destURL
            item.destinationFolderName = folderName
            item.state = .downloading
        }
        attachProgressObservers(to: download, context: context)
        setBannerItem(prompt.itemID, autoDismissAfter: nil)
        finishPrompt(prompt, destinationURL: destURL)
        #else
        if startedSecurityScope {
            // Stage inside temporary directory so WebKit's download XPC process can write cleanly,
            // then copy into the security-scoped custom folder inside `downloadDidFinish`.
            let tempDir = FileManager.default.temporaryDirectory
            let stagedURL = Self.uniqueDestinationURL(in: tempDir, filename: prompt.filename)
            let finalURL = Self.uniqueDestinationURL(in: folderURL, filename: prompt.filename)
            context.securityScopedFolderURL = folderURL
            context.didStartSecurityScopedAccess = true
            context.tempStagingURL = stagedURL
            context.finalDestinationURL = finalURL
            let folderName = folderURL.lastPathComponent.isEmpty ? "Selected Folder" : folderURL.lastPathComponent
            updateItem(id: prompt.itemID) { item in
                item.destinationURL = finalURL
                item.destinationFolderName = folderName
                item.state = .downloading
            }
            attachProgressObservers(to: download, context: context)
            setBannerItem(prompt.itemID, autoDismissAfter: nil)
            finishPrompt(prompt, destinationURL: stagedURL)
        } else {
            let destURL = Self.uniqueDestinationURL(in: folderURL, filename: prompt.filename)
            context.finalDestinationURL = destURL
            let folderName = folderURL.lastPathComponent.isEmpty ? "Downloads" : folderURL.lastPathComponent
            updateItem(id: prompt.itemID) { item in
                item.destinationURL = destURL
                item.destinationFolderName = folderName
                item.state = .downloading
            }
            attachProgressObservers(to: download, context: context)
            setBannerItem(prompt.itemID, autoDismissAfter: nil)
            finishPrompt(prompt, destinationURL: destURL)
        }
        #endif
    }
    
    private func formattedPromptMessage(for prompt: PendingPrompt) -> String {
        var lines: [String] = [
            "Do you want to download \"\(prompt.filename)\" from \(prompt.sourceHost)?"
        ]
        if prompt.expectedContentLength > 0 {
            let formattedSize = ByteCountFormatter.string(
                fromByteCount: prompt.expectedContentLength,
                countStyle: .file
            )
            lines.append("Size: \(formattedSize)")
        }
        lines.append("Default folder: Downloads")
        return lines.joined(separator: "\n")
    }
    
    private func presentPermissionPrompt(for prompt: PendingPrompt) {
        #if os(macOS)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Allow Download?"
        alert.informativeText = formattedPromptMessage(for: prompt)
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Choose Folder…")
        alert.addButton(withTitle: "Cancel")
        
        let handleAlertResponse: @MainActor (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                guard let downloadsDir = Self.defaultDownloadsDirectory() else {
                    self.cancelPrompt(prompt)
                    return
                }
                self.startDownload(for: prompt, in: downloadsDir, startedSecurityScope: false)
            case .alertSecondButtonReturn:
                self.presentMacOSFolderPicker(for: prompt)
            default:
                self.cancelPrompt(prompt)
            }
        }
        
        if let hostWindow = prompt.originatingWebView?.window,
           hostWindow.isVisible,
           hostWindow.attachedSheet == nil {
            alert.beginSheetModal(for: hostWindow) { response in
                MainActor.assumeIsolated {
                    handleAlertResponse(response)
                }
            }
        } else {
            let response = alert.runModal()
            handleAlertResponse(response)
        }
        #else
        guard let presenter = Self.topViewController(for: prompt.originatingWebView) else {
            cancelPrompt(prompt)
            return
        }
        
        let alert = UIAlertController(
            title: "Allow Download?",
            message: formattedPromptMessage(for: prompt),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Download", style: .default) { [weak self] _ in
            guard let self else { return }
            guard let downloadsDir = Self.defaultDownloadsDirectory() else {
                self.cancelPrompt(prompt)
                return
            }
            self.startDownload(for: prompt, in: downloadsDir, startedSecurityScope: false)
        })
        alert.addAction(UIAlertAction(title: "Choose Folder…", style: .default) { [weak self] _ in
            self?.presentIOSFolderPicker(for: prompt, from: presenter)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.cancelPrompt(prompt)
        })
        presenter.present(alert, animated: true)
        #endif
    }
    
    #if os(macOS)
    private func presentMacOSFolderPicker(for prompt: PendingPrompt) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = Self.defaultDownloadsDirectory()
        panel.prompt = "Download Here"
        panel.message = "Choose a folder to save \"\(prompt.filename)\""
        
        let handlePanelResponse: @MainActor (NSApplication.ModalResponse) -> Void = { [weak self] result in
            guard let self else { return }
            if result == .OK, let folderURL = panel.url {
                let didStart = folderURL.startAccessingSecurityScopedResource()
                self.startDownload(for: prompt, in: folderURL, startedSecurityScope: didStart)
            } else {
                self.cancelPrompt(prompt)
            }
        }
        
        if let hostWindow = prompt.originatingWebView?.window,
           hostWindow.isVisible,
           hostWindow.attachedSheet == nil {
            panel.beginSheetModal(for: hostWindow) { result in
                MainActor.assumeIsolated {
                    handlePanelResponse(result)
                }
            }
        } else {
            let result = panel.runModal()
            handlePanelResponse(result)
        }
    }
    #else
    @MainActor
    private final class IOSFolderPickerCoordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: @MainActor (URL?) -> Void
        
        init(onPick: @escaping @MainActor (URL?) -> Void) {
            self.onPick = onPick
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            MainActor.assumeIsolated {
                onPick(urls.first)
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            MainActor.assumeIsolated {
                onPick(nil)
            }
        }
    }
    
    private func presentIOSFolderPicker(for prompt: PendingPrompt, from presenter: UIViewController) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.directoryURL = Self.defaultDownloadsDirectory()
        
        let coordinator = IOSFolderPickerCoordinator { [weak self] folderURL in
            guard let self else { return }
            self.activeFolderPickerCoordinator = nil
            if let folderURL {
                let didStart = folderURL.startAccessingSecurityScopedResource()
                self.startDownload(for: prompt, in: folderURL, startedSecurityScope: didStart)
            } else {
                self.cancelPrompt(prompt)
            }
        }
        activeFolderPickerCoordinator = coordinator
        picker.delegate = coordinator
        presenter.present(picker, animated: true)
    }
    
    private static func topViewController(for webView: WKWebView?) -> UIViewController? {
        let rootVC: UIViewController? = {
            if let vc = webView?.window?.rootViewController {
                return vc
            }
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let foregroundScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            return foregroundScene?.windows.first(where: \.isKeyWindow)?.rootViewController
                ?? foregroundScene?.windows.first?.rootViewController
        }()
        var current = rootVC
        while let presented = current?.presentedViewController {
            current = presented
        }
        return current
    }
    #endif
    
    // MARK: - Progress Observation & State Updates
    
    private func attachProgressObservers(to download: WKDownload, context: DownloadContext) {
        let itemID = context.itemID
        let progress = download.progress
        
        let fractionObs = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] prog, _ in
            let fraction = prog.fractionCompleted
            let completed = prog.completedUnitCount
            let total = prog.totalUnitCount
            Task { @MainActor [weak self] in
                self?.updateItem(id: itemID) { item in
                    guard item.state == .downloading else { return }
                    item.progress = max(0, min(1, fraction))
                    item.completedBytes = completed
                    if total > 0 {
                        item.totalBytes = total
                    }
                }
            }
        }
        let completedObs = progress.observe(\.completedUnitCount, options: [.new]) { [weak self] prog, _ in
            let fraction = prog.fractionCompleted
            let completed = prog.completedUnitCount
            let total = prog.totalUnitCount
            Task { @MainActor [weak self] in
                self?.updateItem(id: itemID) { item in
                    guard item.state == .downloading else { return }
                    item.progress = max(0, min(1, fraction))
                    item.completedBytes = completed
                    if total > 0 {
                        item.totalBytes = total
                    }
                }
            }
        }
        context.progressObservations = [fractionObs, completedObs]
    }
    
    private func updateItem(id: UUID, mutate: (inout CapsuleDownloadItem) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[idx])
    }
    
    private func setBannerItem(_ id: UUID, autoDismissAfter delay: TimeInterval?) {
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
