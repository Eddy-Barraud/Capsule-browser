//
//  WebAppItem.swift
//  isowebapps
//
//  Created on 23/08/2026.
//
//  Description:
//  Defines the primary SwiftData persistence model (`WebAppItem`) representing an
//  isolated web application, along with `SerializableCookie` to serialize WKHTTPCookie
//  objects for persistent, CloudKit-synchronized cookie storage.
//

import Foundation
import SwiftData

/// Represents an individual web application pinned to the Home Screen.
/// Holds configuration, cached icon graphics, metadata, and per-app isolated cookies.
@Model
final class WebAppItem {
    var id: UUID = UUID()
    var name: String = ""
    var urlString: String = "https://"
    var lastOpenedURLString: String? = nil
    var iconData: Data? = nil
    var createdAt: Date = Date()
    var lastVisited: Date? = nil
    var isUBlockEnabled: Bool = true
    
    /// Encoded `[SerializableCookie]` array stored in SwiftData and synced via CloudKit
    var isolatedCookiesData: Data? = nil

    init(
        id: UUID = UUID(),
        name: String = "",
        urlString: String = "https://",
        lastOpenedURLString: String? = nil,
        iconData: Data? = nil,
        createdAt: Date = Date(),
        lastVisited: Date? = nil,
        isUBlockEnabled: Bool = true,
        isolatedCookiesData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.lastOpenedURLString = lastOpenedURLString
        self.iconData = iconData
        self.createdAt = createdAt
        self.lastVisited = lastVisited
        self.isUBlockEnabled = isUBlockEnabled
        self.isolatedCookiesData = isolatedCookiesData
    }
}

/// Codable representation of an `HTTPCookie` allowing seamless serialization to JSON Data
/// for SwiftData and CloudKit synchronization.
struct SerializableCookie: Codable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var version: Int
    var isSecure: Bool
    var isHTTPOnly: Bool
    var expiresDate: Date?
    var sameSitePolicy: String?
    
    /// Initializes from a live `HTTPCookie` instance
    init(from cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.version = cookie.version
        self.isSecure = cookie.isSecure
        self.isHTTPOnly = cookie.isHTTPOnly
        self.expiresDate = cookie.expiresDate
        if let sameSite = cookie.sameSitePolicy {
            self.sameSitePolicy = sameSite.rawValue
        }
    }
    
    /// Converts back into a valid Foundation `HTTPCookie` ready to be loaded into `WKHTTPCookieStore`
    func toHTTPCookie() -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .version: version,
            .secure: isSecure ? "TRUE" : "FALSE"
        ]
        if isHTTPOnly {
            properties[.init("HttpOnly")] = "TRUE"
        }
        if let expiresDate = expiresDate {
            properties[.expires] = expiresDate
        }
        if let sameSitePolicy = sameSitePolicy {
            properties[.sameSitePolicy] = HTTPCookieStringPolicy(rawValue: sameSitePolicy)
        }
        return HTTPCookie(properties: properties)
    }
}
