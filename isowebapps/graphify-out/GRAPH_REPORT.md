# Graph Report - isowebapps  (2026-11-25)

## Corpus Check
- 114 files · ~124,940 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: .entitlements 2, .plist 1)

## Summary
- 1659 nodes · 3401 edges · 298 communities (59 shown, 239 thin omitted)
- Extraction: 89% EXTRACTED · 11% INFERRED · 0% AMBIGUOUS · INFERRED: 385 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7b321be3`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- WebAppContainerView
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
- SafariView
- Foundation
- LiquidGlassButtonModifier
- MainWindowTracker
- SwiftUI
- YouTubeContentBlocker
- IconImageCache
- WebViewNavigationState
- CloudSyncManager
- ContentView
- CapsuleSnapshot
- MarkdownBlockRow
- WebAppItem
- CapsuleDownloadItem
- State
- WebAppGroupTileView
- DownloadContext
- GroupSettingsSheet
- .startDownload
- .resetICloudData
- scriptlet-isolated-begin.js
- TopControlsBar
- .desiredProtectionMode
- .enterSleepIfEligible
- IOSFolderPickerCoordinator
- SummaryDropdownView
- Double
- CapsuleSleepPolicy
- HomeSearchBarView
- scriptlet-main-begin.js
- CapsuleSleepState
- ICloudSyncConflictAlertModifier
- .body
- JSONPath
- WebAppGroup
- AddGroupSheet
- NSWindow
- YouTubeAVKitPlayerView
- .macOSContent
- WindowAccessor
- UIKit
- safeSelf
- parsePropertiesToMatchFn
- SearchEngine
- CapsuleWindowHostView
- jsonEditFetchResponseFn
- URL
- proxyApplyFn
- CapsuleWindowPayload
- WindowPresentationMode
- .domainName
- ArglistParser
- isowebappsApp
- BlockingMode
- YouTubeFreeSupport.swift
- DownloadBannerView
- preventSetInterval
- setConstantFn
- State

## God Nodes (most connected - your core abstractions)
1. `CloudSyncManager` - 80 edges
2. `WebAppItem` - 64 edges
3. `safeSelf()` - 57 edges
4. `MainWindowTracker` - 54 edges
5. `WebAppContainerView` - 53 edges
6. `NSWindow` - 50 edges
7. `CapsuleDownloadManager` - 49 edges
8. `WebViewCoordinator` - 41 edges
9. `CapsuleLifecycleController` - 39 edges
10. `IsolatedCookieManager` - 38 edges

## Surprising Connections (you probably didn't know these)
- `.body` --calls--> `Image`  [INFERRED]
  Views/Capsule/TopControlsBar.swift → Utilities/PlatformAdapters.swift
- `.body` --calls--> `Image`  [INFERRED]
  Views/Components/MacOSSectionCard.swift → Utilities/PlatformAdapters.swift
- `.body` --calls--> `Image`  [INFERRED]
  Views/Reader/MarkdownBlockViews.swift → Utilities/PlatformAdapters.swift
- `.imageContent` --calls--> `Image`  [INFERRED]
  Views/Reader/ReaderImageViews.swift → Utilities/PlatformAdapters.swift
- `WebAppContainerView` --calls--> `CapsuleLifecycleController`  [INFERRED]
  Views/Capsule/WebAppContainerView.swift → Services/WebKit/CapsuleLifecycleController.swift

## Import Cycles
- None detected.

## Communities (298 total, 239 thin omitted)

### Community 1 - "WebAppContainerView"
Cohesion: 0.14
Nodes (3): WebAppContainerView, .hostingWindow, .shouldShowReaderOverlay

### Community 2 - "GeneralSettingsView"
Cohesion: 0.16
Nodes (7): GeneralSettingsView, .currentFilterConfiguration, .hasUncompiledChanges, .iCloudToggleBinding, .iOSLayout, .iCloudSyncStatusSubtitle, .macOSLayout

### Community 5 - "ReaderHTMLUtilities"
Cohesion: 0.06
Nodes (26): HTMLToMarkdown, BackgroundCaptureReadiness, notReadyYet, readyImmediately, requiresHumanVerification, usableAfterSettle, ReaderHTMLCapture, ReaderHTMLUtilities (+18 more)

### Community 6 - "IsolatedCookieManager"
Cohesion: 0.14
Nodes (4): IsolatedCookieManager, .hasPendingClears, .hasPendingOperations, .hasPendingSaves

### Community 7 - "CapsuleLifecyclePolicy.swift"
Cohesion: 0.16
Nodes (10): CoreGraphics, CapsuleSleepEvaluation, awake, ignoreNotYetPresented, sleep, CapsuleWindowClosePolicy, WindowClosePolicyAction, closeAllAppWindows (+2 more)

### Community 9 - "IsolatedWKWebView"
Cohesion: 0.13
Nodes (3): IsolatedWKWebView, .hasActiveAudioPlayback, .isInHTMLFullscreen

### Community 18 - "CapsuleLifecycleController"
Cohesion: 0.13
Nodes (3): CapsuleLifecycleController, .isClosed, .isDeepSleeping

### Community 25 - "MarkdownBlockParser"
Cohesion: 0.09
Nodes (23): ParsedImageMatch, ListKind, ordered, unordered, ParsedListMarker, MarkdownBlock, MarkdownBlockKind, blockquote (+15 more)

### Community 29 - "View"
Cohesion: 0.14
Nodes (9): MarkdownReaderView, .body, .bodyFontDesign, .clampedScale, ReaderViewState, failed, idle, loaded (+1 more)

### Community 30 - "AISummarizer"
Cohesion: 0.13
Nodes (9): FoundationModels, AISummarizer, .isAvailable, WebPageSummaryError, emptyContent, .errorDescription, generationFailed, modelUnavailable (+1 more)

### Community 36 - "UBlockOriginExtensionManager"
Cohesion: 0.06
Nodes (14): SerializableCookie, LoadedScriptPayload, PreparedRulesetPayload, ScriptLoadSpec, UBlockFilterConfiguration, .activeRulesetIDs, .anyFilterListEnabled, .effectiveAnnoyances (+6 more)

### Community 38 - "MarkdownImageView"
Cohesion: 0.13
Nodes (9): MarkdownImageView, .body, .candidateURLs, .imageContent, .linkURL, .resolvedCaption, .taskIdentity, ReaderImageCache (+1 more)

### Community 39 - "HomeGridItem"
Cohesion: 0.10
Nodes (7): HomeGridItem, app, .displayOrder, group, .id, HomeItemDropDelegate, View

### Community 52 - "WebKitMemoryManager"
Cohesion: 0.16
Nodes (3): WebKitMemoryManager, .hasOpenDeleteOnCloseCapsules, .liveWebViewCount

### Community 53 - "CapsuleWindowPayload"
Cohesion: 0.18
Nodes (10): CodingKeys, appId, instanceId, isSecondaryWindow, name, openAsTab, sourceFrame, sourceWindowNumber (+2 more)

### Community 54 - "SafariView"
Cohesion: 0.17
Nodes (4): SafariServices, IdentifiableURL, SafariView, ShareSheet

### Community 55 - "Foundation"
Cohesion: 0.15
Nodes (6): CloudKit, Combine, CoreData, Foundation, SwiftData, WebKit

### Community 57 - "LiquidGlassButtonModifier"
Cohesion: 0.29
Nodes (3): LiquidGlassButtonModifier, LiquidGlassCardModifier, View

### Community 58 - "MainWindowTracker"
Cohesion: 0.14
Nodes (3): .savedWindowSize, MainWindowTracker, .currentPresentationMode

### Community 61 - "SwiftUI"
Cohesion: 0.19
Nodes (4): AppKit, SwiftUI, MacOSSectionCard, .body

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
Cohesion: 0.16
Nodes (3): CapsuleSnapshot, CapsuleSyncConflict, GroupSnapshot

### Community 75 - "MarkdownBlockRow"
Cohesion: 0.18
Nodes (9): MarkdownBlockRow, .body, MarkdownCodeBlockView, .body, MarkdownInlineText, .body, .renderedText, MarkdownTableView (+1 more)

### Community 76 - "WebAppItem"
Cohesion: 0.18
Nodes (6): WebAppItem, WeakWebAppItemBox, OpenURLSheet, .body, .matchingApps, .otherApps

### Community 77 - "CapsuleDownloadItem"
Cohesion: 0.20
Nodes (7): .activeBannerItem, .hasActiveDownloads, CapsuleDownloadItem, .isActive, .isFinished, DownloadsListView, .body

### Community 78 - "State"
Cohesion: 0.19
Nodes (3): FaviconFetcher, AddWebAppSheet, .body

### Community 79 - "WebAppGroupTileView"
Cohesion: 0.18
Nodes (7): WebAppGroupTileView, .body, .uniqueSortedItems, WebAppTileSettingsMenu, .body, .readerLinksToggleTitle, WebAppTileView

### Community 81 - "GroupSettingsSheet"
Cohesion: 0.18
Nodes (7): CapsuleActionRow, GroupSettingsSheet, .appsInOtherGroups, .availableStandaloneApps, .groupItems, .iOSLayout, .macOSLayout

### Community 84 - "scriptlet-isolated-begin.js"
Cohesion: 0.11
Nodes (40): RFC-2616, RFC-6265, closeWindow(), getAllCookiesFn(), getAllLocalStorageFn(), getCookieFn(), getRandomTokenFn(), getSafeCookieValuesFn() (+32 more)

### Community 85 - "TopControlsBar"
Cohesion: 0.21
Nodes (5): ReaderToggleButtonStyleModifier, SleepingCapsulePlaceholderView, .body, TopControlsBar, .body

### Community 87 - ".desiredProtectionMode"
Cohesion: 0.26
Nodes (3): YouTubeFreeSupport, .isDisplayingYouTube, .isYouTube

### Community 91 - "SummaryDropdownView"
Cohesion: 0.28
Nodes (3): SummaryDropdownView, .body, .uiOrNsWindowBackgroundColor

### Community 95 - "scriptlet-main-begin.js"
Cohesion: 0.11
Nodes (14): abortCurrentScript(), freezeElementProperty(), jsonEditXhrResponse(), jsonEditXhrResponseFn(), modifyXhrResponseFn(), mpegdashPrune(), offIdleFn(), onIdleFn() (+6 more)

### Community 96 - "CapsuleSleepState"
Cohesion: 0.40
Nodes (5): CapsuleSleepState, awake, closed, deepSleeping, softSleeping

### Community 98 - "ICloudSyncConflictAlertModifier"
Cohesion: 0.20
Nodes (4): ICloudSyncConflictAlertModifier, .conflictAlertTitle, .isPresentedBinding, View

### Community 125 - "WebAppGroup"
Cohesion: 0.24
Nodes (3): WebAppGroup, HomeScreenLayoutSnapshot, .body

### Community 138 - "AddGroupSheet"
Cohesion: 0.20
Nodes (4): .body, CapsuleIconView, AddGroupSheet, .body

### Community 144 - "NSWindow"
Cohesion: 0.17
Nodes (4): NSWindow, .serializedFrame, WeakWindowBox, .body

### Community 177 - ".macOSContent"
Cohesion: 0.31
Nodes (4): YouTubeAVKitOverlayView, .body, .iOSContent, .macOSContent

### Community 237 - "UIKit"
Cohesion: 0.36
Nodes (3): ImageIO, UIKit, UniformTypeIdentifiers

### Community 241 - "safeSelf"
Cohesion: 0.16
Nodes (19): abortCurrentScriptFn(), abortOnPropertyRead(), abortOnPropertyWrite(), abortOnStackTrace(), adjustSetInterval(), adjustSetTimeout(), getExceptionTokenFn(), getRandomTokenFn() (+11 more)

### Community 242 - "parsePropertiesToMatchFn"
Cohesion: 0.16
Nodes (18): collateFetchArgumentsFn(), generateContentFn(), jsonEditFetchRequest(), jsonEditFetchRequestFn(), jsonlEditFetchResponse(), jsonlEditFetchResponseFn(), jsonPruneXhrResponse(), matchObjectPropertiesFn() (+10 more)

### Community 243 - "SearchEngine"
Cohesion: 0.16
Nodes (9): SearchEngine, bing, custom, .defaultQueryPrefix, .displayName, duckDuckGo, google, .id (+1 more)

### Community 245 - "CapsuleWindowHostView"
Cohesion: 0.18
Nodes (5): CapsuleWindowCloseObserver, CapsuleWindowHostView, .hostingWindow, .initialDomainTitle, .resolvedAppItem

### Community 246 - "jsonEditFetchResponseFn"
Cohesion: 0.16
Nodes (13): editInboundObjectFn(), editObjectOnSetter(), editObjectOnSetterFn(), jsonEdit(), jsonEditFetchResponse(), jsonEditFetchResponseFn(), jsonEditFn(), jsonlEditFn() (+5 more)

### Community 247 - "URL"
Cohesion: 0.26
Nodes (6): ReaderHistoryStack, .canGoBack, .canGoForward, .currentURL, URL, .rootDomain

### Community 248 - "proxyApplyFn"
Cohesion: 0.17
Nodes (13): evaldataPrune(), m3uPrune(), noEvalIf(), noWindowOpenIf(), preventAddEventListener(), preventBab(), preventClipboardWrite(), preventRequestAnimationFrame() (+5 more)

### Community 250 - "CapsuleWindowPayload"
Cohesion: 0.21
Nodes (4): CapsuleWindowPayload, .defaultNewTabPayload, .id, .sourceFrameRect

### Community 251 - "WindowPresentationMode"
Cohesion: 0.20
Nodes (9): WindowPresentationMode, .iconName, .id, .next, separateWindows, singleWindow, tabs, .title (+1 more)

### Community 253 - ".domainName"
Cohesion: 0.27
Nodes (3): WebAppNamingHelper, .activeDomainTitle, .body

### Community 254 - "ArglistParser"
Cohesion: 0.31
Nodes (3): ArglistParser, parseReplaceFn(), trustedReplaceArgument()

### Community 256 - "BlockingMode"
Cohesion: 0.20
Nodes (8): BlockingMode, basic, complete, .description, .id, optimal, .currentSnapshot, RuleSettingsSnapshot

### Community 258 - "YouTubeFreeSupport.swift"
Cohesion: 0.16
Nodes (7): AVFoundation, AVKit, ContentProtectionMode, none, uBlock, youTubeAdFree, WeakScriptMessageHandler

### Community 259 - "DownloadBannerView"
Cohesion: 0.17
Nodes (8): Image, DownloadBannerView, .body, .statusIcon, .subtitleText, .body, .emptyStateView, .body

### Community 260 - "preventSetInterval"
Cohesion: 0.60
Nodes (3): preventSetInterval(), preventSetTimeout(), RangeParser

### Community 261 - "setConstantFn"
Cohesion: 0.33
Nodes (6): setConstant(), setConstantFn(), setConstant(), trustedOverrideElementMethod(), trustedSetConstant(), validateConstantFn()

### Community 262 - "State"
Cohesion: 0.33
Nodes (6): State, awaitingPermission, cancelled, completed, downloading, failed

## Knowledge Gaps
- **152 isolated node(s):** `.isDeepSleeping`, `.isClosed`, `.isInHTMLFullscreen`, `.hasActiveAudioPlayback`, `.liveWebViewCount` (+147 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 621 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **239 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `URL` connect `URL` to `WebAppContainerView`, `IsolatedWebViewRepresentable`, `ReaderHTMLUtilities`, `IsolatedWKWebView`, `CapsuleDownloadManager`, `WebViewCoordinator`, `View`, `UBlockOriginExtensionManager`, `MarkdownImageView`, `YouTubeAVKitPlayerView`, `.macOSContent`, `SafariView`, `Foundation`, `YouTubeContentBlocker`, `WebViewNavigationState`, `CloudSyncManager`, `ContentView`, `MarkdownBlockRow`, `CapsuleDownloadItem`, `State`, `DownloadContext`, `.startDownload`, `.desiredProtectionMode`, `IOSFolderPickerCoordinator`, `.handleReaderAddressSubmit`, `SearchEngine`, `.domainName`?**
  _High betweenness centrality (0.121) - this node is a cross-community bridge._
- **Are the 12 inferred relationships involving `WebAppItem` (e.g. with `.migrateLegacyDefaultStoreIfNeeded()` and `.body`) actually correct?**
  _`WebAppItem` has 12 INFERRED edges - model-reasoned connections that need verification._
- **What connects `.isDeepSleeping`, `.isClosed`, `.isInHTMLFullscreen` to the rest of the system?**
  _152 weakly-connected nodes found - possible missing edges._
- **Should `.handleCloudKitEvent` be split into smaller, more focused modules?**
  _Cohesion score 0.14705882352941177 - nodes in this community are weakly interconnected._
- **Why does `CloudSyncManager` connect `CloudSyncManager` to `.handleCloudKitEvent`, `.buildCoreDataMirrorModel`, `ICloudSyncConflictAlertModifier`, `AppDelegate`, `ContentView`, `CapsuleSnapshot`, `.resetICloudData`, `CapsuleWindowHostView`, `Foundation`, `.deduplicateStore`, `URL`?**
  _High betweenness centrality (0.105) - this node is a cross-community bridge._
- **Should `WebAppContainerView` be split into smaller, more focused modules?**
  _Cohesion score 0.13852813852813853 - nodes in this community are weakly interconnected._
- **Why does `WebAppContainerView` connect `WebAppContainerView` to `ReaderHTMLUtilities`, `WebViewNavigationState`, `ContentView`, `WebAppItem`, `.handleReaderAddressSubmit`, `NSWindow`, `.macOSContent`, `CapsuleLifecycleController`, `View`, `Foundation`, `SafariView`, `URL`, `.domainName`, `SwiftUI`?**
  _High betweenness centrality (0.067) - this node is a cross-community bridge._