//
//  ReaderImageViews.swift
//  isowebapps
//
//  Description:
//  Bounded image cache, background image loader using a shared ephemeral URLSession,
//  and SwiftUI `MarkdownImageView` for Reader Mode.
//

#if os(macOS)
import SwiftUI
import AppKit

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
        cache.setObject(image, forKey: key as NSString, cost: IconImageCache.pixelCost(for: image))
    }

    func clear() {
        cache.removeAllObjects()
    }
}

private nonisolated enum ReaderImageLoader {
    private static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static func loadImage(urlString: String, documentURL: URL) async -> NSImage? {
        let candidates = ReaderHTMLUtilities.candidateImageURLs(from: urlString, relativeTo: documentURL)
        guard !candidates.isEmpty else { return nil }

        for candidate in candidates {
            if let cached = await MainActor.run(body: { ReaderImageCache.shared.image(forKey: candidate.absoluteString) }) {
                return cached
            }
        }

        let userAgent = await MainActor.run { IsolatedWebViewRepresentable.defaultUserAgent }
        let refererOrigin: String? = {
            guard let scheme = documentURL.scheme, let host = documentURL.host else { return nil }
            return "\(scheme)://\(host)/"
        }()

        return await Task.detached(priority: .userInitiated) {
            for candidate in candidates {
                if Task.isCancelled { return nil }
                if let fetched = await fetchCandidate(
                    url: candidate,
                    session: sharedSession,
                    userAgent: userAgent,
                    referer: refererOrigin
                ) {
                    let primaryKey = candidates.first?.absoluteString
                    await MainActor.run {
                        ReaderImageCache.shared.insert(fetched, forKey: candidate.absoluteString)
                        if let primaryKey, primaryKey != candidate.absoluteString {
                            ReaderImageCache.shared.insert(fetched, forKey: primaryKey)
                        }
                    }
                    return fetched
                }
            }
            return nil
        }.value
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
                        continue
                    }
                    guard (200..<300).contains(status) else { return nil }
                }
                guard !data.isEmpty,
                      let nsImage = IconImageCache.decodeBoundedImage(from: data, maxPixelSize: 1600),
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

struct MarkdownImageView: View {
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
#endif
