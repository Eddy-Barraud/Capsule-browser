//
//  HomeSearchBarView.swift
//  isowebapps
//
//  Description:
//  Isolated bottom quick-search / direct-URL bar for the Home Screen.
//  Owns its own text and focus state so typing never triggers full grid layout recalculations.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct HomeSearchBarView: View {
    let defaultSearchEngineDisplayName: String
    let onSubmitInput: (String) -> Void
    
    @State private var quickSearchText = ""
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 20))
                
                TextField(
                    "",
                    text: $quickSearchText,
                    prompt: Text("Search \(defaultSearchEngineDisplayName) or enter URL...")
                        .foregroundColor(.primary.opacity(0.6))
                )
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit {
                    submitQuery()
                }
                
                #if os(macOS)
                if isSearchFocused || !quickSearchText.isEmpty {
                    HStack(spacing: 8) {
                        Button {
                            quickSearchText = ""
                            isSearchFocused = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 20))
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                        
                        Button {
                            submitQuery()
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 20))
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                #endif
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                isSearchFocused = true
            }
            
            #if os(iOS)
            if isSearchFocused || !quickSearchText.isEmpty {
                Button {
                    submitQuery()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity).combined(with: .move(edge: .trailing)))

                Button {
                    quickSearchText = ""
                    isSearchFocused = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity).combined(with: .move(edge: .trailing)))
            }
            #endif
        }
        .padding(.horizontal, 20)
        #if os(macOS)
        .padding(.bottom, 20)
        #else
        .padding(.bottom, 4)
        .containerRelativeFrame(.horizontal) { width, _ in
            isSearchFocused ? width : width * 0.7
        }
        #endif
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSearchFocused)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: quickSearchText.isEmpty)
    }
    
    private func submitQuery() {
        let query = quickSearchText
        quickSearchText = ""
        isSearchFocused = false
        onSubmitInput(query)
    }
}
