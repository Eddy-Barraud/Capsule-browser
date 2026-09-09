import SwiftUI

struct AdaptiveMasonryLayout: Layout {
    var minColumnWidth: CGFloat = 300
    var spacing: CGFloat = 24

    struct Cache {
        var width: CGFloat = -1
        var columnCount: Int = 0
        var frames: [CGRect] = []
        var totalHeight: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.width = -1
    }

    private func computeLayout(width: CGFloat, subviews: Subviews, cache: inout Cache) {
        guard width > 0, !subviews.isEmpty else {
            cache.frames = []
            cache.totalHeight = 0
            return
        }

        // Return cached frames if width has not changed and subview count matches
        if abs(cache.width - width) < 0.5 && cache.frames.count == subviews.count {
            return
        }

        let columns = max(1, Int((width + spacing) / (minColumnWidth + spacing)))
        let columnWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        
        var columnHeights = Array(repeating: CGFloat(0), count: columns)
        var frames: [CGRect] = []
        frames.reserveCapacity(subviews.count)
        
        for subview in subviews {
            var shortestIndex = 0
            var minHeight = columnHeights[0]
            for i in 1..<columns {
                if columnHeights[i] < minHeight {
                    minHeight = columnHeights[i]
                    shortestIndex = i
                }
            }
            
            let x = CGFloat(shortestIndex) * (columnWidth + spacing)
            let y = columnHeights[shortestIndex]
            
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            frames.append(CGRect(x: x, y: y, width: columnWidth, height: size.height))
            
            columnHeights[shortestIndex] += size.height + spacing
        }
        
        cache.width = width
        cache.columnCount = columns
        cache.frames = frames
        cache.totalHeight = max(0, (columnHeights.max() ?? 0) - (columnHeights.isEmpty ? 0 : spacing))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = proposal.width ?? 350
        computeLayout(width: width, subviews: subviews, cache: &cache)
        return CGSize(width: width, height: cache.totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard !subviews.isEmpty, bounds.width > 0 else { return }
        computeLayout(width: bounds.width, subviews: subviews, cache: &cache)
        
        for (index, subview) in subviews.enumerated() {
            guard index < cache.frames.count else { break }
            let frame = cache.frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }
}
