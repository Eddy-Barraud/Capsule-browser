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
    var onCaptureFirstPagePDFText: (() async throws -> (title: String, url: String, text: String))?
}

struct WebAppContainerView: View {
    let appItem: WebAppItem
    let onDismiss: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @StateObject private var navigationState = WebViewNavigationState()
    @State private var isURLExpanded = false
    @State private var isShowingShareSheet = false
    @State private var editableURLString: String = ""
    
    // AI Summarization State
    @State private var isShowingSummary = false
    @State private var isGeneratingSummary = false
    @State private var isSummarizationAvailable = AISummarizer.isAvailable
    @State private var summaryText = ""
    @State private var summaryErrorMessage: String? = nil
    @State private var summaryTask: Task<Void, Never>? = nil
    @State private var safariURL: IdentifiableURL? = nil
    
    var body: some View {
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
                        isGeneratingSummary: isGeneratingSummary,
                        isSummarizationAvailable: isSummarizationAvailable,
                        onDismiss: handleDismiss,
                        onToggleShield: toggleUBlockProtection,
                        onSummarize: handleSummarizeTap,
                        onOpenInReader: openCurrentInSafariReader
                    )
                    
                    Divider()
                    
                    // Web View Content
                    IsolatedWebViewRepresentable(
                        appItem: appItem,
                        navigationState: navigationState,
                        modelContext: modelContext
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture {
                        if isURLExpanded {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isURLExpanded = false
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Solid Bottom Bar on macOS (Home button navigates to configured home URL)
                    MacOSSolidBottomBar(
                        navigationState: navigationState,
                        isURLExpanded: $isURLExpanded,
                        editableURLString: $editableURLString,
                        onGoHome: navigateToConfiguredHome,
                        onShare: shareCurrentURL
                    )
                }
                .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            navigationState.isUBlockEnabled = appItem.isUBlockEnabled
            let initialURL = appItem.lastOpenedURLString ?? appItem.urlString
            navigationState.currentURLString = initialURL
            editableURLString = initialURL
            
            navigationState.onOpenSafari = { url in
                NSWorkspace.shared.open(url)
            }
        }
        .onChange(of: navigationState.currentURLString) { newURL in
            if !isURLExpanded && !newURL.isEmpty && newURL != "about:blank" {
                editableURLString = newURL
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
            navigationState.onStopLoading?()
        }
        #else
        VStack(spacing: 0) {
            // Top Bar with Shield toggle, Summarize button, and Tiles/Home button
            TopControlsBar(
                appItem: appItem,
                navigationState: navigationState,
                isGeneratingSummary: isGeneratingSummary,
                isSummarizationAvailable: isSummarizationAvailable,
                onDismiss: handleDismiss,
                onToggleShield: toggleUBlockProtection,
                onSummarize: handleSummarizeTap,
                onOpenInReader: openCurrentInSafariReader
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
            
            // Main Web Content & Bottom Solid Glass Controls Bar
            ZStack(alignment: .bottom) {
                IsolatedWebViewRepresentable(
                    appItem: appItem,
                    navigationState: navigationState,
                    modelContext: modelContext
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture {
                    // Tap anywhere on the page outside the URL field to collapse it
                    if isURLExpanded {
                        isURLExpanded = false
                    }
                }
                
                // Floating URL Bar and Bottom Action Buttons
                IOSSolidBottomBar(
                    navigationState: navigationState,
                    isURLExpanded: $isURLExpanded,
                    editableURLString: $editableURLString,
                    onGoHome: navigateToConfiguredHome,
                    onShare: shareCurrentURL
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .zIndex(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .edgesIgnoringSafeArea(.bottom)
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .global)
                .onEnded { value in
                    if !navigationState.canGoBack && value.startLocation.x < 30 && value.translation.width > 40 {
                        handleDismiss()
                    }
                }
        )
        .onAppear {
            isSummarizationAvailable = AISummarizer.isAvailable
            navigationState.isUBlockEnabled = appItem.isUBlockEnabled
            let initialURL = appItem.lastOpenedURLString ?? appItem.urlString
            navigationState.currentURLString = initialURL
            editableURLString = initialURL
            
            navigationState.onOpenSafari = { url in
                #if os(iOS)
                safariURL = IdentifiableURL(url: url)
                #else
                NSWorkspace.shared.open(url)
                #endif
            }
        }
        .onChange(of: navigationState.currentURLString) { newURL in
            if !isURLExpanded && !newURL.isEmpty && newURL != "about:blank" {
                editableURLString = newURL
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
            navigationState.onStopLoading?()
        }
        .sheet(isPresented: $isShowingShareSheet) {
            if let url = URL(string: navigationState.currentURLString.isEmpty ? appItem.urlString : navigationState.currentURLString) {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(item: $safariURL) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
        #endif
    }
    
    private func handleDismiss() {
        #if DEBUG
        print("[WebAppContainerView] Exiting web app back to Home Screen")
        #endif
        summaryTask?.cancel()
        navigationState.onStopLoading?()
        
        if appItem.deleteCookiesOnClose {
            Task {
                let dataStore = WKWebsiteDataStore.nonPersistent()
                await IsolatedCookieManager.shared.clearData(for: appItem, dataStore: dataStore, context: modelContext)
            }
        }
        
        onDismiss()
    }
    
    private func navigateToConfiguredHome() {
        #if DEBUG
        print("[WebAppContainerView] Navigating to configured home URL: \(appItem.urlString)")
        #endif
        if let homeURL = URL(string: appItem.urlString) {
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
    
    private func openCurrentInSafariReader() {
        let activeURLString = navigationState.currentURLString.isEmpty ? appItem.urlString : navigationState.currentURLString
        guard let url = URL(string: activeURLString), url.scheme?.hasPrefix("http") == true else { return }
        
        #if os(iOS)
        safariURL = IdentifiableURL(url: url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }
    
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
    let appItem: WebAppItem
    @ObservedObject var navigationState: WebViewNavigationState
    var isGeneratingSummary: Bool = false
    var isSummarizationAvailable: Bool = false
    let onDismiss: () -> Void
    let onToggleShield: () -> Void
    let onSummarize: () -> Void
    let onOpenInReader: () -> Void
    
    private var isYouTube: Bool {
        appItem.urlString.lowercased().contains("youtube.com")
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
            
            // Shield Button (Next to Summarize Button)
            Button(action: onToggleShield) {
                HStack(spacing: 5) {
                    Image(systemName: isYouTube ? "play.rectangle.fill" : (navigationState.isUBlockEnabled ? "shield.fill" : "shield.slash.fill"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isYouTube ? .red : (navigationState.isUBlockEnabled ? .blue : .secondary))
                    
                    Text(isYouTube ? "Ad-Free" : (navigationState.isUBlockEnabled ? "uBlock ON" : "uBlock OFF"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isYouTube ? .primary : (navigationState.isUBlockEnabled ? .primary : .secondary))
                }
                .padding(.horizontal, 9)
                .frame(height: 32)
                .liquidGlassButton(cornerRadius: 10)
            }
            .buttonStyle(.plain)
            .disabled(isYouTube)
            .help(isYouTube ? "YouTube ad-blocking active" : "Toggle uBlock Origin protection")
            
            Spacer()
            
            // Reader Button (Appears only when "open links in safari reader mode" is OFF)
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
            
            // Tiles / Grid Home Button (Top Right)
            Button(action: onDismiss) {
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Apps")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 9)
                .frame(height: 32)
                .liquidGlassButton(cornerRadius: 10)
            }
            .buttonStyle(.plain)
            .help("Back to Apps Home Screen")
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
    
    var body: some View {
        HStack(spacing: 12) {
            // Navigation Buttons (Back & Forward)
            HStack(spacing: 6) {
                Button {
                    navigationState.onGoBack?()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 13, weight: .semibold))
                }
                .disabled(!navigationState.canGoBack)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Button {
                    navigationState.onGoForward?()
                } label: {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 13, weight: .semibold))
                }
                .disabled(!navigationState.canGoForward)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Button {
                    navigationState.onReload?()
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
        var text = editableURLString.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            if text.contains(".") && !text.contains(" ") {
                text = "https://" + text
            } else {
                text = "https://duckduckgo.com/?q=" + text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            }
        }
        if let url = URL(string: text) {
            navigationState.onLoadURL?(url)
        }
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
                        isURLExpanded = false
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
                    isURLExpanded = true
                }
                if !isURLFocused{
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
        .onChange(of: isURLFocused) { _ in
            if !isURLFocused && isURLExpanded {
                isURLExpanded = false
            }
        }
    }
    
    private func submitURL() {
        isURLFocused = false
        isURLExpanded = false
        var text = editableURLString.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
                    if text.contains(".") && !text.contains(" ") {
                        text = "https://" + text
                    } else {
                        text = "https://duckduckgo.com/?q=" + text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
                    }
                }
                if let url = URL(string: text) {
                    navigationState.onLoadURL?(url)
                }
            }
        }
    }
    
    private func cleanHost(from urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        return url.host ?? urlString
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
}

#if os(iOS)
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
    }
}
#endif
