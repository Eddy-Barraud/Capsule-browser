//
//  MarkdownReaderView.swift
//  isowebapps
//
//  Description:
//  Native macOS Markdown Reader View rendering parsed CommonMark + GFM blocks
//  with clean typography, font/serif controls, code & table support, async images,
//  and in-place link navigation.
//

#if os(macOS)
import SwiftUI
import AppKit

enum ReaderViewState: Equatable {
    case idle
    case loading(URL?, statusMessage: String? = nil)
    case loaded(ReaderDocument)
    case failed(message: String, url: URL?)
}

struct MarkdownReaderView: View {
    let state: ReaderViewState
    let onOpenLinkInPlace: (URL) -> Void
    let onOpenLinkInNewReader: (URL) -> Void
    let onLoadFullWebpage: () -> Void
    let onRetry: () -> Void

    @AppStorage("reader_font_scale") private var fontScale: Double = 1.0
    @AppStorage("reader_use_serif") private var useSerif: Bool = false
    @State private var copiedMarkdown = false

    private var clampedScale: CGFloat {
        CGFloat(min(1.6, max(0.8, fontScale)))
    }

    private var bodyFontDesign: Font.Design {
        useSerif ? .serif : .default
    }

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
                .ignoresSafeArea()

            switch state {
            case .idle:
                loadingView(url: nil, statusMessage: nil)

            case .loading(let url, let statusMessage):
                loadingView(url: url, statusMessage: statusMessage)

            case .failed(let message, let url):
                errorView(message: message, url: url)

            case .loaded(let document):
                loadedView(document)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading & Error States

    private func loadingView(url: URL?, statusMessage: String?) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)

            Text(statusMessage ?? "Loading Reader View…")
                .font(.system(size: 14, weight: .medium))

            if let host = url?.host {
                Text(host)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Button("Load Full Webpage", action: onLoadFullWebpage)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 6)
        }
        .padding(32)
    }

    private func errorView(message: String, url: URL?) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.plaintext")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)

            Text("Reader View Unavailable")
                .font(.system(size: 17, weight: .semibold))

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            if let url {
                Text(url.absoluteString)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 440)
            }

            HStack(spacing: 10) {
                Button("Load Full Webpage", action: onLoadFullWebpage)
                    .buttonStyle(.borderedProminent)

                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .padding(32)
    }

    // MARK: - Loaded Reader Article

    private func loadedView(_ document: ReaderDocument) -> some View {
        VStack(spacing: 0) {
            readerUtilityBar(for: document)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if document.shouldShowHeaderTitle {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(document.title)
                                .font(.system(size: 30 * clampedScale, weight: .bold, design: bodyFontDesign))
                                .lineSpacing(4)
                                .foregroundStyle(.primary)

                            if let author = document.author, !author.isEmpty {
                                Text("By \(author)")
                                    .font(.system(size: 13 * clampedScale, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.bottom, 6)

                        Divider()
                    }

                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(document.blocks) { block in
                            MarkdownBlockRow(
                                block: block,
                                documentURL: document.url,
                                fontScale: clampedScale,
                                fontDesign: bodyFontDesign,
                                onNavigateLink: handleLinkActivation
                            )
                        }
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: 740, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .environment(\.openURL, OpenURLAction { url in
                handleOpenURLAction(url)
            })
        }
    }

    private func readerUtilityBar(for document: ReaderDocument) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: document.source == .fastHTMLFetch ? "bolt.fill" : "doc.plaintext.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(document.siteName ?? document.url.host ?? "Reader")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("•")
                    .foregroundStyle(.tertiary)

                Text("\(document.readingMinutes) min read")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if let author = document.author, !author.isEmpty, !document.shouldShowHeaderTitle {
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(author)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    fontScale = max(0.8, (fontScale - 0.1).roundedToTenth())
                } label: {
                    Text("A-")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(fontScale <= 0.81)
                .help("Decrease Reader font size")

                Button {
                    fontScale = min(1.6, (fontScale + 0.1).roundedToTenth())
                } label: {
                    Text("A+")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(fontScale >= 1.59)
                .help("Increase Reader font size")

                Button {
                    useSerif.toggle()
                } label: {
                    Text("Aa")
                        .font(.system(size: 11, weight: .medium, design: useSerif ? .serif : .default))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(useSerif ? "Switch to Sans-Serif font" : "Switch to Serif font")

                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(document.markdown, forType: .string)
                    copiedMarkdown = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedMarkdown = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedMarkdown ? "checkmark" : "doc.on.doc")
                        Text(copiedMarkdown ? "Copied" : "Markdown")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy converted Markdown")

                Button("Full Page", action: onLoadFullWebpage)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Exit Reader View and show full webpage")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Link Handling

    private func handleOpenURLAction(_ url: URL) -> OpenURLAction.Result {
        guard let scheme = url.scheme?.lowercased() else {
            return .discarded
        }
        if scheme == "mailto" || scheme == "tel" {
            NSWorkspace.shared.open(url)
            return .handled
        }
        guard scheme == "http" || scheme == "https" else {
            return .discarded
        }
        handleLinkActivation(url)
        return .handled
    }

    private func handleLinkActivation(_ url: URL) {
        if NSEvent.modifierFlags.contains(.command) {
            onOpenLinkInNewReader(url)
        } else {
            onOpenLinkInPlace(url)
        }
    }
}

// MARK: - Block Renderer

private struct MarkdownBlockRow: View {
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

private struct MarkdownInlineText: View {
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

private struct MarkdownCodeBlockView: View {
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

private struct MarkdownTableView: View {
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

@MainActor
final class ReaderImageCache {
    static let shared = ReaderImageCache()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 40
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    private init() {}

    func image(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: NSImage, forKey key: String) {
        let pixelCost: Int
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            pixelCost = max(1, cgImage.bytesPerRow * cgImage.height)
        } else {
            pixelCost = max(1, Int(image.size.width * image.size.height * 4))
        }
        cache.setObject(image, forKey: key as NSString, cost: pixelCost)
    }

    func clear() {
        cache.removeAllObjects()
    }
}

@MainActor
private enum ReaderImageLoader {
    static func loadImage(urlString: String, documentURL: URL) async -> NSImage? {
        let candidates = ReaderHTMLUtilities.candidateImageURLs(from: urlString, relativeTo: documentURL)
        guard !candidates.isEmpty else { return nil }

        for candidate in candidates {
            if let cached = ReaderImageCache.shared.image(forKey: candidate.absoluteString) {
                return cached
            }
        }

        let userAgent = IsolatedWebViewRepresentable.defaultUserAgent
        let refererOrigin: String? = {
            guard let scheme = documentURL.scheme, let host = documentURL.host else { return nil }
            return "\(scheme)://\(host)/"
        }()

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        for candidate in candidates {
            if Task.isCancelled { return nil }
            if let fetched = await fetchCandidate(
                url: candidate,
                session: session,
                userAgent: userAgent,
                referer: refererOrigin
            ) {
                ReaderImageCache.shared.insert(fetched, forKey: candidate.absoluteString)
                if let primaryKey = candidates.first?.absoluteString, primaryKey != candidate.absoluteString {
                    ReaderImageCache.shared.insert(fetched, forKey: primaryKey)
                }
                return fetched
            }
        }
        return nil
    }

    private static func fetchCandidate(
        url: URL,
        session: URLSession,
        userAgent: String,
        referer: String?
    ) async -> NSImage? {
        let refererModes: [String?] = referer != nil ? [referer, nil] : [nil]
        for (attemptIndex, activeReferer) in refererModes.enumerated() {
            if Task.isCancelled { return nil }
            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("image/avif,image/webp,image/apng,image/png,image/jpeg,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            if let activeReferer {
                request.setValue(activeReferer, forHTTPHeaderField: "Referer")
            }

            do {
                let (data, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    let status = httpResponse.statusCode
                    if (status == 400 || status == 403), attemptIndex == 0, refererModes.count > 1 {
                        // Retry once without Referer for strict anti-hotlink CDNs
                        continue
                    }
                    guard (200..<300).contains(status) else { return nil }
                }
                guard !data.isEmpty,
                      let nsImage = NSImage(data: data),
                      nsImage.size.width > 1,
                      nsImage.size.height > 1 else {
                    return nil
                }
                return nsImage
            } catch is CancellationError {
                return nil
            } catch {
                return nil
            }
        }
        return nil
    }
}

private struct MarkdownImageView: View {
    let alt: String
    let urlString: String
    let title: String?
    let linkURLString: String?
    let documentURL: URL
    let fontScale: CGFloat
    let onNavigateLink: (URL) -> Void

    @State private var loadedImage: NSImage? = nil
    @State private var didFail: Bool = false

    private var candidateURLs: [URL] {
        ReaderHTMLUtilities.candidateImageURLs(from: urlString, relativeTo: documentURL)
    }

    private var linkURL: URL? {
        guard let linkURLString else { return nil }
        return ReaderHTMLUtilities.candidateImageURLs(from: linkURLString, relativeTo: documentURL).first
    }

    private var taskIdentity: String {
        "\(documentURL.absoluteString)|\(urlString)"
    }

    var body: some View {
        if !candidateURLs.isEmpty {
            VStack(alignment: .center, spacing: 6) {
                imageContent
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if let caption = resolvedCaption {
                    Text(caption)
                        .font(.system(size: 12 * fontScale))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 6)
            .task(id: taskIdentity) {
                loadedImage = nil
                didFail = false
                if let image = await ReaderImageLoader.loadImage(urlString: urlString, documentURL: documentURL) {
                    loadedImage = image
                } else if !Task.isCancelled {
                    didFail = true
                }
            }
        }
    }

    private var resolvedCaption: String? {
        if let title, !title.isEmpty { return title }
        if !alt.isEmpty { return alt }
        return nil
    }

    @ViewBuilder
    private var imageContent: some View {
        let rendered: AnyView = {
            if let nsImage = loadedImage {
                let maxW = min(680, max(nsImage.size.width, 1))
                let maxH = min(460, max(nsImage.size.height, 1))
                return AnyView(
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: maxW, maxHeight: maxH)
                )
            } else if didFail {
                if !alt.isEmpty {
                    return AnyView(
                        HStack(spacing: 6) {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                            Text(alt)
                                .font(.system(size: 12 * fontScale))
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    )
                }
                return AnyView(EmptyView())
            } else {
                return AnyView(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(maxWidth: 680)
                        .frame(height: 160)
                        .overlay(ProgressView().controlSize(.small))
                )
            }
        }()

        if let destination = linkURL {
            rendered
                .onTapGesture {
                    onNavigateLink(destination)
                }
                .help("Open linked page: \(destination.absoluteString)")
        } else {
            rendered
        }
    }
}

private extension Double {
    func roundedToTenth() -> Double {
        (self * 10).rounded() / 10
    }
}
#endif
