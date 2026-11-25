//
//  ReaderHTMLUtilities+Readiness.swift
//  isowebapps
//
//  Description:
//  SPA/JS-shell detection, token counting/capping for AI summarization,
//  robot/CAPTCHA challenge detection, background WebView readiness evaluation,
//  and HTML entity/attribute helpers for `ReaderHTMLUtilities`.
//

import Foundation

nonisolated extension ReaderHTMLUtilities {
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
        text = replacingRegex(mdImageRegex, in: text, with: "")
        // Unwrap links [label](url) -> label
        text = replacingRegex(mdLinkRegex, in: text, with: "$1")
        // Remove fence markers and inline code backticks
        text = replacingRegex(mdFenceRegex, in: text, with: "")
        text = text.replacingOccurrences(of: "`", with: "")
        // Strip leading heading hashes and blockquote markers
        text = replacingRegex(mdHeadingRegex, in: text, with: "")
        text = replacingRegex(mdBlockquoteRegex, in: text, with: "")
        // Collapse blank lines
        text = replacingRegex(mdBlankLinesRegex, in: text, with: "\n\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Markdown Token Estimation & Capping (AI Summarization)

    /// Estimates the LLM token count of Markdown text using contiguous alphanumeric word runs
    /// and individual non-whitespace symbol tokens (`ceil(utf8Bytes / 4)` per word run).
    static func estimateTokenCount(for text: String) -> Int {
        scanMarkdownTokens(in: text, maxTokens: nil).tokenCount
    }

    /// Truncates Markdown text to at most `maxTokens` estimated tokens while preserving valid
    /// UTF-8 and `Character` boundaries.
    static func truncateMarkdownToTokenLimit(_ markdown: String, maxTokens: Int = 4000) -> String {
        guard maxTokens > 0 else { return "" }
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let scanResult = scanMarkdownTokens(in: trimmed, maxTokens: maxTokens)
        guard let cutoffIndex = scanResult.cutoffIndex else {
            return trimmed
        }
        return String(trimmed[..<cutoffIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func scanMarkdownTokens(
        in text: String,
        maxTokens: Int?
    ) -> (tokenCount: Int, cutoffIndex: String.Index?) {
        var tokenCount = 0
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character.unicodeScalars.allSatisfy({ whitespaceSet.contains($0) }) {
                index = text.index(after: index)
                continue
            }

            if character.unicodeScalars.contains(where: { alphanumericSet.contains($0) }) {
                let spanStart = index
                var spanUTF8Bytes = 0
                while index < text.endIndex,
                      text[index].unicodeScalars.contains(where: { alphanumericSet.contains($0) }) {
                    spanUTF8Bytes += text[index].utf8.count
                    index = text.index(after: index)
                }

                let spanTokens = max(1, (spanUTF8Bytes + 3) / 4)
                if let limit = maxTokens, tokenCount + spanTokens > limit {
                    let remainingTokens = limit - tokenCount
                    let maxAllowedBytes = remainingTokens * 4
                    var cut = spanStart
                    var accumulatedBytes = 0
                    while cut < index {
                        let charBytes = text[cut].utf8.count
                        if accumulatedBytes + charBytes > maxAllowedBytes {
                            break
                        }
                        accumulatedBytes += charBytes
                        cut = text.index(after: cut)
                    }
                    return (limit, cut)
                }

                tokenCount += spanTokens
                if let limit = maxTokens, tokenCount == limit {
                    return (tokenCount, index)
                }
            } else {
                let symbolStart = index
                if let limit = maxTokens, tokenCount + 1 > limit {
                    return (limit, symbolStart)
                }
                tokenCount += 1
                index = text.index(after: index)
                if let limit = maxTokens, tokenCount == limit {
                    return (tokenCount, index)
                }
            }
        }

        return (tokenCount, nil)
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
        stripped = replacingRegex(scriptTagRegex, in: stripped, with: " ")
        stripped = replacingRegex(styleTagRegex, in: stripped, with: " ")
        stripped = replacingRegex(htmlTagRegex, in: stripped, with: " ")
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
        if let numericRegex = numericEntityRegex {
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

    static func cleanMetadataText(_ raw: String) -> String {
        let decoded = decodeHTMLEntities(in: raw)
        let components = decoded.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return components.joined(separator: " ")
    }

    static func parseHTMLAttributes(_ rawAttributes: String) -> [String: String] {
        guard let attrRegex = htmlAttrRegex else {
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

    static func firstCapture(
        regex: NSRegularExpression,
        in text: String
    ) -> String? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    static func replacingRegex(_ regex: NSRegularExpression?, in text: String, with template: String) -> String {
        guard let regex else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template
        )
    }
}
