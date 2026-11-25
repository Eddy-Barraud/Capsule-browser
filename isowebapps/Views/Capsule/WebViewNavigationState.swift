//
//  WebViewNavigationState.swift
//  isowebapps
//
//  Description:
//  Observable navigation state passed between SwiftUI toolbars and `WebViewCoordinator`.
//

import Foundation
import Combine

final class WebViewNavigationState: ObservableObject {
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
    var onOpenSafariReader: ((URL) -> Void)?
    var onCaptureLiveHTML: (() async throws -> ReaderHTMLCapture)?
    var onOpenNewWindowOrTab: ((URL) -> Void)?
    var activeWebViewToken: UUID? = nil
    #if os(macOS)
    @Published var isReaderModeActive: Bool = false
    var webViewCommitGeneration: Int = 0
    var webViewFinishGeneration: Int = 0
    var currentBackgroundWebViewURL: URL? = nil
    var lastBackgroundLoadError: String? = nil
    var onSetReaderMediaSuspended: ((Bool) -> Void)?
    #endif
    
    func clearWebViewCallbacks(matching token: UUID?) {
        guard token == nil || activeWebViewToken == token else { return }
        onGoBack = nil
        onGoForward = nil
        onReload = nil
        onLoadURL = nil
        onStopLoading = nil
        onToggleUBlock = nil
        onCaptureLiveHTML = nil
        #if os(macOS)
        onSetReaderMediaSuspended = nil
        #endif
    }
    
    func clearCallbacks() {
        activeWebViewToken = nil
        onGoBack = nil
        onGoForward = nil
        onReload = nil
        onLoadURL = nil
        onStopLoading = nil
        onToggleUBlock = nil
        onOpenSafariReader = nil
        onCaptureLiveHTML = nil
        onOpenNewWindowOrTab = nil
        #if os(macOS)
        onSetReaderMediaSuspended = nil
        #endif
    }
}
