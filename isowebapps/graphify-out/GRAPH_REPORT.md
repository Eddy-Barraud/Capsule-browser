# Graph Report - isowebapps  (2026-11-12)

## Corpus Check
- 59 files · ~156,566 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 2 file(s) not represented in the graph (top: .plist 1, .entitlements 1)

## Summary
- 462 nodes · 1056 edges · 17 communities (8 shown, 9 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 55 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `39e72a37`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- CloudSyncManager
- WebViewNavigationState
- SearchEngine
- WebViewCoordinator
- NSWindow
- WebAppItem
- WindowPresentationMode.swift
- AISummarizer
- SerializableCookie
- WindowAccessor

## God Nodes (most connected - your core abstractions)
1. `CloudSyncManager` - 50 edges
2. `WebAppItem` - 47 edges
3. `NSWindow` - 33 edges
4. `MainWindowTracker` - 32 edges
5. `ContentView` - 28 edges
6. `WebViewCoordinator` - 27 edges
7. `WebViewNavigationState` - 25 edges
8. `WebAppContainerView` - 24 edges
9. `IsolatedWKWebView` - 23 edges
10. `CapsuleWindowPayload` - 22 edges

## Surprising Connections (you probably didn't know these)
- `.body` --calls--> `AddGroupSheet`  [INFERRED]
  ContentView.swift → AddGroupSheet.swift
- `.body` --calls--> `AddWebAppSheet`  [INFERRED]
  ContentView.swift → AddWebAppSheet.swift
- `.body` --calls--> `GeneralSettingsView`  [INFERRED]
  ContentView.swift → GeneralSettingsView.swift
- `.body` --calls--> `WebAppContainerView`  [INFERRED]
  ContentView.swift → WebAppContainerView.swift
- `.body` --references--> `WebAppItem`  [INFERRED]
  ContentView.swift → WebAppItem.swift

## Import Cycles
- None detected.

## Communities (17 total, 9 thin omitted)

### Community 0 - "CloudSyncManager"
Cohesion: 0.08
Nodes (13): CapsuleSnapshot, CapsuleSyncConflict, CloudSyncManager, .cloudStoreURL, .currentConflict, .localStoreURL, GroupSnapshot, ICloudSyncConflictAlertModifier (+5 more)

### Community 1 - "WebViewNavigationState"
Cohesion: 0.08
Nodes (19): IdentifiableURL, IOSSolidBottomBar, .body, MacOSSolidBottomBar, .body, SafariView, ShareSheet, SummaryDropdownView (+11 more)

### Community 2 - "SearchEngine"
Cohesion: 0.07
Nodes (33): BlockingMode, basic, complete, .description, .id, optimal, GeneralSettingsView, .currentSnapshot (+25 more)

### Community 3 - "WebViewCoordinator"
Cohesion: 0.06
Nodes (6): IsolatedWebViewRepresentable, IsolatedWKWebView, .hasActiveAudioPlayback, URL, .rootDomain, WebViewCoordinator

### Community 4 - "NSWindow"
Cohesion: 0.06
Nodes (18): ContentView, .body, .deduplicatedGroups, .emptyStateView, .homeScreenView, .isDragDropEnabled, .body, AppDelegate (+10 more)

### Community 6 - "WebAppItem"
Cohesion: 0.06
Nodes (17): AddGroupSheet, .body, .allHomeItems, .deduplicatedStandaloneApps, IconImageCache, OpenURLSheet, .body, .matchingApps (+9 more)

### Community 7 - "WindowPresentationMode.swift"
Cohesion: 0.07
Nodes (11): AddWebAppSheet, .body, AppKit, FaviconFetcher, Foundation, isowebappsApp, SwiftData, SwiftUI (+3 more)

### Community 8 - "AISummarizer"
Cohesion: 0.12
Nodes (12): AISummarizer, .isAvailable, WebPageSummaryError, emptyContent, .errorDescription, generationFailed, modelUnavailable, pdfExtractionFailed (+4 more)

## Knowledge Gaps
- **47 isolated node(s):** `UniformTypeIdentifiers`, `.isDragDropEnabled`, `.deduplicatedGroups`, `.emptyStateView`, `.hasActiveAudioPlayback` (+42 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 134 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **9 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `WebAppItem` connect `WebAppItem` to `CloudSyncManager`, `WebViewNavigationState`, `WebViewCoordinator`, `NSWindow`, `WindowPresentationMode.swift`?**
  _High betweenness centrality (0.211) - this node is a cross-community bridge._
- **Are the 10 inferred relationships involving `WebAppItem` (e.g. with `.body` and `.createGroup()`) actually correct?**
  _`WebAppItem` has 10 INFERRED edges - model-reasoned connections that need verification._
- **What connects `UniformTypeIdentifiers`, `.isDragDropEnabled`, `.deduplicatedGroups` to the rest of the system?**
  _47 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `CloudSyncManager` be split into smaller, more focused modules?**
  _Cohesion score 0.08344988344988345 - nodes in this community are weakly interconnected._
- **Why does `CloudSyncManager` connect `CloudSyncManager` to `AISummarizer`, `WebViewCoordinator`?**
  _High betweenness centrality (0.136) - this node is a cross-community bridge._
- **Are the 6 inferred relationships involving `NSWindow` (e.g. with `.openCapsule()` and `.openEphemeralCapsule()`) actually correct?**
  _`NSWindow` has 6 INFERRED edges - model-reasoned connections that need verification._
- **Should `WebViewNavigationState` be split into smaller, more focused modules?**
  _Cohesion score 0.08490566037735849 - nodes in this community are weakly interconnected._