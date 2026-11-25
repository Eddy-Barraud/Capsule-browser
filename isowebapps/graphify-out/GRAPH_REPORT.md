# Graph Report - isowebapps  (2026-11-25)

## Corpus Check
- 109 files · ~179,590 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: .entitlements 2, .plist 1)

## Summary
- 1404 nodes · 2826 edges · 241 communities (32 shown, 209 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 286 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `8cac4c24`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- URL
- GeneralSettingsView
- IsolatedWebViewRepresentable
- AppDelegate
- ReaderHTMLUtilities
- IsolatedCookieManager
- CapsuleLifecyclePolicy.swift
- IsolatedWKWebView
- CapsuleLifecycleController
- CapsuleDownloadManager
- MarkdownBlockParser
- WebViewCoordinator
- View
- AISummarizer
- UBlockOriginExtensionManager
- MarkdownImageView
- HomeGridItem
- WebKitMemoryManager
- CapsuleWindowPayload
- WindowAccessor
- SwiftUI
- ICloudSyncConflictAlertModifier
- MainWindowTracker
- WebViewNavigationState
- CloudSyncManager
- ContentView
- CapsuleSnapshot
- MarkdownBlockRow
- WebAppItem
- CapsuleDownloadItem
- State
- Image
- PendingDownloadPrompt
- GroupSettingsSheet
- .resetICloudData
- WebAppGroup
- TopControlsBar
- CapsuleActionRow
- .enterSleepIfEligible
- IOSFolderPickerCoordinator
- SummaryDropdownView
- Double
- CapsuleSleepPolicy
- HomeSearchBarView
- AddGroupSheet
- CapsuleSleepState
- MacOSSectionCard

## God Nodes (most connected - your core abstractions)
1. `CloudSyncManager` - 80 edges
2. `WebAppItem` - 65 edges
3. `MainWindowTracker` - 54 edges
4. `WebAppContainerView` - 53 edges
5. `NSWindow` - 50 edges
6. `CapsuleDownloadManager` - 49 edges
7. `CapsuleLifecycleController` - 39 edges
8. `IsolatedCookieManager` - 38 edges
9. `WebViewCoordinator` - 35 edges
10. `ContentView` - 33 edges

## Surprising Connections (you probably didn't know these)
- `.body` --calls--> `Image`  [INFERRED]
  Views/Capsule/TopControlsBar.swift → Utilities/PlatformAdapters.swift
- `.body` --calls--> `Image`  [INFERRED]
  Views/Components/MacOSSectionCard.swift → Utilities/PlatformAdapters.swift
- `.body` --calls--> `Image`  [INFERRED]
  Views/Reader/MarkdownBlockViews.swift → Utilities/PlatformAdapters.swift
- `.imageContent` --calls--> `Image`  [INFERRED]
  Views/Reader/ReaderImageViews.swift → Utilities/PlatformAdapters.swift
- `.body` --calls--> `CapsuleWindowPayload`  [INFERRED]
  App/isowebappsApp.swift → Models/CapsuleWindowPayload.swift

## Import Cycles
- None detected.

## Communities (241 total, 209 thin omitted)

### Community 1 - "URL"
Cohesion: 0.06
Nodes (18): ReaderHistoryStack, .canGoBack, .canGoForward, .currentURL, URL, .rootDomain, WebAppNamingHelper, .initialDomainTitle (+10 more)

### Community 2 - "GeneralSettingsView"
Cohesion: 0.05
Nodes (34): WindowPresentationMode, .iconName, .id, .next, separateWindows, singleWindow, tabs, .title (+26 more)

### Community 5 - "ReaderHTMLUtilities"
Cohesion: 0.07
Nodes (20): HTMLToMarkdown, ReaderHTMLCapture, ReaderHTMLUtilities, ReaderDocument, .shouldShowHeaderTitle, ReaderDocumentSource, fastHTMLFetch, liveWebView (+12 more)

### Community 6 - "IsolatedCookieManager"
Cohesion: 0.13
Nodes (4): IsolatedCookieManager, .hasPendingClears, .hasPendingOperations, .hasPendingSaves

### Community 7 - "CapsuleLifecyclePolicy.swift"
Cohesion: 0.16
Nodes (10): CoreGraphics, CapsuleSleepEvaluation, awake, ignoreNotYetPresented, sleep, CapsuleWindowClosePolicy, WindowClosePolicyAction, closeAllAppWindows (+2 more)

### Community 18 - "CapsuleLifecycleController"
Cohesion: 0.13
Nodes (3): CapsuleLifecycleController, .isClosed, .isDeepSleeping

### Community 25 - "MarkdownBlockParser"
Cohesion: 0.07
Nodes (29): ParsedImageMatch, ListKind, ordered, unordered, ParsedListMarker, MarkdownBlock, MarkdownBlockKind, blockquote (+21 more)

### Community 29 - "View"
Cohesion: 0.14
Nodes (9): MarkdownReaderView, .body, .bodyFontDesign, .clampedScale, ReaderViewState, failed, idle, loaded (+1 more)

### Community 30 - "AISummarizer"
Cohesion: 0.14
Nodes (8): AISummarizer, .isAvailable, WebPageSummaryError, emptyContent, .errorDescription, generationFailed, modelUnavailable, webViewUnavailable

### Community 36 - "UBlockOriginExtensionManager"
Cohesion: 0.06
Nodes (13): LoadedScriptPayload, PreparedRulesetPayload, ScriptLoadSpec, UBlockFilterConfiguration, .activeRulesetIDs, .anyFilterListEnabled, .effectiveAnnoyances, .effectiveCosmeticHiding (+5 more)

### Community 38 - "MarkdownImageView"
Cohesion: 0.09
Nodes (10): IconImageCache, MarkdownImageView, .body, .candidateURLs, .imageContent, .linkURL, .resolvedCaption, .taskIdentity (+2 more)

### Community 39 - "HomeGridItem"
Cohesion: 0.10
Nodes (7): HomeGridItem, app, .displayOrder, group, .id, HomeItemDropDelegate, View

### Community 52 - "WebKitMemoryManager"
Cohesion: 0.13
Nodes (3): WebKitMemoryManager, .hasOpenDeleteOnCloseCapsules, .liveWebViewCount

### Community 53 - "CapsuleWindowPayload"
Cohesion: 0.09
Nodes (14): CapsuleWindowPayload, CodingKeys, appId, instanceId, isSecondaryWindow, name, openAsTab, sourceFrame (+6 more)

### Community 55 - "SwiftUI"
Cohesion: 0.08
Nodes (13): AppKit, CloudKit, Combine, CoreData, Foundation, FoundationModels, ImageIO, SafariServices (+5 more)

### Community 57 - "ICloudSyncConflictAlertModifier"
Cohesion: 0.12
Nodes (7): ICloudSyncConflictAlertModifier, .conflictAlertTitle, .isPresentedBinding, View, LiquidGlassButtonModifier, LiquidGlassCardModifier, View

### Community 58 - "MainWindowTracker"
Cohesion: 0.05
Nodes (14): isowebappsApp, .body, TerminationBackgroundTaskHolder, .savedWindowSize, MainWindowTracker, .currentPresentationMode, NSWindow, .serializedFrame (+6 more)

### Community 71 - "WebViewNavigationState"
Cohesion: 0.14
Nodes (7): IOSSolidBottomBar, .body, MacOSSolidBottomBar, .body, .resolvedCanGoBack, .resolvedCanGoForward, WebViewNavigationState

### Community 72 - "CloudSyncManager"
Cohesion: 0.11
Nodes (4): CloudSyncManager, .cloudStoreURL, .currentConflict, .localStoreURL

### Community 73 - "ContentView"
Cohesion: 0.16
Nodes (5): ContentView, .body, .hostingWindow, .homeScreenView, .isDragDropEnabled

### Community 74 - "CapsuleSnapshot"
Cohesion: 0.19
Nodes (3): CapsuleSnapshot, CapsuleSyncConflict, GroupSnapshot

### Community 75 - "MarkdownBlockRow"
Cohesion: 0.18
Nodes (9): MarkdownBlockRow, .body, MarkdownCodeBlockView, .body, MarkdownInlineText, .body, .renderedText, MarkdownTableView (+1 more)

### Community 76 - "WebAppItem"
Cohesion: 0.16
Nodes (5): WebAppItem, WeakWebAppItemBox, OpenURLSheet, .matchingApps, .otherApps

### Community 77 - "CapsuleDownloadItem"
Cohesion: 0.17
Nodes (7): .activeBannerItem, .hasActiveDownloads, CapsuleDownloadItem, .isActive, .isFinished, DownloadsListView, .body

### Community 78 - "State"
Cohesion: 0.14
Nodes (9): State, awaitingPermission, cancelled, completed, downloading, failed, FaviconFetcher, AddWebAppSheet (+1 more)

### Community 79 - "Image"
Cohesion: 0.15
Nodes (12): Image, DownloadBannerView, .body, .statusIcon, .subtitleText, .emptyStateView, .body, WebAppTileSettingsMenu (+4 more)

### Community 81 - "GroupSettingsSheet"
Cohesion: 0.21
Nodes (7): GroupSettingsSheet, .appsInOtherGroups, .availableStandaloneApps, .body, .groupItems, .iOSLayout, .macOSLayout

### Community 84 - "WebAppGroup"
Cohesion: 0.19
Nodes (4): WebAppGroup, HomeScreenLayoutSnapshot, WebAppGroupTileView, .uniqueSortedItems

### Community 85 - "TopControlsBar"
Cohesion: 0.19
Nodes (6): ReaderToggleButtonStyleModifier, SleepingCapsulePlaceholderView, .body, TopControlsBar, .body, .isYouTube

### Community 87 - "CapsuleActionRow"
Cohesion: 0.18
Nodes (5): CapsuleActionRow, .body, CapsuleIconView, .body, .body

### Community 91 - "SummaryDropdownView"
Cohesion: 0.28
Nodes (3): SummaryDropdownView, .body, .uiOrNsWindowBackgroundColor

### Community 96 - "CapsuleSleepState"
Cohesion: 0.40
Nodes (5): CapsuleSleepState, awake, closed, deepSleeping, softSleeping

## Knowledge Gaps
- **143 isolated node(s):** `CoreGraphics`, `singleWindow`, `separateWindows`, `tabs`, `.id` (+138 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 557 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **209 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `URL` connect `URL` to `GeneralSettingsView`, `IsolatedWebViewRepresentable`, `ReaderHTMLUtilities`, `IsolatedWKWebView`, `CapsuleDownloadManager`, `WebViewCoordinator`, `View`, `UBlockOriginExtensionManager`, `MarkdownImageView`, `SwiftUI`, `WebViewNavigationState`, `CloudSyncManager`, `ContentView`, `MarkdownBlockRow`, `CapsuleDownloadItem`, `State`, `PendingDownloadPrompt`, `.startDownload`, `IOSFolderPickerCoordinator`?**
  _High betweenness centrality (0.166) - this node is a cross-community bridge._
- **Are the 13 inferred relationships involving `WebAppItem` (e.g. with `.migrateLegacyDefaultStoreIfNeeded()` and `.isYouTube`) actually correct?**
  _`WebAppItem` has 13 INFERRED edges - model-reasoned connections that need verification._
- **What connects `CoreGraphics`, `singleWindow`, `separateWindows` to the rest of the system?**
  _143 weakly-connected nodes found - possible missing edges._
- **Should `.handleCloudKitEvent` be split into smaller, more focused modules?**
  _Cohesion score 0.11904761904761904 - nodes in this community are weakly interconnected._
- **Why does `CloudSyncManager` connect `CloudSyncManager` to `.handleCloudKitEvent`, `.buildCoreDataMirrorModel`, `URL`, `AppDelegate`, `ContentView`, `CapsuleSnapshot`, `WebAppItem`, `.resetICloudData`, `SwiftUI`, `.deduplicateStore`, `MainWindowTracker`, `ICloudSyncConflictAlertModifier`?**
  _High betweenness centrality (0.110) - this node is a cross-community bridge._
- **Are the 6 inferred relationships involving `WebAppContainerView` (e.g. with `.body` and `ReaderHistoryStack`) actually correct?**
  _`WebAppContainerView` has 6 INFERRED edges - model-reasoned connections that need verification._
- **Should `URL` be split into smaller, more focused modules?**
  _Cohesion score 0.0554954954954955 - nodes in this community are weakly interconnected._