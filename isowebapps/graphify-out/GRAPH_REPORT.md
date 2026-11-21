# Graph Report - isowebapps  (2026-11-21)

## Corpus Check
- 64 files · ~177,387 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: .entitlements 2, .plist 1)

## Summary
- 876 nodes · 2286 edges · 55 communities (14 shown, 41 thin omitted)
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 99 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `cfb0c006`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- CloudSyncManager
- WebViewNavigationState
- SearchEngine
- .createConfiguredWebView
- NSWindow
- IsolatedCookieManager
- WindowPresentationMode.swift
- ContentView.swift
- SafariView
- ContentView
- ReaderHTMLUtilities
- OpenURLSheet
- IsolatedWKWebView
- CapsuleDownloadManager
- WebKitMemoryManager
- MarkdownBlockParser
- WebViewCoordinator
- UBlockOriginExtensionManager
- URL
- AISummarizer
- WebAppItem
- SerializableCookie
- AddGroupSheet

## God Nodes (most connected - your core abstractions)
1. `CloudSyncManager` - 72 edges
2. `WebAppItem` - 51 edges
3. `MainWindowTracker` - 47 edges
4. `WebAppContainerView` - 46 edges
5. `CapsuleDownloadManager` - 46 edges
6. `NSWindow` - 43 edges
7. `.body` - 33 edges
8. `WebViewNavigationState` - 31 edges
9. `ContentView` - 31 edges
10. `ReaderHTMLUtilities` - 30 edges

## Surprising Connections (you probably didn't know these)
- `.allHomeItems` --references--> `WebAppItem`  [INFERRED]
  ContentView.swift → WebAppItem.swift
- `.deduplicatedStandaloneApps` --references--> `WebAppItem`  [INFERRED]
  ContentView.swift → WebAppItem.swift
- `.matchingApps` --references--> `WebAppItem`  [INFERRED]
  ContentView.swift → WebAppItem.swift
- `.otherApps` --references--> `WebAppItem`  [INFERRED]
  ContentView.swift → WebAppItem.swift
- `.body` --references--> `WebAppItem`  [INFERRED]
  ContentView.swift → WebAppItem.swift

## Import Cycles
- None detected.

## Communities (55 total, 41 thin omitted)

### Community 0 - "CloudSyncManager"
Cohesion: 0.08
Nodes (14): CloudKit, CapsuleSnapshot, CapsuleSyncConflict, CloudSyncManager, .cloudStoreURL, .currentConflict, .localStoreURL, GroupSnapshot (+6 more)

### Community 1 - "WebViewNavigationState"
Cohesion: 0.06
Nodes (29): ReaderHistoryStack, .canGoBack, .canGoForward, .currentURL, DownloadBannerView, .body, .statusIcon, .subtitleText (+21 more)

### Community 2 - "SearchEngine"
Cohesion: 0.05
Nodes (43): BlockingMode, basic, complete, .description, .id, optimal, GeneralSettingsView, .currentSnapshot (+35 more)

### Community 4 - "NSWindow"
Cohesion: 0.06
Nodes (18): .homeScreenView, .body, .body, AppDelegate, CapsuleWindowHostView, .body, .hostingWindow, .resolvedAppItem (+10 more)

### Community 7 - "WindowPresentationMode.swift"
Cohesion: 0.07
Nodes (18): AddWebAppSheet, .body, AppKit, State, awaitingPermission, cancelled, completed, downloading (+10 more)

### Community 8 - "ContentView.swift"
Cohesion: 0.18
Nodes (6): IconImageCache, WebAppTileSettingsMenu, .body, .readerLinksToggleTitle, WebAppTileView, .body

### Community 12 - "ContentView"
Cohesion: 0.18
Nodes (8): ContentView, .allHomeItems, .body, .deduplicatedGroups, .deduplicatedStandaloneApps, .emptyStateView, .hostingWindow, .isDragDropEnabled

### Community 16 - "ReaderHTMLUtilities"
Cohesion: 0.07
Nodes (27): HTMLToMarkdown, BackgroundCaptureReadiness, notReadyYet, readyImmediately, requiresHumanVerification, usableAfterSettle, ReaderHTMLCapture, ReaderHTMLUtilities (+19 more)

### Community 17 - "OpenURLSheet"
Cohesion: 0.22
Nodes (5): OpenURLSheet, .body, .matchingApps, .otherApps, View

### Community 23 - "CapsuleDownloadManager"
Cohesion: 0.08
Nodes (11): CapsuleDownloadItem, .isActive, .isFinished, CapsuleDownloadManager, .activeBannerItem, .hasActiveDownloads, DownloadContext, IOSFolderPickerCoordinator (+3 more)

### Community 25 - "MarkdownBlockParser"
Cohesion: 0.11
Nodes (23): CodeFenceOpen, ListKind, ordered, unordered, MarkdownBlock, MarkdownBlockKind, blockquote, codeBlock (+15 more)

### Community 27 - "UBlockOriginExtensionManager"
Cohesion: 0.12
Nodes (4): UBlockOriginExtensionManager, .hasInMemoryCaches, .isLoaded, UBlockRuleCompiler

### Community 29 - "URL"
Cohesion: 0.08
Nodes (30): URL, .rootDomain, Double, MarkdownBlockRow, .body, MarkdownCodeBlockView, .body, MarkdownImageView (+22 more)

### Community 30 - "AISummarizer"
Cohesion: 0.14
Nodes (9): AISummarizer, .isAvailable, WebPageSummaryError, emptyContent, .errorDescription, generationFailed, modelUnavailable, webViewUnavailable (+1 more)

## Knowledge Gaps
- **119 isolated node(s):** `FoundationModels`, `webViewUnavailable`, `emptyContent`, `modelUnavailable`, `generationFailed` (+114 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 251 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **41 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `URL` connect `URL` to `CloudSyncManager`, `WebViewNavigationState`, `SearchEngine`, `.createConfiguredWebView`, `NSWindow`, `WindowPresentationMode.swift`, `SafariView`, `ContentView`, `ReaderHTMLUtilities`, `IsolatedWKWebView`, `CapsuleDownloadManager`, `WebViewCoordinator`, `UBlockOriginExtensionManager`?**
  _High betweenness centrality (0.226) - this node is a cross-community bridge._
- **Are the 10 inferred relationships involving `WebAppItem` (e.g. with `.body` and `.createGroup()`) actually correct?**
  _`WebAppItem` has 10 INFERRED edges - model-reasoned connections that need verification._
- **What connects `FoundationModels`, `webViewUnavailable`, `emptyContent` to the rest of the system?**
  _119 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `CloudSyncManager` be split into smaller, more focused modules?**
  _Cohesion score 0.07777777777777778 - nodes in this community are weakly interconnected._
- **Why does `CloudSyncManager` connect `CloudSyncManager` to `WebViewNavigationState`, `SearchEngine`, `IsolatedCookieManager`, `ContentView`, `IsolatedWKWebView`, `URL`, `AISummarizer`?**
  _High betweenness centrality (0.132) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `WebAppContainerView` (e.g. with `.body` and `ReaderHistoryStack`) actually correct?**
  _`WebAppContainerView` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Should `WebViewNavigationState` be split into smaller, more focused modules?**
  _Cohesion score 0.05707762557077625 - nodes in this community are weakly interconnected._