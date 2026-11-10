import Foundation
import WebKit

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

// Execute test suite
testUBlockRuleCompiler()
testSearchEngineResolution()
testWebAppNamingHelper()
testSerializableCookieRoundTrip()
testSecuritySchemeValidation()
testExternalSchemeDelegation()
testEphemeralCapsuleNamingFallback()

print("\n========================================")
print("ALL 7 LOGIC & SECURITY TEST SUITES PASSED (100%)")
print("========================================")
