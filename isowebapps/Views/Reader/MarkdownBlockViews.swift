//
//  MarkdownBlockViews.swift
//  isowebapps
//
//  Description:
//  SwiftUI block-level renderers for `MarkdownReaderView` (paragraphs, headings,
//  lists, blockquotes, code blocks, and GFM tables).
//

#if os(macOS)
import SwiftUI
import AppKit

struct MarkdownBlockRow: View {
    let block: MarkdownBlock
    let documentURL: URL
    let fontScale: CGFloat
    let fontDesign: Font.Design
    let onNavigateLink: (URL) -> Void

    var body: some View {
        switch block.kind {
        case .heading(let level, let text):
            headingView(level: level, text: text)

        case .paragraph(let text):
            MarkdownInlineText(
                text: text,
                font: .system(size: 16 * fontScale, design: fontDesign)
            )
            .lineSpacing(5)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)

        case .codeBlock(let language, let code):
            MarkdownCodeBlockView(language: language, code: code, fontScale: fontScale)

        case .blockquote(let innerBlocks):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(innerBlocks) { inner in
                        MarkdownBlockRow(
                            block: inner,
                            documentURL: documentURL,
                            fontScale: fontScale,
                            fontDesign: fontDesign,
                            onNavigateLink: onNavigateLink
                        )
                    }
                }
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.06))
            )

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    listItemRow(
                        marker: nil,
                        isChecked: item.isChecked,
                        item: item
                    )
                }
            }

        case .orderedList(let start, let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    listItemRow(
                        marker: "\(start + index).",
                        isChecked: item.isChecked,
                        item: item
                    )
                }
            }

        case .table(let headers, let alignments, let rows):
            MarkdownTableView(
                headers: headers,
                alignments: alignments,
                rows: rows,
                fontScale: fontScale,
                fontDesign: fontDesign
            )

        case .image(let alt, let urlString, let title, let linkURLString):
            MarkdownImageView(
                alt: alt,
                urlString: urlString,
                title: title,
                linkURLString: linkURLString,
                documentURL: documentURL,
                fontScale: fontScale,
                onNavigateLink: onNavigateLink
            )

        case .thematicBreak:
            Divider()
                .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        let baseSize: CGFloat = {
            switch level {
            case 1: return 28
            case 2: return 22
            case 3: return 18
            case 4: return 16
            case 5: return 15
            default: return 14
            }
        }()

        VStack(alignment: .leading, spacing: 6) {
            MarkdownInlineText(
                text: text,
                font: .system(size: baseSize * fontScale, weight: .bold, design: fontDesign)
            )
            .foregroundStyle(.primary)
            .padding(.top, level <= 2 ? 10 : 4)

            if level <= 2 {
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func listItemRow(marker: String?, isChecked: Bool?, item: MarkdownListItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let isChecked {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14 * fontScale))
                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                    .frame(minWidth: 18, alignment: .trailing)
            } else if let marker {
                Text(marker)
                    .font(.system(size: 15 * fontScale, weight: .medium, design: fontDesign))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 22, alignment: .trailing)
            } else {
                Text("•")
                    .font(.system(size: 16 * fontScale, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 16, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 6) {
                if !item.text.isEmpty {
                    MarkdownInlineText(
                        text: item.text,
                        font: .system(size: 16 * fontScale, design: fontDesign)
                    )
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !item.nestedBlocks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(item.nestedBlocks) { nested in
                            MarkdownBlockRow(
                                block: nested,
                                documentURL: documentURL,
                                fontScale: fontScale,
                                fontDesign: fontDesign,
                                onNavigateLink: onNavigateLink
                            )
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MarkdownInlineText: View {
    let text: String
    let font: Font

    private var renderedText: Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return Text(attributed)
        }
        return Text(text)
    }

    var body: some View {
        renderedText
            .font(font)
            .tint(.accentColor)
    }
}

struct MarkdownCodeBlockView: View {
    let language: String?
    let code: String
    let fontScale: CGFloat
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text((language?.isEmpty == false ? language! : "code").uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(code, forType: .string)
                    didCopy = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        didCopy = false
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy code snippet")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))

            Divider()

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: 13 * fontScale, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }
}

struct MarkdownTableView: View {
    let headers: [String]
    let alignments: [TableColumnAlignment]
    let rows: [[String]]
    let fontScale: CGFloat
    let fontDesign: Font.Design

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { colIndex, cell in
                        MarkdownInlineText(
                            text: cell,
                            font: .system(size: 14 * fontScale, weight: .semibold, design: fontDesign)
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: swiftUIAlignment(for: colIndex))
                    }
                }
                .background(Color.secondary.opacity(0.12))

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    Divider()
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                            MarkdownInlineText(
                                text: cell,
                                font: .system(size: 14 * fontScale, design: fontDesign)
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: swiftUIAlignment(for: colIndex))
                        }
                    }
                    .background(rowIndex % 2 == 1 ? Color.secondary.opacity(0.04) : Color.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
            )
        }
    }

    private func swiftUIAlignment(for colIndex: Int) -> Alignment {
        guard colIndex < alignments.count else { return .leading }
        switch alignments[colIndex] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}
#endif
