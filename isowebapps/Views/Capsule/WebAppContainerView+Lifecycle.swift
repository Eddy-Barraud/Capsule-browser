//
//  WebAppContainerView+Lifecycle.swift
//  isowebapps
//
//  Description:
//  Shared capsule lifecycle, teardown, navigation helpers, and AI summary orchestration
//  for `WebAppContainerView`.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

extension WebAppContainerView {
    func configureCommonOnAppear() {
        isSummarizationAvailable = AISummarizer.isAvailable
        navigationState.isUBlockEnabled = appItem.isUBlockEnabled
        if !hasRegisteredCapsuleInstance && appItem.modelContext != nil {
            hasRegisteredCapsuleInstance = true
            WebKitMemoryManager.shared.registerOpenCapsule(appItem: appItem)
        }
        let initialURL = initialURLString ?? appItem.lastOpenedURLString ?? appItem.urlString
        navigationState.currentURLString = initialURL
        editableURLString = initialURL
        onActiveDomainChange?(WebAppNamingHelper.domainName(from: initialURL) ?? activeDomainTitle)
    }
    
    #if os(macOS)
    func handleOpenNewWindowOrTab(url: URL) {
        let mode = MainWindowTracker.shared.currentPresentationMode
        if mode == .singleWindow {
            navigationState.onLoadURL?(url)
            return
        }
        MainWindowTracker.shared.presentCapsuleWindow(
            appId: appItem.modelContext != nil ? appItem.id : nil,
            urlString: url.absoluteString,
            name: appItem.name,
            preferredSourceWindow: hostingWindow,
            openAsTab: (mode == .tabs),
            openWindowFallback: { payload in
                openWindow(id: "capsuleWindow", value: payload)
            }
        )
    }
    
    func handleSearchInNewEphemeralCapsule(url: URL) {
        let mode = MainWindowTracker.shared.currentPresentationMode
        MainWindowTracker.shared.presentCapsuleWindow(
            appId: nil,
            urlString: url.absoluteString,
            name: "Search",
            preferredSourceWindow: hostingWindow,
            openAsTab: (mode == .tabs),
            openWindowFallback: { payload in
                openWindow(id: "capsuleWindow", value: payload)
            }
        )
    }
    #endif
    
    func handleDismiss() {
        #if os(macOS)
        if isSecondaryWindow {
            MainWindowTracker.shared.focusMainWindow()
            return
        }
        lifecycleController.handleClose()
        performFullCapsuleTeardown()
        onDismiss()
        #else
        performFullCapsuleTeardown()
        onDismiss()
        #endif
    }
    
    func performFullCapsuleTeardown() {
        guard !hasPerformedFullTeardown else { return }
        hasPerformedFullTeardown = true
        
        summaryTask?.cancel()
        summaryTask = nil
        summaryText = ""
        summaryErrorMessage = nil
        isGeneratingSummary = false
        
        #if os(macOS)
        isAwaitingRobotCheckVerification = false
        readerTask?.cancel()
        readerTask = nil
        readerCache.removeAll()
        if !isSecondaryWindow {
            MainWindowTracker.shared.mainWindowContentDismissAction = nil
        }
        #endif
        
        navigationState.onStopLoading?()
        navigationState.clearCallbacks()
        
        var remainingInstances = 0
        if hasRegisteredCapsuleInstance {
            hasRegisteredCapsuleInstance = false
            if appItem.modelContext != nil {
                remainingInstances = WebKitMemoryManager.shared.unregisterOpenCapsule(appId: appItem.id)
            }
        }
        
        if remainingInstances == 0 && appItem.deleteCookiesOnClose && appItem.modelContext != nil {
            IsolatedCookieManager.shared.clearDataInBackground(for: appItem, context: modelContext)
        }
    }
    
    func prefilledTitleForCurrentURL(_ urlString: String) -> String {
        guard let domain = WebAppNamingHelper.domainName(from: urlString) else { return "" }
        let existingNames = ((try? modelContext.fetch(FetchDescriptor<WebAppItem>())) ?? []).map { $0.name }
        return WebAppNamingHelper.uniqueTitle(for: domain, existingNames: existingNames)
    }
    
    func navigateToConfiguredHome() {
        if let homeURL = URL(string: appItem.urlString) {
            #if os(macOS)
            if isReaderModeActive {
                if startInReaderMode {
                    navigateReaderInPlace(url: homeURL)
                } else {
                    exitReaderModeAndLoadFullWebpage(overrideURL: homeURL)
                }
                return
            }
            #endif
            navigationState.onLoadURL?(homeURL)
        }
    }
    
    func toggleUBlockProtection() {
        let newState = !navigationState.isUBlockEnabled
        navigationState.isUBlockEnabled = newState
        appItem.isUBlockEnabled = newState
        try? modelContext.save()
        navigationState.onToggleUBlock?(newState)
    }
    
    #if os(iOS)
    func openCurrentInSafariReader() {
        let activeURLString = navigationState.currentURLString.isEmpty ? appItem.urlString : navigationState.currentURLString
        guard let url = URL(string: activeURLString), url.scheme?.hasPrefix("http") == true else { return }
        safariURL = IdentifiableURL(url: url, entersReader: true)
    }
    #endif
    
    func handleSummarizeTap() {
        if isShowingSummary && !isGeneratingSummary && summaryErrorMessage == nil && !summaryText.isEmpty {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isShowingSummary = false
            }
            return
        }
        startSummarization()
    }
    
    func startSummarization() {
        summaryTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isShowingSummary = true
            isGeneratingSummary = true
            summaryText = ""
            summaryErrorMessage = nil
        }
        
        summaryTask = Task { @MainActor in
            do {
                var readerDocument: ReaderDocument? = nil
                #if os(macOS)
                if isReaderModeActive, case .loaded(let doc) = readerState {
                    readerDocument = doc
                }
                #endif

                let document: ReaderDocument
                if let readerDocument {
                    document = readerDocument
                } else {
                    guard let captureBlock = navigationState.onCaptureLiveHTML else {
                        throw WebPageSummaryError.webViewUnavailable
                    }
                    let capture = try await captureBlock()
                    document = try await ReaderModeService.convertLiveCapture(capture)
                }

                let result = try await AISummarizer.shared.summarize(
                    title: document.title,
                    url: document.url.absoluteString,
                    markdownContent: document.markdown,
                    onPartialUpdate: { partial in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            self.summaryText = partial
                        }
                    }
                )

                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.summaryText = result
                    self.isGeneratingSummary = false
                }
            } catch is CancellationError {
                // Ignore cancellation
            } catch {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.summaryErrorMessage = error.localizedDescription
                    self.isGeneratingSummary = false
                }
            }
        }
    }
    
    func shareCurrentURL() {
        let activeURLString = navigationState.currentURLString.isEmpty ? appItem.urlString : navigationState.currentURLString
        guard let url = URL(string: activeURLString) else { return }
        
        #if os(iOS)
        isShowingShareSheet = true
        #else
        let picker = NSSharingServicePicker(items: [url])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
        #endif
    }
}
