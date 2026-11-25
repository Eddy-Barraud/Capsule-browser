//
//  IsolatedWKWebView.swift
//  isowebapps
//
//  Description:
//  macOS `WKWebView` subclass supporting context-menu search interception,
//  soft-sleep Page Visibility throttling, and active audio playback detection.
//

#if os(macOS)
import Foundation
import AppKit
import WebKit

class IsolatedWKWebView: WKWebView {
    var capsuleName: String = ""
    private(set) var isSleeping: Bool = false
    private(set) var isClosedOrDismantled: Bool = false
    var onSearchInNewEphemeralCapsule: ((URL) -> Void)?
    private var cachedContextMenuSelection: String?
    
    static func isSearchWebMenuItem(_ item: NSMenuItem) -> Bool {
        if item.identifier?.rawValue == "WKMenuItemIdentifierSearchWeb" {
            return true
        }
        if let action = item.action, NSStringFromSelector(action) == "_searchWithGoogleFromMenu:" {
            return true
        }
        return false
    }
    
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        cachedContextMenuSelection = nil
        let modeRaw = UserDefaults.standard.string(forKey: "windowPresentationMode") ?? "singleWindow"
        var didMatchSearchItem = false
        for item in menu.items {
            if modeRaw == "tabs" {
                if item.identifier?.rawValue == "WKMenuItemIdentifierOpenLinkInNewWindow" || item.title.contains("New Window") {
                    item.title = item.title.replacingOccurrences(of: "New Window", with: "New Tab")
                }
            }
            if Self.isSearchWebMenuItem(item) {
                item.title = SearchEngine.current().contextMenuSearchTitle()
                item.target = self
                item.action = #selector(searchSelectionInNewEphemeralCapsule(_:))
                item.isEnabled = true
                didMatchSearchItem = true
            }
        }
        if didMatchSearchItem {
            extractSelectedText { [weak self] text in
                guard let self, !self.isClosedOrDismantled else { return }
                if let text, !text.isEmpty {
                    self.cachedContextMenuSelection = text
                }
            }
        }
    }
    
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(searchSelectionInNewEphemeralCapsule(_:)) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }
    
    @objc private func searchSelectionInNewEphemeralCapsule(_ sender: Any?) {
        let cached = cachedContextMenuSelection
        cachedContextMenuSelection = nil
        extractSelectedText { [weak self] liveText in
            guard let self, !self.isClosedOrDismantled else { return }
            let liveTrimmed = liveText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cachedTrimmed = cached?.trimmingCharacters(in: .whitespacesAndNewlines)
            let query = (liveTrimmed?.isEmpty == false) ? liveTrimmed! : (cachedTrimmed ?? "")
            guard !query.isEmpty,
                  let searchURL = SearchEngine.searchURL(for: query) else {
                return
            }
            self.onSearchInNewEphemeralCapsule?(searchURL)
        }
    }
    
    private func extractSelectedText(completion: @escaping @MainActor (String?) -> Void) {
        evaluateJavaScript(Self.selectionExtractionScript, in: nil, in: .defaultClient) { [weak self] result in
            let rawText: String?
            if case .success(let value) = result {
                rawText = value as? String
            } else {
                rawText = nil
            }
            MainActor.assumeIsolated {
                let trimmed = rawText?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let trimmed, !trimmed.isEmpty {
                    completion(trimmed)
                } else {
                    completion(self?.extractSelectedTextViaServicesPasteboard())
                }
            }
        }
    }
    
    private func extractSelectedTextViaServicesPasteboard() -> String? {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let selector = #selector(NSServicesMenuRequestor.writeSelection(to:types:))
        let types: NSArray = [NSPasteboard.PasteboardType.string]
        typealias WriteSelectionFn = @convention(c) (AnyObject, Selector, NSPasteboard, NSArray) -> Bool
        
        let candidates: [AnyObject?] = [
            validRequestor(forSendType: .string, returnType: nil) as AnyObject?,
            self
        ]
        for case let candidate? in candidates {
            if candidate.responds(to: selector),
               let method = class_getMethodImplementation(type(of: candidate), selector) {
                let fn = unsafeBitCast(method, to: WriteSelectionFn.self)
                if fn(candidate, selector, pasteboard, types),
                   let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }
    
    // MARK: - Sleep & Wake State Transitions
    
    func applySoftSleep() {
        guard !isClosedOrDismantled, !isSleeping else { return }
        isSleeping = true
        #if DEBUG
        print("[IsolatedWKWebView] Tab soft sleeping: \(self.url?.host ?? "untitled")")
        #endif
        
        if !hasActiveAudioPlayback {
            setAllMediaPlaybackSuspended(true)
        }
        evaluateJavaScript(Self.visibilityHiddenScript, completionHandler: nil)
    }
    
    func applyWakeFromSoftSleep() {
        guard !isClosedOrDismantled, isSleeping else { return }
        isSleeping = false
        #if DEBUG
        print("[IsolatedWKWebView] Tab waking from soft sleep: \(self.url?.host ?? "untitled")")
        #endif
        
        setAllMediaPlaybackSuspended(false)
        evaluateJavaScript(Self.visibilityVisibleScript, completionHandler: nil)
    }
    
    func reapplySleepingStateIfNeeded() {
        guard !isClosedOrDismantled, isSleeping else { return }
        if !hasActiveAudioPlayback {
            setAllMediaPlaybackSuspended(true)
        }
        evaluateJavaScript(Self.visibilityHiddenScript, completionHandler: nil)
    }
    
    var hasActiveAudioPlayback: Bool {
        let isPlayingAudioSel = NSSelectorFromString("_isPlayingAudio")
        if responds(to: isPlayingAudioSel) {
            typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
            if let method = class_getMethodImplementation(type(of: self), isPlayingAudioSel) {
                let fn = unsafeBitCast(method, to: Getter.self)
                if fn(self, isPlayingAudioSel) {
                    return true
                }
            }
        }
        
        let nowPlayingSel = NSSelectorFromString("_hasActiveNowPlayingSession")
        if responds(to: nowPlayingSel) {
            typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
            if let method = class_getMethodImplementation(type(of: self), nowPlayingSel) {
                let fn = unsafeBitCast(method, to: Getter.self)
                if fn(self, nowPlayingSel) {
                    return true
                }
            }
        }
        return false
    }
    
    func cleanup() {
        isClosedOrDismantled = true
        onSearchInNewEphemeralCapsule = nil
        cachedContextMenuSelection = nil
    }
    
    deinit {
        #if DEBUG
        print("[Memory] IsolatedWKWebView deinit: '\(capsuleName)'")
        #endif
        cleanup()
    }
    
    // MARK: - Prebuilt JS Snippets
    
    private static let visibilityHiddenScript = """
    if (document.hidden !== true) {
        Object.defineProperty(document, 'hidden', { value: true, configurable: true });
        Object.defineProperty(document, 'visibilityState', { value: 'hidden', configurable: true });
        document.dispatchEvent(new Event('visibilitychange'));
    }
    """
    
    private static let visibilityVisibleScript = """
    if (document.hidden !== false) {
        Object.defineProperty(document, 'hidden', { value: false, configurable: true });
        Object.defineProperty(document, 'visibilityState', { value: 'visible', configurable: true });
        document.dispatchEvent(new Event('visibilitychange'));
    }
    """
    
    private static let selectionExtractionScript = """
    (function() {
        function selectionInDocument(doc, win) {
            if (!doc) return '';
            var active = doc.activeElement;
            while (active) {
                var tag = active.tagName;
                if (tag === 'INPUT' || tag === 'TEXTAREA') {
                    var start = active.selectionStart;
                    var end = active.selectionEnd;
                    if (typeof start === 'number' && typeof end === 'number' && end > start) {
                        var val = active.value.slice(start, end);
                        if (val && val.trim().length > 0) return val;
                    }
                }
                if (active.shadowRoot) {
                    if (typeof active.shadowRoot.getSelection === 'function') {
                        var srSel = active.shadowRoot.getSelection();
                        var srText = srSel ? srSel.toString() : '';
                        if (srText && srText.trim().length > 0) return srText;
                    }
                    if (active.shadowRoot.activeElement) {
                        active = active.shadowRoot.activeElement;
                        continue;
                    }
                }
                break;
            }
            var sel = (win && typeof win.getSelection === 'function') ? win.getSelection() : (typeof doc.getSelection === 'function' ? doc.getSelection() : null);
            var text = sel ? sel.toString() : '';
            if (text && text.trim().length > 0) return text;
            var frames = doc.querySelectorAll('iframe, frame');
            for (var i = 0; i < frames.length; i++) {
                try {
                    var childDoc = frames[i].contentDocument;
                    var childWin = frames[i].contentWindow;
                    if (childDoc) {
                        var childText = selectionInDocument(childDoc, childWin);
                        if (childText && childText.trim().length > 0) return childText;
                    }
                } catch (e) {}
            }
            return '';
        }
        return selectionInDocument(document, window);
    })();
    """
}
#endif
