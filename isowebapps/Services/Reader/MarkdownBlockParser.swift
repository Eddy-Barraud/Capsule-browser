//
//  MarkdownBlockParser.swift
//  isowebapps
//
//  Description:
//  Pure-Foundation CommonMark + GFM block-level Markdown parser that converts
//  Markdown strings into structured `MarkdownBlock` nodes suitable for native
//  SwiftUI typography, tables, code blocks, lists, blockquotes, and images.
//

import Foundation

nonisolated enum TableColumnAlignment: Sendable, Equatable {
    case leading
    case center
    case trailing
}

nonisolated struct MarkdownListItem: Sendable, Equatable, Identifiable {
    let id: Int
    let text: String
    let isChecked: Bool?
    let nestedBlocks: [MarkdownBlock]
}

nonisolated enum MarkdownBlockKind: Sendable, Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case codeBlock(language: String?, code: String)
    case blockquote(blocks: [MarkdownBlock])
    case unorderedList(items: [MarkdownListItem])
    case orderedList(start: Int, items: [MarkdownListItem])
    case table(headers: [String], alignments: [TableColumnAlignment], rows: [[String]])
    case image(alt: String, urlString: String, title: String?, linkURLString: String?)
    case thematicBreak
}

nonisolated struct MarkdownBlock: Sendable, Equatable, Identifiable {
    let id: Int
    let kind: MarkdownBlockKind
}

/// Converts CommonMark + GFM Markdown text into structured blocks for native SwiftUI rendering.
nonisolated enum MarkdownBlockParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var nextID = 0
        return parseLines(lines, nextID: &nextID)
    }

    // MARK: - Core Block Loop

    static func parseLines(_ lines: [String], nextID: inout Int) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var i = 0

        func emit(_ kind: MarkdownBlockKind) {
            blocks.append(MarkdownBlock(id: nextID, kind: kind))
            nextID += 1
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 1. Blank lines
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // 2. HTML comments (single-line or multi-line)
            if trimmed.hasPrefix("<!--") {
                if trimmed.contains("-->") {
                    i += 1
                    continue
                }
                i += 1
                while i < lines.count && !lines[i].contains("-->") {
                    i += 1
                }
                if i < lines.count {
                    i += 1
                }
                continue
            }

            // 3. Fenced code block (``` or ~~~)
            if let fence = parseCodeFenceOpen(line) {
                i += 1
                var codeLines: [String] = []
                while i < lines.count {
                    if isClosingCodeFence(lines[i], markerChar: fence.markerChar, minLength: fence.length) {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                emit(.codeBlock(language: fence.language, code: codeLines.joined(separator: "\n")))
                continue
            }

            // 4. Thematic break (---, ***, ___)
            if isThematicBreak(line) {
                emit(.thematicBreak)
                i += 1
                continue
            }

            // 5. ATX Heading (# ... ######)
            if let heading = parseATXHeading(line) {
                emit(.heading(level: heading.level, text: heading.text))
                i += 1
                continue
            }

            // 6. Blockquote (> ...)
            if isBlockquoteLine(line) {
                var quotedLines: [String] = []
                while i < lines.count && isBlockquoteLine(lines[i]) {
                    quotedLines.append(stripBlockquotePrefix(lines[i]))
                    i += 1
                }
                let innerBlocks = parseLines(quotedLines, nextID: &nextID)
                if !innerBlocks.isEmpty {
                    emit(.blockquote(blocks: innerBlocks))
                }
                continue
            }

            // 7. GFM Pipe Table (header row + delimiter row)
            if i + 1 < lines.count,
               lines[i].contains("|"),
               let alignments = parseTableDelimiterRow(lines[i + 1]) {
                let rawHeaders = splitTableRow(lines[i])
                let colCount = max(rawHeaders.count, alignments.count)
                let headers = padCells(rawHeaders, count: colCount)
                let normalizedAlignments = (0..<colCount).map { idx in
                    idx < alignments.count ? alignments[idx] : .leading
                }
                i += 2
                var rows: [[String]] = []
                while i < lines.count {
                    let rowLine = lines[i]
                    let rowTrimmed = rowLine.trimmingCharacters(in: .whitespaces)
                    if rowTrimmed.isEmpty || !rowTrimmed.contains("|") || startsOtherBlock(rowLine) {
                        break
                    }
                    rows.append(padCells(splitTableRow(rowLine), count: colCount))
                    i += 1
                }
                emit(.table(headers: headers, alignments: normalizedAlignments, rows: rows))
                continue
            }

            // 8. Unordered or Ordered List
            if let firstMarker = parseListMarker(line) {
                let (block, nextIndex) = parseList(lines: lines, startIndex: i, initialMarker: firstMarker, nextID: &nextID)
                emit(block)
                i = nextIndex
                continue
            }

            // 9. Paragraph (or Setext heading)
            var paragraphLines: [String] = []
            while i < lines.count {
                let candidate = lines[i]
                let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)
                if candidateTrimmed.isEmpty {
                    break
                }
                // Check Setext heading underline on a single paragraph line
                if paragraphLines.count == 1, let setextLevel = parseSetextUnderline(candidateTrimmed) {
                    emit(.heading(level: setextLevel, text: paragraphLines[0].trimmingCharacters(in: .whitespaces)))
                    paragraphLines.removeAll()
                    i += 1
                    break
                }
                if !paragraphLines.isEmpty && startsOtherBlock(candidate) {
                    break
                }
                paragraphLines.append(candidate)
                i += 1
            }

            if !paragraphLines.isEmpty {
                let joined = joinParagraphLines(paragraphLines)
                let expanded = expandParagraphWithImages(joined, nextID: &nextID)
                blocks.append(contentsOf: expanded)
            }
        }

        return blocks
    }

    // MARK: - Block Matchers

    static func startsOtherBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("<!--") { return true }
        if parseCodeFenceOpen(line) != nil { return true }
        if isThematicBreak(line) { return true }
        if parseATXHeading(line) != nil { return true }
        if isBlockquoteLine(line) { return true }
        if parseListMarker(line) != nil { return true }
        return false
    }

    private struct CodeFenceOpen {
        let markerChar: Character
        let length: Int
        let language: String?
    }

    private static func parseCodeFenceOpen(_ line: String) -> CodeFenceOpen? {
        let indent = leadingSpaceCount(line)
        guard indent <= 3 else { return nil }
        let trimmed = String(line.dropFirst(indent))
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }

        var count = 0
        for ch in trimmed {
            if ch == first { count += 1 } else { break }
        }
        guard count >= 3 else { return nil }

        let info = String(trimmed.dropFirst(count)).trimmingCharacters(in: .whitespaces)
        // CommonMark: backtick info string cannot contain backticks
        if first == "`" && info.contains("`") {
            return nil
        }
        let lang = info.split(whereSeparator: \.isWhitespace).first.map(String.init)
        return CodeFenceOpen(markerChar: first, length: count, language: lang)
    }

    private static func isClosingCodeFence(_ line: String, markerChar: Character, minLength: Int) -> Bool {
        let indent = leadingSpaceCount(line)
        guard indent <= 3 else { return false }
        let trimmed = String(line.dropFirst(indent)).trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= minLength else { return false }
        return trimmed.allSatisfy { $0 == markerChar }
    }

    static func isThematicBreak(_ line: String) -> Bool {
        let indent = leadingSpaceCount(line)
        guard indent <= 3 else { return false }
        let stripped = line.filter { !$0.isWhitespace }
        guard stripped.count >= 3, let first = stripped.first else { return false }
        guard first == "-" || first == "*" || first == "_" else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    private static func parseATXHeading(_ line: String) -> (level: Int, text: String)? {
        let indent = leadingSpaceCount(line)
        guard indent <= 3 else { return nil }
        let afterIndent = String(line.dropFirst(indent))
        var level = 0
        for ch in afterIndent {
            if ch == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let remainder = String(afterIndent.dropFirst(level))
        guard remainder.isEmpty || remainder.first?.isWhitespace == true else { return nil }

        var content = remainder.trimmingCharacters(in: .whitespaces)
        // Strip optional closing ### sequence preceded by whitespace (or whole content is ###)
        if content.hasSuffix("#") {
            let withoutTrailingHashes = content.reversed().drop(while: { $0 == "#" })
            let candidate = String(withoutTrailingHashes.reversed())
            if candidate.isEmpty {
                content = ""
            } else if candidate.last?.isWhitespace == true {
                content = candidate.trimmingCharacters(in: .whitespaces)
            }
        }
        return (level, content)
    }

    private static func parseSetextUnderline(_ trimmed: String) -> Int? {
        guard !trimmed.isEmpty else { return nil }
        if trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        if trimmed.count >= 2 && trimmed.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func isBlockquoteLine(_ line: String) -> Bool {
        let indent = leadingSpaceCount(line)
        guard indent <= 3 else { return false }
        let dropped = line.dropFirst(indent)
        return dropped.first == ">"
    }

    private static func stripBlockquotePrefix(_ line: String) -> String {
        let indent = leadingSpaceCount(line)
        var remainder = Substring(line.dropFirst(indent))
        if remainder.first == ">" {
            remainder = remainder.dropFirst()
            if remainder.first == " " {
                remainder = remainder.dropFirst()
            }
        }
        return String(remainder)
    }

    // MARK: - GFM Pipe Tables

    private static func parseTableDelimiterRow(_ line: String) -> [TableColumnAlignment]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|"), trimmed.contains("-") else { return nil }
        let cells = splitTableRow(line)
        guard !cells.isEmpty else { return nil }

        var alignments: [TableColumnAlignment] = []
        for rawCell in cells {
            let cell = rawCell.trimmingCharacters(in: .whitespaces)
            guard !cell.isEmpty else { return nil }
            let startsColon = cell.hasPrefix(":")
            let endsColon = cell.hasSuffix(":")
            var middle = Substring(cell)
            if startsColon { middle = middle.dropFirst() }
            if endsColon && !middle.isEmpty { middle = middle.dropLast() }
            guard !middle.isEmpty && middle.allSatisfy({ $0 == "-" }) else {
                return nil
            }
            if startsColon && endsColon {
                alignments.append(.center)
            } else if endsColon {
                alignments.append(.trailing)
            } else {
                alignments.append(.leading)
            }
        }
        return alignments
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") && !trimmed.hasSuffix("\\|") {
            trimmed.removeLast()
        }

        var cells: [String] = []
        var current = ""
        let chars = Array(trimmed)
        var idx = 0
        while idx < chars.count {
            let ch = chars[idx]
            if ch == "\\" && idx + 1 < chars.count && chars[idx + 1] == "|" {
                current.append("|")
                idx += 2
                continue
            }
            if ch == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
            idx += 1
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func padCells(_ cells: [String], count: Int) -> [String] {
        if cells.count == count { return cells }
        if cells.count > count { return Array(cells.prefix(count)) }
        return cells + Array(repeating: "", count: count - cells.count)
    }

    static func allocateBlock(_ kind: MarkdownBlockKind, nextID: inout Int) -> MarkdownBlock {
        let block = MarkdownBlock(id: nextID, kind: kind)
        nextID += 1
        return block
    }
}
