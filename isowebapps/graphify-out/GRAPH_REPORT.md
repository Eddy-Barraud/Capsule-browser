# Graph Report - isowebapps  (2026-11-21)

## Corpus Check
- 64 files · ~176,081 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: .entitlements 2, .plist 1)

## Summary
- 862 nodes · 2237 edges · 52 communities (14 shown, 38 thin omitted)
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 99 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `22b6c3d4`
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
- ContentView
- ReaderHTMLUtilities
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
10. `MarkdownBlockParser` - 30 edges

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

## Communities (52 total, 38 thin omitted)

### Community 0 - "CloudSyncManager"
Cohesion: 0.08
Nodes (14): CloudKit, CapsuleSnapshot, CapsuleSyncConflict, CloudSyncManager, .cloudStoreURL, .currentConflict, .localStoreURL, GroupSnapshot (+6 more)

### Community 1 - "WebViewNavigationState"
Cohesion: 0.05
Nodes (36): URL, .rootDomain, ReaderHistoryStack, .canGoBack, .canGoForward, .currentURL, ReaderDocument, .plainTextForSummary (+28 more)

### Community 2 - "SearchEngine"
Cohesion: 0.05
Nodes (42): BlockingMode, basic, complete, .description, .id, optimal, GeneralSettingsView, .currentSnapshot (+34 more)

### Community 4 - "NSWindow"
Cohesion: 0.06
Nodes (17): .homeScreenView, .body, AppDelegate, CapsuleWindowHostView, .body, .hostingWindow, .resolvedAppItem, CapsuleWindowPayload (+9 more)

### Community 7 - "WindowPresentationMode.swift"
Cohesion: 0.06
Nodes (21): AddWebAppSheet, .body, AppKit, State, awaitingPermission, cancelled, completed, downloading (+13 more)

### Community 8 - "ContentView.swift"
Cohesion: 0.14
Nodes (12): IconImageCache, OpenURLSheet, .body, .matchingApps, .otherApps, View, WebAppTileSettingsMenu, .body (+4 more)

### Community 12 - "ContentView"
Cohesion: 0.20
Nodes (8): ContentView, .allHomeItems, .body, .deduplicatedGroups, .deduplicatedStandaloneApps, .emptyStateView, .hostingWindow, .isDragDropEnabled

### Community 16 - "ReaderHTMLUtilities"
Cohesion: 0.08
Nodes (22): HTMLToMarkdown, BackgroundCaptureReadiness, notReadyYet, readyImmediately, requiresHumanVerification, usableAfterSettle, ReaderHTMLCapture, ReaderHTMLUtilities (+14 more)

### Community 23 - "CapsuleDownloadManager"
Cohesion: 0.09
Nodes (11): CapsuleDownloadItem, .isActive, .isFinished, CapsuleDownloadManager, .activeBannerItem, .hasActiveDownloads, DownloadContext, IOSFolderPickerCoordinator (+3 more)

### Community 25 - "MarkdownBlockParser"
Cohesion: 0.10
Nodes (26): CodeFenceOpen, ListKind, ordered, unordered, MarkdownBlock, MarkdownBlockKind, blockquote, codeBlock (+18 more)

### Community 27 - "UBlockOriginExtensionManager"
Cohesion: 0.15
Nodes (3): UBlockOriginExtensionManager, .hasInMemoryCaches, .isLoaded

### Community 29 - "URL"
Cohesion: 0.09
Nodes (24): Double, MarkdownBlockRow, .body, MarkdownCodeBlockView, .body, MarkdownImageView, .body, .linkURL (+16 more)

### Community 30 - "AISummarizer"
Cohesion: 0.16
Nodes (9): AISummarizer, .isAvailable, WebPageSummaryError, emptyContent, .errorDescription, generationFailed, modelUnavailable, pdfExtractionFailed (+1 more)

### Community 33 - "WebAppItem"
Cohesion: 0.17
Nodes (3): AddGroupSheet, .body, WebAppItem

## Knowledge Gaps
- **120 isolated node(s):** `.liveWebViewCount`, `.hasActiveAudioPlayback`, `.rootDomain`, `notReadyYet`, `requiresHumanVerification` (+115 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 253 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **38 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `URL` connect `WebViewNavigationState` to `CloudSyncManager`, `SearchEngine`, `.createConfiguredWebView`, `NSWindow`, `WindowPresentationMode.swift`, `ContentView`, `ReaderHTMLUtilities`, `IsolatedWKWebView`, `CapsuleDownloadManager`, `WebViewCoordinator`, `UBlockOriginExtensionManager`, `URL`?**
  _High betweenness centrality (0.212) - this node is a cross-community bridge._
- **Are the 10 inferred relationships involving `WebAppItem` (e.g. with `.body` and `.createGroup()`) actually correct?**
  _`WebAppItem` has 10 INFERRED edges - model-reasoned connections that need verification._
- **What connects `.liveWebViewCount`, `.hasActiveAudioPlayback`, `.rootDomain` to the rest of the system?**
  _120 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `CloudSyncManager` be split into smaller, more focused modules?**
  _Cohesion score 0.07943037974683544 - nodes in this community are weakly interconnected._
- **Why does `CloudSyncManager` connect `CloudSyncManager` to `WebViewNavigationState`, `SearchEngine`, `IsolatedCookieManager`, `ContentView`, `IsolatedWKWebView`, `UBlockOriginExtensionManager`?**
  _High betweenness centrality (0.132) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `WebAppContainerView` (e.g. with `.body` and `ReaderHistoryStack`) actually correct?**
  _`WebAppContainerView` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Should `WebViewNavigationState` be split into smaller, more focused modules?**
  _Cohesion score 0.05299145299145299 - nodes in this community are weakly interconnected._