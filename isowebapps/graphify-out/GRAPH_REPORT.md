# Graph Report - isowebapps  (2026-11-21)

## Corpus Check
- 60 files · ~164,719 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: .entitlements 2, .plist 1)

## Summary
- 650 nodes · 1626 edges · 40 communities (10 shown, 30 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 83 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `9ee92d6a`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- CloudSyncManager
- WebViewNavigationState
- SearchEngine
- NSWindow
- IsolatedCookieManager
- WindowPresentationMode.swift
- ContentView.swift
- ContentView
- IsolatedWKWebView
- CapsuleDownloadManager
- WebKitMemoryManager
- WebViewCoordinator
- UBlockOriginExtensionManager
- IsolatedWebViewRepresentable
- WebAppItem
- SerializableCookie

## God Nodes (most connected - your core abstractions)
1. `CloudSyncManager` - 72 edges
2. `WebAppItem` - 50 edges
3. `MainWindowTracker` - 47 edges
4. `CapsuleDownloadManager` - 46 edges
5. `NSWindow` - 43 edges
6. `ContentView` - 31 edges
7. `IsolatedWKWebView` - 29 edges
8. `WebViewCoordinator` - 27 edges
9. `WebAppContainerView` - 27 edges
10. `CapsuleDownloadItem` - 26 edges

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

## Communities (40 total, 30 thin omitted)

### Community 0 - "CloudSyncManager"
Cohesion: 0.07
Nodes (15): CloudKit, CapsuleSnapshot, CapsuleSyncConflict, CloudSyncManager, .cloudStoreURL, .currentConflict, .localStoreURL, GroupSnapshot (+7 more)

### Community 1 - "WebViewNavigationState"
Cohesion: 0.08
Nodes (23): DownloadBannerView, .body, .statusIcon, .subtitleText, IdentifiableURL, IOSSolidBottomBar, .body, MacOSSolidBottomBar (+15 more)

### Community 2 - "SearchEngine"
Cohesion: 0.06
Nodes (31): BlockingMode, basic, complete, .description, .id, optimal, GeneralSettingsView, .currentSnapshot (+23 more)

### Community 4 - "NSWindow"
Cohesion: 0.06
Nodes (16): .body, AppDelegate, CapsuleWindowHostView, .body, .hostingWindow, .resolvedAppItem, CapsuleWindowPayload, .id (+8 more)

### Community 7 - "WindowPresentationMode.swift"
Cohesion: 0.05
Nodes (24): AddWebAppSheet, .body, AISummarizer, .isAvailable, WebPageSummaryError, emptyContent, .errorDescription, generationFailed (+16 more)

### Community 8 - "ContentView.swift"
Cohesion: 0.16
Nodes (10): IconImageCache, OpenURLSheet, .body, .matchingApps, .otherApps, View, WebAppTileSettingsMenu, .body (+2 more)

### Community 12 - "ContentView"
Cohesion: 0.14
Nodes (9): ContentView, .allHomeItems, .body, .deduplicatedGroups, .deduplicatedStandaloneApps, .emptyStateView, .homeScreenView, .hostingWindow (+1 more)

### Community 23 - "CapsuleDownloadManager"
Cohesion: 0.07
Nodes (20): CapsuleDownloadItem, .isActive, .isFinished, CapsuleDownloadManager, .activeBannerItem, .hasActiveDownloads, DownloadContext, IOSFolderPickerCoordinator (+12 more)

### Community 27 - "UBlockOriginExtensionManager"
Cohesion: 0.11
Nodes (4): UBlockOriginExtensionManager, .hasInMemoryCaches, .isLoaded, UBlockRuleCompiler

### Community 33 - "WebAppItem"
Cohesion: 0.17
Nodes (3): AddGroupSheet, .body, WebAppItem

## Knowledge Gaps
- **62 isolated node(s):** `awaitingPermission`, `downloading`, `completed`, `failed`, `cancelled` (+57 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 188 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **30 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CloudSyncManager` connect `CloudSyncManager` to `IsolatedCookieManager`, `ContentView`, `IsolatedWKWebView`, `CapsuleDownloadManager`, `UBlockOriginExtensionManager`?**
  _High betweenness centrality (0.187) - this node is a cross-community bridge._
- **Are the 10 inferred relationships involving `WebAppItem` (e.g. with `.body` and `.createGroup()`) actually correct?**
  _`WebAppItem` has 10 INFERRED edges - model-reasoned connections that need verification._
- **What connects `awaitingPermission`, `downloading`, `completed` to the rest of the system?**
  _62 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `CloudSyncManager` be split into smaller, more focused modules?**
  _Cohesion score 0.06870428422152561 - nodes in this community are weakly interconnected._
- **Why does `URL` connect `CapsuleDownloadManager` to `CloudSyncManager`, `WebViewNavigationState`, `SearchEngine`, `NSWindow`, `WindowPresentationMode.swift`, `ContentView`, `IsolatedWKWebView`, `WebViewCoordinator`, `UBlockOriginExtensionManager`, `.webView`, `IsolatedWebViewRepresentable`?**
  _High betweenness centrality (0.148) - this node is a cross-community bridge._
- **Are the 7 inferred relationships involving `NSWindow` (e.g. with `.openCapsule()` and `.openEphemeralCapsule()`) actually correct?**
  _`NSWindow` has 7 INFERRED edges - model-reasoned connections that need verification._
- **Should `WebViewNavigationState` be split into smaller, more focused modules?**
  _Cohesion score 0.07706766917293233 - nodes in this community are weakly interconnected._