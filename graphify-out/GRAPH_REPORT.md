# Graph Report - isowebapps  (2026-11-10)

## Corpus Check
- 76 files · ~154,943 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 2 file(s) not represented in the graph (top: .plist 1, .entitlements 1)

## Summary
- 1132 nodes · 2574 edges · 50 communities (31 shown, 19 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 331 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- uBlock Scriptlets Filters
- Isolated WebView Controller
- CloudKit Sync Management
- Overlay Annoyance Filters
- App Lifecycle & Windows
- AdGuard Mobile Scriptlets
- Safari Services & Domains
- EasyPrivacy Scriptlets
- French Rule Scriptlets
- Add Capsule Sheet UI
- Isolated uBlock Cookies
- Cookie Annoyance Scriptlets
- Overlay Annoyance Isolated
- uBlock Badware Scriptlets
- Cookie Annoyances Main
- AdGuard Cookie Isolated
- AI Web Summarizer
- Open URL Sheet
- JSONPath Compilation Engine
- Grid Item Reordering
- Isolated Cookie Storage
- JSONPath Expression Parser
- Group Settings Sheet
- French Rule Isolated Cookies
- Content View Home Screen
- EasyPrivacy Isolated Cookies
- Content Blocker Manager
- App Icon Assets
- Capsule Tile & Icon Cache
- General Settings View
- Search Engine Configuration
- Liquid Glass Styling
- Add Group Sheet UI
- Window Presentation Modes
- Capsule Model Metadata
- Badware Node Replacement
- Content Blocking Modes
- Scriptlet Argument Parser
- uBlock WebKit Rule Compiler
- Drag & Drop Delegate
- Spanish AI Prompt Prompts
- French AI Prompt Prompts

## God Nodes (most connected - your core abstractions)
1. `WebAppItem` - 58 edges
2. `safeSelf()` - 56 edges
3. `CloudSyncManager` - 49 edges
4. `safeSelf()` - 33 edges
5. `safeSelf()` - 30 edges
6. `ContentView` - 28 edges
7. `safeSelf()` - 28 edges
8. `WebViewCoordinator` - 27 edges
9. `WebViewNavigationState` - 25 edges
10. `MainWindowTracker` - 25 edges

## Surprising Connections (you probably didn't know these)
- `AISummarizer` --implements--> `Web Page Summarization`  [INFERRED]
  AISummarizer.swift → Prompts/instructions_en.txt
- `.deduplicatedStandaloneApps` --references--> `WebAppItem`  [INFERRED]
  ContentView.swift → WebAppItem.swift
- `.availableStandaloneApps` --references--> `WebAppItem`  [INFERRED]
  GroupSettingsSheet.swift → WebAppItem.swift
- `.appsInOtherGroups` --references--> `WebAppItem`  [INFERRED]
  GroupSettingsSheet.swift → WebAppItem.swift
- `.body` --calls--> `AddGroupSheet`  [INFERRED]
  ContentView.swift → AddGroupSheet.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Multilingual Web Summarization Prompts** — prompts_instructions_en_instruction, prompts_instructions_es_instruction, prompts_instructions_fr_instruction, prompts_prompt_en_template, prompts_prompt_es_template, prompts_prompt_fr_template [INFERRED 0.85]

## Communities (50 total, 19 thin omitted)

### Community 0 - "uBlock Scriptlets Filters"
Cohesion: 0.05
Nodes (85): abortCurrentScript(), abortCurrentScriptFn(), abortOnPropertyRead(), abortOnPropertyWrite(), abortOnStackTrace(), adjustSetInterval(), adjustSetTimeout(), collateFetchArgumentsFn() (+77 more)

### Community 1 - "Isolated WebView Controller"
Cohesion: 0.06
Nodes (4): IsolatedWebViewRepresentable, IsolatedWKWebView, .hasActiveAudioPlayback, WebViewCoordinator

### Community 2 - "CloudKit Sync Management"
Cohesion: 0.09
Nodes (12): CapsuleSnapshot, CapsuleSyncConflict, CloudSyncManager, .cloudStoreURL, .currentConflict, .localStoreURL, GroupSnapshot, ICloudSyncConflictAlertModifier (+4 more)

### Community 3 - "Overlay Annoyance Filters"
Cohesion: 0.08
Nodes (47): abortCurrentScript(), abortCurrentScriptFn(), abortOnPropertyRead(), abortOnPropertyWrite(), abortOnStackTrace(), adjustSetInterval(), adjustSetTimeout(), ArglistParser (+39 more)

### Community 4 - "App Lifecycle & Windows"
Cohesion: 0.06
Nodes (15): isowebappsApp, .body, AppDelegate, CapsuleWindowHostView, .body, .initialDomainTitle, .resolvedAppItem, CapsuleWindowPayload (+7 more)

### Community 5 - "AdGuard Mobile Scriptlets"
Cohesion: 0.09
Nodes (44): abortCurrentScript(), abortCurrentScriptFn(), abortOnPropertyRead(), abortOnPropertyWrite(), abortOnStackTrace(), adjustSetInterval(), adjustSetTimeout(), ArglistParser (+36 more)

### Community 6 - "Safari Services & Domains"
Cohesion: 0.09
Nodes (19): URL, .rootDomain, IdentifiableURL, IOSSolidBottomBar, .body, MacOSSolidBottomBar, .body, SafariView (+11 more)

### Community 7 - "EasyPrivacy Scriptlets"
Cohesion: 0.09
Nodes (27): abortCurrentScript(), abortCurrentScriptFn(), abortOnStackTrace(), collateFetchArgumentsFn(), generateContentFn(), getExceptionTokenFn(), getRandomTokenFn(), jsonEdit() (+19 more)

### Community 8 - "French Rule Scriptlets"
Cohesion: 0.11
Nodes (39): abortCurrentScript(), abortCurrentScriptFn(), abortOnPropertyRead(), abortOnPropertyWrite(), adjustSetInterval(), adjustSetTimeout(), collateFetchArgumentsFn(), generateContentFn() (+31 more)

### Community 9 - "Add Capsule Sheet UI"
Cohesion: 0.08
Nodes (15): AddWebAppSheet, .body, AppKit, Combine, CoreData, FaviconFetcher, Foundation, FoundationModels (+7 more)

### Community 10 - "Isolated uBlock Cookies"
Cohesion: 0.11
Nodes (38): closeWindow(), getAllCookiesFn(), getAllLocalStorageFn(), getCookieFn(), getRandomTokenFn(), getSafeCookieValuesFn(), hrefSanitizer(), RFC-2616 (+30 more)

### Community 11 - "Cookie Annoyance Scriptlets"
Cohesion: 0.13
Nodes (32): getAllCookiesFn(), getAllLocalStorageFn(), getCookieFn(), getRandomTokenFn(), getSafeCookieValuesFn(), RFC-2616, RFC-6265, lookupElementsFn() (+24 more)

### Community 12 - "Overlay Annoyance Isolated"
Cohesion: 0.15
Nodes (29): getAllCookiesFn(), getAllLocalStorageFn(), getCookieFn(), getRandomTokenFn(), getSafeCookieValuesFn(), RFC-2616, RFC-6265, lookupElementsFn() (+21 more)

### Community 13 - "uBlock Badware Scriptlets"
Cohesion: 0.17
Nodes (19): abortCurrentScript(), abortCurrentScriptFn(), abortOnPropertyWrite(), abortOnStackTrace(), ArglistParser, getExceptionTokenFn(), getRandomTokenFn(), matchesStackTraceFn() (+11 more)

### Community 14 - "Cookie Annoyances Main"
Cohesion: 0.17
Nodes (21): abortCurrentScript(), abortCurrentScriptFn(), abortOnPropertyRead(), abortOnPropertyWrite(), getExceptionTokenFn(), getRandomTokenFn(), preventAddEventListener(), preventRequestAnimationFrame() (+13 more)

### Community 15 - "AdGuard Cookie Isolated"
Cohesion: 0.18
Nodes (22): getCookieFn(), getRandomTokenFn(), getSafeCookieValuesFn(), RFC-2616, RFC-6265, onIdleFn(), removeClass(), removeCookie() (+14 more)

### Community 16 - "AI Web Summarizer"
Cohesion: 0.14
Nodes (12): AISummarizer, .isAvailable, WebPageSummaryError, emptyContent, .errorDescription, generationFailed, modelUnavailable, pdfExtractionFailed (+4 more)

### Community 17 - "Open URL Sheet"
Cohesion: 0.16
Nodes (9): OpenURLSheet, .body, .matchingApps, .otherApps, View, WebAppTileSettingsMenu, .body, SerializableCookie (+1 more)

### Community 19 - "Grid Item Reordering"
Cohesion: 0.11
Nodes (7): .allHomeItems, HomeGridItem, app, .displayOrder, group, .id, HomeItemDropDelegate

### Community 22 - "Group Settings Sheet"
Cohesion: 0.18
Nodes (10): .emptyStateView, GroupSettingsSheet, .appsInOtherGroups, .availableStandaloneApps, .body, .groupItems, .iOSLayout, .macOSLayout (+2 more)

### Community 23 - "French Rule Isolated Cookies"
Cohesion: 0.23
Nodes (16): getCookieFn(), getRandomTokenFn(), getSafeCookieValuesFn(), RFC-2616, RFC-6265, onIdleFn(), removeClass(), removeNodeText() (+8 more)

### Community 24 - "Content View Home Screen"
Cohesion: 0.24
Nodes (5): ContentView, .body, .deduplicatedStandaloneApps, .homeScreenView, .isDragDropEnabled

### Community 25 - "EasyPrivacy Isolated Cookies"
Cohesion: 0.24
Nodes (15): getCookieFn(), getRandomTokenFn(), getSafeCookieValuesFn(), RFC-2616, RFC-6265, removeCookie(), removeNodeText(), replaceNodeTextFn() (+7 more)

### Community 27 - "App Icon Assets"
Cohesion: 0.14
Nodes (14): App Icon Asset (appiconv2-iOS-Dark-1024x1024@1x.png), App Icon Asset (appiconv2-iOS-Default-1024x1024@1x.png), App Icon Asset (appiconv2-iOS-Default-1024x1024@1x 1.png), App Icon Asset (appiconv2-iOS-Default-128x128@1x.png), App Icon Asset (appiconv2-iOS-Default-128x128@2x.png), App Icon Asset (appiconv2-iOS-Default-16x16@1x.png), App Icon Asset (appiconv2-iOS-Default-16x16@2x.png), App Icon Asset (appiconv2-iOS-Default-256x256@1x.png) (+6 more)

### Community 28 - "Capsule Tile & Icon Cache"
Cohesion: 0.15
Nodes (6): IconImageCache, WebAppTileView, .body, WebAppGroupTileView, .body, .uniqueSortedItems

### Community 29 - "General Settings View"
Cohesion: 0.22
Nodes (8): GeneralSettingsView, .currentSnapshot, .hasUncompiledChanges, .iCloudToggleBinding, .iOSLayout, .macOSLayout, RuleSettingsSnapshot, SafariServices

### Community 30 - "Search Engine Configuration"
Cohesion: 0.22
Nodes (9): SearchEngine, bing, custom, .defaultQueryPrefix, .displayName, duckDuckGo, google, .id (+1 more)

### Community 31 - "Liquid Glass Styling"
Cohesion: 0.29
Nodes (3): LiquidGlassButtonModifier, LiquidGlassCardModifier, View

### Community 33 - "Window Presentation Modes"
Cohesion: 0.22
Nodes (9): WindowPresentationMode, .iconName, .id, .next, separateWindows, singleWindow, tabs, .title (+1 more)

### Community 35 - "Badware Node Replacement"
Cohesion: 0.46
Nodes (6): getRandomTokenFn(), removeNodeText(), replaceNodeTextFn(), runAt(), safeSelf(), safe

### Community 36 - "Content Blocking Modes"
Cohesion: 0.29
Nodes (6): BlockingMode, basic, complete, .description, .id, optimal

## Knowledge Gaps
- **77 isolated node(s):** `FoundationModels`, `webViewUnavailable`, `pdfExtractionFailed`, `emptyContent`, `modelUnavailable` (+72 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 226 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **19 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `WebAppItem` connect `Open URL Sheet` to `Add Group Sheet UI`, `Isolated WebView Controller`, `CloudKit Sync Management`, `Capsule Model Metadata`, `App Lifecycle & Windows`, `Safari Services & Domains`, `Drag & Drop Delegate`, `Add Capsule Sheet UI`, `Grid Item Reordering`, `Isolated Cookie Storage`, `Group Settings Sheet`, `Content View Home Screen`, `Capsule Tile & Icon Cache`?**
  _High betweenness centrality (0.059) - this node is a cross-community bridge._
- **Are the 14 inferred relationships involving `WebAppItem` (e.g. with `.body` and `.createGroup()`) actually correct?**
  _`WebAppItem` has 14 INFERRED edges - model-reasoned connections that need verification._
- **What connects `FoundationModels`, `webViewUnavailable`, `pdfExtractionFailed` to the rest of the system?**
  _77 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `uBlock Scriptlets Filters` be split into smaller, more focused modules?**
  _Cohesion score 0.052277227722772275 - nodes in this community are weakly interconnected._
- **Why does `CloudSyncManager` connect `CloudKit Sync Management` to `Add Capsule Sheet UI`, `Content Blocker Manager`, `Safari Services & Domains`?**
  _High betweenness centrality (0.024) - this node is a cross-community bridge._
- **Should `Isolated WebView Controller` be split into smaller, more focused modules?**
  _Cohesion score 0.06101190476190476 - nodes in this community are weakly interconnected._
- **Why does `SwiftUI` connect `Add Capsule Sheet UI` to `Capsule Tile & Icon Cache`, `General Settings View`, `Safari Services & Domains`, `Liquid Glass Styling`?**
  _High betweenness centrality (0.023) - this node is a cross-community bridge._