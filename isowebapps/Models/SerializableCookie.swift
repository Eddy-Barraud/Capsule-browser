//
//  SerializableCookie.swift
//  isowebapps
//
//  Description:
//  Codable representation of Foundation HTTPCookie allowing serialization to JSON Data
//  for SwiftData persistence and CloudKit synchronization.
//

import Foundation

/// Codable representation of an `HTTPCookie` allowing seamless serialization to JSON Data
/// for SwiftData and CloudKit synchronization.
public struct SerializableCookie: Codable, Equatable, Sendable {
    public var name: String
    public var value: String
    public var domain: String
    public var path: String
    public var version: Int
    public var isSecure: Bool
    public var isHTTPOnly: Bool
    public var expiresDate: Date?
    public var sameSitePolicy: String?
    
    public init(
        name: String,
        value: String,
        domain: String,
        path: String,
        version: Int = 0,
        isSecure: Bool = false,
        isHTTPOnly: Bool = false,
        expiresDate: Date? = nil,
        sameSitePolicy: String? = nil
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.version = version
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
        self.expiresDate = expiresDate
        self.sameSitePolicy = sameSitePolicy
    }
    
    /// Initializes from a live Foundation `HTTPCookie` instance
    public init(from cookie: HTTPCookie) {
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
    
    /// Converts back into a valid Foundation `HTTPCookie` ready to be loaded into `WKHTTPCookieStore`.
    /// Ensures `path` is non-empty (falling back to `"/"`) to satisfy Foundation initialization requirements.
    public func toHTTPCookie() -> HTTPCookie? {
        let resolvedPath = path.isEmpty ? "/" : path
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: resolvedPath,
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
