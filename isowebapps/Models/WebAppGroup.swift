//
//  WebAppGroup.swift
//  isowebapps
//

import Foundation
import SwiftData

/// Represents a group of isolated web applications that share a combined cookie session at startup.
@Model
final class WebAppGroup {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var displayOrder: Int = 0
    
    @Relationship(deleteRule: .nullify, inverse: \WebAppItem.group)
    var items: [WebAppItem]? = []
    
    init(id: UUID = UUID(), name: String = "", displayOrder: Int = 0) {
        self.id = id
        self.name = name
        self.displayOrder = displayOrder
    }
}

