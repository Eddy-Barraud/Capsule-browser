# Graph Report - isowebapps  (2026-11-25)

## Corpus Check
- 65 files · ~179,866 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: .entitlements 2, .plist 1)

## Summary
- 945 nodes · 2431 edges · 71 communities (25 shown, 46 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 124 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `e0b0c030`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- CloudSyncManager
- WebViewNavigationState
- SearchEngine
- .createConfiguredWebView
- MainWindowTracker
- ReaderModeError
- IsolatedCookieManager
- CapsuleLifecyclePolicy.swift
- ContentView.swift
- IsolatedWKWebView
- WindowPresentationMode
- NSWindow
- ContentView
- ReaderHTMLUtilities
- CapsuleLifecycleController
- CapsuleDownloadManager
- WebKitMemoryManager
- MarkdownBlockParser
- WebViewCoordinator
- UBlockRuleCompiler
- URL
- AISummarizer
- WebAppItem
- CodingKeys
- Equatable
- .body
- .domainName
- URL
- AddWebAppSheet
- WebAppContainerView
- Foundation
- SerializableCookie
- WindowAccessor
- SwiftData
- AppDelegate
- isowebappsApp

## God Nodes (most connected - your core abstractions)
1. `CloudSyncManager` - 77 edges
2. `NSWindow` - 54 edges
3. `MainWindowTracker` - 52 edges
4. `WebAppItem` - 51 edges
5. `WebAppContainerView` - 48 edges
6. `CapsuleDownloadManager` - 47 edges
7. `.body` - 39 edges
8. `CapsuleLifecycleController` - 38 edges
9. `WindowPresentationMode` - 34 edges
10. `WebViewNavigationState` - 34 edges

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

## Communities (71 total, 46 thin omitted)

### Community 0 - "CloudSyncManager"
Cohesion: 0.07
Nodes (15): CloudKit, CapsuleSnapshot, CapsuleSyncConflict, CloudSyncManager, .cloudStoreURL, .currentConflict, .localStoreURL, GroupSnapshot (+7 more)

### Community 1 - "WebViewNavigationState"
Cohesion: 0.07
Nodes (21): DownloadBannerView, .body, .statusIcon, .subtitleText, IOSSolidBottomBar, .body, MacOSSolidBottomBar, .body (+13 more)

### Community 2 - "SearchEngine"
Cohesion: 0.06
Nodes (27): BlockingMode, basic, complete, .description, .id, optimal, GeneralSettingsView, .currentSnapshot (+19 more)

### Community 4 - "MainWindowTracker"
Cohesion: 0.14
Nodes (4): .body, MainWindowTracker, .currentPresentationMode, .savedWindowSize

### Community 5 - "ReaderModeError"
Cohesion: 0.11
Nodes (16): HTMLToMarkdown, ReaderDocument, .plainTextForSummary, .shouldShowHeaderTitle, ReaderModeError, conversionFailed, emptyContent, .errorDescription (+8 more)

### Community 7 - "CapsuleLifecyclePolicy.swift"
Cohesion: 0.12
Nodes (15): CapsuleSleepEvaluation, awake, ignoreNotYetPresented, sleep, CapsuleSleepState, awake, closed, deepSleeping (+7 more)

### Community 8 - "ContentView.swift"
Cohesion: 0.14
Nodes (12): IconImageCache, OpenURLSheet, .body, .matchingApps, .otherApps, View, WebAppTileSettingsMenu, .body (+4 more)

### Community 10 - "WindowPresentationMode"
Cohesion: 0.11
Nodes (14): WindowPresentationMode, .iconName, .id, .next, separateWindows, singleWindow, tabs, .title (+6 more)

### Community 11 - "NSWindow"
Cohesion: 0.24
Nodes (3): .body, NSWindow, .serializedFrame

### Community 12 - "ContentView"
Cohesion: 0.19
Nodes (9): ContentView, .allHomeItems, .body, .deduplicatedGroups, .deduplicatedStandaloneApps, .emptyStateView, .homeScreenView, .hostingWindow (+1 more)

### Community 18 - "CapsuleLifecycleController"
Cohesion: 0.15
Nodes (4): CapsuleWindowSleepSnapshot, CapsuleLifecycleController, .isClosed, .isDeepSleeping

### Community 23 - "CapsuleDownloadManager"
Cohesion: 0.07
Nodes (17): CapsuleDownloadItem, .isActive, .isFinished, State, awaitingPermission, cancelled, completed, downloading (+9 more)

### Community 25 - "MarkdownBlockParser"
Cohesion: 0.11
Nodes (23): CodeFenceOpen, ListKind, ordered, unordered, MarkdownBlock, MarkdownBlockKind, blockquote, codeBlock (+15 more)

### Community 29 - "URL"
Cohesion: 0.07
Nodes (29): CapsuleSleepPolicy, Double, MarkdownBlockRow, .body, MarkdownCodeBlockView, .body, MarkdownImageView, .body (+21 more)

### Community 30 - "AISummarizer"
Cohesion: 0.15
Nodes (9): AISummarizer, .isAvailable, WebPageSummaryError, emptyContent, .errorDescription, generationFailed, modelUnavailable, webViewUnavailable (+1 more)

### Community 33 - "WebAppItem"
Cohesion: 0.17
Nodes (3): AddGroupSheet, .body, WebAppItem

### Community 36 - "CodingKeys"
Cohesion: 0.18
Nodes (10): CodingKeys, appId, instanceId, isSecondaryWindow, name, openAsTab, sourceFrame, sourceWindowNumber (+2 more)

### Community 38 - "Equatable"
Cohesion: 0.14
Nodes (13): BackgroundCaptureReadiness, notReadyYet, readyImmediately, requiresHumanVerification, usableAfterSettle, ReaderHistoryStack, .canGoBack, .canGoForward (+5 more)

### Community 39 - ".body"
Cohesion: 0.26
Nodes (4): .body, CapsuleWindowPayload, .id, .sourceFrameRect

### Community 40 - ".domainName"
Cohesion: 0.38
Nodes (3): .activeDomainTitle, WebAppNamingHelper, .initialDomainTitle

### Community 42 - "URL"
Cohesion: 0.21
Nodes (3): URL, .rootDomain, WebViewNavigationState

### Community 49 - "AddWebAppSheet"
Cohesion: 0.24
Nodes (3): AddWebAppSheet, .body, FaviconFetcher

### Community 50 - "WebAppContainerView"
Cohesion: 0.14
Nodes (4): IdentifiableURL, WebAppContainerView, .hostingWindow, .shouldShowReaderOverlay

### Community 52 - "Foundation"
Cohesion: 0.24
Nodes (3): Combine, Foundation, WebKit

### Community 55 - "SwiftData"
Cohesion: 0.39
Nodes (4): AppKit, SwiftData, SwiftUI, UIKit

## Knowledge Gaps
- **135 isolated node(s):** `CoreGraphics`, `singleWindow`, `separateWindows`, `tabs`, `.id` (+130 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 280 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **46 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `URL` connect `URL` to `CloudSyncManager`, `WebViewNavigationState`, `SearchEngine`, `.createConfiguredWebView`, `ReaderModeError`, `Equatable`, `.body`, `IsolatedWKWebView`, `ContentView`, `AddWebAppSheet`, `WebAppContainerView`, `CapsuleDownloadManager`, `WebKitMemoryManager`, `WebViewCoordinator`, `URL`?**
  _High betweenness centrality (0.198) - this node is a cross-community bridge._
- **Are the 9 inferred relationships involving `NSWindow` (e.g. with `.openCapsule()` and `.openEphemeralCapsule()`) actually correct?**
  _`NSWindow` has 9 INFERRED edges - model-reasoned connections that need verification._
- **What connects `CoreGraphics`, `singleWindow`, `separateWindows` to the rest of the system?**
  _135 weakly-connected nodes found - possible missing edges._
- **Should `CloudSyncManager` be split into smaller, more focused modules?**
  _Cohesion score 0.06629243517775996 - nodes in this community are weakly interconnected._
- **Why does `CloudSyncManager` connect `CloudSyncManager` to `MainWindowTracker`, `IsolatedCookieManager`, `URL`, `WindowPresentationMode`, `ContentView`?**
  _High betweenness centrality (0.132) - this node is a cross-community bridge._
- **Are the 10 inferred relationships involving `WebAppItem` (e.g. with `.body` and `.createGroup()`) actually correct?**
  _`WebAppItem` has 10 INFERRED edges - model-reasoned connections that need verification._
- **Should `WebViewNavigationState` be split into smaller, more focused modules?**
  _Cohesion score 0.06976744186046512 - nodes in this community are weakly interconnected._