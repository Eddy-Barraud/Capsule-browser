import SwiftUI

struct AdaptiveMasonryLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let items: Data
    var minColumnWidth: CGFloat = 300
    var spacing: CGFloat = 24
    @ViewBuilder let content: (Data.Element) -> Content

    @State private var availableWidth: CGFloat = 0

    init(
        items: Data,
        minColumnWidth: CGFloat = 300,
        spacing: CGFloat = 24,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.items = items
        self.minColumnWidth = minColumnWidth
        self.spacing = spacing
        self.content = content
    }

    private func columnsCount(for width: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        let count = Int((width + spacing) / (minColumnWidth + spacing))
        return max(1, count)
    }

    private func distributeItems(width: CGFloat) -> [[Data.Element]] {
        let count = columnsCount(for: width)
        if count <= 1 {
            return [Array(items)]
        }
        
        var columns = Array(repeating: [Data.Element](), count: count)
        var heights = Array(repeating: CGFloat(0), count: count)
        
        for item in items {
            let minIndex = heights.firstIndex(of: heights.min() ?? 0) ?? 0
            columns[minIndex].append(item)
            
            var weight: CGFloat = 120
            if let homeItem = item as? HomeGridItem {
                switch homeItem {
                case .app:
                    weight = 120
                case .group(let g):
                    let count = CGFloat(max(1, g.items?.count ?? 1))
                    weight = 60 + count * 130
                }
            }
            heights[minIndex] += weight + spacing
        }
        return columns
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                Color.clear
                    .preference(key: MasonryWidthPreferenceKey.self, value: geo.size.width)
            }
            .frame(height: 0)
            
            let width = availableWidth > 0 ? availableWidth : 350
            let cols = distributeItems(width: width)
            
            if cols.count <= 1 {
                LazyVStack(spacing: spacing) {
                    ForEach(items) { item in
                        content(item)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0..<cols.count, id: \.self) { colIndex in
                        LazyVStack(spacing: spacing) {
                            ForEach(cols[colIndex]) { item in
                                content(item)
                            }
                        }
                    }
                }
            }
        }
        .onPreferenceChange(MasonryWidthPreferenceKey.self) { newWidth in
            if newWidth > 0 && abs(newWidth - availableWidth) > 1 {
                availableWidth = newWidth
            }
        }
    }
}

private struct MasonryWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}
