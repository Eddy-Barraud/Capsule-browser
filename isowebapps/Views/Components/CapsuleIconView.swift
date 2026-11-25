//
//  CapsuleIconView.swift
//  isowebapps
//
//  Description:
//  Shared SwiftUI icon view rendering cached capsule favicons with a consistent fallback.
//

import SwiftUI

struct CapsuleIconView: View {
    let app: WebAppItem
    var size: CGFloat = 32
    var cornerRadius: CGFloat = 8
    var fallbackSymbolSize: CGFloat = 18
    
    var body: some View {
        if let platformImage = IconImageCache.image(for: app.id, data: app.iconData) {
            Image(platformImage: platformImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            Image(systemName: "globe")
                .font(.system(size: fallbackSymbolSize))
                .foregroundStyle(.blue)
                .frame(width: size, height: size)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
