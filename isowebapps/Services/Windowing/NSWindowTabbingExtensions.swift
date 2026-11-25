//
//  NSWindowTabbingExtensions.swift
//  isowebapps
//
//  Description:
//  macOS NSWindow swizzling hooks and helpers for native tabbing, close routing,
//  frame serialization, and weak window references.
//

#if os(macOS)
import AppKit

final class WeakWindowBox {
    weak var window: NSWindow?
}

extension NSWindow {
    static let swizzleNewWindowForTabOnce: Void = {
        let originalSelector = #selector(NSResponder.newWindowForTab(_:))
        let swizzledSelector = #selector(NSWindow.capsule_newWindowForTab(_:))
        
        guard let swizzledMethod = class_getInstanceMethod(NSWindow.self, swizzledSelector) else { return }
        
        if class_addMethod(
            NSWindow.self,
            originalSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        ) {
            #if DEBUG
            print("[WindowTabbing] Successfully added newWindowForTab: to NSWindow")
            #endif
        } else if let originalMethod = class_getInstanceMethod(NSWindow.self, originalSelector) {
            method_exchangeImplementations(originalMethod, swizzledMethod)
            #if DEBUG
            print("[WindowTabbing] Successfully swizzled newWindowForTab: on NSWindow")
            #endif
        }
    }()
    
    static let swizzlePresentationMethodsOnce: Void = {
        let pairs: [(Selector, Selector)] = [
            (#selector(NSWindow.makeKeyAndOrderFront(_:)), #selector(NSWindow.capsule_makeKeyAndOrderFront(_:))),
            (#selector(NSWindow.orderFront(_:)), #selector(NSWindow.capsule_orderFront(_:))),
            (#selector(NSWindow.order(_:relativeTo:)), #selector(NSWindow.capsule_order(_:relativeTo:))),
            (#selector(NSWindow.performClose(_:)), #selector(NSWindow.capsule_performClose(_:)))
        ]
        
        for (origSel, swizSel) in pairs {
            guard let origMethod = class_getInstanceMethod(NSWindow.self, origSel),
                  let swizMethod = class_getInstanceMethod(NSWindow.self, swizSel) else { continue }
            method_exchangeImplementations(origMethod, swizMethod)
        }
    }()
    
    @objc @MainActor func capsule_newWindowForTab(_ sender: Any?) {
        let source = MainWindowTracker.shared.isManagedCapsuleWindow(self) ? self : nil
        MainWindowTracker.shared.openNewTab(from: source)
    }
    
    @objc @MainActor func capsule_makeKeyAndOrderFront(_ sender: Any?) {
        _ = MainWindowTracker.shared.handleNewWindowPresentation(self)
        capsule_makeKeyAndOrderFront(sender)
    }
    
    @objc @MainActor func capsule_orderFront(_ sender: Any?) {
        _ = MainWindowTracker.shared.handleNewWindowPresentation(self)
        capsule_orderFront(sender)
    }
    
    @objc @MainActor func capsule_order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        if place != .out {
            _ = MainWindowTracker.shared.handleNewWindowPresentation(self)
        }
        capsule_order(place, relativeTo: otherWin)
    }
    
    @objc @MainActor func capsule_performClose(_ sender: Any?) {
        if MainWindowTracker.shared.isManagedCapsuleWindow(self) {
            if let button = sender as? NSButton, button === self.standardWindowButton(.closeButton) {
                MainWindowTracker.shared.handleTrafficLightClose(for: self)
            } else {
                MainWindowTracker.shared.closeTab(self)
            }
            return
        }
        capsule_performClose(sender)
    }
    
    var serializedFrame: [Double] {
        let f = self.frame
        return [Double(f.origin.x), Double(f.origin.y), Double(f.size.width), Double(f.size.height)]
    }
}
#endif
