//
//  CapsuleLifecyclePolicy.swift
//  isowebapps
//
//  Description:
//  Pure, testable macOS policy types governing window presentation modes,
//  traffic-light close semantics, and sleep/wake evaluation for capsules.
//

import Foundation
import CoreGraphics

#if os(macOS)
enum WindowPresentationMode: String, CaseIterable, Identifiable, Codable {
    case singleWindow = "singleWindow"
    case separateWindows = "separateWindows"
    case tabs = "tabs"
    
    var id: String { rawValue }
    
    var next: WindowPresentationMode {
        switch self {
        case .singleWindow:
            return .separateWindows
        case .separateWindows:
            return .tabs
        case .tabs:
            return .singleWindow
        }
    }
    
    var iconName: String {
        switch self {
        case .singleWindow:
            return "macwindow"
        case .separateWindows:
            return "macwindow.on.rectangle"
        case .tabs:
            return "macwindow.stack"
        }
    }
    
    var title: String {
        switch self {
        case .singleWindow:
            return "Single Window"
        case .separateWindows:
            return "Separate Windows"
        case .tabs:
            return "Tabs"
        }
    }
    
    var tooltip: String {
        switch self {
        case .singleWindow:
            return "Mode: Single Window (Click for Separate Windows)"
        case .separateWindows:
            return "Mode: Separate Windows (Click for Tabs)"
        case .tabs:
            return "Mode: Tabs (Click for Single Window)"
        }
    }
}

enum WindowClosePolicyAction: Equatable {
    case closeSingleWindow
    case closeWindowTabGroup
    case closeAllAppWindows
}

enum CapsuleWindowClosePolicy {
    /// Determines what happens when the user clicks the red traffic-light close button on a macOS window.
    static func trafficLightCloseAction(
        isMainWindow: Bool,
        presentationMode: WindowPresentationMode,
        isInMainWindowTabGroup: Bool,
        tabGroupWindowCount: Int,
        isOptionClick: Bool
    ) -> WindowClosePolicyAction {
        if isOptionClick {
            return .closeAllAppWindows
        }
        if isMainWindow {
            return .closeAllAppWindows
        }
        if presentationMode == .tabs {
            return .closeAllAppWindows
        }
        if isInMainWindowTabGroup {
            return .closeAllAppWindows
        }
        if tabGroupWindowCount > 1 {
            return .closeWindowTabGroup
        }
        return .closeSingleWindow
    }
}

enum CapsuleSleepState: Equatable {
    case awake
    case softSleeping
    case deepSleeping
    case closed
}

enum CapsuleSleepEvaluation: Equatable {
    case awake(claimForegroundActivity: Bool)
    case sleep
    case ignoreNotYetPresented
}

struct CapsuleWindowSleepSnapshot: Equatable {
    let sleepingTabsEnabled: Bool
    let isClosed: Bool
    let hasBeenPresented: Bool
    let isMiniaturized: Bool
    let isVisible: Bool
    let isOcclusionVisible: Bool
    let isSubstantiallyCoveredByFrontAppWindow: Bool
    let isAppHidden: Bool
    let isKeyWindow: Bool
    let isInMultiTabGroup: Bool
    let isSelectedTabInGroup: Bool
}

enum CapsuleSleepPolicy {
    static let substantialCoverageThreshold: CGFloat = 0.85
    /// Default inactivity delay (5 minutes) before a background capsule is put to sleep to free RAM.
    static let defaultSleepTimeoutSeconds: TimeInterval = 5 * 60
    
    /// Computes the maximum fraction of `windowFrame` covered by any single frame in `frontFrames`.
    static func coverageFraction(of windowFrame: CGRect, coveredBy frontFrames: [CGRect]) -> CGFloat {
        guard windowFrame.width > 0, windowFrame.height > 0 else { return 0 }
        let windowArea = windowFrame.width * windowFrame.height
        guard windowArea > 0 else { return 0 }
        
        var maxFraction: CGFloat = 0
        for front in frontFrames {
            let intersection = windowFrame.intersection(front)
            guard !intersection.isNull, !intersection.isEmpty else { continue }
            let area = intersection.width * intersection.height
            let fraction = area / windowArea
            if fraction > maxFraction {
                maxFraction = fraction
            }
        }
        return maxFraction
    }
    
    /// Pure state evaluation deciding whether a capsule window should wake, sleep, or ignore pre-presentation churn.
    static func evaluate(_ s: CapsuleWindowSleepSnapshot) -> CapsuleSleepEvaluation {
        if s.isClosed {
            return .ignoreNotYetPresented
        }
        if !s.sleepingTabsEnabled {
            return .awake(claimForegroundActivity: s.isKeyWindow && s.isVisible && !s.isMiniaturized && !s.isAppHidden)
        }
        if s.isAppHidden {
            return .sleep
        }
        if s.isMiniaturized {
            return .sleep
        }
        if s.isInMultiTabGroup {
            if !s.isSelectedTabInGroup {
                return .sleep
            }
            if !s.hasBeenPresented && !s.isVisible {
                return .ignoreNotYetPresented
            }
            if !s.isVisible || !s.isOcclusionVisible {
                return .sleep
            }
            return .awake(claimForegroundActivity: s.isKeyWindow)
        } else {
            if !s.hasBeenPresented && !s.isVisible {
                return .ignoreNotYetPresented
            }
            if !s.isVisible || !s.isOcclusionVisible || (!s.isKeyWindow && s.isSubstantiallyCoveredByFrontAppWindow) {
                return .sleep
            }
            return .awake(claimForegroundActivity: s.isKeyWindow)
        }
    }
}
#endif
