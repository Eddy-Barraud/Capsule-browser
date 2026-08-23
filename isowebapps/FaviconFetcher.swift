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

/// Utility to fetch web application favicon and metadata
final class FaviconFetcher {
    /// Attempts to fetch high-resolution favicon bytes for the given URL
    static func fetchIcon(for url: URL) async -> Data? {
        guard let host = url.host else { return nil }
        
        // 1. Try Google's high-resolution favicon service (256x256)
        if let googleURL = URL(string: "https://www.google.com/s2/favicons?sz=256&domain=\(host)"),
           let (data, response) = try? await URLSession.shared.data(from: googleURL),
           let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, !data.isEmpty {
            return data
        }
        
        // 2. Try direct /apple-touch-icon.png from host root
        if let directAppleIcon = URL(string: "\(url.scheme ?? "https")://\(host)/apple-touch-icon.png"),
           let (data, response) = try? await URLSession.shared.data(from: directAppleIcon),
           let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, !data.isEmpty {
            return data
        }
        
        // 3. Try standard /favicon.ico from host root
        if let directFavicon = URL(string: "\(url.scheme ?? "https")://\(host)/favicon.ico"),
           let (data, response) = try? await URLSession.shared.data(from: directFavicon),
           let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, !data.isEmpty {
            return data
        }
        
        return nil
    }
}
