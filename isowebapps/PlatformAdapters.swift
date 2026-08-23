//
//  PlatformAdapters.swift
//  isowebapps
//
//  Created on 23/08/2026.
//

import SwiftUI

#if os(iOS)
import UIKit
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor

public extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}
#else
import AppKit
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor

public extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}
#endif
