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

    private static func parseLines(_ lines: [String], nextID: inout Int) -> [MarkdownBlock] {
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

    private static func startsOtherBlock(_ line: String) -> Bool {
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

    private static func isThematicBreak(_ line: String) -> Bool {
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

    // MARK: - Lists

    private enum ListKind {
        case unordered
        case ordered(Int)

        func matches(_ other: ListKind) -> Bool {
            switch (self, other) {
            case (.unordered, .unordered), (.ordered, .ordered):
                return true
            default:
                return false
            }
        }
    }

    private struct ParsedListMarker {
        let indent: Int
        let contentOffset: Int
        let kind: ListKind
        let content: String
    }

    private static func parseListMarker(_ line: String) -> ParsedListMarker? {
        let indent = leadingSpaceCount(line)
        let afterIndent = String(line.dropFirst(indent))
        guard !afterIndent.isEmpty else { return nil }

        // Avoid confusing thematic break `---` or `* * *` with unordered list item `- ` / `* `
        if isThematicBreak(line) {
            return nil
        }

        // Unordered: '-', '*', '+' followed by >= 1 whitespace (or end of line)
        if let first = afterIndent.first, first == "-" || first == "*" || first == "+" {
            let rest = String(afterIndent.dropFirst())
            if rest.isEmpty || rest.first == " " || rest.first == "\t" {
                let content = rest.trimmingCharacters(in: .whitespaces)
                return ParsedListMarker(
                    indent: indent,
                    contentOffset: indent + 2,
                    kind: .unordered,
                    content: content
                )
            }
        }

        // Ordered: 1..9 digits followed by '.' or ')' and whitespace
        var digits = ""
        for ch in afterIndent {
            if ch.isNumber && ch.isASCII {
                digits.append(ch)
                if digits.count > 9 { return nil }
            } else {
                break
            }
        }
        if !digits.isEmpty, digits.count < afterIndent.count {
            let afterDigits = afterIndent.dropFirst(digits.count)
            if let delim = afterDigits.first, delim == "." || delim == ")" {
                let afterDelim = afterDigits.dropFirst()
                if afterDelim.isEmpty || afterDelim.first == " " || afterDelim.first == "\t" {
                    let startNum = Int(digits) ?? 1
                    let content = String(afterDelim).trimmingCharacters(in: .whitespaces)
                    return ParsedListMarker(
                        indent: indent,
                        contentOffset: indent + digits.count + 2,
                        kind: .ordered(startNum),
                        content: content
                    )
                }
            }
        }

        return nil
    }

    private static func parseList(
        lines: [String],
        startIndex: Int,
        initialMarker: ParsedListMarker,
        nextID: inout Int
    ) -> (MarkdownBlockKind, Int) {
        let listIndent = initialMarker.indent
        let listKind = initialMarker.kind
        var items: [MarkdownListItem] = []
        var i = startIndex

        while i < lines.count {
            let marker: ParsedListMarker
            if i == startIndex {
                marker = initialMarker
            } else if let m = parseListMarker(lines[i]), m.indent == listIndent, m.kind.matches(listKind) {
                marker = m
            } else {
                break
            }

            let (taskState, cleanItemFirstLine) = extractTaskCheckbox(from: marker.content)
            var itemTextLines: [String] = cleanItemFirstLine.isEmpty ? [] : [cleanItemFirstLine]
            var nestedRawLines: [String] = []
            i += 1

            while i < lines.count {
                let line = lines[i]
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed.isEmpty {
                    // Continue only if another list item or deeply indented continuation follows
                    var lookahead = i + 1
                    while lookahead < lines.count && lines[lookahead].trimmingCharacters(in: .whitespaces).isEmpty {
                        lookahead += 1
                    }
                    guard lookahead < lines.count else {
                        i = lookahead
                        break
                    }
                    let nextNonEmpty = lines[lookahead]
                    if let nextMarker = parseListMarker(nextNonEmpty),
                       nextMarker.indent == listIndent,
                       nextMarker.kind.matches(listKind) {
                        i = lookahead
                        break
                    }
                    if leadingSpaceCount(nextNonEmpty) > listIndent {
                        if !nestedRawLines.isEmpty {
                            nestedRawLines.append("")
                        }
                        i += 1
                        continue
                    }
                    break
                }

                if let nextMarker = parseListMarker(line) {
                    if nextMarker.indent <= listIndent {
                        break
                    }
                    // Nested sub-list
                    nestedRawLines.append(stripIndent(line, upTo: marker.contentOffset))
                    i += 1
                    continue
                }

                let indent = leadingSpaceCount(line)
                if indent > listIndent || !nestedRawLines.isEmpty && indent >= marker.contentOffset {
                    let stripped = stripIndent(line, upTo: marker.contentOffset)
                    if !nestedRawLines.isEmpty || startsOtherBlock(stripped) {
                        nestedRawLines.append(stripped)
                    } else {
                        itemTextLines.append(stripped.trimmingCharacters(in: .whitespaces))
                    }
                    i += 1
                    continue
                }

                break
            }

            var nestedBlocks = nestedRawLines.isEmpty ? [] : parseLines(nestedRawLines, nextID: &nextID)
            var itemText = itemTextLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if itemText.contains("![") {
                let expanded = expandParagraphWithImages(itemText, nextID: &nextID)
                if let first = expanded.first, case .paragraph(let leadingText) = first.kind {
                    itemText = leadingText
                    nestedBlocks = Array(expanded.dropFirst()) + nestedBlocks
                } else {
                    itemText = ""
                    nestedBlocks = expanded + nestedBlocks
                }
            }
            items.append(MarkdownListItem(
                id: nextID,
                text: itemText,
                isChecked: taskState,
                nestedBlocks: nestedBlocks
            ))
            nextID += 1
        }

        switch listKind {
        case .unordered:
            return (.unorderedList(items: items), i)
        case .ordered(let start):
            return (.orderedList(start: start, items: items), i)
        }
    }

    private static func extractTaskCheckbox(from content: String) -> (Bool?, String) {
        if content.hasPrefix("[ ] ") {
            return (false, String(content.dropFirst(4)))
        }
        if content.hasPrefix("[x] ") || content.hasPrefix("[X] ") {
            return (true, String(content.dropFirst(4)))
        }
        if content == "[ ]" {
            return (false, "")
        }
        if content == "[x]" || content == "[X]" {
            return (true, "")
        }
        return (nil, content)
    }

    // MARK: - Paragraphs & Image Extraction

    private static func joinParagraphLines(_ lines: [String]) -> String {
        var result = ""
        for (idx, rawLine) in lines.enumerated() {
            let trimmedLeading = rawLine.drop(while: { $0 == " " || $0 == "\t" })
            let hasHardBreak = rawLine.hasSuffix("  ") || rawLine.hasSuffix("\\")
            var cleanLine = String(trimmedLeading)
            if cleanLine.hasSuffix("\\") {
                cleanLine.removeLast()
            } else {
                while cleanLine.hasSuffix(" ") {
                    cleanLine.removeLast()
                }
            }
            if idx == 0 {
                result = cleanLine
            } else if hasHardBreak {
                result += "\n" + cleanLine
            } else {
                result += " " + cleanLine
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits paragraphs containing `![alt](url)` or `[![alt](img)](link)` so images render natively
    /// instead of being dropped by SwiftUI `AttributedString(markdown:)`.
    private static func expandParagraphWithImages(_ text: String, nextID: inout Int) -> [MarkdownBlock] {
        guard text.contains("![") else {
            return [allocateBlock(.paragraph(text: text), nextID: &nextID)]
        }

        var output: [MarkdownBlock] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            let linkedMatch = matchLinkedImage(in: text, from: cursor)
            let standaloneMatch = matchStandaloneImage(in: text, from: cursor)

            let chosenMatch: ParsedImageMatch?
            switch (linkedMatch, standaloneMatch) {
            case (let linked?, let standalone?):
                chosenMatch = standalone.range.lowerBound < linked.range.lowerBound ? standalone : linked
            case (let linked?, nil):
                chosenMatch = linked
            case (nil, let standalone?):
                chosenMatch = standalone
            case (nil, nil):
                chosenMatch = nil
            }

            if let match = chosenMatch {
                let before = String(text[cursor..<match.range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !before.isEmpty {
                    output.append(allocateBlock(.paragraph(text: before), nextID: &nextID))
                }
                output.append(allocateBlock(
                    .image(
                        alt: match.alt,
                        urlString: match.imageURL,
                        title: match.title,
                        linkURLString: match.linkURL
                    ),
                    nextID: &nextID
                ))
                cursor = match.range.upperBound
                continue
            }

            let remainder = String(text[cursor...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remainder.isEmpty {
                output.append(allocateBlock(.paragraph(text: remainder), nextID: &nextID))
            }
            break
        }

        return output
    }

    private struct ParsedImageMatch {
        let range: Range<String.Index>
        let alt: String
        let imageURL: String
        let title: String?
        let linkURL: String?
    }

    private static func matchLinkedImage(in text: String, from searchStart: String.Index) -> ParsedImageMatch? {
        var idx = searchStart
        while idx < text.endIndex {
            guard let bracketStart = text[idx...].range(of: "[![") else { return nil }
            // Skip escaped bracket
            if bracketStart.lowerBound > text.startIndex {
                let prev = text.index(before: bracketStart.lowerBound)
                if text[prev] == "\\" {
                    idx = text.index(after: bracketStart.lowerBound)
                    continue
                }
            }
            let innerImgStart = text.index(after: bracketStart.lowerBound)
            guard let img = parseImageConstruct(in: text, startingAtBang: innerImgStart) else {
                idx = text.index(after: bracketStart.lowerBound)
                continue
            }
            // Expect `](linkURL)` right after the image's closing `)`
            guard img.endIndex < text.endIndex, text[img.endIndex] == "]" else {
                idx = text.index(after: bracketStart.lowerBound)
                continue
            }
            let parenStart = text.index(after: img.endIndex)
            guard parenStart < text.endIndex, text[parenStart] == "(",
                  let linkTarget = parseDestinationAndTitle(in: text, openParenIndex: parenStart) else {
                idx = text.index(after: bracketStart.lowerBound)
                continue
            }
            return ParsedImageMatch(
                range: bracketStart.lowerBound..<linkTarget.endIndex,
                alt: img.alt,
                imageURL: img.url,
                title: img.title ?? linkTarget.title,
                linkURL: linkTarget.destination
            )
        }
        return nil
    }

    private static func matchStandaloneImage(in text: String, from searchStart: String.Index) -> ParsedImageMatch? {
        var idx = searchStart
        while idx < text.endIndex {
            guard let imgStart = text[idx...].range(of: "![") else { return nil }
            if imgStart.lowerBound > text.startIndex {
                let prev = text.index(before: imgStart.lowerBound)
                if text[prev] == "\\" || text[prev] == "[" {
                    idx = text.index(after: imgStart.lowerBound)
                    continue
                }
            }
            if let parsed = parseImageConstruct(in: text, startingAtBang: imgStart.lowerBound) {
                return ParsedImageMatch(
                    range: imgStart.lowerBound..<parsed.endIndex,
                    alt: parsed.alt,
                    imageURL: parsed.url,
                    title: parsed.title,
                    linkURL: nil
                )
            }
            idx = text.index(after: imgStart.lowerBound)
        }
        return nil
    }

    private static func parseImageConstruct(
        in text: String,
        startingAtBang bangIdx: String.Index
    ) -> (alt: String, url: String, title: String?, endIndex: String.Index)? {
        let openBracket = text.index(after: bangIdx)
        guard openBracket < text.endIndex, text[openBracket] == "[" else { return nil }
        var idx = text.index(after: openBracket)
        var alt = ""
        var escaped = false
        var foundCloseBracket = false

        while idx < text.endIndex {
            let ch = text[idx]
            if escaped {
                alt.append(ch)
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "]" {
                foundCloseBracket = true
                idx = text.index(after: idx)
                break
            } else {
                alt.append(ch)
            }
            idx = text.index(after: idx)
        }

        guard foundCloseBracket, idx < text.endIndex, text[idx] == "(" else { return nil }
        guard let dest = parseDestinationAndTitle(in: text, openParenIndex: idx) else { return nil }
        return (alt.trimmingCharacters(in: .whitespacesAndNewlines), dest.destination, dest.title, dest.endIndex)
    }

    private static func parseDestinationAndTitle(
        in text: String,
        openParenIndex: String.Index
    ) -> (destination: String, title: String?, endIndex: String.Index)? {
        var idx = text.index(after: openParenIndex)
        while idx < text.endIndex && text[idx].isWhitespace {
            idx = text.index(after: idx)
        }
        guard idx < text.endIndex else { return nil }

        var destination = ""
        if text[idx] == "<" {
            idx = text.index(after: idx)
            while idx < text.endIndex && text[idx] != ">" {
                destination.append(text[idx])
                idx = text.index(after: idx)
            }
            guard idx < text.endIndex, text[idx] == ">" else { return nil }
            idx = text.index(after: idx)
        } else {
            var parenDepth = 0
            while idx < text.endIndex {
                let ch = text[idx]
                if ch == ")" {
                    if parenDepth == 0 { break }
                    parenDepth -= 1
                    destination.append(ch)
                } else if ch == "(" {
                    parenDepth += 1
                    destination.append(ch)
                } else if ch.isWhitespace {
                    break
                } else {
                    destination.append(ch)
                }
                idx = text.index(after: idx)
            }
        }

        while idx < text.endIndex && text[idx].isWhitespace {
            idx = text.index(after: idx)
        }

        var title: String?
        if idx < text.endIndex && (text[idx] == "\"" || text[idx] == "'") {
            let quote = text[idx]
            idx = text.index(after: idx)
            var rawTitle = ""
            var escaped = false
            while idx < text.endIndex {
                let ch = text[idx]
                if escaped {
                    rawTitle.append(ch)
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == quote {
                    idx = text.index(after: idx)
                    break
                } else {
                    rawTitle.append(ch)
                }
                idx = text.index(after: idx)
            }
            let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                title = trimmedTitle
            }
            while idx < text.endIndex && text[idx].isWhitespace {
                idx = text.index(after: idx)
            }
        }

        guard idx < text.endIndex, text[idx] == ")" else { return nil }
        let afterClose = text.index(after: idx)
        let cleanDest = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanDest.isEmpty else { return nil }
        return (cleanDest, title, afterClose)
    }

    // MARK: - Helpers

    private static func allocateBlock(_ kind: MarkdownBlockKind, nextID: inout Int) -> MarkdownBlock {
        let block = MarkdownBlock(id: nextID, kind: kind)
        nextID += 1
        return block
    }

    private static func leadingSpaceCount(_ line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " { count += 1 }
            else if ch == "\t" { count += 2 }
            else { break }
        }
        return count
    }

    private static func stripIndent(_ line: String, upTo targetSpaces: Int) -> String {
        var idx = line.startIndex
        var consumed = 0
        while idx < line.endIndex && consumed < targetSpaces {
            let ch = line[idx]
            if ch == " " {
                consumed += 1
                idx = line.index(after: idx)
            } else if ch == "\t" {
                consumed += 2
                idx = line.index(after: idx)
            } else {
                break
            }
        }
        return String(line[idx...])
    }
}
