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

private extension Double {
    func roundedToTenth() -> Double {
        (self * 10).rounded() / 10
    }
}
#endif
