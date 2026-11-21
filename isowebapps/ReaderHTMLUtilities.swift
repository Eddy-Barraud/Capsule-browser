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

        let patterns = [
            #"<meta\b[^>]*\bcharset\s*=\s*["']?\s*([A-Za-z0-9._-]+)"#,
            #"charset\s*=\s*([A-Za-z0-9._-]+)"#
        ]
        for pattern in patterns {
            if let match = firstCapture(pattern: pattern, in: headString, options: [.caseInsensitive]) {
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

        if let metaRegex = try? NSRegularExpression(pattern: #"<meta\b([^>]+)>"#, options: [.caseInsensitive]) {
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
        if let titleCapture = firstCapture(
            pattern: #"<title\b[^>]*>([\s\S]*?)</title>"#,
            in: html,
            options: [.caseInsensitive]
        ) {
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
              let imgRegex = try? NSRegularExpression(pattern: #"<img\b([^>]*)/?>"#, options: [.caseInsensitive]) else {
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
                attrs["data-actualsrc"]
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

        if let srcAttrRegex = try? NSRegularExpression(
            pattern: #"(?<=\s)src\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#,
            options: [.caseInsensitive]
        ),
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

    // MARK: - SPA / Challenge Shell Detection & Metrics

    /// Detects pages fetched without JS execution that contain only an empty SPA mount or JS challenge notice.
    static func looksLikeJavaScriptShell(markdown: String, rawHTML: String) -> Bool {
        let plain = plainText(fromMarkdown: markdown)
        if plain.isEmpty {
            return true
        }

        let combinedLower = (plain + "\n" + rawHTML).lowercased()
        let jsRequiredCues = [
            "enable javascript",
            "javascript is required",
            "javascript must be enabled",
            "please turn on javascript",
            "please enable js",
            "requires javascript",
            "checking your browser",
            "just a moment"
        ]

        if plain.count < 220, jsRequiredCues.contains(where: { combinedLower.contains($0) }) {
            return true
        }

        let htmlLower = rawHTML.lowercased()
        let hasEmptySpaMount = htmlLower.contains("id=\"root\"")
            || htmlLower.contains("id='root'")
            || htmlLower.contains("id=\"app\"")
            || htmlLower.contains("id='app'")
            || htmlLower.contains("id=\"__next\"")
            || htmlLower.contains("id='__next'")

        if plain.count < 60, hasEmptySpaMount, htmlLower.contains("<noscript") {
            return true
        }

        return false
    }

    /// Estimates reading time in minutes at ~220 words per minute (minimum 1 min).
    static func estimatedReadingMinutes(for markdown: String) -> Int {
        let text = plainText(fromMarkdown: markdown)
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        return max(1, Int(ceil(Double(words) / 220.0)))
    }

    /// Strips Markdown syntax into clean readable prose (for reading time and on-device AI summarization).
    static func plainText(fromMarkdown markdown: String) -> String {
        var text = markdown
        // Strip markdown image syntax first so link unwrapping keeps surrounding alt cleanly dropped
        text = replacingRegex(#"!\[[^\]]*\]\([^\)]*\)"#, in: text, with: "")
        // Unwrap links [label](url) -> label
        text = replacingRegex(#"\[([^\]]+)\]\([^\)]+\)"#, in: text, with: "$1")
        // Remove fence markers and inline code backticks
        text = replacingRegex(#"(?m)^[ \t]*(```|~~~).*$"#, in: text, with: "")
        text = text.replacingOccurrences(of: "`", with: "")
        // Strip leading heading hashes and blockquote markers
        text = replacingRegex(#"(?m)^[ \t]*#{1,6}[ \t]*"#, in: text, with: "")
        text = replacingRegex(#"(?m)^[ \t]*>[ \t]?"#, in: text, with: "")
        // Collapse blank lines
        text = replacingRegex(#"\n{3,}"#, in: text, with: "\n\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns `true` when address bar text represents a direct URL rather than a search query.
    static func isLikelyDirectURLInput(_ rawInput: String) -> Bool {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return true
        }
        if lower == "localhost" || lower.hasPrefix("localhost:") || lower.hasPrefix("localhost/") {
            return true
        }
        return trimmed.contains(".") && !trimmed.contains(" ")
    }

    // MARK: - Background WebView Reader Readiness & Fallback Classification

    /// Returns `true` for known JS-only article redirectors that require full browser JS execution.
    static func isKnownJSRedirectorURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host.contains("news.google.") || host == "google.com" || host.hasSuffix(".google.com") {
            let path = url.path.lowercased()
            if path.hasPrefix("/read/") || path.hasPrefix("/articles/") || path.hasPrefix("/rss/articles/") || path.hasPrefix("/stories/") {
                return true
            }
            if path == "/url" || path.hasPrefix("/url/") {
                return true
            }
        }
        return false
    }

    /// Ignores benign cancellation or redirect-interruption errors during hidden WebView polling.
    static func shouldIgnoreBackgroundNavigationError(domain: String, code: Int) -> Bool {
        if domain == NSURLErrorDomain && code == NSURLErrorCancelled {
            return true
        }
        if domain == "WebKitErrorDomain" && code == 102 {
            return true
        }
        return false
    }

    /// Returns `true` when an HTTP failure from plain `URLSession` warrants falling back to a background `WKWebView`.
    static func shouldFallbackToBackgroundWebView(httpStatusCode: Int) -> Bool {
        switch httpStatusCode {
        case 401, 403, 406, 429, 503:
            return true
        default:
            return false
        }
    }

    /// Returns `true` for URLs belonging to known anti-bot / human-verification gates (e.g. Google `/sorry/index`).
    static func isRobotCheckURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()
        if (host == "google.com" || host.hasSuffix(".google.com") || host.contains(".google.")) &&
           (path == "/sorry" || path.hasPrefix("/sorry/")) {
            return true
        }
        if path.hasPrefix("/cdn-cgi/challenge-platform") {
            return true
        }
        if host == "geo.captcha-delivery.com" || host.hasSuffix(".captcha-delivery.com") {
            return true
        }
        return false
    }

    /// Returns `true` when either the URL or visible page content represents an interactive robot/CAPTCHA verification check.
    static func isRobotCheckContent(
        urlString: String,
        html: String,
        title: String? = nil,
        textLength: Int? = nil,
        hasRobotCheckWidget: Bool = false
    ) -> Bool {
        if let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
           isRobotCheckURL(url) {
            return true
        }

        let effectiveTextLength = textLength ?? visibleHTMLTextLength(in: html)
        if hasRobotCheckWidget && effectiveTextLength < 1500 {
            return true
        }

        guard effectiveTextLength < 1500 else {
            return false
        }

        let combinedLower = ((title ?? "") + "\n" + html).lowercased()
        let directPhrases = [
            "unusual traffic from your computer network",
            "trafic inhabituel en provenance de votre réseau",
            "trafic inhabituel en provenance de votre reseau",
            "verify you are human",
            "verifying you are human",
            "i am not a robot",
            "je ne suis pas un robot",
            "are you a robot",
            "complete the security check",
            "please verify you are a human"
        ]
        if directPhrases.contains(where: { combinedLower.contains($0) }) {
            return true
        }

        let widgetSignatures = [
            "g-recaptcha",
            "cf-turnstile",
            "h-captcha",
            "captcha-delivery.com",
            "px-captcha",
            "captcha-form"
        ]
        let contextWords = ["captcha", "robot", "human", "sorry", "verify", "vérif"]
        if widgetSignatures.contains(where: { combinedLower.contains($0) }) &&
           contextWords.contains(where: { combinedLower.contains($0) }) {
            return true
        }

        return false
    }

    private static func visibleHTMLTextLength(in html: String) -> Int {
        var stripped = html
        stripped = replacingRegex(#"(?is)<script\b[^>]*>[\s\S]*?</script>"#, in: stripped, with: " ")
        stripped = replacingRegex(#"(?is)<style\b[^>]*>[\s\S]*?</style>"#, in: stripped, with: " ")
        stripped = replacingRegex(#"<[^>]+>"#, in: stripped, with: " ")
        let compact = stripped.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return compact.count
    }

    /// Evaluates whether a DOM snapshot polled from a hidden background `WKWebView` is ready for Reader display.
    static func evaluateBackgroundCaptureReadiness(_ capture: ReaderHTMLCapture) -> BackgroundCaptureReadiness {
        let trimmedURL = capture.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, trimmedURL.lowercased() != "about:blank" else {
            return .notReadyYet
        }
        if isRobotCheckContent(
            urlString: trimmedURL,
            html: capture.html,
            title: capture.title,
            textLength: capture.textLength,
            hasRobotCheckWidget: capture.hasRobotCheckWidget
        ) {
            return .requiresHumanVerification
        }
        if let url = URL(string: trimmedURL), isKnownJSRedirectorURL(url) {
            return .notReadyYet
        }
        if let readyState = capture.readyState?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           readyState != "interactive" && readyState != "complete" {
            return .notReadyYet
        }

        let trimmedHTML = capture.html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHTML.isEmpty else {
            return .notReadyYet
        }

        let textLen = capture.textLength ?? trimmedHTML.count
        let lowerHTML = trimmedHTML.lowercased()
        let challengeOrShellCues = [
            "enable javascript",
            "javascript is required",
            "javascript must be enabled",
            "please turn on javascript",
            "please enable js",
            "requires javascript",
            "checking your browser",
            "just a moment",
            "attention required"
        ]
        if textLen < 220 && challengeOrShellCues.contains(where: { lowerHTML.contains($0) }) {
            return .notReadyYet
        }

        if (capture.matchedPrimaryContainer && textLen >= 250) || textLen >= 400 {
            return .readyImmediately
        }
        if textLen >= 60 {
            return .usableAfterSettle
        }
        return .notReadyYet
    }

    // MARK: - Internal String & Entity Helpers

    static func decodeHTMLEntities(in input: String) -> String {
        guard input.contains("&") else { return input }
        var result = input
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&hellip;", with: "…")

        // Numeric hex entities &#x...; and decimal entities &#...;
        if let numericRegex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) {
            let matches = numericRegex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let codeRange = Range(match.range(at: 1), in: result) else {
                    continue
                }
                let codeToken = String(result[codeRange])
                let scalarValue: UInt32?
                if codeToken.hasPrefix("x") || codeToken.hasPrefix("X") {
                    scalarValue = UInt32(codeToken.dropFirst(), radix: 16)
                } else {
                    scalarValue = UInt32(codeToken, radix: 10)
                }
                if let value = scalarValue, let scalar = UnicodeScalar(value) {
                    result.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }
        return result
    }

    private static func cleanMetadataText(_ raw: String) -> String {
        let decoded = decodeHTMLEntities(in: raw)
        let components = decoded.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return components.joined(separator: " ")
    }

    private static func parseHTMLAttributes(_ rawAttributes: String) -> [String: String] {
        guard let attrRegex = try? NSRegularExpression(
            pattern: #"([A-Za-z0-9_:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#
        ) else {
            return [:]
        }
        var attributes: [String: String] = [:]
        let matches = attrRegex.matches(
            in: rawAttributes,
            range: NSRange(rawAttributes.startIndex..., in: rawAttributes)
        )
        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: rawAttributes) else { continue }
            let name = rawAttributes[nameRange].lowercased()
            let valueRange =
                Range(match.range(at: 2), in: rawAttributes)
                ?? Range(match.range(at: 3), in: rawAttributes)
                ?? Range(match.range(at: 4), in: rawAttributes)
            if let valueRange {
                attributes[name] = String(rawAttributes[valueRange])
            }
        }
        return attributes
    }

    private static func firstCapture(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func replacingRegex(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template
        )
    }
}
