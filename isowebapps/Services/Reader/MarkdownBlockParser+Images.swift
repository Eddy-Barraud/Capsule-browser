//
//  MarkdownBlockParser+Images.swift
//  isowebapps
//
//  Description:
//  Inline and linked Markdown image extraction helpers for `MarkdownBlockParser`.
//

import Foundation

nonisolated extension MarkdownBlockParser {
    private struct ParsedImageMatch {
        let range: Range<String.Index>
        let alt: String
        let imageURL: String
        let title: String?
        let linkURL: String?
    }

    /// Splits paragraphs containing `![alt](url)` or `[![alt](img)](link)` so images render natively
    /// instead of being dropped by SwiftUI `AttributedString(markdown:)`.
    static func expandParagraphWithImages(_ text: String, nextID: inout Int) -> [MarkdownBlock] {
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

    private static func matchLinkedImage(in text: String, from searchStart: String.Index) -> ParsedImageMatch? {
        var idx = searchStart
        while idx < text.endIndex {
            guard let bracketStart = text[idx...].range(of: "[![") else { return nil }
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
}
