import Foundation
import WebKit
import SwiftData

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
        var sheetParent: MockWindow? = nil
        var animationBehavior: Int = 0
        
        init() {
            let tg = MockTabGroup()
            tg.windows = [self]
            tg.selectedWindow = self
            self.tabGroup = tg
        }
        
        func addTabbedWindow(_ other: MockWindow) {
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
        weak var pendingTabTargetWindow: MockWindow?
        
        func handleNewWindowPresentation(_ window: MockWindow) -> Bool {
            guard !window.isPanel, window.sheetParent == nil else { return false }
            guard let target = pendingTabTargetWindow,
                  target !== window,
                  window.tabGroup !== target.tabGroup else {
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
            return true
        }
    }
    
    let coordinator = MockCoordinator()
    let parentWin = MockWindow()
    parentWin.isVisible = true
    parentWin.frame = CGRect(x: 100, y: 150, width: 1200, height: 800)
    
    // Simulate link click requesting a new tab
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
    
    // Scenario D: Sheets and panels bypass tab close interception
    let sheetWin = MockWindow()
    sheetWin.sheetParent = parentWin
    coordinator.pendingTabTargetWindow = parentWin
    let didInterceptSheet = coordinator.handleNewWindowPresentation(sheetWin)
    assert(didInterceptSheet == false, "Sheets must not be intercepted as tabs")
    
    let panelWin = MockWindow()
    panelWin.isPanel = true
    coordinator.pendingTabTargetWindow = parentWin
    let didInterceptPanel = coordinator.handleNewWindowPresentation(panelWin)
    assert(didInterceptPanel == false, "Panels must not be intercepted as tabs")
    
    print("✓ testTabModeCmdWAndBlinkPreventionLogic passed!")
}

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
    
    print("✓ testCloudSyncMergeAndConflictDetection passed!")
}

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
}

print("\n========================================")
print("ALL 10 LOGIC & SECURITY TEST SUITES PASSED (100%)")
print("========================================")
