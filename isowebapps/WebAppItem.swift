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
    var openLinksInSafariReaderMode: Bool = false
    var deleteCookiesOnClose: Bool = false
    var displayOrder: Int = 0
    
    /// Encoded `[SerializableCookie]` array stored in SwiftData and synced via CloudKit
    var isolatedCookiesData: Data? = nil
    
    /// The group this web app belongs to, if any.
    var group: WebAppGroup? = nil

    init(
        id: UUID = UUID(),
        name: String = "",
        urlString: String = "https://",
        lastOpenedURLString: String? = nil,
        iconData: Data? = nil,
        createdAt: Date = Date(),
        lastVisited: Date? = nil,
        isUBlockEnabled: Bool = true,
        openLinksInSafariReaderMode: Bool = false,
        deleteCookiesOnClose: Bool = false,
        displayOrder: Int = 0,
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
        self.openLinksInSafariReaderMode = openLinksInSafariReaderMode
        self.deleteCookiesOnClose = deleteCookiesOnClose
        self.displayOrder = displayOrder
        self.isolatedCookiesData = isolatedCookiesData
    }
}
