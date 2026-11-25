# Graph Report - isowebapps  (2026-11-25)

## Corpus Check
- 65 files · ~179,338 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: .entitlements 2, .plist 1)

## Summary
- 939 nodes · 2435 edges · 56 communities (19 shown, 37 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 119 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `cf821afc`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- CloudSyncManager
- WebViewNavigationState
- SearchEngine
- .createConfiguredWebView
- NSWindow
- WindowPresentationMode
- WebAppTileSettingsMenu
- IsolatedWKWebView
- SafariView
- ContentView
- ReaderHTMLUtilities
- OpenURLSheet
- CapsuleLifecycleController
- CapsuleDownloadManager
- WebKitMemoryManager
- MarkdownBlockParser
- WebViewCoordinator
- UBlockOriginExtensionManager
- URL
- AISummarizer
- WebAppItem
- CapsuleWindowPayload
- IsolatedCookieManager
- URL
- .body
- .domainName
- CapsuleSleepPolicy
- WebAppContainerView

## God Nodes (most connected - your core abstractions)
1. `CloudSyncManager` - 72 edges
2. `NSWindow` - 54 edges
3. `MainWindowTracker` - 52 edges
4. `WebAppItem` - 51 edges
5. `WebAppContainerView` - 48 edges
6. `CapsuleDownloadManager` - 47 edges
7. `.body` - 39 edges
8. `CapsuleLifecycleController` - 38 edges
9. `WebViewNavigationState` - 34 edges
10. `WindowPresentationMode` - 32 edges

## Surprising Connections (you probably didn't know these)
- `.deduplicatedStandaloneApps` --references--> `WebAppItem`  [INFERRED]
  ContentView.swift → WebAppItem.swift
- `.allHomeItems` --references--> `WebAppItem`  [INFERRED]
  ContentView.swift → WebAppItem.swift
- `.body` --references--> `WebAppItem`  [INFERRED]
  ContentView.swift → WebAppItem.swift
- `.matchingApps` --references--> `WebAppItem`  [INFERRED]
  ContentView.swift → WebAppItem.swift
- `.otherApps` --references--> `WebAppItem`  [INFERRED]
  ContentView.swift → WebAppItem.swift

## Import Cycles
- None detected.

## Communities (56 total, 37 thin omitted)

### Community 0 - "CloudSyncManager"
Cohesion: 0.07
Nodes (14): CloudKit, CapsuleSnapshot, CapsuleSyncConflict, CloudSyncManager, .cloudStoreURL, .currentConflict, .localStoreURL, GroupSnapshot (+6 more)

### Community 1 - "WebViewNavigationState"
Cohesion: 0.11
Nodes (20): DownloadBannerView, .body, .statusIcon, .subtitleText, IOSSolidBottomBar, .body, MacOSSolidBottomBar, .body (+12 more)

### Community 2 - "SearchEngine"
Cohesion: 0.08
Nodes (23): BlockingMode, basic, complete, .description, .id, optimal, GeneralSettingsView, .currentSnapshot (+15 more)

### Community 4 - "NSWindow"
Cohesion: 0.05
Nodes (18): .homeScreenView, isowebappsApp, .body, AppDelegate, CapsuleWindowCloseObserver, CapsuleWindowHostView, .body, .hostingWindow (+10 more)

### Community 7 - "WindowPresentationMode"
Cohesion: 0.05
Nodes (36): AddWebAppSheet, .body, AppKit, CapsuleSleepEvaluation, awake, ignoreNotYetPresented, sleep, CapsuleSleepState (+28 more)

### Community 8 - "WebAppTileSettingsMenu"
Cohesion: 0.40
Nodes (5): WebAppTileSettingsMenu, .body, .readerLinksToggleTitle, WebAppTileView, .body

### Community 12 - "ContentView"
Cohesion: 0.18
Nodes (7): ContentView, .allHomeItems, .deduplicatedGroups, .deduplicatedStandaloneApps, .emptyStateView, .hostingWindow, .isDragDropEnabled

### Community 16 - "ReaderHTMLUtilities"
Cohesion: 0.06
Nodes (32): HTMLToMarkdown, ReaderViewState, failed, idle, loaded, loading, BackgroundCaptureReadiness, notReadyYet (+24 more)

### Community 17 - "OpenURLSheet"
Cohesion: 0.22
Nodes (5): OpenURLSheet, .body, .matchingApps, .otherApps, View

### Community 18 - "CapsuleLifecycleController"
Cohesion: 0.15
Nodes (4): CapsuleWindowSleepSnapshot, CapsuleLifecycleController, .isClosed, .isDeepSleeping

### Community 23 - "CapsuleDownloadManager"
Cohesion: 0.07
Nodes (17): CapsuleDownloadItem, .isActive, .isFinished, State, awaitingPermission, cancelled, completed, downloading (+9 more)

### Community 25 - "MarkdownBlockParser"
Cohesion: 0.11
Nodes (23): CodeFenceOpen, ListKind, ordered, unordered, MarkdownBlock, MarkdownBlockKind, blockquote, codeBlock (+15 more)

### Community 27 - "UBlockOriginExtensionManager"
Cohesion: 0.12
Nodes (4): UBlockOriginExtensionManager, .hasInMemoryCaches, .isLoaded, UBlockRuleCompiler

### Community 29 - "URL"
Cohesion: 0.07
Nodes (23): IconImageCache, MarkdownBlockRow, .body, MarkdownCodeBlockView, .body, MarkdownImageView, .body, .candidateURLs (+15 more)

### Community 30 - "AISummarizer"
Cohesion: 0.16
Nodes (8): AISummarizer, .isAvailable, WebPageSummaryError, emptyContent, .errorDescription, generationFailed, modelUnavailable, webViewUnavailable

### Community 33 - "WebAppItem"
Cohesion: 0.20
Nodes (3): AddGroupSheet, .body, WebAppItem

### Community 36 - "CapsuleWindowPayload"
Cohesion: 0.08
Nodes (16): Double, SerializableCookie, CapsuleWindowPayload, CodingKeys, appId, instanceId, isSecondaryWindow, name (+8 more)

### Community 38 - "URL"
Cohesion: 0.18
Nodes (6): URL, .rootDomain, ReaderHistoryStack, .canGoBack, .canGoForward, .currentURL

### Community 50 - "WebAppContainerView"
Cohesion: 0.17
Nodes (5): IdentifiableURL, WebAppContainerView, .body, .hostingWindow, .shouldShowReaderOverlay

## Knowledge Gaps
- **134 isolated node(s):** `awaitingPermission`, `downloading`, `completed`, `failed`, `cancelled` (+129 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 278 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **37 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `URL` connect `URL` to `CloudSyncManager`, `WebViewNavigationState`, `SearchEngine`, `.createConfiguredWebView`, `WindowPresentationMode`, `.body`, `IsolatedWKWebView`, `SafariView`, `ReaderHTMLUtilities`, `WebAppContainerView`, `CapsuleDownloadManager`, `WebViewCoordinator`, `UBlockOriginExtensionManager`, `URL`?**
  _High betweenness centrality (0.202) - this node is a cross-community bridge._
- **Are the 9 inferred relationships involving `NSWindow` (e.g. with `.openCapsule()` and `.openEphemeralCapsule()`) actually correct?**
  _`NSWindow` has 9 INFERRED edges - model-reasoned connections that need verification._
- **What connects `awaitingPermission`, `downloading`, `completed` to the rest of the system?**
  _134 weakly-connected nodes found - possible missing edges._
- **Should `CloudSyncManager` be split into smaller, more focused modules?**
  _Cohesion score 0.07314974182444062 - nodes in this community are weakly interconnected._
- **Why does `CloudSyncManager` connect `CloudSyncManager` to `SearchEngine`, `NSWindow`, `IsolatedCookieManager`, `URL`, `ContentView`?**
  _High betweenness centrality (0.128) - this node is a cross-community bridge._
- **Are the 10 inferred relationships involving `WebAppItem` (e.g. with `.body` and `.createGroup()`) actually correct?**
  _`WebAppItem` has 10 INFERRED edges - model-reasoned connections that need verification._
- **Should `WebViewNavigationState` be split into smaller, more focused modules?**
  _Cohesion score 0.11428571428571428 - nodes in this community are weakly interconnected._