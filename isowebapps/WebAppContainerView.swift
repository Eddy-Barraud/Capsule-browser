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
    
    var onGoBack: (() -> Void)?
    var onGoForward: (() -> Void)?
    var onReload: (() -> Void)?
    var onLoadURL: ((URL) -> Void)?
    var onStopLoading: (() -> Void)?
}

struct WebAppContainerView: View {
    let appItem: WebAppItem
    let onDismiss: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @StateObject private var navigationState = WebViewNavigationState()
    @State private var isURLExpanded = false
    @State private var isShowingShareSheet = false
    @State private var editableURLString: String = ""
    
    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
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
            
            // Solid Bottom Bar on macOS
            MacOSSolidBottomBar(
                navigationState: navigationState,
                isURLExpanded: $isURLExpanded,
                editableURLString: $editableURLString,
                onDismiss: handleDismiss,
                onShare: shareCurrentURL
            )
        }
        .onAppear {
            navigationState.currentURLString = appItem.urlString
            editableURLString = appItem.urlString
        }
        .onDisappear {
            navigationState.onStopLoading?()
        }
        #else
        ZStack(alignment: .bottom) {
            // Web View Content
            IsolatedWebViewRepresentable(
                appItem: appItem,
                navigationState: navigationState,
                modelContext: modelContext
            )
            .ignoresSafeArea()
            .onTapGesture {
                if isURLExpanded {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isURLExpanded = false
                    }
                }
            }
            
            // Floating Liquid Glass Bottom Bar (no container background, purely floating buttons)
            VStack(spacing: 8) {
                if navigationState.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .liquidGlassCard(cornerRadius: 12)
                }
                
                LiquidGlassBottomBar(
                    navigationState: navigationState,
                    isURLExpanded: $isURLExpanded,
                    editableURLString: $editableURLString,
                    onDismiss: handleDismiss,
                    onShare: shareCurrentURL
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .onAppear {
            navigationState.currentURLString = appItem.urlString
            editableURLString = appItem.urlString
        }
        .onDisappear {
            navigationState.onStopLoading?()
        }
        .sheet(isPresented: $isShowingShareSheet) {
            if let url = URL(string: navigationState.currentURLString.isEmpty ? appItem.urlString : navigationState.currentURLString) {
                ShareSheet(activityItems: [url])
            }
        }
        #endif
    }
    
    private func handleDismiss() {
        #if DEBUG
        print("[WebAppContainerView] Immediately closing webview on Home click")
        #endif
        navigationState.onStopLoading?()
        onDismiss()
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

// Solid Bottom Bar specifically for macOS
#if os(macOS)
struct MacOSSolidBottomBar: View {
    @ObservedObject var navigationState: WebViewNavigationState
    @Binding var isURLExpanded: Bool
    @Binding var editableURLString: String
    let onDismiss: () -> Void
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
            
            // Home Button
            Button(action: onDismiss) {
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
                text = "https://www.google.com/search?q=" + text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            }
        }
        if let url = URL(string: text) {
            navigationState.onLoadURL?(url)
        }
    }
}
#endif

// Floating Liquid Glass Bottom Bar (Purely floating liquid glass elements without parent box background)
struct LiquidGlassBottomBar: View {
    @ObservedObject var navigationState: WebViewNavigationState
    @Binding var isURLExpanded: Bool
    @Binding var editableURLString: String
    let onDismiss: () -> Void
    let onShare: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if !isURLExpanded {
                // Navigation Buttons (Back & Forward)
                HStack(spacing: 8) {
                    Button {
                        navigationState.onGoBack?()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 42, height: 42)
                    }
                    .disabled(!navigationState.canGoBack)
                    .opacity(navigationState.canGoBack ? 1.0 : 0.4)
                    .liquidGlassButton(cornerRadius: 14)
                    .buttonStyle(.plain)
                    
                    if navigationState.canGoForward {
                        Button {
                            navigationState.onGoForward?()
                        } label: {
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 42, height: 42)
                        }
                        .liquidGlassButton(cornerRadius: 14)
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Current Page URL (Expands to full width when clicked)
            HStack {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                if isURLExpanded {
                    TextField("Search or enter website", text: $editableURLString)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .onSubmit {
                            submitURL()
                        }
                    
                    Button {
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
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .liquidGlassButton(cornerRadius: 14)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if !isURLExpanded {
                        editableURLString = navigationState.currentURLString
                        isURLExpanded = true
                    }
                }
            }
            
            if !isURLExpanded {
                // Share Button
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 42, height: 42)
                }
                .liquidGlassButton(cornerRadius: 14)
                .buttonStyle(.plain)
                
                // Home Button to go back to Home Screen
                Button(action: onDismiss) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 42, height: 42)
                }
                .liquidGlassButton(cornerRadius: 14)
                .buttonStyle(.plain)
            }
        }
    }
    
    private func submitURL() {
        withAnimation(.spring()) {
            isURLExpanded = false
            var text = editableURLString.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
                    if text.contains(".") && !text.contains(" ") {
                        text = "https://" + text
                    } else {
                        text = "https://www.google.com/search?q=" + text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
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
}

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
