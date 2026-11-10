//
//  SearchEngine.swift
//  isowebapps
//
//  Description:
//  Domain model defining supported search engines (DuckDuckGo, Google, Bing, Custom)
//  and URL resolution logic for search queries and direct address inputs.
//

import Foundation

/// Defines the search engine used by the home search bar and capsule address bars.
public enum SearchEngine: String, CaseIterable, Identifiable, Sendable {
    case duckDuckGo = "duckduckgo"
    case google = "google"
    case bing = "bing"
    case custom = "custom"
    
    public var id: String { rawValue }
    
    public static let storageKey = "defaultSearchEngine"
    public static let customURLStorageKey = "customSearchEngineURL"
    
    public var displayName: String {
        switch self {
        case .duckDuckGo: return "DuckDuckGo"
        case .google: return "Google"
        case .bing: return "Bing"
        case .custom: return "Custom"
        }
    }
    
    public var label: String {
        switch self {
        case .duckDuckGo: return "DuckDuckGo (duckduckgo.com)"
        case .google: return "Google (google.com)"
        case .bing: return "Bing (bing.com)"
        case .custom: return "Custom URL"
        }
    }
    
    public var defaultQueryPrefix: String {
        switch self {
        case .duckDuckGo: return "https://duckduckgo.com/?q="
        case .google: return "https://www.google.com/search?q="
        case .bing: return "https://www.bing.com/search?q="
        case .custom: return ""
        }
    }
    
    public func homeURLString(customTemplate: String = UserDefaults.standard.string(forKey: Self.customURLStorageKey) ?? "") -> String {
        switch self {
        case .duckDuckGo: return "https://duckduckgo.com"
        case .google: return "https://www.google.com"
        case .bing: return "https://www.bing.com"
        case .custom:
            let normalized = Self.normalizedCustomTemplate(customTemplate)
            if let url = URL(string: normalized), let scheme = url.scheme, let host = url.host {
                return "\(scheme)://\(host)"
            }
            return "https://duckduckgo.com"
        }
    }
    
    public static func normalizedCustomTemplate(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "https://duckduckgo.com/?q=" }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        return "https://" + trimmed
    }
    
    /// Builds the search URL string for a raw search query.
    public func searchURLString(
        for query: String,
        customTemplate: String = UserDefaults.standard.string(forKey: Self.customURLStorageKey) ?? ""
    ) -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        switch self {
        case .duckDuckGo, .google, .bing:
            return defaultQueryPrefix + encoded
        case .custom:
            let template = Self.normalizedCustomTemplate(customTemplate)
            if template.contains("%s") {
                return template.replacingOccurrences(of: "%s", with: encoded)
            } else if template.contains("{query}") {
                return template.replacingOccurrences(of: "{query}", with: encoded)
            } else {
                return template + encoded
            }
        }
    }
    
    /// Resolves user input from a search or address bar into either a direct URL or a search query URL.
    public static func resolveInput(_ rawInput: String) -> String? {
        let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        
        if text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") {
            return text
        } else if text.contains(".") && !text.contains(" ") {
            return "https://" + text
        } else {
            let rawEngine = UserDefaults.standard.string(forKey: storageKey) ?? SearchEngine.duckDuckGo.rawValue
            let engine = SearchEngine(rawValue: rawEngine) ?? .duckDuckGo
            let customURL = UserDefaults.standard.string(forKey: customURLStorageKey) ?? ""
            return engine.searchURLString(for: text, customTemplate: customURL)
        }
    }
}
