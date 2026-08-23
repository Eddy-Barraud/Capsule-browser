//
//  LiquidGlassStyles.swift
//  isowebapps
//
//  Created on 23/08/2026.
//
//  Description:
//  Provides customizable "Liquid Glass" visual styling modifiers for SwiftUI views.
//  Combines ultra-thin materials, specular highlight gradient borders, and multi-layer
//  drop shadows for a modern translucent aesthetic across iOS and macOS.
//

import SwiftUI

/// Liquid Glass visual card modifier for tiles, panels, and containers
struct LiquidGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    var cornerRadius: CGFloat = 20
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        colorScheme == .dark
                        ? Color(white: 0.15).opacity(0.65)
                        : Color.white.opacity(0.65)
                    )
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        colorScheme == .dark ? Color.white.opacity(0.35) : Color.white.opacity(0.8),
                                        colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.08),
                        radius: 12,
                        x: 0,
                        y: 6
                    )
            )
    }
}

/// Liquid Glass button modifier for floating navigation and toolbar buttons
struct LiquidGlassButtonModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    var cornerRadius: CGFloat = 14
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        colorScheme == .dark
                        ? Color(white: 0.2).opacity(0.7)
                        : Color.white.opacity(0.75)
                    )
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.4 : 0.9),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(0.12),
                        radius: 8,
                        x: 0,
                        y: 4
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    /// Applies the Liquid Glass translucent card style
    func liquidGlassCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius))
    }
    
    /// Applies the Liquid Glass button style with interactive shape bounds
    func liquidGlassButton(cornerRadius: CGFloat = 14) -> some View {
        modifier(LiquidGlassButtonModifier(cornerRadius: cornerRadius))
    }
}
