//
//  ReaderHTMLUtilities.swift
//  isowebapps
//
//  Description:
//  Pure-Foundation helpers supporting the macOS in-app Markdown Reader view:
//  HTML charset decoding, metadata extraction, lazy-image normalization,
//  JavaScript-shell detection, Reader history navigation, and reading metrics.
//

import Foundation

/// Live or fetched HTML payload ready for conversion into a Reader document.
nonisolated struct ReaderHTMLCapture: Sendable, Equatable {
    let title: String
    let urlString: String
    let siteName: String?
    let author: String?
    let html: String
    let readyState: String?
    let textLength: Int?
    let matchedPrimaryContainer: Bool
    let hasRobotCheckWidget: Bool

    init(
        title: String,
        urlString: String,
        siteName: String? = nil,
        author: String? = nil,
        html: String,
        readyState: String? = nil,
        textLength: Int? = nil,
        matchedPrimaryContainer: Bool = false,
        hasRobotCheckWidget: Bool = false
    ) {
        self.title = title
        self.urlString = urlString
        self.siteName = siteName
        self.author = author
        self.html = html
        self.readyState = readyState
        self.textLength = textLength
        self.matchedPrimaryContainer = matchedPrimaryContainer
        self.hasRobotCheckWidget = hasRobotCheckWidget
    }
}

/// Readiness assessment for DOM captures polled from a background `WKWebView`.
nonisolated enum BackgroundCaptureReadiness: Sendable, Equatable {
    case notReadyYet
    case requiresHumanVerification
    case usableAfterSettle
    case readyImmediately
}

/// Page metadata parsed from HTML `<head>` / `<meta>` tags.
nonisolated struct ReaderPageMetadata: Sendable, Equatable {
    let title: String?
    let siteName: String?
    let author: String?
}

/// Linear browser-style back/forward URL stack for in-place navigation in Reader mode.
nonisolated struct ReaderHistoryStack: Sendable, Equatable {
    private(set) var entries: [URL] = []
    private(set) var currentIndex: Int = -1

    var currentURL: URL? {
        guard currentIndex >= 0, currentIndex < entries.count else { return nil }
        return entries[currentIndex]
    }

    var canGoBack: Bool {
        currentIndex > 0
    }

    var canGoForward: Bool {
        currentIndex >= 0 && currentIndex + 1 < entries.count
    }

    mutating func reset(to url: URL) {
        entries = [url]
        currentIndex = 0
    }

    mutating func push(_ url: URL) {
        if let current = currentURL, current == url {
            return
        }
        if currentIndex >= 0 && currentIndex + 1 < entries.count {
            entries.removeSubrange((currentIndex + 1)..<entries.count)
        }
        entries.append(url)
        currentIndex = entries.count - 1
    }

    mutating func replaceCurrent(with url: URL) {
        if currentIndex >= 0 && currentIndex < entries.count {
            entries[currentIndex] = url
        } else {
            reset(to: url)
        }
    }

    mutating func goBack() -> URL? {
        guard canGoBack else { return nil }
        currentIndex -= 1
        return entries[currentIndex]
    }

    mutating func goForward() -> URL? {
        guard canGoForward else { return nil }
        currentIndex += 1
        return entries[currentIndex]
    }
}

/// Pure Foundation HTML & Markdown Reader utilities.
nonisolated enum ReaderHTMLUtilities {
    // MARK: - Precompiled Regular Expressions & Character Sets
    
    static let whitespaceSet = CharacterSet.whitespacesAndNewlines
    static let alphanumericSet = CharacterSet.alphanumerics
    
    static let charsetMetaRegex = try? NSRegularExpression(pattern: #"<meta\b[^>]*\bcharset\s*=\s*["']?\s*([A-Za-z0-9._-]+)"#, options: [.caseInsensitive])
    static let charsetFallbackRegex = try? NSRegularExpression(pattern: #"charset\s*=\s*([A-Za-z0-9._-]+)"#, options: [.caseInsensitive])
    static let metaTagRegex = try? NSRegularExpression(pattern: #"<meta\b([^>]+)>"#, options: [.caseInsensitive])
    static let titleTagRegex = try? NSRegularExpression(pattern: #"<title\b[^>]*>([\s\S]*?)</title>"#, options: [.caseInsensitive])
    static let imgTagRegex = try? NSRegularExpression(pattern: #"<img\b([^>]*)/?>"#, options: [.caseInsensitive])
    static let srcsetSplitRegex = try? NSRegularExpression(pattern: #"(?:,\s+|,(?=(?:https?://|//|/)))"#)
    static let srcAttrRegex = try? NSRegularExpression(pattern: #"(?<=\s)src\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#, options: [.caseInsensitive])
    static let numericEntityRegex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#)
    static let htmlAttrRegex = try? NSRegularExpression(pattern: #"([A-Za-z0-9_:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#)
    static let scriptTagRegex = try? NSRegularExpression(pattern: #"(?is)<script\b[^>]*>[\s\S]*?</script>"#)
    static let styleTagRegex = try? NSRegularExpression(pattern: #"(?is)<style\b[^>]*>[\s\S]*?</style>"#)
    static let htmlTagRegex = try? NSRegularExpression(pattern: #"<[^>]+>"#)
    static let mdImageRegex = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\([^\)]*\)"#)
    static let mdLinkRegex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\([^\)]+\)"#)
    static let mdFenceRegex = try? NSRegularExpression(pattern: #"(?m)^[ \t]*(```|~~~).*$"#)
    static let mdHeadingRegex = try? NSRegularExpression(pattern: #"(?m)^[ \t]*#{1,6}[ \t]*"#)
    static let mdBlockquoteRegex = try? NSRegularExpression(pattern: #"(?m)^[ \t]*>[ \t]?"#)
    static let mdBlankLinesRegex = try? NSRegularExpression(pattern: #"\n{3,}"#)
    
    // MARK: - Charset Decoding

    /// Decodes raw HTML bytes using the HTTP `Content-Type` charset, HTML `<meta charset>`,
    /// or UTF-8 / ISO-Latin-1 fallbacks.
    static func decodeHTMLData(_ data: Data, textEncodingName: String?) -> String {
        if let headerCharset = textEncodingName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !headerCharset.isEmpty,
           let encoding = stringEncoding(fromIANACharset: headerCharset),
           let decoded = String(data: data, encoding: encoding) {
            return decoded
        }

        if let sniffedCharset = sniffHTMLCharset(in: data),
           let encoding = stringEncoding(fromIANACharset: sniffedCharset),
           let decoded = String(data: data, encoding: encoding) {
            return decoded
        }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        if let cp1252 = String(data: data, encoding: .windowsCP1252) {
            return cp1252
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func stringEncoding(fromIANACharset charset: String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }

    private static func sniffHTMLCharset(in data: Data) -> String? {
        let prefixCount = min(data.count, 4096)
        guard prefixCount > 0 else { return nil }
        let headData = data.prefix(prefixCount)
        guard let headString = String(data: headData, encoding: .ascii)
            ?? String(data: headData, encoding: .isoLatin1) else {
            return nil
        }

        let regexes = [charsetMetaRegex, charsetFallbackRegex]
        for regex in regexes {
            if let regex, let match = firstCapture(regex: regex, in: headString) {
                return match
            }
        }
        return nil
    }

    // MARK: - Metadata Extraction

    /// Extracts title (`og:title`, `twitter:title`, or `<title>`), site name, and author from HTML.
    static func extractMetadata(from html: String) -> ReaderPageMetadata {
        var ogTitle: String?
        var twitterTitle: String?
        var siteName: String?
        var author: String?

        if let metaRegex = metaTagRegex {
            let fullRange = NSRange(html.startIndex..., in: html)
            for match in metaRegex.matches(in: html, range: fullRange) {
                guard let attrRange = Range(match.range(at: 1), in: html) else { continue }
                let attrs = parseHTMLAttributes(String(html[attrRange]))
                guard let content = attrs["content"].map({ cleanMetadataText($0) }), !content.isEmpty else {
                    continue
                }
                let key = (attrs["property"] ?? attrs["name"] ?? "").lowercased()
                switch key {
                case "og:title":
                    if ogTitle == nil { ogTitle = content }
                case "twitter:title":
                    if twitterTitle == nil { twitterTitle = content }
                case "og:site_name", "application-name":
                    if siteName == nil { siteName = content }
                case "author", "article:author", "parsely-author":
                    if author == nil { author = content }
                default:
                    break
                }
            }
        }

        var rawTitleTag: String?
        if let titleTagRegex,
           let titleCapture = firstCapture(regex: titleTagRegex, in: html) {
            let cleaned = cleanMetadataText(titleCapture)
            if !cleaned.isEmpty {
                rawTitleTag = cleaned
            }
        }

        return ReaderPageMetadata(
            title: ogTitle ?? twitterTitle ?? rawTitleTag,
            siteName: siteName,
            author: author
        )
    }

    // MARK: - Lazy Image Normalization

    /// Promotes `data-src` / `data-original` / `data-lazy-src` attributes onto `src` for `<img>`
    /// elements whose `src` is missing, empty, or an inline placeholder.
    static func normalizeLazyImages(in html: String) -> String {
        guard html.localizedCaseInsensitiveContains("<img"),
              let imgRegex = imgTagRegex else {
            return html
        }

        let matches = imgRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        guard !matches.isEmpty else { return html }

        var output = ""
        output.reserveCapacity(html.count)
        var lastIndex = html.startIndex

        for match in matches {
            guard let fullRange = Range(match.range, in: html),
                  let attrRange = Range(match.range(at: 1), in: html) else {
                continue
            }
            output.append(contentsOf: html[lastIndex..<fullRange.lowerBound])

            let originalTag = String(html[fullRange])
            let rawAttrs = String(html[attrRange])
            let attrs = parseHTMLAttributes(rawAttrs)

            let candidateURL = [
                attrs["data-src"],
                attrs["data-original"],
                attrs["data-lazy-src"],
                attrs["data-actualsrc"],
                attrs["data-srcset"].flatMap { bestURLFromSrcset($0) },
                attrs["srcset"].flatMap { bestURLFromSrcset($0) }
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { isUsableLazyImageURL($0) })

            if let realSrc = candidateURL, shouldReplaceImageSrc(attrs["src"]) {
                output.append(rewrittenImageTag(originalTag: originalTag, newSrc: realSrc))
            } else {
                output.append(originalTag)
            }

            lastIndex = fullRange.upperBound
        }

        output.append(contentsOf: html[lastIndex...])
        return output
    }

    /// Selects the highest-resolution usable URL from an HTML `srcset` / `data-srcset` attribute,
    /// handling URLs that legitimately contain commas (such as CDN transformation segments).
    static func bestURLFromSrcset(_ srcset: String) -> String? {
        let trimmed = srcset.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Split on commas followed by whitespace or directly preceding a new URL start,
        // avoiding splitting inside URL path segments like `w_800,f_auto`.
        let entries: [String]
        if let splitRegex = srcsetSplitRegex {
            let ns = trimmed as NSString
            let matches = splitRegex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
            var parts: [String] = []
            var lastLoc = 0
            for m in matches {
                let len = m.range.location - lastLoc
                if len > 0 {
                    parts.append(ns.substring(with: NSRange(location: lastLoc, length: len)))
                }
                lastLoc = m.range.location + m.range.length
            }
            if lastLoc < ns.length {
                parts.append(ns.substring(from: lastLoc))
            }
            entries = parts
        } else {
            entries = trimmed.components(separatedBy: ",")
        }

        var bestURL: String?
        var bestScore: Double = -1

        for rawEntry in entries {
            let tokens = rawEntry
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isWhitespace)
            guard let urlToken = tokens.first else { continue }
            let urlCandidate = String(urlToken)
            guard isUsableLazyImageURL(urlCandidate) else { continue }

            var score: Double = 0
            if tokens.count >= 2 {
                let descriptor = String(tokens[1]).lowercased()
                if descriptor.hasSuffix("w"), let w = Double(descriptor.dropLast()) {
                    score = w
                } else if descriptor.hasSuffix("x"), let x = Double(descriptor.dropLast()) {
                    score = x * 1000.0
                }
            }
            if bestURL == nil || score > bestScore {
                bestURL = urlCandidate
                bestScore = score
            }
        }
        return bestURL
    }

    /// Produces candidate HTTP(S) URLs for a Markdown image reference, restoring Markdown-escaped
    /// delimiters like `%28`/`%29`/`%5B`/`%5D` first while keeping the original encoded URL as fallback.
    static func candidateImageURLs(from rawURLString: String, relativeTo baseURL: URL? = nil) -> [URL] {
        var cleaned = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        cleaned = cleaned
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\(", with: "(")
            .replacingOccurrences(of: "\\)", with: ")")
            .replacingOccurrences(of: "\\[", with: "[")
            .replacingOccurrences(of: "\\]", with: "]")

        let lower = cleaned.lowercased()
        if lower.hasPrefix("data:") || lower.hasPrefix("javascript:") || lower.hasPrefix("blob:") || lower.hasPrefix("about:") || lower.hasPrefix("file:") {
            return []
        }

        let restored = cleaned
            .replacingOccurrences(of: "%28", with: "(", options: [.caseInsensitive])
            .replacingOccurrences(of: "%29", with: ")", options: [.caseInsensitive])
            .replacingOccurrences(of: "%5B", with: "[", options: [.caseInsensitive])
            .replacingOccurrences(of: "%5D", with: "]", options: [.caseInsensitive])

        func resolveHTTPURL(_ candidate: String) -> URL? {
            let normalizedCandidate: String
            if candidate.hasPrefix("//") {
                normalizedCandidate = (baseURL?.scheme ?? "https") + ":" + candidate
            } else {
                normalizedCandidate = candidate
            }

            let url = URL(string: normalizedCandidate, relativeTo: baseURL)?.absoluteURL
                ?? normalizedCandidate
                    .addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
                    .flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }

            guard let url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return nil
            }
            return url
        }

        var results: [URL] = []
        var seen: Set<String> = []
        for candidate in [restored, cleaned] {
            if let resolved = resolveHTTPURL(candidate), seen.insert(resolved.absoluteString).inserted {
                results.append(resolved)
            }
        }
        return results
    }

    private static func isUsableLazyImageURL(_ candidate: String) -> Bool {
        let lower = candidate.lowercased()
        return lower.hasPrefix("https://")
            || lower.hasPrefix("http://")
            || lower.hasPrefix("//")
            || lower.hasPrefix("/")
    }

    private static func shouldReplaceImageSrc(_ existingSrc: String?) -> Bool {
        guard let existingSrc else { return true }
        let lower = existingSrc.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return true }
        if lower.hasPrefix("data:image/svg+xml") || lower.hasPrefix("about:") { return true }
        if lower.hasPrefix("data:image/gif;base64,r0lgodlh") { return true }
        if lower.contains("placeholder") || lower.contains("blank.gif") || lower.contains("1x1.") {
            return true
        }
        return false
    }

    private static func rewrittenImageTag(originalTag: String, newSrc: String) -> String {
        let escapedSrc = newSrc
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        if let srcAttrRegex,
           let match = srcAttrRegex.firstMatch(in: originalTag, range: NSRange(originalTag.startIndex..., in: originalTag)),
           let range = Range(match.range, in: originalTag) {
            var copy = originalTag
            copy.replaceSubrange(range, with: "src=\"\(escapedSrc)\"")
            return copy
        }

        if let insertIdx = originalTag.range(of: "<img", options: [.caseInsensitive])?.upperBound {
            var copy = originalTag
            copy.insert(contentsOf: " src=\"\(escapedSrc)\"", at: insertIdx)
            return copy
        }
        return originalTag
    }
}
