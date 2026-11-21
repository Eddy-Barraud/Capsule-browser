# Graph Report - isowebapps  (2026-11-21)

## Corpus Check
- 59 files · ~160,440 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: .entitlements 2, .plist 1)

## Summary
- 555 nodes · 1339 edges · 29 communities (10 shown, 19 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 65 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `4627cc20`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- CloudSyncManager
- WebViewNavigationState
- SearchEngine
- WebViewCoordinator
- NSWindow
- IsolatedCookieManager
- WindowPresentationMode.swift
- AISummarizer
- AddWebAppSheet
- WebAppItem
- IsolatedWKWebView
- SerializableCookie
- UBlockOriginExtensionManager

## God Nodes (most connected - your core abstractions)
1. `CloudSyncManager` - 72 edges
2. `WebAppItem` - 50 edges
3. `MainWindowTracker` - 47 edges
4. `NSWindow` - 43 edges
5. `ContentView` - 31 edges
6. `WebViewCoordinator` - 27 edges
7. `WebViewNavigationState` - 26 edges
8. `WebAppContainerView` - 26 edges
9. `IsolatedCookieManager` - 25 edges
10. `UBlockOriginExtensionManager` - 25 edges

## Surprising Connections (you probably didn't know these)
- `ContentView` --calls--> `WeakWindowBox`  [INFERRED]
  ContentView.swift → WindowPresentationMode.swift
- `.body` --calls--> `ContentView`  [INFERRED]
  isowebappsApp.swift → ContentView.swift
- `.body` --calls--> `AddWebAppSheet`  [INFERRED]
  ContentView.swift → AddWebAppSheet.swift
- `.body` --calls--> `GeneralSettingsView`  [INFERRED]
  ContentView.swift → GeneralSettingsView.swift
- `.body` --calls--> `WebAppContainerView`  [INFERRED]
  ContentView.swift → WebAppContainerView.swift

## Import Cycles
- None detected.

## Communities (29 total, 19 thin omitted)

### Community 0 - "CloudSyncManager"
Cohesion: 0.07
Nodes (11): CapsuleSnapshot, CapsuleSyncConflict, CloudSyncManager, .cloudStoreURL, .currentConflict, .localStoreURL, GroupSnapshot, ICloudSyncConflictAlertModifier (+3 more)

### Community 1 - "WebViewNavigationState"
Cohesion: 0.08
Nodes (20): IdentifiableURL, IOSSolidBottomBar, .body, MacOSSolidBottomBar, .body, SafariView, ShareSheet, SummaryDropdownView (+12 more)

### Community 2 - "SearchEngine"
Cohesion: 0.07
Nodes (33): BlockingMode, basic, complete, .description, .id, optimal, GeneralSettingsView, .currentSnapshot (+25 more)

### Community 3 - "WebViewCoordinator"
Cohesion: 0.07
Nodes (6): IsolatedWebViewRepresentable, URL, .rootDomain, WebKitMemoryManager, .liveWebViewCount, WebViewCoordinator

### Community 4 - "NSWindow"
Cohesion: 0.07
Nodes (14): .body, AppDelegate, CapsuleWindowHostView, .body, .hostingWindow, .resolvedAppItem, CapsuleWindowPayload, .id (+6 more)

### Community 7 - "WindowPresentationMode.swift"
Cohesion: 0.08
Nodes (16): AppKit, CloudKit, View, Combine, CoreData, Foundation, FoundationModels, isowebappsApp (+8 more)

### Community 8 - "AISummarizer"
Cohesion: 0.16
Nodes (9): AISummarizer, .isAvailable, WebPageSummaryError, emptyContent, .errorDescription, generationFailed, modelUnavailable, pdfExtractionFailed (+1 more)

### Community 9 - "AddWebAppSheet"
Cohesion: 0.24
Nodes (3): AddWebAppSheet, .body, FaviconFetcher

### Community 12 - "WebAppItem"
Cohesion: 0.06
Nodes (22): AddGroupSheet, .body, ContentView, .allHomeItems, .body, .deduplicatedGroups, .deduplicatedStandaloneApps, .emptyStateView (+14 more)

### Community 27 - "UBlockOriginExtensionManager"
Cohesion: 0.11
Nodes (4): UBlockOriginExtensionManager, .hasInMemoryCaches, .isLoaded, UBlockRuleCompiler

## Knowledge Gaps
- **54 isolated node(s):** `UniformTypeIdentifiers`, `.hostingWindow`, `.isDragDropEnabled`, `.deduplicatedGroups`, `.emptyStateView` (+49 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 165 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **19 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CloudSyncManager` connect `CloudSyncManager` to `SearchEngine`, `WebViewCoordinator`, `IsolatedCookieManager`, `WindowPresentationMode.swift`, `WebAppItem`, `UBlockOriginExtensionManager`?**
  _High betweenness centrality (0.208) - this node is a cross-community bridge._
- **Are the 10 inferred relationships involving `WebAppItem` (e.g. with `.body` and `.createGroup()`) actually correct?**
  _`WebAppItem` has 10 INFERRED edges - model-reasoned connections that need verification._
- **What connects `UniformTypeIdentifiers`, `.hostingWindow`, `.isDragDropEnabled` to the rest of the system?**
  _54 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `CloudSyncManager` be split into smaller, more focused modules?**
  _Cohesion score 0.07142857142857142 - nodes in this community are weakly interconnected._
- **Why does `WebAppItem` connect `WebAppItem` to `CloudSyncManager`, `WebViewNavigationState`, `WebViewCoordinator`, `NSWindow`, `IsolatedCookieManager`, `WindowPresentationMode.swift`, `AddWebAppSheet`?**
  _High betweenness centrality (0.160) - this node is a cross-community bridge._
- **Are the 7 inferred relationships involving `NSWindow` (e.g. with `.openCapsule()` and `.openEphemeralCapsule()`) actually correct?**
  _`NSWindow` has 7 INFERRED edges - model-reasoned connections that need verification._
- **Should `WebViewNavigationState` be split into smaller, more focused modules?**
  _Cohesion score 0.08345428156748912 - nodes in this community are weakly interconnected._