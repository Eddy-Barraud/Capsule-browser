//
//  WebAppNamingHelper.swift
//  isowebapps
//
//  Description:
//  Domain utility for extracting clean domain titles from URLs and resolving
//  name collisions with incremental numbers.
//

import Foundation

public enum WebAppNamingHelper {
    /// Extracts a clean domain name from a URL string (e.g. "https://www.apple.com/shop" -> "apple.com")
    public static func domainName(from urlString: String) -> String? {
        var normalized = urlString.trimmingCharacters(in: .whitespaces)
        if !normalized.lowercased().hasPrefix("http://") && !normalized.lowercased().hasPrefix("https://") {
            normalized = "https://" + normalized
        }
        guard let url = URL(string: normalized),
              let host = url.host?.lowercased() else {
            return nil
        }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return domain.isEmpty ? nil : domain
    }
    
    /// Generates a unique capsule title by appending an incremental number (e.g. "apple.com 2") if the name is already taken
    public static func uniqueTitle(for baseName: String, existingNames: [String]) -> String {
        let trimmedBase = baseName.trimmingCharacters(in: .whitespaces)
        guard !trimmedBase.isEmpty else { return "" }
        
        let existingSet = Set(existingNames.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        guard existingSet.contains(trimmedBase.lowercased()) else {
            return trimmedBase
        }
        
        var counter = 2
        while existingSet.contains("\(trimmedBase) \(counter)".lowercased()) {
            counter += 1
        }
        return "\(trimmedBase) \(counter)"
    }
}
