//
//  WebAppContainerView+Reader.swift
//  isowebapps
//
//  Description:
//  macOS in-app Markdown Reader navigation, fast HTML fetch, background WebView
//  polling fallback, and robot/CAPTCHA verification passthrough.
//

#if os(macOS)
import SwiftUI

extension WebAppContainerView {
    func handleOpenInReaderCapsule(url: URL) {
        let mode = MainWindowTracker.shared.currentPresentationMode
        MainWindowTracker.shared.presentCapsuleWindow(
            appId: nil,
            urlString: url.absoluteString,
            name: WebAppNamingHelper.domainName(from: url.absoluteString) ?? "Reader",
            startInReaderMode: true,
            preferredSourceWindow: hostingWindow,
            openAsTab: (mode == .tabs),
            openWindowFallback: { payload in
                openWindow(id: "capsuleWindow", value: payload)
            }
        )
    }
    
    func toggleReaderMode() {
        if isReaderModeActive {
            exitReaderModeAndLoadFullWebpage()
        } else {
            activateReaderFromLiveWebView()
        }
    }
    
    func activateReaderFromLiveWebView() {
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
    
    func exitReaderModeAndLoadFullWebpage(overrideURL: URL? = nil) {
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
    
    func navigateReaderInPlace(url: URL) {
        readerHistory.push(url)
        loadFastReader(url: url, bypassCache: false)
    }
    
    func navigateReaderBack() {
        guard let previousURL = readerHistory.goBack() else { return }
        loadFastReader(url: previousURL, bypassCache: false)
    }
    
    func navigateReaderForward() {
        guard let nextURL = readerHistory.goForward() else { return }
        loadFastReader(url: nextURL, bypassCache: false)
    }
    
    func reloadActiveReader() {
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
    
    func handleReaderAddressSubmit(_ rawInput: String) {
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
    
    func loadFastReader(url: URL, bypassCache: Bool) {
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
}
#endif
