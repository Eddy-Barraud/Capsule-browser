//
//  IconImageCache.swift
//  isowebapps
//
//  Description:
//  Cost-bounded in-memory cache of decoded capsule icon images keyed by capsule UUID
//  and icon byte count, downsampling oversized favicons to keep RAM minimal.
//

import Foundation
import ImageIO

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// In-memory cache of decoded `PlatformImage` icons keyed by capsule UUID + icon byte count.
enum IconImageCache {
    private static let maxIconPixelSize: CGFloat = 256
    
    private static let cache: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.countLimit = 256
        cache.totalCostLimit = 16 * 1024 * 1024 // 16 MB cap for decoded home screen icons
        return cache
    }()
    
    static func image(for id: UUID, data: Data?) -> PlatformImage? {
        guard let data, !data.isEmpty else { return nil }
        let key = "\(id.uuidString)-\(data.count)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let decoded = decodeBoundedImage(from: data, maxPixelSize: maxIconPixelSize) else { return nil }
        cache.setObject(decoded, forKey: key, cost: pixelCost(for: decoded))
        return decoded
    }
    
    static func clear() {
        cache.removeAllObjects()
    }
    
    nonisolated static func decodeBoundedImage(from data: Data, maxPixelSize: CGFloat) -> PlatformImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        if let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) {
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) {
                #if os(macOS)
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                #else
                return UIImage(cgImage: cgImage)
                #endif
            }
        }
        return PlatformImage(data: data)
    }
    
    static func pixelCost(for image: PlatformImage) -> Int {
        #if os(macOS)
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return max(1, cgImage.bytesPerRow * cgImage.height)
        }
        return max(1, Int(image.size.width * image.size.height * 4))
        #else
        if let cgImage = image.cgImage {
            return max(1, cgImage.bytesPerRow * cgImage.height)
        }
        return max(1, Int(image.size.width * image.size.height * 4))
        #endif
    }
}
