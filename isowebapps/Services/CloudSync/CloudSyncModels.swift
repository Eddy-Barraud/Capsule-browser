//
//  CloudSyncModels.swift
//  isowebapps
//
//  Description:
//  Value snapshots and conflict descriptors for iCloud (CloudKit) synchronization.
//

import Foundation

/// Value snapshot of a `WebAppGroup` for safe cross-container transfer.
public struct GroupSnapshot: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    public let displayOrder: Int
    
    init(from group: WebAppGroup) {
        self.id = group.id
        self.name = group.name
        self.createdAt = group.createdAt
        self.displayOrder = group.displayOrder
    }
}

/// Value snapshot of a `WebAppItem` for safe cross-container transfer and conflict resolution.
public struct CapsuleSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let urlString: String
    public let lastOpenedURLString: String?
    public let iconData: Data?
    public let createdAt: Date
    public let lastVisited: Date?
    public let isUBlockEnabled: Bool
    public let openLinksInSafariReaderMode: Bool
    public let deleteCookiesOnClose: Bool
    public let displayOrder: Int
    public let isolatedCookiesData: Data?
    public let groupName: String?
    
    init(from item: WebAppItem) {
        self.id = item.id
        self.name = item.name
        self.urlString = item.urlString
        self.lastOpenedURLString = item.lastOpenedURLString
        self.iconData = item.iconData
        self.createdAt = item.createdAt
        self.lastVisited = item.lastVisited
        self.isUBlockEnabled = item.isUBlockEnabled
        self.openLinksInSafariReaderMode = item.openLinksInSafariReaderMode
        self.deleteCookiesOnClose = item.deleteCookiesOnClose
        self.displayOrder = item.displayOrder
        self.isolatedCookiesData = item.isolatedCookiesData
        self.groupName = item.group?.name
    }
}

/// Represents a single sync conflict where a local capsule and an iCloud capsule share the same name.
public struct CapsuleSyncConflict: Identifiable, Equatable {
    public let id = UUID()
    public let localCapsule: CapsuleSnapshot
    public let cloudCapsuleID: UUID
    public let cloudCapsuleName: String
    public let cloudCapsuleURL: String
    /// If the local capsule was already inserted before a late CloudKit import arrived, holds its inserted UUID.
    public let insertedLocalCapsuleID: UUID?
}
