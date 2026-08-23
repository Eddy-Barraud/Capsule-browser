//
//  PlatformAdapters.swift
//  isowebapps
//
//  Created on 23/08/2026.
//
//  Description:
//  Cross-platform type aliases and initializers enabling shared SwiftUI code
//  between iOS (UIKit / UIImage) and macOS (AppKit / NSImage).
//

import SwiftUI

#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
typealias PlatformColor = UIColor

extension Image {
    /// Initializes a SwiftUI `Image` from a cross-platform `PlatformImage` (UIImage on iOS)
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}
#else
import AppKit
typealias PlatformImage = NSImage
typealias PlatformColor = NSColor

extension Image {
    /// Initializes a SwiftUI `Image` from a cross-platform `PlatformImage` (NSImage on macOS)
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}
#endif
