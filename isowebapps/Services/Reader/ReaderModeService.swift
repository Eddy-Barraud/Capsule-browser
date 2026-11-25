//
//  ReaderModeService.swift
//  isowebapps
//
//  Description:
//  HTML fetching and conversion pipeline powering the in-app Markdown Reader (macOS)
//  and AI Markdown summarization (macOS & iOS).
//  Converts either live DOM HTML extracted from WKWebView or lightweight HTML-only HTTP fetches
//  via `HTMLToMarkdown` into parsed `ReaderDocument` models.
//

import Foundation
import HTMLToMarkdown

nonisolated enum ReaderDocumentSource: Sendable, Equatable {
    case liveWebView
    case fastHTMLFetch
}

nonisolated struct ReaderDocument: Sendable, Equatable {
    let url: URL
    let title: String
    let siteName: String?
    let author: String?
    let markdown: String
    let blocks: [MarkdownBlock]
    let readingMinutes: Int
    let source: ReaderDocumentSource

    var shouldShowHeaderTitle: Bool {
        let cleanTitle = Self.normalizedComparisonKey(title)
        guard !cleanTitle.isEmpty else { return false }
        for block in blocks {
            if case .heading(let level, let headingText) = block.kind, level == 1 {
                let cleanHeading = Self.normalizedComparisonKey(ReaderHTMLUtilities.plainText(fromMarkdown: headingText))
                if !cleanHeading.isEmpty && (cleanHeading == cleanTitle || cleanTitle.hasPrefix(cleanHeading)) {
                    return false
                }
                break
            }
            if case .paragraph = block.kind {
                break
            }
        }
        return true
    }

    private static func normalizedComparisonKey(_ input: String) -> String {
        input
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}

nonisolated enum ReaderModeError: LocalizedError, Sendable {
    case invalidURL
    case httpError(Int)
    case nonHTMLContent(String)
    case javaScriptRequired
    case humanVerificationRequired(URL)
    case emptyContent
    case networkFailed(String)
    case conversionFailed(String)

    var shouldFallbackToBackgroundWebView: Bool {
        switch self {
        case .javaScriptRequired, .emptyContent, .humanVerificationRequired:
            return true
        case .httpError(let statusCode):
            return ReaderHTMLUtilities.shouldFallbackToBackgroundWebView(httpStatusCode: statusCode)
        case .invalidURL, .nonHTMLContent, .networkFailed, .conversionFailed:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The page URL is invalid or unsupported for Reader view."
        case .httpError(let statusCode):
            if statusCode == 403 || statusCode == 401 {
                return "This website blocked lightweight Reader access (HTTP \(statusCode)). Load the full webpage to view it."
            }
            return "The server returned HTTP \(statusCode). Load the full webpage instead."
        case .nonHTMLContent(let mime):
            return "This resource (\(mime)) is not an HTML article and cannot be rendered in Reader mode."
        case .javaScriptRequired:
            return "This page requires JavaScript to render its content. Load the full webpage to view it."
        case .humanVerificationRequired:
            return "This website requires a human verification check before it can be shown in Reader view."
        case .emptyContent:
            return "No readable article content could be extracted from this page."
        case .networkFailed(let reason):
            return "Failed to fetch Reader page: \(reason)"
        case .conversionFailed(let reason):
            return "Could not convert webpage HTML to Markdown: \(reason)"
        }
    }
}

nonisolated enum ReaderModeService {
    static let readerExcludeSelectors: [String] = [
        "nav",
        "footer",
        "aside",
        "form",
        "button",
        "dialog",
        "svg",
        "canvas",
        "template",
        "[role=navigation]",
        "[role=banner]",
        "[role=contentinfo]",
        "[role=complementary]",
        "[role=search]",
        "[role=dialog]",
        "[aria-hidden=true]",
        ".cookie-banner",
        "#cookie-banner",
        ".advertisement",
        ".ad-container"
    ]

    static let tieredIncludeSelectors: [String] = [
        "article",
        "main, [role=main]",
        "#mw-content-text, .article-content, .post-content, .entry-content, .story-body, [itemprop=articleBody]"
    ]

    /// Converts raw HTML into clean CommonMark + GFM Markdown using `HTMLToMarkdown`.
    static func convertHTMLToMarkdown(
        _ html: String,
        baseURL: URL,
        useTieredExtraction: Bool
    ) throws -> String {
        let preparedHTML = ReaderHTMLUtilities.normalizeLazyImages(in: html)

        func makePlugins() -> [Plugin] {
            var cmOptions = CommonmarkOptions()
            cmOptions.disableListEndComment = true
            return [
                BasePlugin(),
                CommonmarkPlugin(options: cmOptions),
                GFMPlugin()
            ]
        }

        let domainOption = ConverterOption.domain(baseURL.absoluteString)
        let excludeOption = ConverterOption.excludeSelectors(readerExcludeSelectors)

        if useTieredExtraction {
            for selector in tieredIncludeSelectors {
                let candidate = try HTMLToMarkdown.convert(
                    preparedHTML,
                    plugins: makePlugins(),
                    options: [
                        domainOption,
                        excludeOption,
                        .includeSelector(selector)
                    ]
                )
                let plainCount = ReaderHTMLUtilities.plainText(fromMarkdown: candidate).count
                if plainCount >= 250 {
                    return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        let fullConverted = try HTMLToMarkdown.convert(
            preparedHTML,
            plugins: makePlugins(),
            options: [domainOption, excludeOption]
        )
        return fullConverted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Converts already-rendered DOM HTML captured from a live `WKWebView`.
    static func convertLiveCapture(_ capture: ReaderHTMLCapture) async throws -> ReaderDocument {
        guard let url = URL(string: capture.urlString) else {
            throw ReaderModeError.invalidURL
        }

        return try await Task.detached(priority: .userInitiated) {
            let extractedMeta = ReaderHTMLUtilities.extractMetadata(from: capture.html)
            let resolvedTitle = !capture.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? capture.title.trimmingCharacters(in: .whitespacesAndNewlines)
                : (extractedMeta.title ?? url.host ?? url.absoluteString)
            let resolvedSiteName = capture.siteName ?? extractedMeta.siteName ?? url.host
            let resolvedAuthor = capture.author ?? extractedMeta.author

            let markdown: String
            do {
                markdown = try convertHTMLToMarkdown(capture.html, baseURL: url, useTieredExtraction: false)
            } catch {
                throw ReaderModeError.conversionFailed(error.localizedDescription)
            }

            let trimmedMarkdown = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedMarkdown.isEmpty else {
                throw ReaderModeError.emptyContent
            }

            let blocks = MarkdownBlockParser.parse(trimmedMarkdown)
            let minutes = ReaderHTMLUtilities.estimatedReadingMinutes(for: trimmedMarkdown)

            return ReaderDocument(
                url: url,
                title: resolvedTitle,
                siteName: resolvedSiteName,
                author: resolvedAuthor,
                markdown: trimmedMarkdown,
                blocks: blocks,
                readingMinutes: minutes,
                source: .liveWebView
            )
        }.value
    }

    private static let sharedEphemeralSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Fetches only the target URL's HTML via an ephemeral `URLSession` (no JS/CSS/subresources)
    /// and converts it directly into a rendered `ReaderDocument`.
    static func fetchAndConvert(url: URL) async throws -> ReaderDocument {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ReaderModeError.invalidURL
        }

        let userAgent = await MainActor.run {
            IsolatedWebViewRepresentable.defaultUserAgent
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await sharedEphemeralSession.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ReaderModeError.networkFailed(error.localizedDescription)
        }

        let resolvedURL = response.url ?? url
        if ReaderHTMLUtilities.isRobotCheckURL(resolvedURL) {
            throw ReaderModeError.humanVerificationRequired(resolvedURL)
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            throw ReaderModeError.httpError(httpResponse.statusCode)
        }

        if let mimeType = response.mimeType?.lowercased(), !mimeType.isEmpty {
            let isHTMLCompatible = mimeType.contains("html") || mimeType.contains("xhtml") || mimeType == "text/plain"
            if !isHTMLCompatible {
                throw ReaderModeError.nonHTMLContent(mimeType)
            }
        }

        let textEncodingName = response.textEncodingName

        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            let html = ReaderHTMLUtilities.decodeHTMLData(data, textEncodingName: textEncodingName)
            let metadata = ReaderHTMLUtilities.extractMetadata(from: html)
            if ReaderHTMLUtilities.isRobotCheckContent(
                urlString: resolvedURL.absoluteString,
                html: html,
                title: metadata.title
            ) {
                throw ReaderModeError.humanVerificationRequired(resolvedURL)
            }
            let title = metadata.title ?? resolvedURL.host ?? resolvedURL.absoluteString
            let siteName = metadata.siteName ?? resolvedURL.host

            let markdown: String
            do {
                markdown = try convertHTMLToMarkdown(html, baseURL: resolvedURL, useTieredExtraction: true)
            } catch {
                throw ReaderModeError.conversionFailed(error.localizedDescription)
            }

            try Task.checkCancellation()

            if ReaderHTMLUtilities.looksLikeJavaScriptShell(markdown: markdown, rawHTML: html) {
                throw ReaderModeError.javaScriptRequired
            }

            let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ReaderModeError.emptyContent
            }

            let blocks = MarkdownBlockParser.parse(trimmed)
            let minutes = ReaderHTMLUtilities.estimatedReadingMinutes(for: trimmed)

            return ReaderDocument(
                url: resolvedURL,
                title: title,
                siteName: siteName,
                author: metadata.author,
                markdown: trimmed,
                blocks: blocks,
                readingMinutes: minutes,
                source: .fastHTMLFetch
            )
        }.value
    }
}
