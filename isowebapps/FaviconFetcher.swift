//
//  FaviconFetcher.swift
//  isowebapps
//
//  Created on 23/08/2026.
//

import Foundation

/// Utility to fetch web application favicon and metadata
public final class FaviconFetcher {
    public static func fetchIcon(for url: URL) async -> Data? {
        guard let host = url.host else { return nil }
        
        // 1. Try Google's high-resolution favicon service
        if let googleURL = URL(string: "https://www.google.com/s2/favicons?sz=256&domain=\(host)"),
           let (data, response) = try? await URLSession.shared.data(from: googleURL),
           let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, !data.isEmpty {
            return data
        }
        
        // 2. Try direct /apple-touch-icon.png
        if let directAppleIcon = URL(string: "\(url.scheme ?? "https")://\(host)/apple-touch-icon.png"),
           let (data, response) = try? await URLSession.shared.data(from: directAppleIcon),
           let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, !data.isEmpty {
            return data
        }
        
        // 3. Try standard /favicon.ico
        if let directFavicon = URL(string: "\(url.scheme ?? "https")://\(host)/favicon.ico"),
           let (data, response) = try? await URLSession.shared.data(from: directFavicon),
           let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, !data.isEmpty {
            return data
        }
        
        return nil
    }
}
