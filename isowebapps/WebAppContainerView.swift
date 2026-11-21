//
//  WebAppContainerView.swift
//  isowebapps
//
//  Created on 23/08/2026.
//
//  Description:
//  The active isolated web container view. Embeds `IsolatedWebViewRepresentable`,
//  handles back/forward navigation state via `WebViewNavigationState`, manages
//  the platform-specific bottom navigation bars (solid native toolbar on macOS,
//  floating Liquid Glass on iOS), URL expansion/search, and immediate dismiss teardown.
//

import SwiftUI
import WebKit
import SwiftData
import Combine

/// Observable navigation state passed between SwiftUI toolbars and the WKWebView coordinator
class WebViewNavigationState: ObservableObject {
    @Published var currentURLString: String = ""
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var isUBlockEnabled: Bool = true
    
    var onGoBack: (() -> Void)?
    var onGoForward: (() -> Void)?
    var onReload: (() -> Void)?
    var onLoadURL: ((URL) -> Void)?
    var onStopLoading: (() -> Void)?
    var onToggleUBlock: ((Bool) -> Void)?
    var onOpenSafari: ((URL) -> Void)?
    var onOpenSafariReader: ((URL) -> Void)?
    var onCaptureFirstPagePDFText: (() async throws -> (title: String, url: String, text: String))?
    var onOpenNewWindowOrTab: ((URL) -> Void)?
    #if os(macOS)
    @Published var isReaderModeActive: Bool = false
    var webViewCommitGeneration: Int = 0
    var webViewFinishGeneration: Int = 0
    var currentBackgroundWebViewURL: URL? = nil
    var lastBackgroundLoadError: String? = nil
    var onCaptureLiveHTML: (() async throws -> ReaderHTMLCapture)?
    var onSetReaderMediaSuspended: ((Bool) -> Void)?
    #endif
    
    func clearCallbacks() {
        onGoBack = nil
        onGoForward = nil
        onReload = nil
        onLoadURL = nil
        onStopLoading = nil
        onToggleUBlock = nil
        onOpenSafari = nil
        onOpenSafariReader = nil
        onCaptureFirstPagePDFText = nil
        onOpenNewWindowOrTab = nil
        #if os(macOS)
        onCaptureLiveHTML = nil
        onSetReaderMediaSuspended = nil
        #endif
    }
}

struct WebAppContainerView: View {
    let appItem: WebAppItem
    var initialURLString: String? = nil
    var isSecondaryWindow: Bool = false
    var startInReaderMode: Bool = false
    var onActiveDomainChange: ((String) -> Void)? = nil
    let onDismiss: () -> Void
    
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @State private var hostingWindowBox = WeakWindowBox()
    private var hostingWindow: NSWindow? { hostingWindowBox.window }
    @State private var isReaderModeActive: Bool
    @State private var hasMountedWebView: Bool
    @State private var deferredWebViewInitialURL: String? = nil
    @State private var readerState: ReaderViewState = .idle
    @State private var readerTask: Task<Void, Never>? = nil
    @State private var readerHistory = ReaderHistoryStack()
    @State private var readerCache: [URL: ReaderDocument] = [:]
    @State private var webViewURLBeforeReader: String? = nil
    @State private var isAwaitingRobotCheckVerification: Bool = false
    
    private var shouldShowReaderOverlay: Bool {
        isReaderModeActive && !isAwaitingRobotCheckVerification
    }
    #endif
    
    @Environment(\.modelContext) private var modelContext
    @StateObject private var navigationState = WebViewNavigationState()
    @ObservedObject private var downloadManager = CapsuleDownloadManager.shared
    @State private var isShowingDownloadsPopover = false
    
    init(
        appItem: WebAppItem,
        initialURLString: String? = nil,
        isSecondaryWindow: Bool = false,
        startInReaderMode: Bool = false,
        onActiveDomainChange: ((String) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.appItem = appItem
        self.initialURLString = initialURLString
        self.isSecondaryWindow = isSecondaryWindow
        self.startInReaderMode = startInReaderMode
        self.onActiveDomainChange = onActiveDomainChange
        self.onDismiss = onDismiss
        #if os(macOS)
        _isReaderModeActive = State(initialValue: startInReaderMode)
        _hasMountedWebView = State(initialValue: !startInReaderMode)
        #endif
    }
    
    private var activeDomainTitle: String {
        let urlStr = !navigationState.currentURLString.isEmpty && navigationState.currentURLString != "about:blank"
            ? navigationState.currentURLString
            : (initialURLString ?? appItem.lastOpenedURLString ?? appItem.urlString)
        return WebAppNamingHelper.domainName(from: urlStr) ?? appItem.name
    }
    @State private var isURLExpanded = false
    @State private var isShowingShareSheet = false
    @State private var editableURLString: String = ""
    @State private var isShowingAddSheet = false
    
    // AI Summarization State
    @State private var isShowingSummary = false
    @State private var isGeneratingSummary = false
    @State private var isSummarizationAvailable = AISummarizer.isAvailable
    @State private var summaryText = ""
    @State private var summaryErrorMessage: String? = nil
    @State private var summaryTask: Task<Void, Never>? = nil
    @State private var safariURL: IdentifiableURL? = nil
    
    var body: some View {
        Group {
            #if os(macOS)
            GeometryReader { geo in
            HStack(spacing: 0) {
                if isShowingSummary {
                    SummaryDropdownView(
                        isGenerating: isGeneratingSummary,
                        summaryText: summaryText,
                        errorMessage: summaryErrorMessage,
                        onClose: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isShowingSummary = false
                            }
                        },
                        onRegenerate: {
                            startSummarization()
                        }
                    )
                    .frame(width: max(300, min(400, geo.size.width * 0.25)))
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(10)
                    
                    Divider()
                }
                
                VStack(spacing: 0) {
                    // Top Bar with Shield toggle, Summarize button, and Tiles/Home button
                    TopControlsBar(
                        appItem: appItem,
                        navigationState: navigationState,
                        downloadManager: downloadManager,
                        isShowingDownloadsPopover: $isShowingDownloadsPopover,
                        isGeneratingSummary: isGeneratingSummary,
                        isSummarizationAvailable: isSummarizationAvailable,
                        isSecondaryWindow: isSecondaryWindow,
                        isReaderModeActive: isReaderModeActive,
                        onDismiss: handleDismiss,
                        onToggleShield: toggleUBlockProtection,
                        onSummarize: handleSummarizeTap,
                        onOpenInReader: toggleReaderMode,
                        onAddCapsule: {
                            isShowingAddSheet = true
                        }
                    )
                    
                    Divider()
                    
                    if isAwaitingRobotCheckVerification {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.orange)
                            Text("Verification required — complete the check below to continue loading in Reader View.")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Button("Stay on Full Page") {
                                exitReaderModeAndLoadFullWebpage()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.12))
                        
                        Divider()
                    }
                    
                    // Web View + In-App Markdown Reader Content
                    ZStack {
                        if hasMountedWebView {
                            IsolatedWebViewRepresentable(
                                appItem: appItem,
                                initialURLString: deferredWebViewInitialURL ?? initialURLString,
                                navigationState: navigationState,
                                modelContext: modelContext,
                                onOpenNewWindowOrTab: { url in
                                    handleOpenNewWindowOrTab(url: url)
                                },
                                onSearchInNewEphemeralCapsule: { url in
                                    handleSearchInNewEphemeralCapsule(url: url)
                                }
                            )
                            .opacity(shouldShowReaderOverlay ? 0 : 1)
                            .allowsHitTesting(!shouldShowReaderOverlay)
                            .accessibilityHidden(shouldShowReaderOverlay)
                            .onTapGesture {
                                if isURLExpanded {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        isURLExpanded = false
                                    }
                                }
                            }
                        }
                        
                        if shouldShowReaderOverlay {
                            MarkdownReaderView(
                                state: readerState,
                                onOpenLinkInPlace: { url in
                                    navigateReaderInPlace(url: url)
                                },
                                onOpenLinkInNewReader: { url in
                                    handleOpenInReaderCapsule(url: url)
                                },
                                onLoadFullWebpage: {
                                    exitReaderModeAndLoadFullWebpage()
                                },
                                onRetry: {
                                    reloadActiveReader()
                                }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    if let bannerItem = downloadManager.activeBannerItem {
                        Divider()
                        DownloadBannerView(
                            item: bannerItem,
                            onCancel: {
                                downloadManager.cancelDownload(id: bannerItem.id)
                            },
                            onReveal: {
                                downloadManager.revealInFinder(id: bannerItem.id)
                            },
                            onDismiss: {
                                downloadManager.dismissBanner()
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    Divider()
                    
                    // Solid Bottom Bar on macOS (Home button navigates to configured home URL)
                    MacOSSolidBottomBar(
                        navigationState: navigationState,
                        isURLExpanded: $isURLExpanded,
                        editableURLString: $editableURLString,
                        onGoHome: navigateToConfiguredHome,
                        onShare: shareCurrentURL,
                        canGoBackOverride: isReaderModeActive ? readerHistory.canGoBack : nil,
                        canGoForwardOverride: isReaderModeActive ? readerHistory.canGoForward : nil,
                        onGoBackOverride: isReaderModeActive ? { navigateReaderBack() } : nil,
                        onGoForwardOverride: isReaderModeActive ? { navigateReaderForward() } : nil,
                        onReloadOverride: isReaderModeActive ? { reloadActiveReader() } : nil,
                        onSubmitRawInput: isReaderModeActive ? { rawInput in handleReaderAddressSubmit(rawInput) } : nil
                    )
                }
                .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            isSummarizationAvailable = AISummarizer.isAvailable
            navigationState.isUBlockEnabled = appItem.isUBlockEnabled
            navigationState.isReaderModeActive = isReaderModeActive
            let initialURL = initialURLString ?? appItem.lastOpenedURLString ?? appItem.urlString
            navigationState.currentURLString = initialURL
            editableURLString = initialURL
            if let domain = WebAppNamingHelper.domainName(from: initialURL) {
                onActiveDomainChange?(domain)
            } else {
                onActiveDomainChange?(activeDomainTitle)
            }
            
            navigationState.onOpenSafari = { url in
                NSWorkspace.shared.open(url)
            }
            navigationState.onOpenSafariReader = { url in
                handleOpenInReaderCapsule(url: url)
            }
            navigationState.onOpenNewWindowOrTab = { url in
                handleOpenNewWindowOrTab(url: url)
            }
            #if os(macOS)
            if MainWindowTracker.shared.openWindowAction == nil {
                MainWindowTracker.shared.openWindowAction = { payload in
                    openWindow(id: "capsuleWindow", value: payload)
                }
            }
            if startInReaderMode, case .idle = readerState {
                if let targetURL = URL(string: initialURL) {
                    readerHistory.reset(to: targetURL)
                    loadFastReader(url: targetURL, bypassCache: false)
                } else {
                    readerState = .failed(message: ReaderModeError.invalidURL.localizedDescription, url: nil)
                }
            }
            #endif
        }
        .onChange(of: navigationState.currentURLString) { _, newURL in
            if !isURLExpanded && !newURL.isEmpty && newURL != "about:blank" {
                editableURLString = newURL
            }
            if let domain = WebAppNamingHelper.domainName(from: newURL) {
                onActiveDomainChange?(domain)
            }
            if isShowingSummary {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isShowingSummary = false
                }
                summaryText = ""
                summaryErrorMessage = nil
                isGeneratingSummary = false
                summaryTask?.cancel()
            }
        }
        .onDisappear {
            if isSecondaryWindow {
                // Secondary tabs/windows remain alive in the background; do not stop loading or blank the web view
                return
            }
            summaryTask?.cancel()
            readerTask?.cancel()
            readerCache.removeAll()
            summaryText = ""
            summaryErrorMessage = nil
            isGeneratingSummary = false
            navigationState.onStopLoading?()
        }
        .sheet(isPresented: $isShowingAddSheet) {
            let activeURLString = navigationState.currentURLString.isEmpty ? appItem.urlString : navigationState.currentURLString
            let prefilledTitle = prefilledTitleForCurrentURL(activeURLString)
            AddWebAppSheet(initialURLString: activeURLString, initialName: prefilledTitle)
        }
        #else
        VStack(spacing: 0) {
            // Top Bar with Shield toggle, Summarize button, and Tiles/Home button
            TopControlsBar(
                appItem: appItem,
                navigationState: navigationState,
                downloadManager: downloadManager,
                isShowingDownloadsPopover: $isShowingDownloadsPopover,
                isGeneratingSummary: isGeneratingSummary,
                isSummarizationAvailable: isSummarizationAvailable,
                isSecondaryWindow: isSecondaryWindow,
                onDismiss: handleDismiss,
                onToggleShield: toggleUBlockProtection,
                onSummarize: handleSummarizeTap,
                onOpenInReader: openCurrentInSafariReader,
                onAddCapsule: {
                    isShowingAddSheet = true
                }
            )
            
            // Dropdown AI Summary section directly below top bar
            if isShowingSummary {
                SummaryDropdownView(
                    isGenerating: isGeneratingSummary,
                    summaryText: summaryText,
                    errorMessage: summaryErrorMessage,
                    onClose: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isShowingSummary = false
                        }
                    },
                    onRegenerate: {
                        startSummarization()
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
                
                Divider()
            }
            
            Divider()
            
            // Web View Content
            IsolatedWebViewRepresentable(
                appItem: appItem,
                initialURLString: initialURLString,
                navigationState: navigationState,
                modelContext: modelContext
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture {
                // Tap anywhere on the page outside the URL field to collapse it
                if isURLExpanded {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isURLExpanded = false
                    }
                }
            }
            
            if let bannerItem = downloadManager.activeBannerItem {
                Divider()
                DownloadBannerView(
                    item: bannerItem,
                    onCancel: {
                        downloadManager.cancelDownload(id: bannerItem.id)
                    },
                    onReveal: {},
                    onDismiss: {
                        downloadManager.dismissBanner()
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            Divider()
            
            // Solid Bottom Bar on iOS
            IOSSolidBottomBar(
                navigationState: navigationState,
                isURLExpanded: $isURLExpanded,
                editableURLString: $editableURLString,
                onGoHome: navigateToConfiguredHome,
                onShare: shareCurrentURL
            )
        }
        .ignoresSafeArea(.keyboard, edges: isURLExpanded ? [] : .bottom)
        #if os(iOS)
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .global)
                .onEnded { value in
                    if !navigationState.canGoBack && value.startLocation.x < 30 && value.translation.width > 40 {
                        handleDismiss()
                    }
                }
        )
        #endif
        .onAppear {
            isSummarizationAvailable = AISummarizer.isAvailable
            navigationState.isUBlockEnabled = appItem.isUBlockEnabled
            let initialURL = initialURLString ?? appItem.lastOpenedURLString ?? appItem.urlString
            navigationState.currentURLString = initialURL
            editableURLString = initialURL
            onActiveDomainChange?(activeDomainTitle)
            
            navigationState.onOpenSafari = { url in
                #if os(iOS)
                safariURL = IdentifiableURL(url: url, entersReader: false)
                #else
                NSWorkspace.shared.open(url)
                #endif
            }
            navigationState.onOpenSafariReader = { url in
                #if os(iOS)
                safariURL = IdentifiableURL(url: url, entersReader: true)
                #else
                NSWorkspace.shared.open(url)
                #endif
            }
        }
        .onChange(of: navigationState.currentURLString) { _, newURL in
            if !isURLExpanded && !newURL.isEmpty && newURL != "about:blank" {
                editableURLString = newURL
            }
            if let domain = WebAppNamingHelper.domainName(from: newURL) {
                onActiveDomainChange?(domain)
            }
            if isShowingSummary {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isShowingSummary = false
                }
                summaryText = ""
                summaryErrorMessage = nil
                isGeneratingSummary = false
                summaryTask?.cancel()
            }
        }
        .onDisappear {
            summaryTask?.cancel()
            summaryText = ""
            summaryErrorMessage = nil
            isGeneratingSummary = false
            navigationState.onStopLoading?()
        }
        .sheet(isPresented: $isShowingAddSheet) {
            let activeURLString = navigationState.currentURLString.isEmpty ? appItem.urlString : navigationState.currentURLString
            let prefilledTitle = prefilledTitleForCurrentURL(activeURLString)
            AddWebAppSheet(initialURLString: activeURLString, initialName: prefilledTitle)
        }
        .sheet(isPresented: $isShowingShareSheet) {
            if let url = URL(string: navigationState.currentURLString.isEmpty ? appItem.urlString : navigationState.currentURLString) {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(item: $safariURL) { item in
            SafariView(url: item.url, entersReaderIfAvailable: item.entersReader)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $isShowingDownloadsPopover) {
            NavigationStack {
                DownloadsListView(downloadManager: downloadManager)
                    .navigationTitle("Downloads")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                isShowingDownloadsPopover = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        #endif
        }
        .navigationTitle(activeDomainTitle)
        #if os(macOS)
        .background(
            WindowAccessor { window in
                if hostingWindowBox.window !== window {
                    hostingWindowBox.window = window
                }
                if window.title != activeDomainTitle {
                    window.title = activeDomainTitle
                }
                if window.tab.title != activeDomainTitle {
                    window.tab.title = activeDomainTitle
                }
            }
        )
        #endif
    }
    
    #if os(macOS)
    private func handleOpenNewWindowOrTab(url: URL) {
        let modeRaw = UserDefaults.standard.string(forKey: "windowPresentationMode") ?? "singleWindow"
        let mode = WindowPresentationMode(rawValue: modeRaw) ?? .singleWindow
        #if DEBUG
        print("[WebAppContainerView] handleOpenNewWindowOrTab url: \(url), mode: \(mode)")
        #endif
        
        switch mode {
        case .tabs:
            let sourceWin = MainWindowTracker.shared.resolveSourceWindow(
                preferred: hostingWindow,
                includeFallbackTarget: true
            )
            if let win = sourceWin {
                MainWindowTracker.shared.persistWindowSize(from: win)
            }
            let payload = CapsuleWindowPayload(
                appId: appItem.modelContext != nil ? appItem.id : nil,
                urlString: url.absoluteString,
                name: appItem.name,
                isSecondaryWindow: true,
                openAsTab: true,
                sourceWindowNumber: sourceWin?.windowNumber,
                sourceFrame: sourceWin?.serializedFrame
            )
            if MainWindowTracker.shared.openWindowAction != nil {
                MainWindowTracker.shared.openNewTab(with: payload, from: sourceWin)
            } else {
                if let win = sourceWin {
                    MainWindowTracker.shared.armPendingTabTarget(win)
                }
                openWindow(id: "capsuleWindow", value: payload)
            }
        case .separateWindows:
            let sourceWin = MainWindowTracker.shared.resolveSourceWindow(
                preferred: hostingWindow,
                includeFallbackTarget: false
            )
            if let win = sourceWin {
                MainWindowTracker.shared.persistWindowSize(from: win)
            }
            let payload = CapsuleWindowPayload(
                appId: appItem.modelContext != nil ? appItem.id : nil,
                urlString: url.absoluteString,
                name: appItem.name,
                isSecondaryWindow: true,
                openAsTab: false,
                sourceWindowNumber: sourceWin?.windowNumber,
                sourceFrame: sourceWin?.serializedFrame
            )
            openWindow(id: "capsuleWindow", value: payload)
        case .singleWindow:
            navigationState.onLoadURL?(url)
        }
    }
    
    private func handleSearchInNewEphemeralCapsule(url: URL) {
        let modeRaw = UserDefaults.standard.string(forKey: "windowPresentationMode") ?? "singleWindow"
        let mode = WindowPresentationMode(rawValue: modeRaw) ?? .singleWindow
        let openAsTab = (mode == .tabs)
        let sourceWin = MainWindowTracker.shared.resolveSourceWindow(
            preferred: hostingWindow,
            includeFallbackTarget: openAsTab
        )
        if let win = sourceWin {
            MainWindowTracker.shared.persistWindowSize(from: win)
        }
        let payload = CapsuleWindowPayload(
            appId: nil,
            urlString: url.absoluteString,
            name: "Search",
            isSecondaryWindow: true,
            openAsTab: openAsTab,
            sourceWindowNumber: sourceWin?.windowNumber,
            sourceFrame: sourceWin?.serializedFrame
        )
        if openAsTab {
            if MainWindowTracker.shared.openWindowAction != nil {
                MainWindowTracker.shared.openNewTab(with: payload, from: sourceWin)
            } else {
                if let win = sourceWin {
                    MainWindowTracker.shared.armPendingTabTarget(win)
                }
                openWindow(id: "capsuleWindow", value: payload)
            }
        } else {
            openWindow(id: "capsuleWindow", value: payload)
        }
    }
    
    // MARK: - macOS In-App Reader Mode Helpers
    
    private func handleOpenInReaderCapsule(url: URL) {
        let modeRaw = UserDefaults.standard.string(forKey: "windowPresentationMode") ?? "singleWindow"
        let mode = WindowPresentationMode(rawValue: modeRaw) ?? .singleWindow
        let openAsTab = (mode == .tabs)
        let sourceWin = MainWindowTracker.shared.resolveSourceWindow(
            preferred: hostingWindow,
            includeFallbackTarget: openAsTab
        )
        if let win = sourceWin {
            MainWindowTracker.shared.persistWindowSize(from: win)
        }
        let payload = CapsuleWindowPayload(
            appId: nil,
            urlString: url.absoluteString,
            name: WebAppNamingHelper.domainName(from: url.absoluteString) ?? "Reader",
            isSecondaryWindow: true,
            openAsTab: openAsTab,
            startInReaderMode: true,
            sourceWindowNumber: sourceWin?.windowNumber,
            sourceFrame: sourceWin?.serializedFrame
        )
        if openAsTab {
            if MainWindowTracker.shared.openWindowAction != nil {
                MainWindowTracker.shared.openNewTab(with: payload, from: sourceWin)
            } else {
                if let win = sourceWin {
                    MainWindowTracker.shared.armPendingTabTarget(win)
                }
                openWindow(id: "capsuleWindow", value: payload)
            }
        } else {
            openWindow(id: "capsuleWindow", value: payload)
        }
    }
    
    private func toggleReaderMode() {
        if isReaderModeActive {
            exitReaderModeAndLoadFullWebpage()
        } else {
            activateReaderFromLiveWebView()
        }
    }
    
    private func activateReaderFromLiveWebView() {
        let activeURLString = navigationState.currentURLString.isEmpty ? appItem.urlString : navigationState.currentURLString
        let currentURL = URL(string: activeURLString)
        webViewURLBeforeReader = activeURLString
        isAwaitingRobotCheckVerification = false
        isReaderModeActive = true
        navigationState.isReaderModeActive = true
        navigationState.onSetReaderMediaSuspended?(true)
        if let currentURL {
            readerHistory.reset(to: currentURL)
        }
        
        readerTask?.cancel()
        readerState = .loading(currentURL, statusMessage: "Loading Reader View…")
        navigationState.isLoading = true
        
        readerTask = Task { @MainActor in
            do {
                guard let captureBlock = navigationState.onCaptureLiveHTML else {
                    throw ReaderModeError.conversionFailed("Web view capture handler unavailable.")
                }
                let capture = try await captureBlock()
                try Task.checkCancellation()
                if ReaderHTMLUtilities.evaluateBackgroundCaptureReadiness(capture) == .requiresHumanVerification {
                    let verifyURL = URL(string: capture.urlString) ?? currentURL ?? URL(string: "https://example.com")!
                    throw ReaderModeError.humanVerificationRequired(verifyURL)
                }
                let document = try await ReaderModeService.convertLiveCapture(capture)
                try Task.checkCancellation()
                applyLoadedReaderDocument(document, requestedURL: currentURL)
            } catch is CancellationError {
                // Ignore cancellation
            } catch {
                readerState = .failed(message: error.localizedDescription, url: currentURL)
                navigationState.isLoading = false
            }
        }
    }
    
    private func exitReaderModeAndLoadFullWebpage(overrideURL: URL? = nil) {
        let wasAwaitingVerification = isAwaitingRobotCheckVerification
        isAwaitingRobotCheckVerification = false
        readerTask?.cancel()
        readerTask = nil
        navigationState.isLoading = false
        isReaderModeActive = false
        navigationState.isReaderModeActive = false
        
        if wasAwaitingVerification && overrideURL == nil {
            navigationState.onSetReaderMediaSuspended?(false)
            return
        }
        
        let targetURL = overrideURL
            ?? readerHistory.currentURL
            ?? URL(string: navigationState.currentURLString.isEmpty ? appItem.urlString : navigationState.currentURLString)
        
        guard let targetURL else { return }
        
        if !hasMountedWebView {
            deferredWebViewInitialURL = targetURL.absoluteString
            navigationState.currentURLString = targetURL.absoluteString
            editableURLString = targetURL.absoluteString
            hasMountedWebView = true
            return
        }
        
        navigationState.onSetReaderMediaSuspended?(false)
        
        if overrideURL != nil || targetURL.absoluteString != webViewURLBeforeReader {
            navigationState.currentURLString = targetURL.absoluteString
            editableURLString = targetURL.absoluteString
            navigationState.onLoadURL?(targetURL)
        }
    }
    
    private func navigateReaderInPlace(url: URL) {
        readerHistory.push(url)
        loadFastReader(url: url, bypassCache: false)
    }
    
    private func navigateReaderBack() {
        guard let previousURL = readerHistory.goBack() else { return }
        loadFastReader(url: previousURL, bypassCache: false)
    }
    
    private func navigateReaderForward() {
        guard let nextURL = readerHistory.goForward() else { return }
        loadFastReader(url: nextURL, bypassCache: false)
    }
    
    private func reloadActiveReader() {
        let activeURL = readerHistory.currentURL
            ?? URL(string: navigationState.currentURLString.isEmpty ? appItem.urlString : navigationState.currentURLString)
        if hasMountedWebView, let activeURL, activeURL.absoluteString == webViewURLBeforeReader {
            if !startInReaderMode {
                activateReaderFromLiveWebView()
            } else {
                loadFastReader(url: activeURL, bypassCache: true)
            }
            return
        }
        if let activeURL {
            loadFastReader(url: activeURL, bypassCache: true)
        }
    }
    
    private func handleReaderAddressSubmit(_ rawInput: String) {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let resolved = SearchEngine.resolveInput(trimmed),
              let url = URL(string: resolved) else { return }
        if ReaderHTMLUtilities.isLikelyDirectURLInput(trimmed) {
            navigateReaderInPlace(url: url)
        } else {
            exitReaderModeAndLoadFullWebpage(overrideURL: url)
        }
    }
    
    private func applyLoadedReaderDocument(_ document: ReaderDocument, requestedURL: URL?) {
        cacheReaderDocument(document, requestedURL: requestedURL)
        readerHistory.replaceCurrent(with: document.url)
        navigationState.currentURLString = document.url.absoluteString
        editableURLString = document.url.absoluteString
        if document.source == .liveWebView {
            webViewURLBeforeReader = document.url.absoluteString
        }
        if let domain = WebAppNamingHelper.domainName(from: document.url.absoluteString) {
            onActiveDomainChange?(domain)
        }
        readerState = .loaded(document)
        navigationState.isLoading = false
    }
    
    private func loadFastReader(url: URL, bypassCache: Bool) {
        readerTask?.cancel()
        isAwaitingRobotCheckVerification = false
        navigationState.currentURLString = url.absoluteString
        editableURLString = url.absoluteString
        if let domain = WebAppNamingHelper.domainName(from: url.absoluteString) {
            onActiveDomainChange?(domain)
        }
        
        if !bypassCache, let cached = readerCache[url] {
            navigationState.isLoading = false
            readerState = .loaded(cached)
            return
        }
        
        readerState = .loading(url, statusMessage: "Loading Reader View…")
        navigationState.isLoading = true
        
        readerTask = Task { @MainActor in
            do {
                if ReaderHTMLUtilities.isRobotCheckURL(url) {
                    try await loadReaderViaBackgroundWebView(
                        url: url,
                        requestedURL: url,
                        initialVerificationRequired: true
                    )
                    return
                }
                
                if ReaderHTMLUtilities.isKnownJSRedirectorURL(url) {
                    try await loadReaderViaBackgroundWebView(url: url, requestedURL: url)
                    return
                }
                
                do {
                    let document = try await ReaderModeService.fetchAndConvert(url: url)
                    try Task.checkCancellation()
                    applyLoadedReaderDocument(document, requestedURL: url)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let readerError as ReaderModeError where readerError.shouldFallbackToBackgroundWebView {
                    let isVerification: Bool
                    let fallbackURL: URL
                    if case .humanVerificationRequired(let verifyURL) = readerError {
                        isVerification = true
                        fallbackURL = verifyURL
                    } else {
                        isVerification = false
                        fallbackURL = url
                    }
                    try await loadReaderViaBackgroundWebView(
                        url: fallbackURL,
                        requestedURL: url,
                        initialVerificationRequired: isVerification
                    )
                }
            } catch is CancellationError {
                isAwaitingRobotCheckVerification = false
            } catch {
                isAwaitingRobotCheckVerification = false
                readerState = .failed(message: error.localizedDescription, url: url)
                navigationState.isLoading = false
            }
        }
    }
    
    private func loadReaderViaBackgroundWebView(
        url: URL,
        requestedURL: URL,
        initialVerificationRequired: Bool = false
    ) async throws {
        isAwaitingRobotCheckVerification = initialVerificationRequired
        if initialVerificationRequired {
            navigationState.currentURLString = url.absoluteString
            editableURLString = url.absoluteString
        } else {
            readerState = .loading(url, statusMessage: "Rendering page for Reader View…")
        }
        navigationState.isLoading = true
        navigationState.lastBackgroundLoadError = nil
        
        let startCommitGen = navigationState.webViewCommitGeneration
        var startFinishGen = navigationState.webViewFinishGeneration
        webViewURLBeforeReader = url.absoluteString
        
        if !hasMountedWebView {
            deferredWebViewInitialURL = url.absoluteString
            hasMountedWebView = true
        } else {
            navigationState.onSetReaderMediaSuspended?(!initialVerificationRequired)
            navigationState.onLoadURL?(url)
        }
        
        // Wait for the hidden WKWebView to mount and attach its capture callback (up to 3s).
        let captureAttachDeadline = Date().addingTimeInterval(3.0)
        while navigationState.onCaptureLiveHTML == nil && Date() < captureAttachDeadline {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        
        guard let captureBlock = navigationState.onCaptureLiveHTML else {
            throw ReaderModeError.conversionFailed("Background web view is unavailable.")
        }
        
        var articleDeadline = Date().addingTimeInterval(15.0)
        let verificationMaxDeadline = Date().addingTimeInterval(300.0)
        var trackedCommitGen = startCommitGen
        var finishObservedAt: Date? = nil
        var lastBestCapture: ReaderHTMLCapture? = nil
        var verifiedURLStartedAtGate = initialVerificationRequired && ReaderHTMLUtilities.isRobotCheckURL(url)
        
        while Date() < (isAwaitingRobotCheckVerification ? verificationMaxDeadline : articleDeadline) {
            try Task.checkCancellation()
            
            if let errMsg = navigationState.lastBackgroundLoadError,
               navigationState.webViewCommitGeneration == startCommitGen {
                throw ReaderModeError.networkFailed(errMsg)
            }
            
            // Immediate URL-level robot check detection (covers HTTP 429 or mid-navigation transitions)
            if let bgURL = navigationState.currentBackgroundWebViewURL,
               ReaderHTMLUtilities.isRobotCheckURL(bgURL) {
                verifiedURLStartedAtGate = true
                if !isAwaitingRobotCheckVerification {
                    isAwaitingRobotCheckVerification = true
                    navigationState.onSetReaderMediaSuspended?(false)
                    navigationState.currentURLString = bgURL.absoluteString
                    editableURLString = bgURL.absoluteString
                    finishObservedAt = nil
                    lastBestCapture = nil
                }
                try await Task.sleep(nanoseconds: 250_000_000)
                continue
            }
            
            if isAwaitingRobotCheckVerification {
                if navigationState.webViewCommitGeneration > startCommitGen,
                   let bgURL = navigationState.currentBackgroundWebViewURL,
                   !ReaderHTMLUtilities.isRobotCheckURL(bgURL),
                   bgURL.absoluteString != "about:blank" {
                    let capture = try? await captureBlock()
                    try Task.checkCancellation()
                    let readiness = capture.map { ReaderHTMLUtilities.evaluateBackgroundCaptureReadiness($0) }
                    
                    let passedGate = (verifiedURLStartedAtGate && !ReaderHTMLUtilities.isRobotCheckURL(bgURL))
                        || (readiness != nil && readiness != .requiresHumanVerification)
                    
                    if passedGate {
                        isAwaitingRobotCheckVerification = false
                        verifiedURLStartedAtGate = false
                        navigationState.onSetReaderMediaSuspended?(true)
                        readerState = .loading(bgURL, statusMessage: "Loading article for Reader View…")
                        navigationState.currentURLString = bgURL.absoluteString
                        editableURLString = bgURL.absoluteString
                        webViewURLBeforeReader = bgURL.absoluteString
                        articleDeadline = Date().addingTimeInterval(15.0)
                        finishObservedAt = nil
                        lastBestCapture = nil
                        if ReaderHTMLUtilities.isKnownJSRedirectorURL(bgURL) {
                            startFinishGen = navigationState.webViewFinishGeneration
                        }
                    }
                }
                if isAwaitingRobotCheckVerification {
                    try await Task.sleep(nanoseconds: 250_000_000)
                    continue
                }
            }
            
            if navigationState.webViewCommitGeneration > startCommitGen {
                if navigationState.webViewCommitGeneration != trackedCommitGen {
                    trackedCommitGen = navigationState.webViewCommitGeneration
                    finishObservedAt = nil
                    lastBestCapture = nil
                }
                
                if let capture = try? await captureBlock() {
                    try Task.checkCancellation()
                    let readiness = ReaderHTMLUtilities.evaluateBackgroundCaptureReadiness(capture)
                    
                    switch readiness {
                    case .requiresHumanVerification:
                        isAwaitingRobotCheckVerification = true
                        if let captureURL = URL(string: capture.urlString),
                           ReaderHTMLUtilities.isRobotCheckURL(captureURL) {
                            verifiedURLStartedAtGate = true
                        }
                        navigationState.onSetReaderMediaSuspended?(false)
                        if !capture.urlString.isEmpty {
                            navigationState.currentURLString = capture.urlString
                            editableURLString = capture.urlString
                        }
                        finishObservedAt = nil
                        lastBestCapture = nil
                        try await Task.sleep(nanoseconds: 250_000_000)
                        continue
                        
                    case .readyImmediately:
                        if let doc = try? await ReaderModeService.convertLiveCapture(capture) {
                            try Task.checkCancellation()
                            if !ReaderHTMLUtilities.looksLikeJavaScriptShell(markdown: doc.markdown, rawHTML: capture.html),
                               !doc.blocks.isEmpty {
                                applyLoadedReaderDocument(doc, requestedURL: requestedURL)
                                return
                            }
                        }
                        
                    case .usableAfterSettle:
                        lastBestCapture = capture
                        
                    case .notReadyYet:
                        break
                    }
                    
                    let isJSRedirector = URL(string: capture.urlString).map { ReaderHTMLUtilities.isKnownJSRedirectorURL($0) } ?? false
                    if !isJSRedirector && navigationState.webViewFinishGeneration > startFinishGen {
                        if finishObservedAt == nil {
                            finishObservedAt = Date()
                        }
                    } else {
                        finishObservedAt = nil
                    }
                }
                
                if let finishedAt = finishObservedAt,
                   Date().timeIntervalSince(finishedAt) >= 1.75 {
                    if let best = lastBestCapture,
                       let doc = try? await ReaderModeService.convertLiveCapture(best),
                       !doc.blocks.isEmpty {
                        try Task.checkCancellation()
                        applyLoadedReaderDocument(doc, requestedURL: requestedURL)
                        return
                    }
                    throw ReaderModeError.emptyContent
                }
            }
            
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        
        if !isAwaitingRobotCheckVerification,
           let best = lastBestCapture,
           let doc = try? await ReaderModeService.convertLiveCapture(best),
           !doc.blocks.isEmpty {
            applyLoadedReaderDocument(doc, requestedURL: requestedURL)
            return
        }
        
        if isAwaitingRobotCheckVerification {
            throw ReaderModeError.humanVerificationRequired(url)
        }
        throw ReaderModeError.javaScriptRequired
    }
    
    private func cacheReaderDocument(_ document: ReaderDocument, requestedURL: URL?) {
        if readerCache.count >= 8 {
            readerCache.removeAll()
        }
        readerCache[document.url] = document
        if let requestedURL {
            readerCache[requestedURL] = document
        }
    }
    #endif
    
    private func handleDismiss() {
        #if os(macOS)
        if isSecondaryWindow {
            #if DEBUG
            print("[CapsuleClose] Home button in secondary window/tab for '\(appItem.name)': focusing main window (capsule stays open in tab/window)")
            #endif
            MainWindowTracker.shared.focusMainWindow()
            return
        }
        #endif
        
        #if DEBUG
        print("[CapsuleClose] Dismissing capsule '\(appItem.name)' back to Home Screen (deleteCookiesOnClose: \(appItem.deleteCookiesOnClose))")
        #endif
        summaryTask?.cancel()
        #if os(macOS)
        isAwaitingRobotCheckVerification = false
        readerTask?.cancel()
        readerCache.removeAll()
        #endif
        navigationState.onStopLoading?()
        
        if appItem.deleteCookiesOnClose {
            Task {
                await IsolatedCookieManager.shared.clearData(for: appItem, context: modelContext)
            }
        }
        
        onDismiss()
    }
    
    private func prefilledTitleForCurrentURL(_ urlString: String) -> String {
        guard let domain = WebAppNamingHelper.domainName(from: urlString) else { return "" }
        let existingNames = ((try? modelContext.fetch(FetchDescriptor<WebAppItem>())) ?? []).map { $0.name }
        return WebAppNamingHelper.uniqueTitle(for: domain, existingNames: existingNames)
    }
    
    private func navigateToConfiguredHome() {
        #if DEBUG
        print("[WebAppContainerView] Navigating to configured home URL: \(appItem.urlString)")
        #endif
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
    
    private func toggleUBlockProtection() {
        let newState = !navigationState.isUBlockEnabled
        navigationState.isUBlockEnabled = newState
        appItem.isUBlockEnabled = newState
        try? modelContext.save()
        navigationState.onToggleUBlock?(newState)
    }
    
    #if os(iOS)
    private func openCurrentInSafariReader() {
        let activeURLString = navigationState.currentURLString.isEmpty ? appItem.urlString : navigationState.currentURLString
        guard let url = URL(string: activeURLString), url.scheme?.hasPrefix("http") == true else { return }
        safariURL = IdentifiableURL(url: url, entersReader: true)
    }
    #endif
    
    private func handleSummarizeTap() {
        if isShowingSummary && !isGeneratingSummary && summaryErrorMessage == nil && !summaryText.isEmpty {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isShowingSummary = false
            }
            return
        }
        startSummarization()
    }
    
    private func startSummarization() {
        summaryTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isShowingSummary = true
            isGeneratingSummary = true
            summaryText = ""
            summaryErrorMessage = nil
        }
        
        summaryTask = Task { @MainActor in
            do {
                #if os(macOS)
                if isReaderModeActive, case .loaded(let doc) = readerState {
                    let result = try await AISummarizer.shared.summarize(
                        title: doc.title,
                        url: doc.url.absoluteString,
                        firstPageText: doc.plainTextForSummary,
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
                    return
                }
                #endif
                
                guard let captureBlock = navigationState.onCaptureFirstPagePDFText else {
                    throw WebPageSummaryError.webViewUnavailable
                }
                
                let captured = try await captureBlock()
                
                let result = try await AISummarizer.shared.summarize(
                    title: captured.title,
                    url: captured.url,
                    firstPageText: captured.text,
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
    
    private func shareCurrentURL() {
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

// MARK: - Top Controls Bar (Shield, Summarize & Tiles)

/// Top Controls Bar for both iOS and macOS:
/// - Top Left: Shield button to toggle uBlock Origin Lite protection for the active isolated app
/// - Top Left (Next to Shield): Summarize button to generate an on-device AI summary of the web page
/// - Center: App Title
/// - Top Right: Tiles/Grid button to navigate back to the global app Home Screen
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
        appItem.urlString.lowercased().contains("youtube.com") ||
        navigationState.currentURLString.lowercased().contains("youtube.com")
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Summarize Button (Top Left - shown only if Apple Intelligence is available)
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
            
            // Shield Button (Next to Summarize Button) - hidden if uBlock is disabled globally
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
            
            // Ephemeral Add Button (Middle)
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
            
            // Downloads Button (Appears when active or recent downloads exist)
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
            // Reader Button (macOS): Always visible; toggles in-app Markdown Reader view ON/OFF
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
            // Reader Button (iOS): Appears only when "open links in safari reader mode" is OFF
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
            
            // Tiles / Grid Home Button (Top Right)
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
private struct ReaderToggleButtonStyleModifier: ViewModifier {
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

// MARK: - Downloads UI (Status Banner & Popover List)

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

// MARK: - Summary Dropdown View

/// Dropdown section presented directly below the top bar displaying the AI-generated web page summary.
struct SummaryDropdownView: View {
    let isGenerating: Bool
    let summaryText: String
    let errorMessage: String?
    let onClose: () -> Void
    let onRegenerate: () -> Void
    
    @State private var hasCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
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
            
            // Content Body
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
                    Text("Rendering PDF & generating AI summary...")
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

// Solid Bottom Bar specifically for macOS
#if os(macOS)
struct MacOSSolidBottomBar: View {
    @ObservedObject var navigationState: WebViewNavigationState
    @Binding var isURLExpanded: Bool
    @Binding var editableURLString: String
    let onGoHome: () -> Void
    let onShare: () -> Void
    var canGoBackOverride: Bool? = nil
    var canGoForwardOverride: Bool? = nil
    var onGoBackOverride: (() -> Void)? = nil
    var onGoForwardOverride: (() -> Void)? = nil
    var onReloadOverride: (() -> Void)? = nil
    var onSubmitRawInput: ((String) -> Void)? = nil
    
    private var resolvedCanGoBack: Bool {
        canGoBackOverride ?? navigationState.canGoBack
    }
    
    private var resolvedCanGoForward: Bool {
        canGoForwardOverride ?? navigationState.canGoForward
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Navigation Buttons (Back & Forward)
            HStack(spacing: 6) {
                Button {
                    if let onGoBackOverride {
                        onGoBackOverride()
                    } else {
                        navigationState.onGoBack?()
                    }
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 13, weight: .semibold))
                }
                .disabled(!resolvedCanGoBack)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Button {
                    if let onGoForwardOverride {
                        onGoForwardOverride()
                    } else {
                        navigationState.onGoForward?()
                    }
                } label: {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 13, weight: .semibold))
                }
                .disabled(!resolvedCanGoForward)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Button {
                    if let onReloadOverride {
                        onReloadOverride()
                    } else {
                        navigationState.onReload?()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            
            // Address & Search Bar
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                TextField("Search or enter website address", text: $editableURLString)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit {
                        submitURL()
                    }
                
                if navigationState.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            
            // Share Button
            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            
            // Home Button (Navigates to configured website home URL)
            Button(action: onGoHome) {
                HStack(spacing: 4) {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func submitURL() {
        if let onSubmitRawInput {
            onSubmitRawInput(editableURLString)
            return
        }
        guard let resolved = SearchEngine.resolveInput(editableURLString),
              let url = URL(string: resolved) else { return }
        navigationState.onLoadURL?(url)
    }
}
#endif

#if os(iOS)
/// Solid Bottom Bar for iOS (non-transparent, does not overlay web content)
struct IOSSolidBottomBar: View {
    @ObservedObject var navigationState: WebViewNavigationState
    @Binding var isURLExpanded: Bool
    @Binding var editableURLString: String
    let onGoHome: () -> Void
    let onShare: () -> Void
    
    @FocusState private var isURLFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            if !isURLExpanded {
                // Navigation Buttons (Back & Forward)
                HStack(spacing: 6) {
                    Button {
                        navigationState.onGoBack?()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 38, height: 38)
                    }
                    .disabled(!navigationState.canGoBack)
                    .opacity(navigationState.canGoBack ? 1.0 : 0.35)
                    .liquidGlassButton(cornerRadius: 12)
                    .buttonStyle(.plain)
                    
                    if navigationState.canGoForward {
                        Button {
                            navigationState.onGoForward?()
                        } label: {
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 38, height: 38)
                        }
                        .liquidGlassButton(cornerRadius: 12)
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Current Page URL (Expands to full width when tapped)
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                if isURLExpanded {
                    TextField("Search or enter website", text: $editableURLString)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.default)
                        .focused($isURLFocused)
                        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { obj in
                            if let textField = obj.object as? UITextField {
                                textField.selectedTextRange = textField.textRange(from: textField.beginningOfDocument, to: textField.endOfDocument)
                            }
                        }
                        .onSubmit {
                            submitURL()
                        }
                    
                    Button {
                        isURLFocused = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isURLExpanded = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(navigationState.currentURLString.isEmpty ? "about:blank" : cleanHost(from: navigationState.currentURLString))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    if navigationState.isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .liquidGlassButton(cornerRadius: 12)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isURLExpanded {
                    editableURLString = navigationState.currentURLString
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isURLExpanded = true
                    }
                }
                if !isURLFocused {
                    isURLFocused = true
                }
            }
            
            if !isURLExpanded {
                // Share Button
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 38, height: 38)
                }
                .liquidGlassButton(cornerRadius: 12)
                .buttonStyle(.plain)
                
                // Home Button (Navigates to configured website home URL)
                Button(action: onGoHome) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 38, height: 38)
                }
                .liquidGlassButton(cornerRadius: 12)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Color(uiColor: .systemBackground))
        .onChange(of: isURLFocused) { _,  _ in
            if !isURLFocused && isURLExpanded {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isURLExpanded = false
                }
            }
        }
    }
    
    private func submitURL() {
        isURLFocused = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isURLExpanded = false
        }
        guard let resolved = SearchEngine.resolveInput(editableURLString),
              let url = URL(string: resolved) else { return }
        navigationState.onLoadURL?(url)
    }
    
    private func cleanHost(from urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        return url.host ?? urlString
    }
}

#endif

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
    var entersReader: Bool = false
}

#if os(iOS)
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    var entersReaderIfAvailable: Bool = false

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = entersReaderIfAvailable
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
    }
}
#endif
