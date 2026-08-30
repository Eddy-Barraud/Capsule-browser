# Capsule browser

Capsule browser is a SwiftUI application for turning websites into app-like shortcuts. Each saved web app opens in its own `WKWebView` with a separate non-persistent `WKWebsiteDataStore`, while selected cookies are serialized into SwiftData so an app's session can be restored independently of the others.

The project targets macOS and iOS and uses SwiftData, WebKit, and platform-specific UIKit/AppKit adapters.

## Features

- Home screen of saved web app tiles with fetched favicons.
- Web-App setting to open links in Safari reader view by default, using `SFSafariViewController` instead of `WKWebView` on iOS, and in the Safari app on macOS.
- Independent cookies, cache, and website storage for each web app.
- Back, forward, reload, stop, URL entry, and share actions.
- URL bar synchronization as pages redirect or navigate internally.
- SwiftData persistence for app metadata, icons, visit dates, and cookies.
- CloudKit sync between user devices of the SwiftData
- uBlock Origin Lite filter lists, cosmetic hiding, and scriptlet defusers.
- Settings for enabling individual uBlock filter groups.
- macOS solid toolbar and iOS floating Liquid Glass navigation controls.
- Teardown of the active web view when leaving an app to stop background activity.

## Build and Run

1. Clone with the uBlock Origin Lite submodule:

   ```sh
   git clone --recurse-submodules https://github.com/Eddy-Barraud/Capsule-browser.git
   ```

2. Open `isowebapps.xcodeproj` in Xcode.
3. Select the `Capsule-Browser` scheme and a macOS or iOS destination.
4. Build and run.

Command-line builds can use the generic destinations:

```sh
xcodebuild -project isowebapps.xcodeproj \
  -scheme Capsule-Browser \
  -destination 'generic/platform=macOS' \
  -derivedDataPath ./build build

xcodebuild -project isowebapps.xcodeproj \
  -scheme Capsule-Browser \
  -destination 'generic/platform=iOS' \
  -derivedDataPath ./build build
```

The project expects the ruleset resource link at `isowebapps/rulesets`, pointing to `../shared/uBOL-home/chromium/rulesets`. Keep the submodule checked out when building or testing filtering.

## Source Files

- `isowebappsApp.swift`: application entry point and SwiftData model container.
- `ContentView.swift`: saved-app home screen, add/settings sheets, deletion, and data clearing.
- `WebAppItem.swift`: persisted web app model and Codable cookie representation.
- `Item.swift`: unused Xcode template model retained for reference; it is not part of the app schema.
- `AddWebAppSheet.swift`: validates new URLs, fetches favicons, and creates `WebAppItem` records.
- `WebAppContainerView.swift`: active web app layout, URL bar, navigation controls, sharing, and dismissal.
- `IsolatedWebView.swift`: `WKWebView` wrapper, delegates, navigation KVO, cookie observation, configuration, and teardown.
- `CookieManager.swift`: restores, serializes, saves, and clears per-app cookies.
- `FaviconFetcher.swift`: downloads and decodes website icon data.
- `PlatformAdapters.swift`: shared image and activity-sharing abstractions for UIKit and AppKit.
- `LiquidGlassStyles.swift`: reusable Liquid Glass card and button styling.
- `AISummarizer.swift`: provides on-device Apple Foundation Models web page summarization from rendered first-page PDF text.
- `UBlockRuleCompiler.swift`: converts uBlock declarative network request rules into WebKit content blocker rules.
- `UBlockOriginExtensionManager.swift`: locates filter lists, compiles independent `WKContentRuleList` instances, and injects cosmetic scripts.
- `UBlockSettingsView.swift`: filter and scriptlet preferences plus active rule/list diagnostics.

## Architecture and Data Flow

`isowebappsApp` creates the SwiftData container and presents `ContentView`. The home screen queries `WebAppItem` records. Selecting one presents `WebAppContainerView`, which creates an `IsolatedWebViewRepresentable` for that record and binds toolbar state through `WebViewNavigationState`.

`IsolatedWebView` creates a new non-persistent WebKit data store for the selected app. `CookieManager` restores that app's serialized cookies before loading its URL and observes cookie changes for persistence. Navigation delegates and Key-Value Observing (KVO) update the URL bar, loading state, and back/forward state. Dismissing the container stops loading and tears down the web view.

At startup, `ContentView` asks `UBlockOriginExtensionManager` to prepare. The manager reads enabled JSON rulesets from the linked uBOL resources, asks `UBlockRuleCompiler` to translate them, compiles each ruleset independently, and applies the resulting WebKit rule lists and user scripts to new web view configurations.

## Limitations and Notes

- uBlock filters use WebKit's content blocker format, so unsupported or malformed source rules are dropped during validation. The manager retains valid rules and reports rejected rules in debug output.
- The ruleset symlink and initialized submodule are required for bundled filtering resources.
- CloudKit synchronization requires the correct Apple Developer entitlements, iCloud container configuration, signing team, and runtime device testing. Generic builds only verify compilation.
- WebKit non-persistent data stores isolate site data at runtime; cookie persistence is explicitly copied into SwiftData and is not a complete substitute for every browser storage API.
- Website behavior, redirects, popups, media playback, and content blocker support vary between iOS and macOS. Test important sites on each target platform.
- The app has no authentication layer of its own. Website login state is controlled by the site's cookies and storage.
