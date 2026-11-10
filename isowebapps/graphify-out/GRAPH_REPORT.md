# Graph Report - isowebapps  (2026-11-10)

## Corpus Check
- 59 files · ~155,240 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 2 file(s) not represented in the graph (top: .plist 1, .entitlements 1)

## Summary
- 433 nodes · 985 edges · 11 communities (9 shown, 2 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 50 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `2084e6b1`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- CloudSyncManager
- WebViewNavigationState
- SearchEngine
- WebViewCoordinator
- MainWindowTracker
- ContentView
- WebAppItem
- WindowPresentationMode.swift
- AISummarizer
- IsolatedWKWebView
- SerializableCookie

## God Nodes (most connected - your core abstractions)
1. `CloudSyncManager` - 50 edges
2. `WebAppItem` - 47 edges
3. `ContentView` - 27 edges
4. `WebViewCoordinator` - 27 edges
5. `WebViewNavigationState` - 25 edges
6. `MainWindowTracker` - 25 edges
7. `IsolatedWKWebView` - 23 edges
8. `WebAppContainerView` - 23 edges
9. `NSWindow` - 21 edges
10. `IsolatedCookieManager` - 20 edges

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

## Communities (11 total, 2 thin omitted)

### Community 0 - "CloudSyncManager"
Cohesion: 0.08
Nodes (13): CapsuleSnapshot, CapsuleSyncConflict, CloudSyncManager, .cloudStoreURL, .currentConflict, .localStoreURL, GroupSnapshot, ICloudSyncConflictAlertModifier (+5 more)

### Community 1 - "WebViewNavigationState"
Cohesion: 0.08
Nodes (19): IdentifiableURL, IOSSolidBottomBar, .body, MacOSSolidBottomBar, .body, SafariView, ShareSheet, SummaryDropdownView (+11 more)

### Community 2 - "SearchEngine"
Cohesion: 0.06
Nodes (35): BlockingMode, basic, complete, .description, .id, optimal, GeneralSettingsView, .currentSnapshot (+27 more)

### Community 3 - "WebViewCoordinator"
Cohesion: 0.08
Nodes (4): IsolatedWebViewRepresentable, URL, .rootDomain, WebViewCoordinator

### Community 4 - "MainWindowTracker"
Cohesion: 0.08
Nodes (9): AppDelegate, CapsuleWindowHostView, .body, .resolvedAppItem, MainWindowTracker, .savedWindowSize, NSWindow, WindowAccessor (+1 more)

### Community 5 - "ContentView"
Cohesion: 0.08
Nodes (19): ContentView, .allHomeItems, .body, .deduplicatedGroups, .deduplicatedStandaloneApps, .emptyStateView, .homeScreenView, .isDragDropEnabled (+11 more)

### Community 6 - "WebAppItem"
Cohesion: 0.09
Nodes (4): AddGroupSheet, .body, IsolatedCookieManager, WebAppItem

### Community 7 - "WindowPresentationMode.swift"
Cohesion: 0.09
Nodes (10): AddWebAppSheet, .body, AppKit, FaviconFetcher, Foundation, SwiftData, SwiftUI, UBlockRuleCompiler (+2 more)

### Community 8 - "AISummarizer"
Cohesion: 0.12
Nodes (12): AISummarizer, .isAvailable, WebPageSummaryError, emptyContent, .errorDescription, generationFailed, modelUnavailable, pdfExtractionFailed (+4 more)

## Knowledge Gaps
- **45 isolated node(s):** `FoundationModels`, `webViewUnavailable`, `pdfExtractionFailed`, `emptyContent`, `modelUnavailable` (+40 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 123 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **2 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `WebAppItem` connect `WebAppItem` to `CloudSyncManager`, `WebViewNavigationState`, `WebViewCoordinator`, `MainWindowTracker`, `ContentView`, `WindowPresentationMode.swift`?**
  _High betweenness centrality (0.229) - this node is a cross-community bridge._
- **Are the 10 inferred relationships involving `WebAppItem` (e.g. with `.body` and `.createGroup()`) actually correct?**
  _`WebAppItem` has 10 INFERRED edges - model-reasoned connections that need verification._
- **What connects `FoundationModels`, `webViewUnavailable`, `pdfExtractionFailed` to the rest of the system?**
  _45 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `CloudSyncManager` be split into smaller, more focused modules?**
  _Cohesion score 0.08344988344988345 - nodes in this community are weakly interconnected._
- **Why does `CloudSyncManager` connect `CloudSyncManager` to `AISummarizer`, `WebViewCoordinator`?**
  _High betweenness centrality (0.148) - this node is a cross-community bridge._
- **Are the 12 inferred relationships involving `WebViewNavigationState` (e.g. with `.openInSafari()` and `.openInSafariReader()`) actually correct?**
  _`WebViewNavigationState` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Should `WebViewNavigationState` be split into smaller, more focused modules?**
  _Cohesion score 0.08245981830887492 - nodes in this community are weakly interconnected._