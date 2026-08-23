//
//  UBlockRuleCompiler.swift
//  isowebapps
//
//  Created on 23/08/2026.
//
//  Description:
//  Converts uBlock Origin Lite declarativeNetRequest (DNR) rules into WebKit native
//  `WKContentRuleList` JSON formatting. Handles character-by-character regex sanitization,
//  splitting multi-domain triggers, and stripping unsupported WebKit regex tokens.
//

import Foundation
import WebKit

/// Compiles uBlock Origin Lite MV3 declarativeNetRequest rules and cosmetic filters
/// into Safari/WebKit WKContentRuleList compatible JSON rules.
public final class UBlockRuleCompiler {
    public static let shared = UBlockRuleCompiler()
    
    private init() {}
    
    /// Compiles DNR JSON rules into WebKit Content Blocker JSON
    public func convertDNRToWebKitRuleList(dnrRules: [[String: Any]]) -> [[String: Any]] {
        var webkitRules: [[String: Any]] = []
        
        for rule in dnrRules {
            guard let action = rule["action"] as? [String: Any],
                  let actionType = action["type"] as? String,
                  let condition = rule["condition"] as? [String: Any] else {
                continue
            }
            
            // Map action
            var wkAction: [String: Any] = [:]
            switch actionType {
            case "block":
                wkAction["type"] = "block"
            case "allow":
                wkAction["type"] = "ignore-previous-rules"
            default:
                continue
            }
            
            // Map condition (trigger)
            var wkTrigger: [String: Any] = [:]
            
            if let initiatorDomains = condition["initiatorDomains"] as? [String], !initiatorDomains.isEmpty {
                let validDomains = sanitizeDomains(initiatorDomains)
                if !validDomains.isEmpty {
                    wkTrigger["if-domain"] = validDomains
                }
            }
            
            if let excludedInitiatorDomains = condition["excludedInitiatorDomains"] as? [String], !excludedInitiatorDomains.isEmpty {
                let validExcluded = sanitizeDomains(excludedInitiatorDomains)
                if !validExcluded.isEmpty {
                    wkTrigger["unless-domain"] = validExcluded
                }
            }
            
            if let domainType = condition["domainType"] as? String {
                if domainType == "thirdParty" {
                    wkTrigger["load-type"] = ["third-party"]
                } else if domainType == "firstParty" {
                    wkTrigger["load-type"] = ["first-party"]
                }
            }
            
            if let resourceTypes = condition["resourceTypes"] as? [String], !resourceTypes.isEmpty {
                var wkResourceTypes: [String] = []
                for res in resourceTypes {
                    switch res {
                    case "script": wkResourceTypes.append("script")
                    case "image": wkResourceTypes.append("image")
                    case "stylesheet": wkResourceTypes.append("style-sheet")
                    case "xmlhttprequest": wkResourceTypes.append("raw")
                    case "sub_frame": wkResourceTypes.append("document")
                    case "media": wkResourceTypes.append("media")
                    case "websocket": wkResourceTypes.append("websocket")
                    case "font": wkResourceTypes.append("font")
                    case "ping": wkResourceTypes.append("raw")
                    default: break
                    }
                }
                if !wkResourceTypes.isEmpty {
                    wkTrigger["resource-type"] = wkResourceTypes
                }
            }
            
            if let requestDomains = condition["requestDomains"] as? [String], !requestDomains.isEmpty {
                let validRequestDomains = sanitizeDomains(requestDomains)
                for domain in validRequestDomains {
                    var domainTrigger = wkTrigger
                    let cleanDomain = domain.hasPrefix("*") ? String(domain.dropFirst()) : domain
                    var escaped = ""
                    for char in cleanDomain {
                        if char == "." || char == "-" {
                            escaped += "\\\(char)"
                        } else if char == "*" {
                            escaped += ".*"
                        } else {
                            escaped.append(char)
                        }
                    }
                    domainTrigger["url-filter"] = "^https?://[^/]*" + escaped
                    webkitRules.append([
                        "trigger": domainTrigger,
                        "action": wkAction
                    ])
                }
            } else if let urlFilter = condition["urlFilter"] as? String {
                let convertedRegex = convertUrlFilterToWebKitRegex(urlFilter)
                if !convertedRegex.isEmpty {
                    wkTrigger["url-filter"] = convertedRegex
                    webkitRules.append([
                        "trigger": wkTrigger,
                        "action": wkAction
                    ])
                }
            } else {
                wkTrigger["url-filter"] = ".*"
                webkitRules.append([
                    "trigger": wkTrigger,
                    "action": wkAction
                ])
            }
        }
        
        return webkitRules
    }
    
    private func sanitizeDomains(_ domains: [String]) -> [String] {
        var result: [String] = []
        for d in domains {
            var domain = d.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if domain.isEmpty || domain == "[::1]" || domain == "[::]" || domain == "0.0.0.0" || domain == "127.0.0.1" || domain == "localhost" {
                continue
            }
            // In WebKit Content Blockers, if-domain and unless-domain must contain a dot (domain.tld)
            // Bare TLDs like "de" or "pl" are invalid in WebKit domain triggers.
            guard domain.contains(".") else { continue }
            
            // Domain must only contain valid hostname chars (a-z, 0-9, ., -, *)
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-*")
            if domain.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
                // Ensure format is *domain.com or domain.com
                if !domain.hasPrefix("*") && !domain.hasPrefix(".") {
                    domain = "*" + domain
                }
                result.append(domain)
            }
        }
        return result
    }
    
    /// Converts adblock / DNR urlFilter to a clean, valid WebKit Content Blocker regex
    public func convertUrlFilterToWebKitRegex(_ filter: String) -> String {
        var str = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.isEmpty || str == "*" { return ".*" }
        
        var isDomainAnchor = false
        var isStartAnchor = false
        var isEndAnchor = false
        
        if str.hasPrefix("||") {
            isDomainAnchor = true
            str.removeFirst(2)
        } else if str.hasPrefix("|") {
            isStartAnchor = true
            str.removeFirst(1)
        }
        
        if str.hasSuffix("|") {
            isEndAnchor = true
            str.removeLast(1)
        }
        
        // Convert characters safely to regex:
        // * -> .*
        // ^ -> [/?#:]
        // Escape regex special characters: . $ + ? ( ) [ ] { } \
        var regex = ""
        for char in str {
            switch char {
            case "*":
                regex += ".*"
            case "^":
                regex += "[/?#:]"
            case ".", "$", "+", "?", "(", ")", "[", "]", "{", "}", "\\":
                regex += "\\\(char)"
            case "|":
                // Inside filter, ignore or treat as literal
                break
            default:
                regex.append(char)
            }
        }
        
        if isDomainAnchor {
            regex = "^https?://[^/]*" + regex
        } else if isStartAnchor {
            regex = "^" + regex
        }
        
        if isEndAnchor {
            regex = regex + "$"
        }
        
        // Validate that the output compiles as a valid regular expression
        if (try? NSRegularExpression(pattern: regex)) == nil {
            return ".*"
        }
        
        return regex
    }
}

