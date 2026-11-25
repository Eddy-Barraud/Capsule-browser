//
//  WebAppContainerView.swift
//  isowebapps
//
//  Created on 23/08/2026.
//
//  Description:
//  The active isolated web container view. Embeds `IsolatedWebViewRepresentable`,
//  manages back/forward navigation state via `WebViewNavigationState`, hosts
//  platform-specific toolbars and AI summary panels, and ensures full resource teardown.
//

import SwiftUI
import WebKit
import SwiftData
import Combine
#if os(macOS)
import AppKit
#endif

struct WebAppContainerView: View {
    let appItem: WebAppItem
    var initialURLString: String? = nil
    var isSecondaryWindow: Bool = false
    var startInReaderMode: Bool = false
    var onActiveDomainChange: ((String) -> Void)? = nil
    let onDismiss: () -> Void
    
    #if os(macOS)
    @Environment(\.openWindow) var openWindow
    @StateObject var lifecycleController = CapsuleLifecycleController()
    @State var hostingWindowBox = WeakWindowBox()
    var hostingWindow: NSWindow? { hostingWindowBox.window }
    @State var isReaderModeActive: Bool
    @State var hasMountedWebView: Bool
    @State var deferredWebViewInitialURL: String? = nil
    @State var readerState: ReaderViewState = .idle
    @State var readerTask: Task<Void, Never>? = nil
    @State var readerHistory = ReaderHistoryStack()
    @State var readerCache: [URL: ReaderDocument] = [:]
    @State var webViewURLBeforeReader: String? = nil
    @State var isAwaitingRobotCheckVerification: Bool = false
    
    private var shouldShowReaderOverlay: Bool {
        isReaderModeActive && !isAwaitingRobotCheckVerification
    }
    #endif
    
    @Environment(\.modelContext) var modelContext
    @StateObject var navigationState = WebViewNavigationState()
    @ObservedObject private var downloadManager = CapsuleDownloadManager.shared
    @State private var isShowingDownloadsPopover = false
    @State var hasRegisteredCapsuleInstance = false
    @State var hasPerformedFullTeardown = false
    
    @State private var isURLExpanded = false
    @State var isShowingShareSheet = false
    @State var editableURLString: String = ""
    @State private var isShowingAddSheet = false
    
    // AI Summarization State
    @State var isShowingSummary = false
    @State var isGeneratingSummary = false
    @State var isSummarizationAvailable = AISummarizer.isAvailable
    @State var summaryText = ""
    @State var summaryErrorMessage: String? = nil
    @State var summaryTask: Task<Void, Never>? = nil
    @State var safariURL: IdentifiableURL? = nil
    
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
    
    var activeDomainTitle: String {
        let urlStr = !navigationState.currentURLString.isEmpty && navigationState.currentURLString != "about:blank"
            ? navigationState.currentURLString
            : (initialURLString ?? appItem.lastOpenedURLString ?? appItem.urlString)
        return WebAppNamingHelper.domainName(from: urlStr) ?? appItem.name
    }
    
    var body: some View {
        Group {
            #if os(macOS)
            macOSContent
            #else
            iOSContent
            #endif
        }
        .navigationTitle(activeDomainTitle)
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
        .sheet(isPresented: $isShowingAddSheet) {
            let activeURLString = navigationState.currentURLString.isEmpty ? appItem.urlString : navigationState.currentURLString
            let prefilledTitle = prefilledTitleForCurrentURL(activeURLString)
            AddWebAppSheet(initialURLString: activeURLString, initialName: prefilledTitle)
        }
        #if os(macOS)
        .background(
            WindowAccessor(
                onWindowSync: { window in
                    lifecycleController.attachWindow(window)
                },
                onWindow: { window in
                    if hostingWindowBox.window !== window {
                        hostingWindowBox.window = window
                    }
                    lifecycleController.attachWindow(window)
                    if window.title != activeDomainTitle {
                        window.title = activeDomainTitle
                    }
                    if window.tab.title != activeDomainTitle {
                        window.tab.title = activeDomainTitle
                    }
                }
            )
        )
        #endif
    }
    
    // MARK: - Platform Layouts
    
    #if os(macOS)
    private var macOSContent: some View {
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
                    
                    ZStack {
                        if hasMountedWebView && !lifecycleController.isDeepSleeping {
                            IsolatedWebViewRepresentable(
                                appItem: appItem,
                                initialURLString: deferredWebViewInitialURL ?? initialURLString,
                                navigationState: navigationState,
                                modelContext: modelContext,
                                lifecycleController: lifecycleController,
                                onOpenNewWindowOrTab: { url in
                                    handleOpenNewWindowOrTab(url: url)
                                },
                                onSearchInNewEphemeralCapsule: { url in
                                    handleSearchInNewEphemeralCapsule(url: url)
                                }
                            )
                            .id(lifecycleController.webViewGeneration)
                            .opacity(shouldShowReaderOverlay ? 0 : 1)
                            .allowsHitTesting(!shouldShowReaderOverlay)
                            .accessibilityHidden(shouldShowReaderOverlay)
                            .overlay {
                                if isURLExpanded {
                                    Color.black.opacity(0.001)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                isURLExpanded = false
                                            }
                                        }
                                }
                                if let hlsURL = navigationState.avkitHLSURL {
                                    YouTubeAVKitOverlayView(url: hlsURL) {
                                        navigationState.onCloseAVKitOverlay?()
                                    }
                                }
                            }
                        } else if hasMountedWebView && lifecycleController.isDeepSleeping && !shouldShowReaderOverlay {
                            SleepingCapsulePlaceholderView(
                                capsuleName: activeDomainTitle,
                                urlString: lifecycleController.savedURLString ?? navigationState.currentURLString,
                                onWakeNow: {
                                    lifecycleController.wakeUp(forceImmediate: true)
                                }
                            )
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
            configureCommonOnAppear()
            navigationState.isReaderModeActive = isReaderModeActive
            navigationState.onOpenSafariReader = { url in
                handleOpenInReaderCapsule(url: url)
            }
            navigationState.onOpenNewWindowOrTab = { url in
                handleOpenNewWindowOrTab(url: url)
            }
            lifecycleController.capsuleName = appItem.name
            lifecycleController.isEphemeral = (appItem.modelContext == nil)
            lifecycleController.canDeepSleepProvider = {
                !isGeneratingSummary && readerTask == nil && !isAwaitingRobotCheckVerification
            }
            lifecycleController.onBeforeDeepSleep = {
                if !isReaderModeActive {
                    readerCache.removeAll()
                }
                if !isShowingSummary {
                    summaryText = ""
                    summaryErrorMessage = nil
                }
            }
            lifecycleController.onWindowWillClose = {
                performFullCapsuleTeardown()
            }
            if let existingWin = hostingWindow {
                lifecycleController.attachWindow(existingWin)
            }
            if MainWindowTracker.shared.openWindowAction == nil {
                MainWindowTracker.shared.openWindowAction = { payload in
                    openWindow(id: "capsuleWindow", value: payload)
                }
            }
            if !isSecondaryWindow {
                MainWindowTracker.shared.mainWindowContentDismissAction = {
                    handleDismiss()
                }
            }
            if startInReaderMode, case .idle = readerState {
                let initialURL = initialURLString ?? appItem.lastOpenedURLString ?? appItem.urlString
                if let targetURL = URL(string: initialURL) {
                    readerHistory.reset(to: targetURL)
                    loadFastReader(url: targetURL, bypassCache: false)
                } else {
                    readerState = .failed(message: ReaderModeError.invalidURL.localizedDescription, url: nil)
                }
            }
        }
        .onDisappear {
            if isSecondaryWindow {
                if lifecycleController.isClosed || hostingWindow == nil || hostingWindow?.isVisible == false {
                    lifecycleController.handleClose()
                    performFullCapsuleTeardown()
                }
                return
            }
            lifecycleController.handleClose()
            performFullCapsuleTeardown()
        }
    }
    #else
    private var iOSContent: some View {
        VStack(spacing: 0) {
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
            
            IsolatedWebViewRepresentable(
                appItem: appItem,
                initialURLString: initialURLString,
                navigationState: navigationState,
                modelContext: modelContext
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if isURLExpanded {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isURLExpanded = false
                            }
                        }
                }
                if let hlsURL = navigationState.avkitHLSURL {
                    YouTubeAVKitOverlayView(url: hlsURL) {
                        navigationState.onCloseAVKitOverlay?()
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
            
            IOSSolidBottomBar(
                navigationState: navigationState,
                isURLExpanded: $isURLExpanded,
                editableURLString: $editableURLString,
                onGoHome: navigateToConfiguredHome,
                onShare: shareCurrentURL
            )
        }
        .ignoresSafeArea(.keyboard, edges: isURLExpanded ? [] : .bottom)
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .global)
                .onEnded { value in
                    if !navigationState.canGoBack && value.startLocation.x < 30 && value.translation.width > 40 {
                        handleDismiss()
                    }
                }
        )
        .onAppear {
            configureCommonOnAppear()
            navigationState.onOpenSafariReader = { url in
                safariURL = IdentifiableURL(url: url, entersReader: true)
            }
        }
        .onDisappear {
            performFullCapsuleTeardown()
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
    }
    #endif
}
