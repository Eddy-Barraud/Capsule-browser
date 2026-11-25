//
//  SolidBottomBars.swift
//  isowebapps
//
//  Description:
//  Platform-specific bottom navigation & address bars for macOS and iOS capsules.
//

import SwiftUI

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
            
            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            
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
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 38, height: 38)
                }
                .liquidGlassButton(cornerRadius: 12)
                .buttonStyle(.plain)
                
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
        .onChange(of: isURLFocused) { _, _ in
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
