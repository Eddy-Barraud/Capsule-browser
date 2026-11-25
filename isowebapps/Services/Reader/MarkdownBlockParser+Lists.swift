//
//  MarkdownBlockParser+Lists.swift
//  isowebapps
//
//  Description:
//  Ordered/unordered/task list parsing, paragraph line joining, and indentation
//  helpers for `MarkdownBlockParser`.
//

import Foundation

nonisolated extension MarkdownBlockParser {
    // MARK: - Lists

    enum ListKind {
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

    struct ParsedListMarker {
        let indent: Int
        let contentOffset: Int
        let kind: ListKind
        let content: String
    }

    static func parseListMarker(_ line: String) -> ParsedListMarker? {
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

    static func parseList(
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

    // MARK: - Paragraphs & Indentation Helpers

    static func joinParagraphLines(_ lines: [String]) -> String {
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

    static func leadingSpaceCount(_ line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " { count += 1 }
            else if ch == "\t" { count += 2 }
            else { break }
        }
        return count
    }

    static func stripIndent(_ line: String, upTo targetSpaces: Int) -> String {
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
