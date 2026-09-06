//
//  HomeGridItem.swift
//  isowebapps
//

import SwiftUI
import SwiftData

enum HomeGridItem: Identifiable, Hashable {
    case app(WebAppItem)
    case group(WebAppGroup)
    
    var id: String {
        switch self {
        case .app(let a): return "app-\(a.id.uuidString)"
        case .group(let g): return "group-\(g.id.uuidString)"
        }
    }
    
    var displayOrder: Int {
        get {
            switch self {
            case .app(let a): return a.displayOrder
            case .group(let g): return g.displayOrder
            }
        }
        set {
            switch self {
            case .app(let a): a.displayOrder = newValue
            case .group(let g): g.displayOrder = newValue
            }
        }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: HomeGridItem, rhs: HomeGridItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct HomeItemDropDelegate: DropDelegate {
    let item: HomeGridItem
    let items: [HomeGridItem]
    @Binding var draggingItem: HomeGridItem?
    var modelContext: ModelContext
    
    func dropEntered(info: DropInfo) {
        guard let draggingItem = draggingItem, draggingItem.id != item.id else { return }
        
        guard let fromIndex = items.firstIndex(where: { $0.id == draggingItem.id }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else { return }
        
        if fromIndex != toIndex {
            withAnimation(.default) {
                var sortedItems = items
                let movedItem = sortedItems.remove(at: fromIndex)
                sortedItems.insert(movedItem, at: toIndex)
                
                for (index, homeItem) in sortedItems.enumerated() {
                    var mutableItem = homeItem
                    mutableItem.displayOrder = index
                }
                
                try? modelContext.save()
            }
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        self.draggingItem = nil
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

