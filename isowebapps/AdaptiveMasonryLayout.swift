import SwiftUI

struct AdaptiveMasonryLayout: Layout {
    var minColumnWidth: CGFloat
    var spacing: CGFloat

    private func computeColumns(width: CGFloat) -> Int {
        let maxColumns = Int((width + spacing) / (minColumnWidth + spacing))
        return max(1, maxColumns)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let columns = computeColumns(width: width)
        let columnWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        
        var columnHeights = Array(repeating: CGFloat(0), count: columns)
        
        for subview in subviews {
            let shortestColumnIndex = columnHeights.firstIndex(of: columnHeights.min()!) ?? 0
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            columnHeights[shortestColumnIndex] += size.height + spacing
        }
        
        let maxHeight = (columnHeights.max() ?? 0) - spacing
        return CGSize(width: width, height: max(0, maxHeight))
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = computeColumns(width: bounds.width)
        let columnWidth = (bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        
        var columnHeights = Array(repeating: bounds.minY, count: columns)
        
        for subview in subviews {
            let shortestColumnIndex = columnHeights.firstIndex(of: columnHeights.min()!) ?? 0
            
            let x = bounds.minX + CGFloat(shortestColumnIndex) * (columnWidth + spacing)
            let y = columnHeights[shortestColumnIndex]
            
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: columnWidth, height: size.height))
            
            columnHeights[shortestColumnIndex] += size.height + spacing
        }
    }
}

