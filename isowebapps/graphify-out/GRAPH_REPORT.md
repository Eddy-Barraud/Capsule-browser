# Graph Report - isowebapps  (2026-11-13)

## Corpus Check
- 59 files · ~158,461 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: .entitlements 2, .plist 1)

## Summary
- 488 nodes · 1147 edges · 27 communities (9 shown, 18 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 61 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `a8801340`
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
- SerializableCookie
- ContentView.swift
- ContentView
- WebAppItem
- AddGroupSheet

## God Nodes (most connected - your core abstractions)
1. `CloudSyncManager` - 70 edges
2. `WebAppItem` - 49 edges
3. `NSWindow` - 33 edges
4. `MainWindowTracker` - 32 edges
5. `ContentView` - 29 edges
6. `WebViewCoordinator` - 27 edges
7. `WebViewNavigationState` - 25 edges
8. `WebAppContainerView` - 24 edges
9. `IsolatedWKWebView` - 23 edges
10. `CapsuleWindowPayload` - 22 edges

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

## Communities (27 total, 18 thin omitted)

### Community 0 - "CloudSyncManager"
Cohesion: 0.07
Nodes (15): CloudKit, CapsuleSnapshot, CapsuleSyncConflict, CloudSyncManager, .cloudStoreURL, .currentConflict, .localStoreURL, GroupSnapshot (+7 more)

### Community 1 - "WebViewNavigationState"
Cohesion: 0.08
Nodes (19): IdentifiableURL, IOSSolidBottomBar, .body, MacOSSolidBottomBar, .body, SafariView, ShareSheet, SummaryDropdownView (+11 more)

### Community 2 - "SearchEngine"
Cohesion: 0.07
Nodes (32): BlockingMode, basic, complete, .description, .id, optimal, GeneralSettingsView, .currentSnapshot (+24 more)

### Community 3 - "WebViewCoordinator"
Cohesion: 0.06
Nodes (6): IsolatedWebViewRepresentable, IsolatedWKWebView, .hasActiveAudioPlayback, URL, .rootDomain, WebViewCoordinator

### Community 4 - "NSWindow"
Cohesion: 0.06
Nodes (15): .homeScreenView, .body, AppDelegate, CapsuleWindowHostView, .body, .resolvedAppItem, CapsuleWindowPayload, .id (+7 more)

### Community 7 - "WindowPresentationMode.swift"
Cohesion: 0.08
Nodes (11): AddWebAppSheet, .body, AppKit, FaviconFetcher, Foundation, isowebappsApp, SwiftData, SwiftUI (+3 more)

### Community 8 - "AISummarizer"
Cohesion: 0.12
Nodes (12): AISummarizer, .isAvailable, WebPageSummaryError, emptyContent, .errorDescription, generationFailed, modelUnavailable, pdfExtractionFailed (+4 more)

### Community 12 - "ContentView.swift"
Cohesion: 0.15
Nodes (11): IconImageCache, OpenURLSheet, .body, .matchingApps, .otherApps, View, WebAppTileSettingsMenu, .body (+3 more)

### Community 13 - "ContentView"
Cohesion: 0.22
Nodes (7): ContentView, .allHomeItems, .body, .deduplicatedGroups, .deduplicatedStandaloneApps, .emptyStateView, .isDragDropEnabled

## Knowledge Gaps
- **48 isolated node(s):** `CoreData`, `CloudKit`, `.currentConflict`, `.isPresentedBinding`, `.conflictAlertTitle` (+43 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 138 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **18 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CloudSyncManager` connect `CloudSyncManager` to `AISummarizer`, `WebViewNavigationState`, `WebViewCoordinator`, `ContentView`?**
  _High betweenness centrality (0.221) - this node is a cross-community bridge._
- **Are the 10 inferred relationships involving `WebAppItem` (e.g. with `.body` and `.createGroup()`) actually correct?**
  _`WebAppItem` has 10 INFERRED edges - model-reasoned connections that need verification._
- **What connects `CoreData`, `CloudKit`, `.currentConflict` to the rest of the system?**
  _48 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `CloudSyncManager` be split into smaller, more focused modules?**
  _Cohesion score 0.0694938440492476 - nodes in this community are weakly interconnected._
- **Why does `WebAppItem` connect `WebAppItem` to `CloudSyncManager`, `WebViewNavigationState`, `WebViewCoordinator`, `NSWindow`, `IsolatedCookieManager`, `WindowPresentationMode.swift`, `ContentView.swift`, `ContentView`, `AddGroupSheet`?**
  _High betweenness centrality (0.186) - this node is a cross-community bridge._
- **Are the 6 inferred relationships involving `NSWindow` (e.g. with `.openCapsule()` and `.openEphemeralCapsule()`) actually correct?**
  _`NSWindow` has 6 INFERRED edges - model-reasoned connections that need verification._
- **Should `WebViewNavigationState` be split into smaller, more focused modules?**
  _Cohesion score 0.08245981830887492 - nodes in this community are weakly interconnected._