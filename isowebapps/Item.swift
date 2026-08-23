//
//  Item.swift
//  isowebapps
//
//  Created by Eddy Barraud on 23/08/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
