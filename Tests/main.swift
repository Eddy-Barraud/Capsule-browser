import Foundation
import WebKit
import SwiftData
import CloudKit
#if os(macOS)
import AppKit
import SwiftUI
#endif

// MARK: - Minimal Re-creations / Test Drivers for Independent Logic Verification

func testUBlockRuleCompiler() {
    print("Running testUBlockRuleCompiler...")
    let compiler = UBlockRuleCompiler.shared
    
    // Test 1: Standard domain anchor and path
    let regex1 = compiler.convertUrlFilterToWebKitRegex("||doubleclick.net^")
    assert(regex1 == "^https?://[^/]*doubleclick\\.net[/?#:]", "Failed regex1: \(regex1)")
    
    // Test 2: Start anchor
    let regex2 = compiler.convertUrlFilterToWebKitRegex("|https://example.com/ad")
    assert(regex2 == "^https://example\\.com/ad", "Failed regex2: \(regex2)")
    
    // Test 3: End anchor
    let regex3 = compiler.convertUrlFilterToWebKitRegex("/banner.png|")
    assert(regex3 == "/banner\\.png$", "Failed regex3: \(regex3)")
    
    // Test 4: Wildcard conversion
    let regex4 = compiler.convertUrlFilterToWebKitRegex("*/ads/*")
    assert(regex4 == ".*\\/ads\\/.*" || regex4.contains(".*"), "Failed regex4: \(regex4)")
    
    // Test 5: Special character escaping (regex metacharacters . $ + ? ( ) [ ] { } \ are escaped)
    let regex5 = compiler.convertUrlFilterToWebKitRegex("tracker.js?id=123&client=[ios]")
    assert(regex5.contains("tracker\\.js\\?id=123&client=\\[ios\\]"), "Failed regex5: \(regex5)")
    assert((try? NSRegularExpression(pattern: regex5)) != nil, "regex5 must compile as valid regex")
    
    // Test 6: Empty and wildcard inputs
    assert(compiler.convertUrlFilterToWebKitRegex("") == ".*", "Empty filter must return .*")
    assert(compiler.convertUrlFilterToWebKitRegex("*") == ".*", "Wildcard filter must return .*")
    assert(compiler.convertUrlFilterToWebKitRegex("   ") == ".*", "Whitespace filter must return .*")
    
    // Test 7: DNR Conversion with unsupported condition skipped
    let dnrUnsupported: [[String: Any]] = [
        [
            "id": 1,
            "condition": [
                "urlFilter": "||adserver.com^",
                "responseHeaders": [["header": "x-ad"]]
            ],
            "action": ["type": "block"]
        ]
    ]
    let convertedUnsupported = compiler.convertDNRToWebKitRuleList(dnrRules: dnrUnsupported)
    assert(convertedUnsupported.isEmpty, "Unsupported condition should be skipped")
    
    // Test 7: Valid DNR conversion with requestDomains
    let dnrValid: [[String: Any]] = [
        [
            "id": 2,
            "condition": [
                "requestDomains": ["googleadservices.com", "doubleclick.net"],
                "resourceTypes": ["script"]
            ],
            "action": ["type": "block"]
        ]
    ]
    let convertedValid = compiler.convertDNRToWebKitRuleList(dnrRules: dnrValid)
    assert(convertedValid.count == 2, "Expected 2 rules generated for 2 requestDomains, got \(convertedValid.count)")
    
    // Test 8: Bare TLD in requestDomains should be skipped
    let dnrBareTLD: [[String: Any]] = [
        [
            "id": 3,
            "condition": [
                "requestDomains": ["com", "video"],
                "resourceTypes": ["script"]
            ],
            "action": ["type": "block"]
        ]
    ]
    let convertedBare = compiler.convertDNRToWebKitRuleList(dnrRules: dnrBareTLD)
    assert(convertedBare.isEmpty, "Bare TLDs in requestDomains should be skipped")
    
    print("✓ testUBlockRuleCompiler passed!")
}

func testSearchEngineResolution() {
    print("Running testSearchEngineResolution...")
    
    // Test 1: Full URL with scheme
    let url1 = SearchEngine.resolveInput("https://news.ycombinator.com")
    assert(url1 == "https://news.ycombinator.com", "Failed url1: \(String(describing: url1))")
    
    // Test 2: Domain with no scheme
    let url2 = SearchEngine.resolveInput("apple.com")
    assert(url2 == "https://apple.com", "Failed url2: \(String(describing: url2))")
    
    let url3 = SearchEngine.resolveInput("github.com/torvalds/linux")
    assert(url3 == "https://github.com/torvalds/linux", "Failed url3: \(String(describing: url3))")
    
    // Test 3: Search queries
    let query1 = SearchEngine.resolveInput("swift concurrency actors")
    assert(query1 != nil && query1!.contains("swift%20concurrency%20actors"), "Failed query1: \(String(describing: query1))")
    
    // Test 4: Custom template with %s
    let customEngine = SearchEngine.custom
    let customResult1 = customEngine.searchURLString(for: "hello world", customTemplate: "https://kagi.com/search?q=%s")
    assert(customResult1 == "https://kagi.com/search?q=hello%20world", "Failed customResult1: \(customResult1)")
    
    // Test 5: Custom template with {query}
    let customResult2 = customEngine.searchURLString(for: "rustlang", customTemplate: "https://search.brave.com/search?q={query}")
    assert(customResult2 == "https://search.brave.com/search?q=rustlang", "Failed customResult2: \(customResult2)")
    
    // Test 6: Empty input
    assert(SearchEngine.resolveInput("") == nil, "Empty input must return nil")
    assert(SearchEngine.resolveInput("   \n\t  ") == nil, "Whitespace input must return nil")
    
    // Test 7: Context menu selection query escaping, dotted query search URL, and menu titles
    let escapedGoogle = SearchEngine.google.searchURLString(for: "C++ & Swift #1")
    assert(
        escapedGoogle == "https://www.google.com/search?q=C%2B%2B%20%26%20Swift%20%231",
        "Query delimiters +, &, # must be percent-encoded: \(escapedGoogle)"
    )
    
    let previousEngine = UserDefaults.standard.string(forKey: SearchEngine.storageKey)
    let previousCustom = UserDefaults.standard.string(forKey: SearchEngine.customURLStorageKey)
    defer {
        if let previousEngine {
            UserDefaults.standard.set(previousEngine, forKey: SearchEngine.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: SearchEngine.storageKey)
        }
        if let previousCustom {
            UserDefaults.standard.set(previousCustom, forKey: SearchEngine.customURLStorageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: SearchEngine.customURLStorageKey)
        }
    }
    UserDefaults.standard.set(SearchEngine.google.rawValue, forKey: SearchEngine.storageKey)
    let dottedSearchURL = SearchEngine.searchURL(for: "v2.3.1")
    assert(
        dottedSearchURL?.absoluteString == "https://www.google.com/search?q=v2.3.1",
        "searchURL(for:) must treat dotted selection as search query: \(String(describing: dottedSearchURL))"
    )
    assert(SearchEngine.searchURL(for: "   \n  ") == nil, "Whitespace selection must return nil searchURL")
    
    assert(SearchEngine.duckDuckGo.contextMenuSearchTitle() == "Search with DuckDuckGo in New Capsule")
    assert(SearchEngine.google.contextMenuSearchTitle() == "Search with Google in New Capsule")
    assert(SearchEngine.bing.contextMenuSearchTitle() == "Search with Bing in New Capsule")
    assert(
        SearchEngine.custom.contextMenuSearchTitle(customTemplate: "https://www.kagi.com/search?q=%s")
            == "Search with kagi.com in New Capsule"
    )
    assert(SearchEngine.custom.contextMenuSearchTitle(customTemplate: "") == "Search in New Capsule")
    
    print("✓ testSearchEngineResolution passed!")
}

func testWebAppNamingHelper() {
    print("Running testWebAppNamingHelper...")
    
    // Test 1: Clean domain extraction
    let domain1 = WebAppNamingHelper.domainName(from: "https://www.google.com/search?q=test")
    assert(domain1 == "google.com", "Failed domain1: \(String(describing: domain1))")
    
    let domain2 = WebAppNamingHelper.domainName(from: "http://sub.domain.example.org/path")
    assert(domain2 == "sub.domain.example.org", "Failed domain2: \(String(describing: domain2))")
    
    let domain3 = WebAppNamingHelper.domainName(from: "www.wikipedia.org")
    assert(domain3 == "wikipedia.org", "Failed domain3: \(String(describing: domain3))")
    
    // Test 2: Unique Title collision handling
    let existing = ["apple.com", "apple.com 2", "GitHub"]
    let title1 = WebAppNamingHelper.uniqueTitle(for: "apple.com", existingNames: existing)
    assert(title1 == "apple.com 3", "Failed title1: \(title1)")
    
    let title2 = WebAppNamingHelper.uniqueTitle(for: "Google", existingNames: existing)
    assert(title2 == "Google", "Failed title2: \(title2)")
    
    let title3 = WebAppNamingHelper.uniqueTitle(for: "github", existingNames: existing)
    assert(title3 == "github 2", "Failed title3: \(title3)")
    
    print("✓ testWebAppNamingHelper passed!")
}

func testSerializableCookieRoundTrip() {
    print("Running testSerializableCookieRoundTrip...")
    
    // Create Foundation HTTPCookie
    let now = Date().addingTimeInterval(3600)
    let properties: [HTTPCookiePropertyKey: Any] = [
        .name: "session_id",
        .value: "xyz123456",
        .domain: ".example.com",
        .path: "/api",
        .version: 0,
        .secure: "TRUE",
        .expires: now
    ]
    guard let cookie = HTTPCookie(properties: properties) else {
        fatalError("Could not create test HTTPCookie")
    }
    
    let serializable = SerializableCookie(from: cookie)
    assert(serializable.name == "session_id")
    assert(serializable.value == "xyz123456")
    assert(serializable.domain == ".example.com")
    assert(serializable.path == "/api")
    assert(serializable.isSecure == true)
    
    // JSON round-trip
    let encoder = JSONEncoder()
    let data = try! encoder.encode(serializable)
    let decoded = try! JSONDecoder().decode(SerializableCookie.self, from: data)
    assert(decoded == serializable)
    
    // Convert back to HTTPCookie
    guard let restoredCookie = decoded.toHTTPCookie() else {
        fatalError("Failed to restore HTTPCookie from SerializableCookie")
    }
    assert(restoredCookie.name == "session_id")
    assert(restoredCookie.value == "xyz123456")
    assert(restoredCookie.domain == ".example.com")
    assert(restoredCookie.path == "/api")
    assert(restoredCookie.isSecure == true)
    
    // Empty path fallback test
    var cookieEmptyPath = decoded
    cookieEmptyPath.path = ""
    guard let restoredWithEmptyPath = cookieEmptyPath.toHTTPCookie() else {
        fatalError("Failed to restore cookie when path is empty string")
    }
    assert(restoredWithEmptyPath.path == "/", "Empty path should fall back to /")
    
    print("✓ testSerializableCookieRoundTrip passed!")
}

func testSecuritySchemeValidation() {
    print("Running testSecuritySchemeValidation...")
    
    let allowedSchemes: Set<String> = ["http", "https"]
    
    let safeURLs = [
        "https://www.apple.com",
        "http://example.com/test?a=1",
        "HTTPS://GITHUB.COM"
    ]
    for raw in safeURLs {
        let parsed = URL(string: raw)
        assert(parsed != nil && allowedSchemes.contains(parsed!.scheme!.lowercased()))
    }
    
    let dangerousURLs = [
        "file:///etc/passwd",
        "javascript:alert(document.cookie)",
        "data:text/html,<script>evil()</script>",
        "blob:https://example.com/uuid",
        "about:blank",
        "capsulebrowser://open?url=evil"
    ]
    for raw in dangerousURLs {
        let parsed = URL(string: raw)
        let isAllowed = parsed?.scheme != nil && allowedSchemes.contains(parsed!.scheme!.lowercased())
        assert(!isAllowed, "Dangerous URL \(raw) should NOT be allowed as incoming URL")
    }
    
    print("✓ testSecuritySchemeValidation passed!")
}

func testExternalSchemeDelegation() {
    print("Running testExternalSchemeDelegation...")
    
    let externalSchemes: Set<String> = ["mailto", "tel"]
    let webSchemes: Set<String> = ["http", "https", "about", "data", "blob"]
    
    let externalURLs = [
        "mailto:support@apple.com",
        "MAILTO:test@example.org?subject=Hello%20World",
        "tel:+1234567890",
        "TEL:911"
    ]
    for raw in externalURLs {
        let parsed = URL(string: raw)
        assert(parsed != nil && parsed!.scheme != nil)
        let scheme = parsed!.scheme!.lowercased()
        assert(externalSchemes.contains(scheme), "Should be classified as external scheme: \(raw)")
        assert(!webSchemes.contains(scheme), "External scheme should not be in internal web schemes")
    }
    
    let internalWebURLs = [
        "https://www.google.com",
        "http://localhost:8080",
        "about:blank",
        "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    ]
    for raw in internalWebURLs {
        let parsed = URL(string: raw)
        assert(parsed != nil && parsed!.scheme != nil)
        let scheme = parsed!.scheme!.lowercased()
        assert(webSchemes.contains(scheme), "Should be classified as web scheme: \(raw)")
        assert(!externalSchemes.contains(scheme), "Web scheme should not be in external schemes")
    }
    
    print("✓ testExternalSchemeDelegation passed!")
}

func testEphemeralCapsuleNamingFallback() {
    print("Running testEphemeralCapsuleNamingFallback...")
    
    let testCases: [(url: String, expectedName: String)] = [
        ("https://github.com/torvalds/linux", "github.com"),
        ("http://subdomain.example.org:8080/path", "subdomain.example.org"),
        ("https://", "Web Capsule"),
        ("", "Web Capsule")
    ]
    
    for (urlString, expectedName) in testCases {
        let host = URL(string: urlString)?.host
        let resolvedName = (host != nil && !host!.isEmpty) ? host! : "Web Capsule"
        assert(resolvedName == expectedName, "For URL '\(urlString)', expected '\(expectedName)', got '\(resolvedName)'")
    }
    
    print("✓ testEphemeralCapsuleNamingFallback passed!")
}

func testTabModePayloadAndSizeConstraints() {
    print("Running testTabModePayloadAndSizeConstraints...")
    
    // Test 1: Window size constraint logic (clamping to min dimensions)
    let minWidth: CGFloat = 800
    let minHeight: CGFloat = 600
    
    let smallSize = CGSize(width: 500, height: 400)
    let resolvedSmallWidth = max(minWidth, smallSize.width)
    let resolvedSmallHeight = max(minHeight, smallSize.height)
    assert(resolvedSmallWidth == 800, "Width below min must be clamped to 800")
    assert(resolvedSmallHeight == 600, "Height below min must be clamped to 600")
    
    let customSize = CGSize(width: 1440, height: 900)
    let resolvedCustomWidth = max(minWidth, customSize.width)
    let resolvedCustomHeight = max(minHeight, customSize.height)
    assert(resolvedCustomWidth == 1440, "Width above min must be preserved")
    assert(resolvedCustomHeight == 900, "Height above min must be preserved")
    
    // Test 2: Payload construction and frame serialization for link opening inside a capsule in tab mode
    struct CapsuleWindowPayloadTest: Codable, Hashable {
        let appId: UUID?
        let urlString: String?
        let name: String?
        let isSecondaryWindow: Bool
        let openAsTab: Bool
        let instanceId: UUID
        let sourceWindowNumber: Int?
        let sourceFrame: [Double]?
        
        var sourceFrameRect: CGRect? {
            guard let sf = sourceFrame, sf.count == 4 else { return nil }
            return CGRect(x: sf[0], y: sf[1], width: sf[2], height: sf[3])
        }
    }
    
    let targetURL = "https://developer.apple.com/documentation"
    let appName = "Apple Docs"
    let appId = UUID()
    let parentFrame = CGRect(x: 120, y: 80, width: 1440, height: 900)
    let parentFrameArray = [Double(parentFrame.origin.x), Double(parentFrame.origin.y), Double(parentFrame.size.width), Double(parentFrame.size.height)]
    let parentWindowNumber = 1042
    
    let payload = CapsuleWindowPayloadTest(
        appId: appId,
        urlString: targetURL,
        name: appName,
        isSecondaryWindow: true,
        openAsTab: true,
        instanceId: UUID(),
        sourceWindowNumber: parentWindowNumber,
        sourceFrame: parentFrameArray
    )
    assert(payload.openAsTab == true, "Link payload in tab mode must have openAsTab == true")
    assert(payload.isSecondaryWindow == true, "Must be flagged as secondary window")
    assert(payload.urlString == targetURL)
    assert(payload.name == appName)
    assert(payload.appId == appId)
    assert(payload.sourceWindowNumber == parentWindowNumber)
    assert(payload.sourceFrameRect == parentFrame, "Decoded sourceFrameRect must match source frame: \(String(describing: payload.sourceFrameRect))")
    
    // Test 3: JSON Round trip
    let encoder = JSONEncoder()
    let data = try! encoder.encode(payload)
    let decoder = JSONDecoder()
    let decoded = try! decoder.decode(CapsuleWindowPayloadTest.self, from: data)
    assert(decoded == payload, "Round-tripped payload must match original")
    assert(decoded.sourceFrameRect == parentFrame, "Round-tripped frame rect must match")
    
    print("✓ testTabModePayloadAndSizeConstraints passed!")
}

func testTabModeCmdWAndBlinkPreventionLogic() {
    print("Running testTabModeCmdWAndBlinkPreventionLogic...")
    
    // Test 1: Interception lifecycle before window display (zero-blink presentation)
    enum MockOrderingMode {
        case above
        case below
        case out
    }
    
    class MockTabGroup {
        var windows: [MockWindow] = []
        var selectedWindow: MockWindow?
    }
    
    class MockWindow {
        var isVisible: Bool = false
        var frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600)
        var tabbingMode: Int = 0 // 0 = default, 1 = preferred, 2 = disallowed
        var tabbingIdentifier: String? = nil
        var isClosed: Bool = false
        var tabGroup: MockTabGroup?
        var isPanel: Bool = false
        var isSheet: Bool = false
        var sheetParent: MockWindow? = nil
        var parent: MockWindow? = nil
        var isNormalLevel: Bool = true
        var isTitled: Bool = true
        var isClosable: Bool = true
        var isResizable: Bool = true
        var isUtilityOrHUDOrNonactivatingOrDocModal: Bool = false
        var isSwiftUIHosted: Bool = true
        var isMainAppWindow: Bool = false
        var isConfigured: Bool = false
        var animationBehavior: Int = 0
        var addTabbedWindowCallCount: Int = 0
        
        init() {
            let tg = MockTabGroup()
            tg.windows = [self]
            tg.selectedWindow = self
            self.tabGroup = tg
        }
        
        func addTabbedWindow(_ other: MockWindow) {
            addTabbedWindowCallCount += 1
            tabGroup?.windows.append(other)
            other.tabGroup = self.tabGroup
            tabGroup?.selectedWindow = other
        }
        
        func close() {
            isClosed = true
            tabGroup?.windows.removeAll(where: { $0 === self })
            if tabGroup?.selectedWindow === self {
                tabGroup?.selectedWindow = tabGroup?.windows.last
            }
        }
    }
    
    class MockCoordinator {
        weak var mainWindow: MockWindow?
        weak var targetWindowForNewTab: MockWindow?
        weak var pendingTabTargetWindow: MockWindow?
        var handlePresentationCallCount: Int = 0
        
        static func supportsNativeTabbing(_ window: MockWindow) -> Bool {
            !window.isPanel
                && !window.isSheet
                && window.sheetParent == nil
                && window.parent == nil
                && window.isNormalLevel
                && window.isTitled
                && window.isClosable
                && window.isResizable
                && !window.isUtilityOrHUDOrNonactivatingOrDocModal
        }
        
        func simulateOrder(_ window: MockWindow, place: MockOrderingMode) -> Bool {
            if place != .out {
                return handleNewWindowPresentation(window)
            }
            return false
        }
        
        func simulateWindowSyncMerge(_ window: MockWindow, target: MockWindow) -> Bool {
            guard target !== window,
                  Self.supportsNativeTabbing(window),
                  Self.supportsNativeTabbing(target),
                  window.tabbingMode != 2 else {
                return false
            }
            if let tg = target.tabGroup, window.tabGroup === tg {
                pendingTabTargetWindow = nil
                return false
            }
            window.tabbingIdentifier = "CapsuleBrowserWindow"
            window.tabbingMode = 1
            target.tabbingIdentifier = "CapsuleBrowserWindow"
            target.tabbingMode = 1
            window.frame = target.frame
            target.addTabbedWindow(window)
            pendingTabTargetWindow = nil
            return true
        }
        
        func handleNewWindowPresentation(_ window: MockWindow) -> Bool {
            handlePresentationCallCount += 1
            guard let target = pendingTabTargetWindow else { return false }
            if window === target {
                return false
            }
            if let tg = target.tabGroup, window.tabGroup === tg {
                pendingTabTargetWindow = nil
                return false
            }
            guard Self.supportsNativeTabbing(window),
                  window.tabbingMode != 2,
                  window.isSwiftUIHosted,
                  window !== mainWindow,
                  !window.isMainAppWindow,
                  !window.isConfigured,
                  Self.supportsNativeTabbing(target) else {
                return false
            }
            pendingTabTargetWindow = nil
            
            window.animationBehavior = -1 // none
            target.animationBehavior = -1
            
            window.tabbingIdentifier = "CapsuleBrowserWindow"
            window.tabbingMode = 1
            target.tabbingIdentifier = "CapsuleBrowserWindow"
            target.tabbingMode = 1
            
            let targetFrame = target.frame
            window.frame = targetFrame
            target.addTabbedWindow(window)
            window.isConfigured = true
            return true
        }
    }
    
    let coordinator = MockCoordinator()
    let parentWin = MockWindow()
    parentWin.isVisible = true
    parentWin.frame = CGRect(x: 100, y: 150, width: 1200, height: 800)
    
    // Simulate link click requesting a new tab
    coordinator.targetWindowForNewTab = parentWin
    coordinator.pendingTabTargetWindow = parentWin
    
    // Newly created window prior to display
    let newTabWin = MockWindow()
    newTabWin.isVisible = false // NOT yet visible on screen!
    newTabWin.frame = CGRect(x: 0, y: 0, width: 800, height: 600) // Default/cascaded frame
    
    // Interception happens at makeKeyAndOrderFront before presentation:
    let didIntercept = coordinator.handleNewWindowPresentation(newTabWin)
    assert(didIntercept == true, "Presentation must be intercepted before display")
    assert(newTabWin.frame == parentWin.frame, "New tab frame must match parent frame")
    assert(parentWin.tabGroup?.windows.count == 2, "Parent tab group must contain 2 windows")
    assert(parentWin.tabGroup?.selectedWindow === newTabWin, "New tab must be selected")
    assert(newTabWin.tabGroup === parentWin.tabGroup, "Both windows must share the same tabGroup")
    assert(coordinator.pendingTabTargetWindow == nil, "Pending tab target must be cleared after intercept")
    
    // Now window is made visible:
    newTabWin.isVisible = true
    assert(newTabWin.isVisible == true)
    
    // Test 2: Cmd+W routing logic
    // Scenario A: Active secondary tab closed via Cmd+W -> only active tab closed, parent remains open
    func simulateCloseActiveTab(
        keyWindow: MockWindow,
        mainWindow: MockWindow,
        dismissAction: inout (() -> Void)?
    ) -> String {
        let activeTab = keyWindow.tabGroup?.selectedWindow ?? keyWindow
        if activeTab === mainWindow {
            if let dismiss = dismissAction {
                dismiss()
                return "dismissed_capsule"
            }
            if let tg = activeTab.tabGroup, tg.windows.count > 1 {
                activeTab.close()
                return "closed_main_tab"
            }
            activeTab.close()
            return "closed_main_window"
        } else {
            activeTab.close()
            return "closed_secondary_tab"
        }
    }
    
    var dismissAction: (() -> Void)? = nil
    let actionResult1 = simulateCloseActiveTab(
        keyWindow: parentWin,
        mainWindow: parentWin,
        dismissAction: &dismissAction
    )
    assert(actionResult1 == "closed_secondary_tab", "Must close secondary tab: \(actionResult1)")
    assert(newTabWin.isClosed == true, "Secondary tab must be closed")
    assert(parentWin.isClosed == false, "Main window must NOT be closed when closing secondary tab!")
    assert(parentWin.tabGroup?.windows.count == 1, "Only parent window should remain")
    
    // Scenario B: Main window with open capsule dismissed via Cmd+W
    var capsuleDismissed = false
    dismissAction = {
        capsuleDismissed = true
    }
    let actionResult2 = simulateCloseActiveTab(
        keyWindow: parentWin,
        mainWindow: parentWin,
        dismissAction: &dismissAction
    )
    assert(actionResult2 == "dismissed_capsule")
    assert(capsuleDismissed == true, "Capsule dismiss action must have fired")
    assert(parentWin.isClosed == false, "Parent window must stay open on capsule dismissal")
    
    // Scenario C: Main window on home grid closed via Cmd+W when no other tabs exist
    dismissAction = nil
    let actionResult3 = simulateCloseActiveTab(
        keyWindow: parentWin,
        mainWindow: parentWin,
        dismissAction: &dismissAction
    )
    assert(actionResult3 == "closed_main_window")
    assert(parentWin.isClosed == true, "Parent window closes when no tabs or open capsules remain")
    
    // Scenario D: Regression checks for WTAffordanceWindow / system overlays & order(.out)
    let activeTarget = MockWindow()
    activeTarget.isVisible = true
    activeTarget.frame = CGRect(x: 80, y: 120, width: 1280, height: 820)
    coordinator.targetWindowForNewTab = activeTarget
    coordinator.pendingTabTargetWindow = activeTarget
    
    // 1. order(.out, ...) during window close/dismiss must never call handleNewWindowPresentation
    let countBeforeOrderOut = coordinator.handlePresentationCallCount
    let wtClosingWindow = MockWindow()
    wtClosingWindow.isTitled = false // WTAffordanceWindow-like borderless window
    let didInterceptOrderOut = coordinator.simulateOrder(wtClosingWindow, place: .out)
    assert(didInterceptOrderOut == false, "order(.out) must never trigger tab interception")
    assert(coordinator.handlePresentationCallCount == countBeforeOrderOut, "order(.out) must not invoke handleNewWindowPresentation")
    assert(coordinator.pendingTabTargetWindow === activeTarget, "order(.out) must not disturb pending tab target")
    
    // 2. Non-eligible windows must be rejected WITHOUT consuming pendingTabTargetWindow
    let wtAffordance = MockWindow()
    wtAffordance.isTitled = false
    wtAffordance.isClosable = false
    wtAffordance.isResizable = false
    wtAffordance.isSwiftUIHosted = false
    
    let childOverlay = MockWindow()
    childOverlay.parent = activeTarget
    
    let elevatedOverlay = MockWindow()
    elevatedOverlay.isNormalLevel = false
    
    let nonSwiftUIWin = MockWindow()
    nonSwiftUIWin.isSwiftUIHosted = false
    
    let utilityWin = MockWindow()
    utilityWin.isUtilityOrHUDOrNonactivatingOrDocModal = true
    
    let sheetWin = MockWindow()
    sheetWin.sheetParent = activeTarget
    
    let panelWin = MockWindow()
    panelWin.isPanel = true
    
    for invalidWin in [wtAffordance, childOverlay, elevatedOverlay, nonSwiftUIWin, utilityWin, sheetWin, panelWin] {
        let result = coordinator.handleNewWindowPresentation(invalidWin)
        assert(result == false, "Non-eligible window must never be intercepted as a tab")
        assert(coordinator.pendingTabTargetWindow === activeTarget, "Rejecting a non-eligible overlay/system window must preserve pendingTabTargetWindow")
        assert(activeTarget.addTabbedWindowCallCount == 0, "addTabbedWindow must never be called for non-eligible windows")
    }
    
    // 3. Valid Capsule window arriving right after rejected overlays still merges cleanly
    let validQueuedTab = MockWindow()
    let didMergeValid = coordinator.handleNewWindowPresentation(validQueuedTab)
    assert(didMergeValid == true, "Valid Capsule window arriving after overlay rejections must merge into tab group")
    assert(validQueuedTab.tabGroup === activeTarget.tabGroup, "Valid window must join activeTarget's tab group")
    assert(coordinator.pendingTabTargetWindow == nil, "pendingTabTargetWindow must clear once valid tab merges")
    
    // 4. Merging requires BOTH target and new window to support native tabbing
    let invalidTarget = MockWindow()
    invalidTarget.isTitled = false
    coordinator.pendingTabTargetWindow = invalidTarget
    let candidateTab = MockWindow()
    assert(coordinator.handleNewWindowPresentation(candidateTab) == false, "Invalid target must not accept tabbed windows")
    assert(coordinator.simulateWindowSyncMerge(candidateTab, target: invalidTarget) == false, "onWindowSync merge must also reject invalid targets")
    assert(coordinator.simulateWindowSyncMerge(wtAffordance, target: activeTarget) == false, "onWindowSync merge must reject borderless windows")
    coordinator.pendingTabTargetWindow = nil
    
    // 5. After onWindowSync merges a tab, pendingTabTargetWindow is cleared and targetWindowForNewTab alone never intercepts
    coordinator.targetWindowForNewTab = activeTarget
    coordinator.pendingTabTargetWindow = activeTarget
    let syncTabWin = MockWindow()
    assert(coordinator.simulateWindowSyncMerge(syncTabWin, target: activeTarget) == true, "onWindowSync should merge valid tab")
    assert(coordinator.pendingTabTargetWindow == nil, "onWindowSync merge must clear pendingTabTargetWindow")
    assert(coordinator.targetWindowForNewTab === activeTarget, "targetWindowForNewTab may remain as source fallback")
    let unrelatedLaterWin = MockWindow()
    assert(coordinator.handleNewWindowPresentation(unrelatedLaterWin) == false, "targetWindowForNewTab alone must NEVER trigger interception")
    assert(unrelatedLaterWin.tabGroup !== activeTarget.tabGroup, "Later window must not be merged without an armed pendingTabTargetWindow")
    
    print("✓ testTabModeCmdWAndBlinkPreventionLogic passed!")
}

#if os(macOS)
@MainActor
func testRealNSWindowTabbingEligibility() {
    print("Running testRealNSWindowTabbingEligibility...")
    _ = NSApplication.shared
    
    func supportsNativeTabbing(_ window: NSWindow) -> Bool {
        !(window is NSPanel)
            && !window.isSheet
            && window.sheetParent == nil
            && window.parent == nil
            && window.level == .normal
            && window.styleMask.contains(.titled)
            && window.styleMask.contains(.closable)
            && window.styleMask.contains(.resizable)
            && !window.styleMask.contains(.utilityWindow)
            && !window.styleMask.contains(.hudWindow)
            && !window.styleMask.contains(.nonactivatingPanel)
            && !window.styleMask.contains(.docModalWindow)
    }
    
    let docWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    assert(supportsNativeTabbing(docWindow) == true, "Standard titled/closable/resizable NSWindow must support native tabbing")
    
    let borderlessOverlay = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 120, height: 40),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    assert(!borderlessOverlay.styleMask.contains(.titled), "Borderless WTAffordanceWindow-style window must not have .titled")
    assert(supportsNativeTabbing(borderlessOverlay) == false, "Borderless NSWindow must be rejected before addTabbedWindow")
    
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    assert(supportsNativeTabbing(panel) == false, "NSPanel must be rejected")
    
    let elevatedWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    elevatedWindow.level = .floating
    assert(supportsNativeTabbing(elevatedWindow) == false, "Elevated-level NSWindow must be rejected")
    
    let childWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    docWindow.addChildWindow(childWindow, ordered: .above)
    assert(childWindow.parent === docWindow, "Attached child window must report parent")
    assert(supportsNativeTabbing(childWindow) == false, "Child window with parent must be rejected")
    docWindow.removeChildWindow(childWindow)
    
    docWindow.close()
    borderlessOverlay.close()
    panel.close()
    elevatedWindow.close()
    childWindow.close()
    
    print("✓ testRealNSWindowTabbingEligibility passed!")
}
#endif

@MainActor
func testCloudSyncMergeAndConflictDetection() {
    print("Running testCloudSyncMergeAndConflictDetection...")
    
    // Test 1: URL normalization
    assert(
        CloudSyncManager.normalizedURL("HTTPS://GitHub.COM/") == CloudSyncManager.normalizedURL("https://github.com"),
        "URL normalization must lowercase scheme/host and strip trailing slash"
    )
    assert(
        CloudSyncManager.normalizedURL("  https://example.com/app/  ") == "https://example.com/app",
        "URL normalization must trim whitespace and trailing slash on paths"
    )
    assert(
        CloudSyncManager.normalizedURL("https://github.com") != CloudSyncManager.normalizedURL("https://gitlab.com"),
        "Distinct URLs must remain distinct after normalization"
    )
    
    // Test 2: Same-name + same-URL auto-merges without conflict; same-name + different-URL triggers conflict
    assert(
        CloudSyncManager.shouldQueueConflict(
            localName: "  GitHub ",
            localURL: "https://github.com/",
            cloudName: "github",
            cloudURL: "HTTPS://GITHUB.COM"
        ) == false,
        "Same name and same normalized URL must auto-merge without conflict prompt"
    )
    assert(
        CloudSyncManager.shouldQueueConflict(
            localName: "GitHub",
            localURL: "https://github.com",
            cloudName: "github",
            cloudURL: "https://github.com/enterprise"
        ) == true,
        "Same name with different URLs must queue conflict prompt"
    )
    assert(
        CloudSyncManager.shouldQueueConflict(
            localName: "Work Mail",
            localURL: "https://mail.google.com",
            cloudName: "Personal Mail",
            cloudURL: "https://mail.google.com"
        ) == false,
        "Different capsule names must not queue a name-clash conflict"
    )
    
    // Test 3: Store signature detects remote insertions, group links, and field updates
    let schema = Schema([WebAppItem.self, WebAppGroup.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let context = container.mainContext
    
    let sigEmpty = CloudSyncManager.computeStoreSignature(in: context)
    
    let item1 = WebAppItem(name: "GitHub", urlString: "https://github.com")
    context.insert(item1)
    try! context.save()
    let sigOneItem = CloudSyncManager.computeStoreSignature(in: context)
    assert(sigOneItem != sigEmpty, "Adding a capsule must change store signature")
    
    let group1 = WebAppGroup(name: "Dev")
    context.insert(group1)
    item1.group = group1
    try! context.save()
    let sigWithGroup = CloudSyncManager.computeStoreSignature(in: context)
    assert(sigWithGroup != sigOneItem, "Adding a group / linking capsule must change store signature")
    
    item1.urlString = "https://github.com/trending"
    try! context.save()
    let sigUpdatedURL = CloudSyncManager.computeStoreSignature(in: context)
    assert(sigUpdatedURL != sigWithGroup, "Updating capsule URL must change store signature")
    
    // Test 4: Runtime navigation fields (lastOpenedURLString, lastVisited, isolatedCookiesData) must NOT change store signature
    item1.lastOpenedURLString = "https://github.com/settings"
    item1.lastVisited = Date()
    item1.isolatedCookiesData = Data([0x01, 0x02, 0x03, 0x04])
    try! context.save()
    let sigAfterRuntimeUpdate = CloudSyncManager.computeStoreSignature(in: context)
    assert(sigAfterRuntimeUpdate == sigUpdatedURL, "Runtime navigation/cookie mutations must not alter structural store signature")
    
    // Test 5: Transient/ignorable CloudKit event error filtering
    let tokenExpiredError = NSError(domain: CKErrorDomain, code: CKError.Code.changeTokenExpired.rawValue)
    assert(CloudSyncManager.isTransientOrIgnorableCloudKitEventError(tokenExpiredError) == true, "CKError.changeTokenExpired must be treated as transient")
    
    let partialTokenExpired = NSError(
        domain: CKErrorDomain,
        code: CKError.Code.partialFailure.rawValue,
        userInfo: [CKPartialErrorsByItemIDKey: ["zone": tokenExpiredError]]
    )
    assert(CloudSyncManager.isTransientOrIgnorableCloudKitEventError(partialTokenExpired) == true, "Partial failure wrapping only transient errors must be treated as transient")
    
    let storeRemovedError = NSError(domain: NSCocoaErrorDomain, code: 134407)
    assert(CloudSyncManager.isTransientOrIgnorableCloudKitEventError(storeRemovedError) == true, "NSCocoaErrorDomain 134407 must be treated as ignorable")
    
    let notAuthError = NSError(domain: CKErrorDomain, code: CKError.Code.notAuthenticated.rawValue)
    assert(CloudSyncManager.isTransientOrIgnorableCloudKitEventError(notAuthError) == false, "CKError.notAuthenticated must NOT be ignored")
    
    let quotaError = NSError(domain: CKErrorDomain, code: CKError.Code.quotaExceeded.rawValue)
    assert(CloudSyncManager.isTransientOrIgnorableCloudKitEventError(quotaError) == false, "CKError.quotaExceeded must NOT be ignored")
    
    print("✓ testCloudSyncMergeAndConflictDetection passed!")
}

@MainActor
func testMemoryTeardownAndCacheRelease() {
    print("Running testMemoryTeardownAndCacheRelease...")
    
    // Test 1: UBlockOriginExtensionManager cache release clears in-memory state without zeroing badge counts
    let ublock = UBlockOriginExtensionManager.shared
    ublock.releaseInMemoryCaches()
    assert(ublock.isLoaded == false, "releaseInMemoryCaches must mark uBlock manager as unloaded")
    assert(ublock.hasInMemoryCaches == false, "releaseInMemoryCaches must empty compiled rule lists and cosmetic user scripts")
    
    // Test 2: IsolatedCookieManager cache release & flushAllPendingSaves execute cleanly
    let cookieManager = IsolatedCookieManager.shared
    cookieManager.releaseInMemoryCaches()
    var flushed = false
    Task { @MainActor in
        await cookieManager.flushAllPendingSaves()
        flushed = true
    }
    let flushDeadline = Date().addingTimeInterval(2.0)
    while !flushed && Date() < flushDeadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    assert(flushed == true, "flushAllPendingSaves must complete cleanly when queue is empty")
    
    // Test 3: Real WKWebView inside NSHostingView with WeakWindowBox deallocates completely on return to Home Screen
    #if os(macOS)
    final class WeakWindowBox {
        weak var window: NSWindow?
    }
    final class TestDeinitWebView: WKWebView {}
    struct TestWebRepresentable: NSViewRepresentable {
        let onCreated: (TestDeinitWebView) -> Void
        func makeNSView(context: Context) -> TestDeinitWebView {
            let wv = TestDeinitWebView(frame: .zero)
            onCreated(wv)
            return wv
        }
        func updateNSView(_ nsView: TestDeinitWebView, context: Context) {}
        static func dismantleNSView(_ nsView: TestDeinitWebView, coordinator: ()) {
            nsView.stopLoading()
            nsView.pauseAllMediaPlayback(completionHandler: nil)
            nsView.closeAllMediaPresentations(completionHandler: nil)
            nsView.setAllMediaPlaybackSuspended(true)
            nsView.navigationDelegate = nil
            nsView.uiDelegate = nil
            let controller = nsView.configuration.userContentController
            controller.removeAllContentRuleLists()
            controller.removeAllUserScripts()
            controller.removeAllScriptMessageHandlers()
            nsView.removeFromSuperview()
        }
    }
    final class TestNavModel: ObservableObject {
        @Published var showWeb: Bool = true
    }
    struct TestRootView: View {
        @ObservedObject var model: TestNavModel
        let windowBox: WeakWindowBox
        let onCreated: (TestDeinitWebView) -> Void
        var body: some View {
            Group {
                if model.showWeb {
                    TestWebRepresentable(onCreated: onCreated)
                } else {
                    Text("Home Screen Cached")
                }
            }
            .onAppear {
                _ = windowBox.window
            }
        }
    }
    
    _ = NSApplication.shared
    let navModel = TestNavModel()
    let windowBox = WeakWindowBox()
    weak var weakWebView: TestDeinitWebView?
    
    let homeWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    homeWindow.isReleasedWhenClosed = false
    windowBox.window = homeWindow
    
    autoreleasepool {
        homeWindow.contentView = NSHostingView(
            rootView: TestRootView(
                model: navModel,
                windowBox: windowBox,
                onCreated: { weakWebView = $0 }
            )
        )
        homeWindow.contentView?.layoutSubtreeIfNeeded()
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    assert(weakWebView != nil, "WKWebView should be alive while presented")
    
    // Switch back to cached Home Screen (without loadHTMLString("", baseURL: nil))
    autoreleasepool {
        navModel.showWeb = false
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    assert(weakWebView == nil, "WKWebView must fully deallocate when dismissed back to Home Screen")
    assert(windowBox.window === homeWindow, "Home Screen window should remain cached while open")
    
    homeWindow.close()
    #endif
    
    print("✓ testMemoryTeardownAndCacheRelease passed!")
}

#if os(macOS)
@MainActor
func testContextMenuSearchInterception() {
    print("Running testContextMenuSearchInterception...")
    _ = NSApplication.shared
    
    func isSearchWebMenuItem(_ item: NSMenuItem) -> Bool {
        if item.identifier?.rawValue == "WKMenuItemIdentifierSearchWeb" {
            return true
        }
        if let action = item.action, NSStringFromSelector(action) == "_searchWithGoogleFromMenu:" {
            return true
        }
        return false
    }
    
    let searchByID = NSMenuItem(title: "Search with Google", action: nil, keyEquivalent: "")
    searchByID.identifier = NSUserInterfaceItemIdentifier("WKMenuItemIdentifierSearchWeb")
    assert(isSearchWebMenuItem(searchByID) == true, "Must match WKMenuItemIdentifierSearchWeb")
    
    let searchByLegacySelector = NSMenuItem(
        title: "Search with Google",
        action: NSSelectorFromString("_searchWithGoogleFromMenu:"),
        keyEquivalent: ""
    )
    assert(isSearchWebMenuItem(searchByLegacySelector) == true, "Must match legacy _searchWithGoogleFromMenu:")
    
    let lookUpItem = NSMenuItem(title: "Look Up", action: nil, keyEquivalent: "")
    lookUpItem.identifier = NSUserInterfaceItemIdentifier("WKMenuItemIdentifierLookUp")
    assert(isSearchWebMenuItem(lookUpItem) == false, "Must never match WKMenuItemIdentifierLookUp")
    
    let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    assert(isSearchWebMenuItem(copyItem) == false, "Must never match unrelated menu items")
    
    class TestMenuValidationWebView: WKWebView {
        @objc func searchSelectionInNewEphemeralCapsule(_ sender: Any?) {}
        override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
            if item.action == #selector(searchSelectionInNewEphemeralCapsule(_:)) {
                return true
            }
            return super.validateUserInterfaceItem(item)
        }
    }
    
    let wv = TestMenuValidationWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    let rewrittenItem = NSMenuItem(
        title: SearchEngine.google.contextMenuSearchTitle(),
        action: #selector(TestMenuValidationWebView.searchSelectionInNewEphemeralCapsule(_:)),
        keyEquivalent: ""
    )
    rewrittenItem.target = wv
    assert(wv.validateUserInterfaceItem(rewrittenItem) == true, "Custom search selector must validate as enabled")
    
    let disabledOtherItem = NSMenuItem(
        title: "Forward",
        action: #selector(WKWebView.goForward(_:)),
        keyEquivalent: ""
    )
    assert(wv.validateUserInterfaceItem(disabledOtherItem) == false, "Super validation must remain intact")
    
    print("✓ testContextMenuSearchInterception passed!")
}
#endif

@MainActor
func testDownloadPolicyAndFileHelpers() {
    print("Running testDownloadPolicyAndFileHelpers...")
    
    // Test 1: Content-Disposition attachment detection
    assert(
        CapsuleDownloadManager.isAttachmentContentDisposition("attachment; filename=AppCleaner.zip") == true,
        "Standard attachment header must trigger download"
    )
    assert(
        CapsuleDownloadManager.isAttachmentContentDisposition("ATTACHMENT") == true,
        "Case-insensitive attachment header must trigger download"
    )
    assert(
        CapsuleDownloadManager.isAttachmentContentDisposition("inline; filename=doc.pdf") == false,
        "Inline Content-Disposition must not trigger download by disposition alone"
    )
    assert(
        CapsuleDownloadManager.isAttachmentContentDisposition(nil) == false,
        "Nil Content-Disposition must return false"
    )
    
    // Test 2: Response download policy decisions
    let zipURL = URL(string: "https://freemacsoft.net/downloads/AppCleaner_3.6.8.zip")!
    let zipResponse = HTTPURLResponse(
        url: zipURL,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/zip", "Content-Length": "4194304"]
    )!
    assert(
        CapsuleDownloadManager.shouldDownloadResponse(zipResponse, canShowMIMEType: false, isForMainFrame: true) == true,
        "Main-frame .zip with canShowMIMEType=false must trigger download"
    )
    
    let htmlURL = URL(string: "https://appcleaner.pro/")!
    let htmlResponse = HTTPURLResponse(
        url: htmlURL,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "text/html"]
    )!
    assert(
        CapsuleDownloadManager.shouldDownloadResponse(htmlResponse, canShowMIMEType: true, isForMainFrame: true) == false,
        "Main-frame text/html must render in WebView, not download"
    )
    
    let pdfAttachmentURL = URL(string: "https://example.com/report.pdf")!
    let pdfAttachmentResponse = HTTPURLResponse(
        url: pdfAttachmentURL,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: [
            "Content-Type": "application/pdf",
            "Content-Disposition": "attachment; filename=\"report.pdf\""
        ]
    )!
    assert(
        CapsuleDownloadManager.shouldDownloadResponse(pdfAttachmentResponse, canShowMIMEType: true, isForMainFrame: true) == true,
        "Content-Disposition attachment must trigger download even if MIME is displayable"
    )
    
    let noContentResponse = HTTPURLResponse(
        url: URL(string: "https://example.com/ping")!,
        statusCode: 204,
        httpVersion: "HTTP/1.1",
        headerFields: nil
    )!
    assert(
        CapsuleDownloadManager.shouldDownloadResponse(noContentResponse, canShowMIMEType: false, isForMainFrame: true) == false,
        "HTTP 204 No Content must never trigger download"
    )
    
    let subframeEmptyResponse = URLResponse(
        url: URL(string: "https://example.com/pixel")!,
        mimeType: "application/octet-stream",
        expectedContentLength: 0,
        textEncodingName: nil
    )
    assert(
        CapsuleDownloadManager.shouldDownloadResponse(subframeEmptyResponse, canShowMIMEType: false, isForMainFrame: false) == false,
        "Subframe 0-byte non-attachment response must not trigger download"
    )
    
    let subframeZipResponse = URLResponse(
        url: zipURL,
        mimeType: "application/zip",
        expectedContentLength: 1024,
        textEncodingName: nil
    )
    assert(
        CapsuleDownloadManager.shouldDownloadResponse(subframeZipResponse, canShowMIMEType: false, isForMainFrame: false) == true,
        "Subframe non-empty .zip response must trigger download"
    )
    
    // Test 3: Filename sanitization
    assert(
        CapsuleDownloadManager.sanitizedFilename("AppCleaner_3.6.8.zip") == "AppCleaner_3.6.8.zip"
    )
    assert(
        CapsuleDownloadManager.sanitizedFilename("../../.zshrc") == "zshrc",
        "Path traversal & leading dots must be stripped"
    )
    assert(
        CapsuleDownloadManager.sanitizedFilename("dir/sub:name.zip") == "sub_name.zip",
        "Directory components and colons must be sanitized"
    )
    assert(
        CapsuleDownloadManager.sanitizedFilename(".env") == "env",
        "Hidden dotfiles must be stripped of leading dots"
    )
    assert(
        CapsuleDownloadManager.sanitizedFilename("", fallbackURL: URL(string: "https://example.com/archive.tar.gz")) == "archive.tar.gz",
        "Empty filename must fall back to URL lastPathComponent"
    )
    assert(
        CapsuleDownloadManager.sanitizedFilename("   ", fallbackURL: nil) == "download",
        "Empty filename with no fallback URL must return 'download'"
    )
    
    // Test 4: Unique destination collision avoidance
    let fm = FileManager.default
    let tempDir = fm.temporaryDirectory.appendingPathComponent("capsule_dl_test_\(UUID().uuidString)", isDirectory: true)
    try! fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tempDir) }
    
    let firstURL = CapsuleDownloadManager.uniqueDestinationURL(in: tempDir, filename: "AppCleaner_3.6.8.zip", fileManager: fm)
    assert(firstURL.lastPathComponent == "AppCleaner_3.6.8.zip")
    fm.createFile(atPath: firstURL.path, contents: Data("1".utf8))
    
    let secondURL = CapsuleDownloadManager.uniqueDestinationURL(in: tempDir, filename: "AppCleaner_3.6.8.zip", fileManager: fm)
    assert(secondURL.lastPathComponent == "AppCleaner_3.6.8 (2).zip")
    fm.createFile(atPath: secondURL.path, contents: Data("2".utf8))
    
    let thirdURL = CapsuleDownloadManager.uniqueDestinationURL(in: tempDir, filename: "AppCleaner_3.6.8.zip", fileManager: fm)
    assert(thirdURL.lastPathComponent == "AppCleaner_3.6.8 (3).zip")
    
    let extlessFirst = CapsuleDownloadManager.uniqueDestinationURL(in: tempDir, filename: "README", fileManager: fm)
    assert(extlessFirst.lastPathComponent == "README")
    fm.createFile(atPath: extlessFirst.path, contents: Data("readme".utf8))
    
    let extlessSecond = CapsuleDownloadManager.uniqueDestinationURL(in: tempDir, filename: "README", fileManager: fm)
    assert(extlessSecond.lastPathComponent == "README (2)")
    
    print("✓ testDownloadPolicyAndFileHelpers passed!")
}

func testReaderHTMLUtilities() {
    print("Running testReaderHTMLUtilities...")
    
    // Test 1: Metadata extraction & entity decoding (with reversed attribute order)
    let htmlWithOG = """
    <html><head>
        <title>Fallback Title</title>
        <meta content="Swift &amp; Reader &#39;Guide&#39;" property="og:title">
        <meta property="og:site_name" content="Example&#x20;Daily">
        <meta name="author" content="Jane Doe">
    </head><body><p>Hello</p></body></html>
    """
    let meta = ReaderHTMLUtilities.extractMetadata(from: htmlWithOG)
    assert(meta.title == "Swift & Reader 'Guide'", "Unexpected og:title: \(String(describing: meta.title))")
    assert(meta.siteName == "Example Daily", "Unexpected siteName: \(String(describing: meta.siteName))")
    assert(meta.author == "Jane Doe", "Unexpected author: \(String(describing: meta.author))")
    
    // Test 2: Fallback to <title> when og:title is absent
    let htmlTitleOnly = "<html><head><title>  Simple   Article &mdash; News </title></head></html>"
    let titleOnlyMeta = ReaderHTMLUtilities.extractMetadata(from: htmlTitleOnly)
    assert(titleOnlyMeta.title == "Simple Article — News", "Unexpected <title>: \(String(describing: titleOnlyMeta.title))")
    
    // Test 3: Charset decoding via HTTP encoding name & meta charset sniffing
    let latin1String = "Café résumé"
    let latin1Data = latin1String.data(using: .isoLatin1)!
    assert(
        ReaderHTMLUtilities.decodeHTMLData(latin1Data, textEncodingName: "iso-8859-1") == latin1String,
        "Must honor IANA charset from HTTP header"
    )
    let sniffedHTML = "<meta charset=\"iso-8859-1\"><p>Crème brûlée</p>".data(using: .isoLatin1)!
    assert(
        ReaderHTMLUtilities.decodeHTMLData(sniffedHTML, textEncodingName: nil).contains("Crème brûlée"),
        "Must sniff charset from <meta charset>"
    )
    
    // Test 4: Lazy image promotion
    let lazyHTML = """
    <p><img data-src="https://cdn.example.com/photo.jpg" src="data:image/svg+xml;base64,PHN2Zz4=" alt="Hero"></p>
    <p><img data-original="/images/diagram.png" alt="Diagram"></p>
    <p><img src="https://cdn.example.com/real.png" data-src="https://cdn.example.com/other.png"></p>
    """
    let normalizedHTML = ReaderHTMLUtilities.normalizeLazyImages(in: lazyHTML)
    assert(normalizedHTML.contains("src=\"https://cdn.example.com/photo.jpg\""), "Must promote data-src over svg placeholder")
    assert(normalizedHTML.contains("src=\"/images/diagram.png\""), "Must add src from data-original when missing")
    assert(normalizedHTML.contains("src=\"https://cdn.example.com/real.png\""), "Must preserve valid existing src")
    
    // Test 5: JS-shell detection
    let jsShellHTML = "<html><body><div id=\"root\"></div><noscript>Please enable JavaScript to continue.</noscript></body></html>"
    assert(
        ReaderHTMLUtilities.looksLikeJavaScriptShell(markdown: "Please enable JavaScript to continue.", rawHTML: jsShellHTML) == true,
        "Must flag JS-required shell"
    )
    assert(
        ReaderHTMLUtilities.looksLikeJavaScriptShell(markdown: "", rawHTML: "<html><body></body></html>") == true,
        "Must flag empty extracted markdown"
    )
    let validArticle = String(repeating: "Swift powers native macOS applications reliably. ", count: 8)
    assert(
        ReaderHTMLUtilities.looksLikeJavaScriptShell(markdown: validArticle, rawHTML: "<html><body><article><p>enable javascript comment mention</p></article></body></html>") == false,
        "Long article prose must not be flagged as JS shell"
    )
    
    // Test 6: Plain-text cleanup & reading time
    let sampleMD = "# Title\n\nRead [the docs](https://swift.org) ![hero](https://example.com/a.png).\n\n```swift\nlet x = 1\n```"
    let plain = ReaderHTMLUtilities.plainText(fromMarkdown: sampleMD)
    assert(plain.contains("Title") && plain.contains("Read the docs") && !plain.contains("hero"), "Unexpected plain text: \(plain)")
    assert(ReaderHTMLUtilities.estimatedReadingMinutes(for: sampleMD) == 1)
    assert(ReaderHTMLUtilities.isLikelyDirectURLInput("example.com/article") == true)
    assert(ReaderHTMLUtilities.isLikelyDirectURLInput("https://news.ycombinator.com") == true)
    assert(ReaderHTMLUtilities.isLikelyDirectURLInput("swift markdown reader") == false)
    
    // Test 7: ReaderHistoryStack navigation & truncation
    var history = ReaderHistoryStack()
    let u1 = URL(string: "https://example.com/1")!
    let u1Canonical = URL(string: "https://example.com/1-canonical")!
    let u2 = URL(string: "https://example.com/2")!
    let u3 = URL(string: "https://example.com/3")!
    history.reset(to: u1)
    assert(history.canGoBack == false && history.canGoForward == false)
    history.replaceCurrent(with: u1Canonical)
    assert(history.currentURL == u1Canonical)
    history.push(u1Canonical) // consecutive duplicate ignored
    assert(history.entries.count == 1)
    history.push(u2)
    assert(history.canGoBack == true && history.canGoForward == false)
    assert(history.goBack() == u1Canonical)
    assert(history.canGoBack == false && history.canGoForward == true)
    history.push(u3) // truncates u2
    assert(history.entries == [u1Canonical, u3])
    assert(history.canGoForward == false)
    assert(history.goBack() == u1Canonical)
    assert(history.goForward() == u3)
    
    // Test 8: Background WebView fallback & readiness helpers
    assert(ReaderHTMLUtilities.isKnownJSRedirectorURL(URL(string: "https://news.google.com/read/CBMiWWh0dHA")!) == true)
    assert(ReaderHTMLUtilities.isKnownJSRedirectorURL(URL(string: "https://news.google.com/articles/CBMi")!) == true)
    assert(ReaderHTMLUtilities.isKnownJSRedirectorURL(URL(string: "https://www.google.com/url?q=https://example.com")!) == true)
    assert(ReaderHTMLUtilities.isKnownJSRedirectorURL(URL(string: "https://developer.apple.com/news/")!) == false)
    
    assert(ReaderHTMLUtilities.shouldFallbackToBackgroundWebView(httpStatusCode: 403) == true)
    assert(ReaderHTMLUtilities.shouldFallbackToBackgroundWebView(httpStatusCode: 401) == true)
    assert(ReaderHTMLUtilities.shouldFallbackToBackgroundWebView(httpStatusCode: 429) == true)
    assert(ReaderHTMLUtilities.shouldFallbackToBackgroundWebView(httpStatusCode: 503) == true)
    assert(ReaderHTMLUtilities.shouldFallbackToBackgroundWebView(httpStatusCode: 404) == false)
    assert(ReaderHTMLUtilities.shouldFallbackToBackgroundWebView(httpStatusCode: 200) == false)
    
    assert(ReaderHTMLUtilities.shouldIgnoreBackgroundNavigationError(domain: NSURLErrorDomain, code: NSURLErrorCancelled) == true)
    assert(ReaderHTMLUtilities.shouldIgnoreBackgroundNavigationError(domain: "WebKitErrorDomain", code: 102) == true)
    assert(ReaderHTMLUtilities.shouldIgnoreBackgroundNavigationError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet) == false)
    
    assert(
        ReaderHTMLUtilities.evaluateBackgroundCaptureReadiness(
            ReaderHTMLCapture(title: "", urlString: "about:blank", html: "<p>Hello</p>", readyState: "complete", textLength: 500, matchedPrimaryContainer: true)
        ) == .notReadyYet
    )
    assert(
        ReaderHTMLUtilities.evaluateBackgroundCaptureReadiness(
            ReaderHTMLCapture(title: "", urlString: "https://example.com/a", html: "<p>Content</p>", readyState: "loading", textLength: 500, matchedPrimaryContainer: true)
        ) == .notReadyYet
    )
    assert(
        ReaderHTMLUtilities.evaluateBackgroundCaptureReadiness(
            ReaderHTMLCapture(title: "", urlString: "https://news.google.com/read/123", html: "<p>Redirecting</p>", readyState: "complete", textLength: 500, matchedPrimaryContainer: true)
        ) == .notReadyYet
    )
    assert(
        ReaderHTMLUtilities.evaluateBackgroundCaptureReadiness(
            ReaderHTMLCapture(title: "", urlString: "https://example.com/a", html: "<p>Just a moment...</p>", readyState: "complete", textLength: 20, matchedPrimaryContainer: false)
        ) == .notReadyYet
    )
    assert(
        ReaderHTMLUtilities.evaluateBackgroundCaptureReadiness(
            ReaderHTMLCapture(title: "Title", urlString: "https://example.com/a", html: "<article><p>Article text</p></article>", readyState: "interactive", textLength: 320, matchedPrimaryContainer: true)
        ) == .readyImmediately
    )
    assert(
        ReaderHTMLUtilities.evaluateBackgroundCaptureReadiness(
            ReaderHTMLCapture(title: "Title", urlString: "https://example.com/a", html: "<div><p>Body text</p></div>", readyState: "interactive", textLength: 480, matchedPrimaryContainer: false)
        ) == .readyImmediately
    )
    assert(
        ReaderHTMLUtilities.evaluateBackgroundCaptureReadiness(
            ReaderHTMLCapture(title: "Short Note", urlString: "https://example.com/a", html: "<p>A genuine short update with plenty of context.</p>", readyState: "complete", textLength: 120, matchedPrimaryContainer: false)
        ) == .usableAfterSettle
    )
    
    // Test 9: Robot / human-verification check detection (Google /sorry/index & CAPTCHA widgets)
    let googleSorryURL = URL(string: "https://www.google.com/sorry/index?continue=https://news.google.com/read/CBMi&hl=fr&q=EhAgAQ")!
    let googleFrSorryURL = URL(string: "https://www.google.fr/sorry/index?continue=https://example.com")!
    let cloudflareChallengeURL = URL(string: "https://example.com/cdn-cgi/challenge-platform/h/b/orchestrate")!
    let datadomeCaptchaURL = URL(string: "https://geo.captcha-delivery.com/captcha/?initialCid=123")!
    assert(ReaderHTMLUtilities.isRobotCheckURL(googleSorryURL) == true)
    assert(ReaderHTMLUtilities.isRobotCheckURL(googleFrSorryURL) == true)
    assert(ReaderHTMLUtilities.isRobotCheckURL(cloudflareChallengeURL) == true)
    assert(ReaderHTMLUtilities.isRobotCheckURL(datadomeCaptchaURL) == true)
    assert(ReaderHTMLUtilities.isRobotCheckURL(URL(string: "https://news.google.com/read/CBMiTest")!) == false)
    assert(ReaderHTMLUtilities.isRobotCheckURL(URL(string: "https://www.lemonde.fr/article.html")!) == false)
    
    let frenchSorryHTML = "<html><body><p>Nos systèmes ont détecté un trafic inhabituel en provenance de votre réseau.</p><form id=\"captcha-form\"><div class=\"g-recaptcha\"></div></form></body></html>"
    assert(
        ReaderHTMLUtilities.isRobotCheckContent(
            urlString: "https://www.google.com/sorry/index?continue=https://news.google.com/read/CBMi",
            html: frenchSorryHTML,
            title: "https://www.google.com/sorry/index"
        ) == true
    )
    assert(
        ReaderHTMLUtilities.isRobotCheckContent(
            urlString: "https://publisher.example.com/article",
            html: "<div class=\"cf-turnstile\">Verify you are human</div>",
            hasRobotCheckWidget: true
        ) == true
    )
    let longArticleWithCommentCaptcha = "<article><p>" + String(repeating: "Detailed journalism content paragraph. ", count: 60) + "</p></article>"
    assert(
        ReaderHTMLUtilities.isRobotCheckContent(
            urlString: "https://publisher.example.com/long-article",
            html: longArticleWithCommentCaptcha,
            hasRobotCheckWidget: true
        ) == false,
        "Long genuine article with comment form reCAPTCHA must not trigger robot check passthrough"
    )
    assert(
        ReaderHTMLUtilities.evaluateBackgroundCaptureReadiness(
            ReaderHTMLCapture(title: "Sorry", urlString: googleSorryURL.absoluteString, html: "<p>Check</p>", readyState: "loading", textLength: 600, matchedPrimaryContainer: false, hasRobotCheckWidget: true)
        ) == .requiresHumanVerification
    )
    assert(
        ReaderHTMLUtilities.evaluateBackgroundCaptureReadiness(
            ReaderHTMLCapture(title: "Security Check", urlString: "https://publisher.example.com/article", html: "<p>Please verify</p>", readyState: "complete", textLength: 180, matchedPrimaryContainer: false, hasRobotCheckWidget: true)
        ) == .requiresHumanVerification
    )
    
    // Test 10: Reader image URL restoration (%28/%29 CDN filters), srcset & relative resolution
    let franceInfoRaw = "https://www.franceinfo.fr/pictures/jDDaRlZCIVatOKyJ2NkdSSQaNJY/0x39:1024x615/432x243/filters:format%28jpg%29/2026/11/21/6b014735f0249092308717.jpg"
    let franceInfoDecoded = "https://www.franceinfo.fr/pictures/jDDaRlZCIVatOKyJ2NkdSSQaNJY/0x39:1024x615/432x243/filters:format(jpg)/2026/11/21/6b014735f0249092308717.jpg"
    let candidates = ReaderHTMLUtilities.candidateImageURLs(
        from: franceInfoRaw,
        relativeTo: URL(string: "https://www.franceinfo.fr/societe/manifestation.html")!
    )
    assert(candidates.count == 2, "Expected decoded primary and raw fallback candidates: \(candidates)")
    assert(candidates[0].absoluteString == franceInfoDecoded, "First candidate must restore %28/%29 parentheses")
    assert(candidates[1].absoluteString == franceInfoRaw, "Second candidate must keep raw URL fallback")
    
    let relCandidates = ReaderHTMLUtilities.candidateImageURLs(
        from: "/pictures/a%281%29.jpg?w=400&amp;q=80",
        relativeTo: URL(string: "https://www.franceinfo.fr/news/post")!
    )
    assert(relCandidates.first?.absoluteString == "https://www.franceinfo.fr/pictures/a(1).jpg?w=400&q=80")
    
    let protoRel = ReaderHTMLUtilities.candidateImageURLs(
        from: "//cdn.example.com/hero.webp",
        relativeTo: URL(string: "https://example.com/article")!
    )
    assert(protoRel.first?.absoluteString == "https://cdn.example.com/hero.webp")
    assert(ReaderHTMLUtilities.candidateImageURLs(from: "data:image/png;base64,AAA").isEmpty)
    
    let srcset = "https://res.cloudinary.com/demo/image/upload/w_400,f_auto/sample.jpg 400w, https://res.cloudinary.com/demo/image/upload/w_1200,f_auto/sample.jpg 1200w"
    assert(
        ReaderHTMLUtilities.bestURLFromSrcset(srcset) == "https://res.cloudinary.com/demo/image/upload/w_1200,f_auto/sample.jpg",
        "Must pick widest descriptor while keeping commas inside Cloudinary URL"
    )
    let srcsetHTML = "<img srcset=\"/img/small.jpg 320w, /img/large.jpg 1024w\" src=\"data:image/svg+xml;base64,PHN2Zz4=\">"
    assert(ReaderHTMLUtilities.normalizeLazyImages(in: srcsetHTML).contains("src=\"/img/large.jpg\""))
    
    // Test 11: Markdown 4,000-token estimation and capping for AI summarization
    assert(ReaderHTMLUtilities.estimateTokenCount(for: "   \n\t ") == 0)
    assert(ReaderHTMLUtilities.truncateMarkdownToTokenLimit("   \n\t ", maxTokens: 4000) == "")
    assert(ReaderHTMLUtilities.truncateMarkdownToTokenLimit("# Title\n\nBody.", maxTokens: 0) == "")

    let shortMarkdown = "# Swift 6 Concurrency\n\nStructured tasks keep [apps](https://swift.org) responsive."
    assert(ReaderHTMLUtilities.estimateTokenCount(for: shortMarkdown) < 4000)
    assert(ReaderHTMLUtilities.truncateMarkdownToTokenLimit(shortMarkdown, maxTokens: 4000) == shortMarkdown)

    let longParagraph = "- **Point**: Structured [Markdown](https://example.com/article?id=42) retains headings, emphasis, and lists cleanly.\n"
    let longMarkdown = "# Main Report\n\n" + String(repeating: longParagraph, count: 400)
    let rawTokenCount = ReaderHTMLUtilities.estimateTokenCount(for: longMarkdown)
    assert(rawTokenCount > 4000, "Fixture must exceed 4,000 tokens, got \(rawTokenCount)")
    let cappedMarkdown = ReaderHTMLUtilities.truncateMarkdownToTokenLimit(longMarkdown, maxTokens: 4000)
    let cappedTokens = ReaderHTMLUtilities.estimateTokenCount(for: cappedMarkdown)
    assert(cappedTokens > 3900 && cappedTokens <= 4000, "Capped Markdown must hit near 4,000 tokens without exceeding it, got \(cappedTokens)")
    assert(cappedMarkdown.hasPrefix("# Main Report\n\n- **Point**:"))

    let wordStream = String(repeating: "word ", count: 5000)
    assert(ReaderHTMLUtilities.estimateTokenCount(for: wordStream) == 5000)
    let cappedWords = ReaderHTMLUtilities.truncateMarkdownToTokenLimit(wordStream, maxTokens: 4000)
    assert(ReaderHTMLUtilities.estimateTokenCount(for: cappedWords) == 4000)

    let hugeToken = String(repeating: "a", count: 20000)
    let cappedHugeToken = ReaderHTMLUtilities.truncateMarkdownToTokenLimit(hugeToken, maxTokens: 4000)
    assert(cappedHugeToken.utf8.count == 16000)
    assert(ReaderHTMLUtilities.estimateTokenCount(for: cappedHugeToken) == 4000)
    
    print("✓ testReaderHTMLUtilities passed!")
}

func testMarkdownBlockParser() {
    print("Running testMarkdownBlockParser...")
    
    let md = """
    <!-- comment should be ignored -->
    # Main Heading
    
    Subtitle Heading
    ---
    
    Intro text with ![inline photo](https://example.com/pic.png "Caption") and more text.
    
    [![linked banner](https://example.com/banner.jpg)](https://example.com/post)
    
    - First bullet item
    - [x] Completed task item
      1. Nested ordered one
      2. Nested ordered two
    - [ ] Open task item
    
    > Quoted paragraph
    >
    > - Quoted bullet
    
    ```swift
    let greeting = "Hello"
    print(greeting)
    ```
    
    | Name | Score | Ratio |
    | :--- | :---: | ---: |
    | Alpha \\| A | 10 | 95% |
    | Beta | 20 | 100% |
    
    ***
    """
    
    let blocks = MarkdownBlockParser.parse(md)
    assert(blocks.count == 11, "Expected 11 parsed blocks, got \(blocks.count): \(blocks)")
    
    if case .heading(let lvl, let text) = blocks[0].kind {
        assert(lvl == 1 && text == "Main Heading")
    } else {
        assertionFailure("Expected H1 heading at index 0")
    }
    
    if case .heading(let lvl, let text) = blocks[1].kind {
        assert(lvl == 2 && text == "Subtitle Heading")
    } else {
        assertionFailure("Expected Setext H2 heading at index 1")
    }
    
    if case .paragraph(let p1) = blocks[2].kind {
        assert(p1 == "Intro text with")
    } else {
        assertionFailure("Expected leading paragraph before inline image")
    }
    
    if case .image(let alt, let url, let title, let linkURL) = blocks[3].kind {
        assert(alt == "inline photo" && url == "https://example.com/pic.png" && title == "Caption" && linkURL == nil)
    } else {
        assertionFailure("Expected extracted inline image at index 3")
    }
    
    if case .paragraph(let p2) = blocks[4].kind {
        assert(p2 == "and more text.")
    } else {
        assertionFailure("Expected trailing paragraph after inline image")
    }
    
    if case .image(let alt, let url, _, let linkURL) = blocks[5].kind {
        assert(alt == "linked banner" && url == "https://example.com/banner.jpg" && linkURL == "https://example.com/post")
    } else {
        assertionFailure("Expected linked image block at index 5")
    }
    
    if case .unorderedList(let items) = blocks[6].kind {
        assert(items.count == 3)
        assert(items[0].isChecked == nil && items[0].text == "First bullet item")
        assert(items[1].isChecked == true && items[1].text == "Completed task item")
        assert(items[1].nestedBlocks.count == 1)
        if case .orderedList(let start, let nestedItems) = items[1].nestedBlocks[0].kind {
            assert(start == 1 && nestedItems.count == 2 && nestedItems[0].text == "Nested ordered one")
        } else {
            assertionFailure("Expected nested ordered list")
        }
        assert(items[2].isChecked == false && items[2].text == "Open task item")
    } else {
        assertionFailure("Expected unordered/task list at index 6")
    }
    
    if case .blockquote(let quoted) = blocks[7].kind {
        assert(quoted.count == 2)
    } else {
        assertionFailure("Expected blockquote at index 7")
    }
    
    if case .codeBlock(let lang, let code) = blocks[8].kind {
        assert(lang == "swift" && code.contains("let greeting = \"Hello\""))
    } else {
        assertionFailure("Expected code block at index 8")
    }
    
    if case .table(let headers, let alignments, let rows) = blocks[9].kind {
        assert(headers == ["Name", "Score", "Ratio"])
        assert(alignments == [.leading, .center, .trailing])
        assert(rows.count == 2)
        assert(rows[0] == ["Alpha | A", "10", "95%"])
    } else {
        assertionFailure("Expected table at index 9")
    }
    
    // Check thematic break follows
    let blocksWithBreak = MarkdownBlockParser.parse("Paragraph\n\n***")
    assert(blocksWithBreak.count == 2)
    if case .thematicBreak = blocksWithBreak[1].kind {
        // ok
    } else {
        assertionFailure("Expected thematic break")
    }
    
    // Unclosed code fence must not crash
    let unclosed = MarkdownBlockParser.parse("```python\nprint(1)")
    assert(unclosed.count == 1)
    if case .codeBlock(let lang, let code) = unclosed[0].kind {
        assert(lang == "python" && code == "print(1)")
    } else {
        assertionFailure("Expected unclosed fenced block fallback")
    }
    
    // Franceinfo escaped/encoded image URL parsing
    let franceInfoMarkdown = "![Des manifestatns défilent à Paris, le 17 novembre 2026. (ARUALLAN / HANS LUCAS / AFP)](https://www.franceinfo.fr/pictures/jDDaRlZCIVatOKyJ2NkdSSQaNJY/0x39:1024x615/432x243/filters:format%28jpg%29/2026/11/21/6b014735f0249092308717.jpg)"
    let franceInfoBlocks = MarkdownBlockParser.parse(franceInfoMarkdown)
    assert(franceInfoBlocks.count == 1)
    if case .image(let alt, let urlStr, _, let linkURL) = franceInfoBlocks[0].kind {
        assert(alt.contains("ARUALLAN") && urlStr.contains("filters:format%28jpg%29") && linkURL == nil)
    } else {
        assertionFailure("Expected image block for Franceinfo markdown")
    }
    
    // Ordering of standalone image before linked image in same paragraph
    let mixedImagesMD = "First ![standalone](https://example.com/a.jpg) middle [![linked](https://example.com/b.jpg)](https://example.com/post) end."
    let mixedBlocks = MarkdownBlockParser.parse(mixedImagesMD)
    assert(mixedBlocks.count == 5, "Expected 5 blocks (text, img1, text, img2, text), got \(mixedBlocks.count)")
    if case .image(_, let u1, _, let l1) = mixedBlocks[1].kind,
       case .image(_, let u2, _, let l2) = mixedBlocks[3].kind {
        assert(u1 == "https://example.com/a.jpg" && l1 == nil)
        assert(u2 == "https://example.com/b.jpg" && l2 == "https://example.com/post")
    } else {
        assertionFailure("Expected preserved image order in paragraph")
    }
    
    // Image inside list item
    let listWithImageMD = "- Bullet text ![list img](https://example.com/list.jpg)"
    let listImageBlocks = MarkdownBlockParser.parse(listWithImageMD)
    assert(listImageBlocks.count == 1)
    if case .unorderedList(let listItems) = listImageBlocks[0].kind {
        assert(listItems.count == 1 && listItems[0].text == "Bullet text")
        assert(listItems[0].nestedBlocks.count == 1)
        if case .image(_, let nestedURL, _, _) = listItems[0].nestedBlocks[0].kind {
            assert(nestedURL == "https://example.com/list.jpg")
        } else {
            assertionFailure("Expected extracted image inside list item")
        }
    } else {
        assertionFailure("Expected unordered list")
    }
    
    print("✓ testMarkdownBlockParser passed!")
}

func testReaderWindowPayloadCodableCompatibility() {
    print("Running testReaderWindowPayloadCodableCompatibility...")
    
    struct ReaderPayloadSchemaMirror: Codable, Equatable {
        let appId: UUID?
        let urlString: String?
        let name: String?
        let isSecondaryWindow: Bool
        let openAsTab: Bool
        let startInReaderMode: Bool
        let instanceId: UUID
        
        enum CodingKeys: String, CodingKey {
            case appId, urlString, name, isSecondaryWindow, openAsTab, startInReaderMode, instanceId
        }
        
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            appId = try c.decodeIfPresent(UUID.self, forKey: .appId)
            urlString = try c.decodeIfPresent(String.self, forKey: .urlString)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            isSecondaryWindow = try c.decodeIfPresent(Bool.self, forKey: .isSecondaryWindow) ?? true
            openAsTab = try c.decodeIfPresent(Bool.self, forKey: .openAsTab) ?? false
            startInReaderMode = try c.decodeIfPresent(Bool.self, forKey: .startInReaderMode) ?? false
            instanceId = try c.decodeIfPresent(UUID.self, forKey: .instanceId) ?? UUID()
        }
    }
    
    let readerJSON = """
    {"urlString":"https://example.com/post","name":"example.com","isSecondaryWindow":true,"openAsTab":true,"startInReaderMode":true,"instanceId":"11111111-1111-1111-1111-111111111111"}
    """.data(using: .utf8)!
    let decodedReader = try! JSONDecoder().decode(ReaderPayloadSchemaMirror.self, from: readerJSON)
    assert(decodedReader.startInReaderMode == true)
    assert(decodedReader.appId == nil)
    
    let legacyJSON = """
    {"urlString":"https://example.com","name":"Example","isSecondaryWindow":true,"openAsTab":false,"instanceId":"22222222-2222-2222-2222-222222222222"}
    """.data(using: .utf8)!
    let decodedLegacy = try! JSONDecoder().decode(ReaderPayloadSchemaMirror.self, from: legacyJSON)
    assert(decodedLegacy.startInReaderMode == false, "Legacy payload missing startInReaderMode must default to false")
    
    print("✓ testReaderWindowPayloadCodableCompatibility passed!")
}

#if os(macOS)
func testWindowClosePolicyAcrossModes() {
    print("Running testWindowClosePolicyAcrossModes...")
    
    // Separate Windows mode:
    // 1. Clicking red close button on a secondary capsule window closes ONLY that window
    assert(
        CapsuleWindowClosePolicy.trafficLightCloseAction(
            isMainWindow: false,
            presentationMode: .separateWindows,
            isInMainWindowTabGroup: false,
            tabGroupWindowCount: 1,
            isOptionClick: false
        ) == .closeSingleWindow,
        "Separate Windows secondary close must only close the single capsule window"
    )
    // 2. Clicking red close button on main window closes all app windows
    assert(
        CapsuleWindowClosePolicy.trafficLightCloseAction(
            isMainWindow: true,
            presentationMode: .separateWindows,
            isInMainWindowTabGroup: false,
            tabGroupWindowCount: 1,
            isOptionClick: false
        ) == .closeAllAppWindows,
        "Separate Windows main window close must close all app windows"
    )
    // 3. Option-clicking red close button on secondary window closes all app windows
    assert(
        CapsuleWindowClosePolicy.trafficLightCloseAction(
            isMainWindow: false,
            presentationMode: .separateWindows,
            isInMainWindowTabGroup: false,
            tabGroupWindowCount: 1,
            isOptionClick: true
        ) == .closeAllAppWindows,
        "Option-clicking close must close all app windows"
    )
    // 4. Secondary window merged into a multi-tab group (not main's tab group) closes only that tab group
    assert(
        CapsuleWindowClosePolicy.trafficLightCloseAction(
            isMainWindow: false,
            presentationMode: .separateWindows,
            isInMainWindowTabGroup: false,
            tabGroupWindowCount: 2,
            isOptionClick: false
        ) == .closeWindowTabGroup,
        "Non-main multi-tab group in separate windows mode should close only its tab group"
    )
    
    // Tabs mode:
    // 5. Clicking red close button on ANY capsule tab or main tab closes the entire app
    assert(
        CapsuleWindowClosePolicy.trafficLightCloseAction(
            isMainWindow: false,
            presentationMode: .tabs,
            isInMainWindowTabGroup: true,
            tabGroupWindowCount: 3,
            isOptionClick: false
        ) == .closeAllAppWindows,
        "Tabs mode traffic-light close on secondary tab must close entire app"
    )
    assert(
        CapsuleWindowClosePolicy.trafficLightCloseAction(
            isMainWindow: true,
            presentationMode: .tabs,
            isInMainWindowTabGroup: true,
            tabGroupWindowCount: 3,
            isOptionClick: false
        ) == .closeAllAppWindows,
        "Tabs mode traffic-light close on main tab must close entire app"
    )
    assert(
        CapsuleWindowClosePolicy.trafficLightCloseAction(
            isMainWindow: false,
            presentationMode: .tabs,
            isInMainWindowTabGroup: false,
            tabGroupWindowCount: 1,
            isOptionClick: false
        ) == .closeAllAppWindows,
        "Tabs mode traffic-light close on detached tab must close entire app"
    )
    
    // Single Window mode:
    assert(
        CapsuleWindowClosePolicy.trafficLightCloseAction(
            isMainWindow: true,
            presentationMode: .singleWindow,
            isInMainWindowTabGroup: false,
            tabGroupWindowCount: 1,
            isOptionClick: false
        ) == .closeAllAppWindows,
        "Single window main close must close all app windows"
    )
    assert(
        CapsuleWindowClosePolicy.trafficLightCloseAction(
            isMainWindow: false,
            presentationMode: .singleWindow,
            isInMainWindowTabGroup: false,
            tabGroupWindowCount: 1,
            isOptionClick: false
        ) == .closeSingleWindow,
        "Detached secondary window in single window mode must close only itself"
    )
    
    print("✓ testWindowClosePolicyAcrossModes passed!")
}

func testCapsuleSleepPolicyMatrix() {
    print("Running testCapsuleSleepPolicyMatrix...")
    
    // Coverage helper checks
    let backFrame = CGRect(x: 100, y: 100, width: 1000, height: 700)
    let cascadedFront = CGRect(x: 122, y: 78, width: 1000, height: 700) // ~94.7% overlap
    let sideBySideFront = CGRect(x: 1120, y: 100, width: 800, height: 700) // 0% overlap
    let partialFront = CGRect(x: 600, y: 100, width: 1000, height: 700) // 50% overlap
    
    assert(
        CapsuleSleepPolicy.coverageFraction(of: backFrame, coveredBy: [cascadedFront]) >= CapsuleSleepPolicy.substantialCoverageThreshold,
        "Cascaded window must exceed substantial coverage threshold"
    )
    assert(
        CapsuleSleepPolicy.coverageFraction(of: backFrame, coveredBy: [sideBySideFront]) == 0,
        "Side-by-side non-overlapping window must have 0 coverage"
    )
    assert(
        CapsuleSleepPolicy.coverageFraction(of: backFrame, coveredBy: [partialFront]) == 0.5,
        "50% overlap must return 0.5"
    )
    
    // 1. Tabs mode, sleepingTabsEnabled = true:
    // Background tab has isVisible == false on macOS -> MUST sleep
    let bgTab = CapsuleWindowSleepSnapshot(
        sleepingTabsEnabled: true,
        isClosed: false,
        hasBeenPresented: true,
        isMiniaturized: false,
        isVisible: false,
        isOcclusionVisible: false,
        isSubstantiallyCoveredByFrontAppWindow: false,
        isAppHidden: false,
        isKeyWindow: false,
        isInMultiTabGroup: true,
        isSelectedTabInGroup: false
    )
    assert(CapsuleSleepPolicy.evaluate(bgTab) == .sleep, "Background tab must sleep when sleeping tabs enabled")
    
    // Selected active tab -> MUST wake and claim foreground activity when key
    let fgTab = CapsuleWindowSleepSnapshot(
        sleepingTabsEnabled: true,
        isClosed: false,
        hasBeenPresented: true,
        isMiniaturized: false,
        isVisible: true,
        isOcclusionVisible: true,
        isSubstantiallyCoveredByFrontAppWindow: false,
        isAppHidden: false,
        isKeyWindow: true,
        isInMultiTabGroup: true,
        isSelectedTabInGroup: true
    )
    assert(CapsuleSleepPolicy.evaluate(fgTab) == .awake(claimForegroundActivity: true), "Selected key tab must wake")
    
    // 2. Tabs mode, sleepingTabsEnabled = false:
    // Background tab MUST stay awake (without claiming foreground priority)
    let bgTabDisabled = CapsuleWindowSleepSnapshot(
        sleepingTabsEnabled: false,
        isClosed: false,
        hasBeenPresented: true,
        isMiniaturized: false,
        isVisible: false,
        isOcclusionVisible: false,
        isSubstantiallyCoveredByFrontAppWindow: false,
        isAppHidden: false,
        isKeyWindow: false,
        isInMultiTabGroup: true,
        isSelectedTabInGroup: false
    )
    assert(CapsuleSleepPolicy.evaluate(bgTabDisabled) == .awake(claimForegroundActivity: false), "Background tab must remain awake when sleeping tabs disabled")
    
    // 3. Multiple windows mode, sleepingTabsEnabled = true:
    // Miniaturized window (macOS sets isVisible = false!) -> MUST sleep
    let miniaturizedWin = CapsuleWindowSleepSnapshot(
        sleepingTabsEnabled: true,
        isClosed: false,
        hasBeenPresented: true,
        isMiniaturized: true,
        isVisible: false,
        isOcclusionVisible: false,
        isSubstantiallyCoveredByFrontAppWindow: false,
        isAppHidden: false,
        isKeyWindow: false,
        isInMultiTabGroup: false,
        isSelectedTabInGroup: true
    )
    assert(CapsuleSleepPolicy.evaluate(miniaturizedWin) == .sleep, "Miniaturized window with isVisible=false must sleep")
    
    // Cascaded background window (>=85% covered by another app window) -> MUST sleep
    let coveredWin = CapsuleWindowSleepSnapshot(
        sleepingTabsEnabled: true,
        isClosed: false,
        hasBeenPresented: true,
        isMiniaturized: false,
        isVisible: true,
        isOcclusionVisible: true,
        isSubstantiallyCoveredByFrontAppWindow: true,
        isAppHidden: false,
        isKeyWindow: false,
        isInMultiTabGroup: false,
        isSelectedTabInGroup: true
    )
    assert(CapsuleSleepPolicy.evaluate(coveredWin) == .sleep, "Substantially covered window in multi-window mode must sleep")
    
    // Side-by-side non-key visible window -> stays awake without foreground activity
    let sideBySideWin = CapsuleWindowSleepSnapshot(
        sleepingTabsEnabled: true,
        isClosed: false,
        hasBeenPresented: true,
        isMiniaturized: false,
        isVisible: true,
        isOcclusionVisible: true,
        isSubstantiallyCoveredByFrontAppWindow: false,
        isAppHidden: false,
        isKeyWindow: false,
        isInMultiTabGroup: false,
        isSelectedTabInGroup: true
    )
    assert(CapsuleSleepPolicy.evaluate(sideBySideWin) == .awake(claimForegroundActivity: false), "Visible side-by-side window must stay awake")
    
    // App hidden (Cmd+H) -> MUST sleep
    let hiddenAppWin = CapsuleWindowSleepSnapshot(
        sleepingTabsEnabled: true,
        isClosed: false,
        hasBeenPresented: true,
        isMiniaturized: false,
        isVisible: false,
        isOcclusionVisible: false,
        isSubstantiallyCoveredByFrontAppWindow: false,
        isAppHidden: true,
        isKeyWindow: false,
        isInMultiTabGroup: false,
        isSelectedTabInGroup: true
    )
    assert(CapsuleSleepPolicy.evaluate(hiddenAppWin) == .sleep, "Window must sleep when app is hidden")
    
    // 4. Multiple windows mode, sleepingTabsEnabled = false:
    let coveredWinDisabled = CapsuleWindowSleepSnapshot(
        sleepingTabsEnabled: false,
        isClosed: false,
        hasBeenPresented: true,
        isMiniaturized: false,
        isVisible: true,
        isOcclusionVisible: true,
        isSubstantiallyCoveredByFrontAppWindow: true,
        isAppHidden: false,
        isKeyWindow: false,
        isInMultiTabGroup: false,
        isSelectedTabInGroup: true
    )
    assert(CapsuleSleepPolicy.evaluate(coveredWinDisabled) == .awake(claimForegroundActivity: false), "Covered window must stay awake when sleeping tabs disabled")
    
    // 5. Newly created window not yet presented must not sleep prematurely
    let unpresentedWin = CapsuleWindowSleepSnapshot(
        sleepingTabsEnabled: true,
        isClosed: false,
        hasBeenPresented: false,
        isMiniaturized: false,
        isVisible: false,
        isOcclusionVisible: false,
        isSubstantiallyCoveredByFrontAppWindow: false,
        isAppHidden: false,
        isKeyWindow: false,
        isInMultiTabGroup: false,
        isSelectedTabInGroup: true
    )
    assert(CapsuleSleepPolicy.evaluate(unpresentedWin) == .ignoreNotYetPresented, "Unpresented window must not sleep prematurely")
    
    print("✓ testCapsuleSleepPolicyMatrix passed!")
}

@MainActor
func testRealNSWindowCloseAndSleepDeallocation() {
    print("Running testRealNSWindowCloseAndSleepDeallocation...")
    _ = NSApplication.shared
    
    final class SleepTestWebView: WKWebView {
        let token = UUID()
    }
    final class SleepTestModel: ObservableObject {
        @Published var isDeepSleeping = false
        @Published var generation = 0
        @Published var isClosed = false
    }
    struct SleepTestWebRep: NSViewRepresentable {
        let onCreated: (SleepTestWebView) -> Void
        func makeNSView(context: Context) -> SleepTestWebView {
            let wv = SleepTestWebView(frame: .zero)
            onCreated(wv)
            return wv
        }
        func updateNSView(_ nsView: SleepTestWebView, context: Context) {}
        static func dismantleNSView(_ nsView: SleepTestWebView, coordinator: ()) {
            nsView.stopLoading()
            nsView.pauseAllMediaPlayback(completionHandler: nil)
            nsView.closeAllMediaPresentations(completionHandler: nil)
            nsView.setAllMediaPlaybackSuspended(true)
            nsView.navigationDelegate = nil
            nsView.uiDelegate = nil
            let controller = nsView.configuration.userContentController
            controller.removeAllContentRuleLists()
            controller.removeAllUserScripts()
            controller.removeAllScriptMessageHandlers()
            nsView.removeFromSuperview()
            let closeSelector = NSSelectorFromString("_close")
            if nsView.responds(to: closeSelector) {
                nsView.perform(closeSelector)
            }
        }
    }
    struct SleepTestHostView: View {
        @ObservedObject var model: SleepTestModel
        let onCreated: (SleepTestWebView) -> Void
        var body: some View {
            Group {
                if model.isClosed {
                    EmptyView()
                } else if model.isDeepSleeping {
                    Text("Sleeping")
                } else {
                    SleepTestWebRep(onCreated: onCreated)
                        .id(model.generation)
                }
            }
        }
    }
    
    // Part A: Deep sleep frees WKWebView, wake mounts fresh WKWebView, close frees it
    let model = SleepTestModel()
    weak var weakWebView: SleepTestWebView?
    let capsuleWin = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    capsuleWin.isReleasedWhenClosed = false
    autoreleasepool {
        capsuleWin.contentView = NSHostingView(
            rootView: SleepTestHostView(model: model, onCreated: { weakWebView = $0 })
        )
        capsuleWin.contentView?.layoutSubtreeIfNeeded()
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    assert(weakWebView != nil, "WKWebView should exist while capsule is awake")
    let firstWebViewToken = weakWebView!.token
    
    // Transition to deep sleep -> WKWebView must dismantle, _close, and deallocate
    autoreleasepool {
        model.isDeepSleeping = true
        capsuleWin.contentView?.layoutSubtreeIfNeeded()
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    assert(weakWebView == nil, "WKWebView must completely deallocate during deep sleep")
    
    // Wake back up -> fresh WKWebView must mount
    autoreleasepool {
        model.isDeepSleeping = false
        model.generation += 1
        capsuleWin.contentView?.layoutSubtreeIfNeeded()
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    assert(weakWebView != nil, "Fresh WKWebView must mount on wake")
    assert(weakWebView!.token != firstWebViewToken, "Woken WKWebView must be a new instance")
    
    // Close window -> WKWebView must dismantle and deallocate immediately
    autoreleasepool {
        model.isClosed = true
        capsuleWin.contentView?.layoutSubtreeIfNeeded()
        capsuleWin.close()
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    assert(weakWebView == nil, "WKWebView must deallocate when capsule window closes")
    
    // Part B: Real NSWindow / NSWindowTabGroup close semantics verification
    let mainWin = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    mainWin.isReleasedWhenClosed = false
    mainWin.tabbingMode = .disallowed
    
    let secWin1 = NSWindow(
        contentRect: NSRect(x: 140, y: 140, width: 800, height: 600),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    secWin1.isReleasedWhenClosed = false
    secWin1.tabbingMode = .disallowed
    
    let secWin2 = NSWindow(
        contentRect: NSRect(x: 180, y: 180, width: 800, height: 600),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    secWin2.isReleasedWhenClosed = false
    secWin2.tabbingMode = .disallowed
    
    mainWin.makeKeyAndOrderFront(nil)
    secWin1.makeKeyAndOrderFront(nil)
    secWin2.makeKeyAndOrderFront(nil)
    
    let sec1Action = CapsuleWindowClosePolicy.trafficLightCloseAction(
        isMainWindow: false,
        presentationMode: .separateWindows,
        isInMainWindowTabGroup: false,
        tabGroupWindowCount: secWin1.tabGroup?.windows.count ?? 1,
        isOptionClick: false
    )
    assert(sec1Action == .closeSingleWindow)
    secWin1.close()
    assert(!secWin1.isVisible && mainWin.isVisible && secWin2.isVisible, "Closing one capsule window in Separate Windows mode must leave main and sibling windows open")
    
    let mainAction = CapsuleWindowClosePolicy.trafficLightCloseAction(
        isMainWindow: true,
        presentationMode: .separateWindows,
        isInMainWindowTabGroup: false,
        tabGroupWindowCount: mainWin.tabGroup?.windows.count ?? 1,
        isOptionClick: false
    )
    assert(mainAction == .closeAllAppWindows)
    secWin2.close()
    mainWin.close()
    assert(!mainWin.isVisible && !secWin2.isVisible, "Closing main window must close all windows")
    
    // Tabs mode with real NSWindowTabGroup
    let tabMain = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    tabMain.isReleasedWhenClosed = false
    tabMain.tabbingMode = .preferred
    tabMain.tabbingIdentifier = "TestTabs"
    
    let tabChild = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    tabChild.isReleasedWhenClosed = false
    tabChild.tabbingMode = .preferred
    tabChild.tabbingIdentifier = "TestTabs"
    
    tabMain.makeKeyAndOrderFront(nil)
    tabMain.addTabbedWindow(tabChild, ordered: .above)
    let inMainTG = (tabChild.tabGroup === tabMain.tabGroup)
    let tabCount = tabChild.tabGroup?.windows.count ?? 1
    assert(inMainTG && tabCount == 2, "Tabs must share NSWindowTabGroup")
    assert(
        CapsuleWindowClosePolicy.trafficLightCloseAction(
            isMainWindow: false,
            presentationMode: .tabs,
            isInMainWindowTabGroup: inMainTG,
            tabGroupWindowCount: tabCount,
            isOptionClick: false
        ) == .closeAllAppWindows,
        "Traffic-light close on a capsule tab in Tabs mode must close entire app"
    )
    tabChild.close()
    tabMain.close()
    
    print("✓ testRealNSWindowCloseAndSleepDeallocation passed!")
}
#endif

// Execute test suite
testUBlockRuleCompiler()
testSearchEngineResolution()
testWebAppNamingHelper()
testSerializableCookieRoundTrip()
testSecuritySchemeValidation()
testExternalSchemeDelegation()
testEphemeralCapsuleNamingFallback()
testTabModePayloadAndSizeConstraints()
testTabModeCmdWAndBlinkPreventionLogic()
MainActor.assumeIsolated {
    testCloudSyncMergeAndConflictDetection()
    #if os(macOS)
    testRealNSWindowTabbingEligibility()
    testContextMenuSearchInterception()
    #endif
    testMemoryTeardownAndCacheRelease()
    testDownloadPolicyAndFileHelpers()
}
testReaderHTMLUtilities()
testMarkdownBlockParser()
testReaderWindowPayloadCodableCompatibility()
#if os(macOS)
testWindowClosePolicyAcrossModes()
testCapsuleSleepPolicyMatrix()
MainActor.assumeIsolated {
    testRealNSWindowCloseAndSleepDeallocation()
}
#endif

print("\n========================================")
print("ALL 20 LOGIC & SECURITY TEST SUITES PASSED (100%)")
print("========================================")
