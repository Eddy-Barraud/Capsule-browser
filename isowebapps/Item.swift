//
//  Item.swift
//  isowebapps
//
//  Created by Eddy Barraud on 23/08/2026.
//

import Foundation
import SwiftData

/// Xcode's original SwiftData sample model.
///
/// The application persists `WebAppItem` instead; this type remains in the
/// project as unused template code and is not included in the app schema.
@Model
final class Item {
    var timestamp: Date

    /// Creates a sample item with the supplied timestamp.
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
