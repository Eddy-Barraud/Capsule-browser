//
//  CapsuleDownloadManager+Prompts.swift
//  isowebapps
//
//  Description:
//  Permission prompt queue, macOS/iOS folder pickers, and throttled `WKDownload`
//  progress observation for `CapsuleDownloadManager`.
//

import Foundation
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
import UniformTypeIdentifiers
#endif

extension CapsuleDownloadManager {
    // MARK: - Permission Prompt Queue & Platform Pickers
    
    func processNextPromptIfIdle() {
        guard !isPresentingPrompt, !pendingPrompts.isEmpty else { return }
        let next = pendingPrompts.removeFirst()
        isPresentingPrompt = true
        activePrompt = next
        presentPermissionPrompt(for: next)
    }
    
    func finishPrompt(_ prompt: PendingDownloadPrompt, destinationURL: URL?) {
        prompt.complete(with: destinationURL)
        if activePrompt === prompt {
            activePrompt = nil
        }
        isPresentingPrompt = false
        processNextPromptIfIdle()
    }
    
    func cancelPrompt(_ prompt: PendingDownloadPrompt) {
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
    
    private func startDownload(for prompt: PendingDownloadPrompt, in folderURL: URL, startedSecurityScope: Bool) {
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
    
    private func formattedPromptMessage(for prompt: PendingDownloadPrompt) -> String {
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
    
    private func presentPermissionPrompt(for prompt: PendingDownloadPrompt) {
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
    private func presentMacOSFolderPicker(for prompt: PendingDownloadPrompt) {
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
    final class IOSFolderPickerCoordinator: NSObject, UIDocumentPickerDelegate {
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
    
    private func presentIOSFolderPicker(for prompt: PendingDownloadPrompt, from presenter: UIViewController) {
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
    
    // MARK: - Throttled Progress Observation
    
    private nonisolated final class ProgressThrottleState: @unchecked Sendable {
        private let lock = NSLock()
        private var lastDispatchTime: CFAbsoluteTime = 0
        private var lastReportedFraction: Double = -1
        
        func shouldDispatch(fraction: Double, now: CFAbsoluteTime) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let dispatch = (fraction >= 1.0)
                || (abs(fraction - lastReportedFraction) >= 0.01)
                || (now - lastDispatchTime >= 0.1)
            if dispatch {
                lastDispatchTime = now
                lastReportedFraction = fraction
            }
            return dispatch
        }
    }
    
    private func attachProgressObservers(to download: WKDownload, context: DownloadContext) {
        let itemID = context.itemID
        let progress = download.progress
        let throttle = ProgressThrottleState()
        
        let applyProgress: @Sendable (Progress) -> Void = { [weak self] prog in
            let fraction = max(0, min(1, prog.fractionCompleted))
            let completed = prog.completedUnitCount
            let total = prog.totalUnitCount
            guard throttle.shouldDispatch(fraction: fraction, now: CFAbsoluteTimeGetCurrent()) else {
                return
            }
            
            Task { @MainActor [weak self] in
                self?.updateItem(id: itemID) { item in
                    guard item.state == .downloading else { return }
                    item.progress = fraction
                    item.completedBytes = completed
                    if total > 0 {
                        item.totalBytes = total
                    }
                }
            }
        }
        
        let fractionObs = progress.observe(\.fractionCompleted, options: [.new]) { prog, _ in
            applyProgress(prog)
        }
        let completedObs = progress.observe(\.completedUnitCount, options: [.new]) { prog, _ in
            applyProgress(prog)
        }
        context.progressObservations = [fractionObs, completedObs]
    }
}
