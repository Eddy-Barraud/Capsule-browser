# Graph Report - isowebapps  (2026-11-21)

## Corpus Check
- 59 files · ~161,292 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: .entitlements 2, .plist 1)

## Summary
- 567 nodes · 1378 edges · 38 communities (9 shown, 29 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 67 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `9a1d8cbc`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- CloudSyncManager
- WebViewNavigationState
- SearchEngine
- NSWindow
- IsolatedCookieManager
- WindowPresentationMode.swift
- AISummarizer
- WebAppItem
- IsolatedWKWebView
- WebKitMemoryManager
- WebViewCoordinator
- UBlockOriginExtensionManager
- IsolatedWebViewRepresentable

## God Nodes (most connected - your core abstractions)
1. `CloudSyncManager` - 72 edges
2. `WebAppItem` - 50 edges
3. `MainWindowTracker` - 47 edges
4. `NSWindow` - 43 edges
5. `ContentView` - 31 edges
6. `IsolatedWKWebView` - 29 edges
7. `WebViewCoordinator` - 27 edges
8. `WebAppContainerView` - 27 edges
9. `WebViewNavigationState` - 26 edges
10. `UBlockOriginExtensionManager` - 25 edges

## Surprising Connections (you probably didn't know these)
- `.body` --calls--> `IsolatedWebViewRepresentable`  [INFERRED]
  WebAppContainerView.swift → IsolatedWebView.swift
- `.body` --calls--> `WebAppContainerView`  [INFERRED]
  ContentView.swift → WebAppContainerView.swift
- `WebAppContainerView` --calls--> `WeakWindowBox`  [INFERRED]
  WebAppContainerView.swift → WindowPresentationMode.swift
- `.body` --calls--> `WebAppContainerView`  [INFERRED]
  WindowPresentationMode.swift → WebAppContainerView.swift
- `.body` --calls--> `AddWebAppSheet`  [INFERRED]
  WebAppContainerView.swift → AddWebAppSheet.swift

## Import Cycles
- None detected.

## Communities (38 total, 29 thin omitted)

### Community 0 - "CloudSyncManager"
Cohesion: 0.07
Nodes (14): CloudKit, CapsuleSnapshot, CapsuleSyncConflict, CloudSyncManager, .cloudStoreURL, .currentConflict, .localStoreURL, GroupSnapshot (+6 more)

### Community 1 - "WebViewNavigationState"
Cohesion: 0.08
Nodes (20): IdentifiableURL, IOSSolidBottomBar, .body, MacOSSolidBottomBar, .body, SafariView, ShareSheet, SummaryDropdownView (+12 more)

### Community 2 - "SearchEngine"
Cohesion: 0.07
Nodes (32): BlockingMode, basic, complete, .description, .id, optimal, GeneralSettingsView, .currentSnapshot (+24 more)

### Community 4 - "NSWindow"
Cohesion: 0.06
Nodes (16): .body, AppDelegate, CapsuleWindowHostView, .body, .hostingWindow, .resolvedAppItem, CapsuleWindowPayload, .id (+8 more)

### Community 7 - "WindowPresentationMode.swift"
Cohesion: 0.07
Nodes (15): AddWebAppSheet, .body, AppKit, Combine, FaviconFetcher, Foundation, FoundationModels, isowebappsApp (+7 more)

### Community 8 - "AISummarizer"
Cohesion: 0.16
Nodes (9): AISummarizer, .isAvailable, WebPageSummaryError, emptyContent, .errorDescription, generationFailed, modelUnavailable, pdfExtractionFailed (+1 more)

### Community 12 - "WebAppItem"
Cohesion: 0.06
Nodes (23): AddGroupSheet, .body, ContentView, .allHomeItems, .body, .deduplicatedGroups, .deduplicatedStandaloneApps, .emptyStateView (+15 more)

### Community 26 - "WebViewCoordinator"
Cohesion: 0.26
Nodes (3): URL, .rootDomain, WebViewCoordinator

### Community 27 - "UBlockOriginExtensionManager"
Cohesion: 0.15
Nodes (3): UBlockOriginExtensionManager, .hasInMemoryCaches, .isLoaded

## Knowledge Gaps
- **54 isolated node(s):** `.liveWebViewCount`, `.hasActiveAudioPlayback`, `.rootDomain`, `duckDuckGo`, `google` (+49 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 162 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **29 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CloudSyncManager` connect `CloudSyncManager` to `WebViewNavigationState`, `SearchEngine`, `IsolatedCookieManager`, `WebAppItem`, `IsolatedWKWebView`, `WebViewCoordinator`, `UBlockOriginExtensionManager`?**
  _High betweenness centrality (0.201) - this node is a cross-community bridge._
- **Are the 10 inferred relationships involving `WebAppItem` (e.g. with `.body` and `.createGroup()`) actually correct?**
  _`WebAppItem` has 10 INFERRED edges - model-reasoned connections that need verification._
- **What connects `.liveWebViewCount`, `.hasActiveAudioPlayback`, `.rootDomain` to the rest of the system?**
  _54 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `CloudSyncManager` be split into smaller, more focused modules?**
  _Cohesion score 0.07401032702237521 - nodes in this community are weakly interconnected._
- **Why does `WebAppItem` connect `WebAppItem` to `CloudSyncManager`, `WebViewNavigationState`, `NSWindow`, `IsolatedCookieManager`, `WindowPresentationMode.swift`, `WebViewCoordinator`, `IsolatedWebViewRepresentable`?**
  _High betweenness centrality (0.151) - this node is a cross-community bridge._
- **Are the 7 inferred relationships involving `NSWindow` (e.g. with `.openCapsule()` and `.openEphemeralCapsule()`) actually correct?**
  _`NSWindow` has 7 INFERRED edges - model-reasoned connections that need verification._
- **Should `WebViewNavigationState` be split into smaller, more focused modules?**
  _Cohesion score 0.08106219426974144 - nodes in this community are weakly interconnected._