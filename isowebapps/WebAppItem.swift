//
//  WebAppItem.swift
//  isowebapps
//
//  Created on 23/08/2026.
//

import Foundation
import SwiftData

@Model
final class WebAppItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var urlString: String
    var iconData: Data?
    var createdAt: Date
    var lastVisited: Date?
    
    // CloudKit-synced isolated cookies stored as JSON data
    var isolatedCookiesData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        urlString: String,
        iconData: Data? = nil,
        createdAt: Date = Date(),
        lastVisited: Date? = nil,
        isolatedCookiesData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.iconData = iconData
        self.createdAt = createdAt
        self.lastVisited = lastVisited
        self.isolatedCookiesData = isolatedCookiesData
    }
}

// Codable representation of an HTTPCookie for SwiftData/CloudKit persistence
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
