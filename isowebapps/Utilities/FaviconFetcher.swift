//
//  FaviconFetcher.swift
//  isowebapps
//
//  Created on 23/08/2026.
//
//  Description:
//  Asynchronously fetches high-resolution site icons (favicons and apple-touch-icons)
//  for newly added web applications to display on the Home Screen grid.
//

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Utility to fetch web application favicon and metadata
final class FaviconFetcher {
    /// Dedicated URLSession with bounded request timeouts to avoid indefinite hangs on unresponsive servers.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 7.0
        config.timeoutIntervalForResource = 10.0
        return URLSession(configuration: config)
    }()

    /// Attempts to fetch high-resolution favicon bytes for the given URL,
    /// ensuring returned data represents a valid decoded image.
    static func fetchIcon(for url: URL) async -> Data? {
        guard let host = url.host, !host.isEmpty else { return nil }
        
        let candidates: [URL?] = [
            // 1. Try Google's high-resolution favicon service (256x256)
            URL(string: "https://www.google.com/s2/favicons?sz=256&domain=\(host)"),
            // 2. Try direct /apple-touch-icon.png from host root
            URL(string: "\(url.scheme ?? "https")://\(host)/apple-touch-icon.png"),
            // 3. Try standard /favicon.ico from host root
            URL(string: "\(url.scheme ?? "https")://\(host)/favicon.ico")
        ]
        
        for case let candidateURL? in candidates {
            if let (data, response) = try? await session.data(from: candidateURL),
               let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               !data.isEmpty,
               // Validate that the returned bytes actually represent a decodable image,
               // filtering out 200 OK HTML error pages or captive portal payloads.
               PlatformImage(data: data) != nil {
                return data
            }
        }
        
        return nil
    }
}
