//
//  YouTubeFreeSupport.swift
//  isowebapps
//
//  Description:
//  Copies Youtube-Free's native WebKit content blocking, 4-layer document-start
//  ad-stripping/player script, platform URL normalization, audio session setup,
//  and AVKit HLS overlay support for YouTube capsules.
//

import AVFoundation
import AVKit
import Foundation
import SwiftUI
import WebKit

enum ContentProtectionMode: Equatable, Sendable {
    case none
    case uBlock
    case youTubeAdFree
}

enum YouTubeFreeSupport {
    private static var hasActivatedIOSAudioSession = false

    nonisolated static func isYouTubeHost(_ rawHost: String?) -> Bool {
        guard let rawHost else { return false }
        var host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while host.hasSuffix(".") {
            host.removeLast()
        }
        guard !host.isEmpty else { return false }
        let roots = ["youtube.com", "youtu.be", "youtube-nocookie.com", "youtubekids.com"]
        return roots.contains { root in
            host == root || host.hasSuffix(".\(root)")
        }
    }

    nonisolated static func isYouTubeURL(_ url: URL?) -> Bool {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return isYouTubeHost(url.host)
    }

    nonisolated static func isYouTubeURLString(_ rawURLString: String) -> Bool {
        let trimmed = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           !scheme.isEmpty {
            return isYouTubeURL(url)
        }
        if !trimmed.contains("://"),
           let url = URL(string: "https://\(trimmed)") {
            return isYouTubeURL(url)
        }
        return false
    }

    nonisolated static func normalizedInitialYouTubeURL(_ url: URL) -> URL {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let rawHost = url.host?.lowercased() else {
            return url
        }
        let standardHosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com"]
        guard standardHosts.contains(rawHost) else {
            return url
        }
        let lowerPath = url.path.lowercased()
        let authPrefixes = [
            "/signin",
            "/servicelogin",
            "/checkcookie",
            "/rotatecookies",
            "/logout",
            "/o/oauth",
            "/account"
        ]
        if authPrefixes.contains(where: { lowerPath.hasPrefix($0) }) {
            return url
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.scheme = "https"
        #if os(macOS)
        components.host = "www.youtube.com"
        #else
        components.host = "m.youtube.com"
        #endif
        return components.url ?? url
    }

    nonisolated static func desiredProtectionMode(
        isCapsuleProtectionEnabled: Bool,
        targetURL: URL?,
        fallbackURLString: String = "",
        defaults: UserDefaults = .standard
    ) -> ContentProtectionMode {
        let masterEnabled = defaults.object(forKey: "ublock_master_enabled") as? Bool ?? true
        guard masterEnabled, isCapsuleProtectionEnabled else {
            return .none
        }
        if let targetURL,
           let scheme = targetURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return isYouTubeURL(targetURL) ? .youTubeAdFree : .uBlock
        }
        return isYouTubeURLString(fallbackURLString) ? .youTubeAdFree : .uBlock
    }

    static func activateIOSPlaybackAudioSessionIfNeeded() {
        #if os(iOS)
        guard !hasActivatedIOSAudioSession else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .moviePlayback,
                options: []
            )
            try AVAudioSession.sharedInstance().setActive(true)
            hasActivatedIOSAudioSession = true
        } catch {
            #if DEBUG
            print("[YouTubeFreeSupport] Failed to configure AVAudioSession: \(error)")
            #endif
        }
        #endif
    }

    static let playerUserScript: WKUserScript = {
        #if os(macOS)
        let useNativePlayerPlaceholder = false
        #else
        let useNativePlayerPlaceholder = true
        #endif
        return WKUserScript(
            source: makeYouTubeScript(withNativePlayerPlaceholder: useNativePlayerPlaceholder),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .page
        )
    }()

    /// Builds the YouTube user script (injected at `.atDocumentStart` in `.page` world so
    /// player responses are stripped of pre-roll/mid-roll ads before playback starts).
    /// On iOS (`withNativePlayerPlaceholder == true`), hides/prevents ads, attaches a
    /// Trusted-Types-safe tap-to-play placeholder overlay on `/watch` pages, and starts
    /// the video in native full-screen player when tapped.
    /// On macOS (`withNativePlayerPlaceholder == false`), prevents/skips ads while keeping
    /// only the YouTube player (no macOS `<video controls>`, `::-webkit-media-controls`,
    /// or native player overlay).
    nonisolated static func makeYouTubeScript(withNativePlayerPlaceholder: Bool) -> String {
        let placeholderCSS = withNativePlayerPlaceholder ? """
                '.yt-free-placeholder {',
                '    position: absolute !important;',
                '    top: 0 !important;',
                '    left: 0 !important;',
                '    width: 100% !important;',
                '    height: 100% !important;',
                '    z-index: 99999 !important;',
                '    background: rgba(12, 12, 12, 0.90) !important;',
                '    backdrop-filter: blur(10px) !important;',
                '    -webkit-backdrop-filter: blur(10px) !important;',
                '    display: flex !important;',
                '    flex-direction: column !important;',
                '    align-items: center !important;',
                '    justify-content: center !important;',
                '    cursor: pointer !important;',
                '    user-select: none !important;',
                '    -webkit-user-select: none !important;',
                '    -webkit-tap-highlight-color: transparent !important;',
                '    transition: opacity 0.2s ease;',
                '}',
                '.yt-free-placeholder:active {',
                '    background: rgba(25, 25, 25, 0.96) !important;',
                '}',
                '.yt-free-btn {',
                '    width: 64px !important;',
                '    height: 64px !important;',
                '    background: #ff0000 !important;',
                '    border-radius: 50% !important;',
                '    display: flex !important;',
                '    align-items: center !important;',
                '    justify-content: center !important;',
                '    box-shadow: 0 4px 20px rgba(255, 0, 0, 0.5), 0 2px 10px rgba(0, 0, 0, 0.5) !important;',
                '    margin-bottom: 12px !important;',
                '    transition: transform 0.15s ease !important;',
                '    pointer-events: none !important;',
                '}',
                '.yt-free-placeholder:active .yt-free-btn {',
                '    transform: scale(0.92) !important;',
                '}',
                '.yt-free-btn svg {',
                '    width: 26px !important;',
                '    height: 26px !important;',
                '    fill: #ffffff !important;',
                '    margin-left: 3px !important;',
                '    pointer-events: none !important;',
                '}',
                '.yt-free-label {',
                '    color: #ffffff !important;',
                '    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif !important;',
                '    font-size: 15px !important;',
                '    font-weight: 600 !important;',
                '    letter-spacing: -0.2px !important;',
                '    text-shadow: 0 1px 4px rgba(0,0,0,0.8) !important;',
                '    pointer-events: none !important;',
                '}',
                '.yt-free-badge {',
                '    color: rgba(255, 255, 255, 0.7) !important;',
                '    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif !important;',
                '    font-size: 11px !important;',
                '    margin-top: 4px !important;',
                '    text-shadow: 0 1px 3px rgba(0,0,0,0.8) !important;',
                '    pointer-events: none !important;',
                '}'
        """ : """
                '#movie_player video::-webkit-media-controls,',
                '#movie_player video::-webkit-media-controls-enclosure,',
                '.html5-video-player video::-webkit-media-controls,',
                '.html5-video-player video::-webkit-media-controls-enclosure {',
                '    display: none !important;',
                '}'
        """

        let placeholderJS = withNativePlayerPlaceholder ? """
            function isShorts() {
                var path = window.location.pathname || '';
                return path.startsWith('/shorts') || window.location.href.includes('/shorts/');
            }

            function isWatchPage() {
                if (isShorts()) return false;
                var path = window.location.pathname || '';
                return path.startsWith('/watch') || window.location.search.includes('v=');
            }

            function currentWatchVideoKey() {
                try {
                    var params = new URLSearchParams(window.location.search || '');
                    return params.get('v') || (window.location.pathname + window.location.search);
                } catch (e) {
                    return window.location.href;
                }
            }

            function hasActivePlaceholder() {
                var ph = document.querySelector('.yt-free-placeholder');
                return !!(ph && ph.style.display !== 'none');
            }

            function enforceYouTubeOnlyControls() {}

            function findPlayerContainer() {
                return document.getElementById('player-container-id') ||
                       document.getElementById('player') ||
                       document.getElementById('movie_player') ||
                       document.getElementById('ytd-player') ||
                       document.querySelector('.player-container') ||
                       document.querySelector('.html5-video-player') ||
                       (document.querySelector('video') && document.querySelector('video').parentElement);
            }

            function buildPlaceholderElement() {
                var placeholder = document.createElement('div');
                placeholder.className = 'yt-free-placeholder';

                var btn = document.createElement('div');
                btn.className = 'yt-free-btn';
                var svgNS = 'http://www.w3.org/2000/svg';
                var svg = document.createElementNS(svgNS, 'svg');
                svg.setAttribute('viewBox', '0 0 24 24');
                var path = document.createElementNS(svgNS, 'path');
                path.setAttribute('d', 'M8 5v14l11-7z');
                svg.appendChild(path);
                btn.appendChild(svg);

                var label = document.createElement('div');
                label.className = 'yt-free-label';
                label.textContent = 'Play in Native Player';

                var badge = document.createElement('div');
                badge.className = 'yt-free-badge';
                badge.textContent = 'Ad-Free Fullscreen';

                placeholder.appendChild(btn);
                placeholder.appendChild(label);
                placeholder.appendChild(badge);
                return placeholder;
            }

            function launchNativePlayer(placeholder) {
                if (placeholder) {
                    placeholder.style.display = 'none';
                }

                var container = findPlayerContainer();
                var video = (container && container.querySelector('video')) || document.querySelector('video');
                var player = document.getElementById('movie_player');

                if (video) {
                    video.__ytFreeSavedMuted = false;
                    video.__ytFreeSavedRate = 1.0;
                    video.removeAttribute('playsinline');
                    video.removeAttribute('webkit-playsinline');

                    var exited = false;
                    function isCurrentlyFullscreen() {
                        return !!(document.fullscreenElement || document.webkitFullscreenElement || video.webkitDisplayingFullscreen);
                    }

                    function onExitFS() {
                        if (exited || isCurrentlyFullscreen()) {
                            return;
                        }
                        exited = true;
                        video.removeEventListener('webkitendfullscreen', onExitFS);
                        video.removeEventListener('fullscreenchange', onExitFS);
                        document.removeEventListener('fullscreenchange', onExitFS);
                        document.removeEventListener('webkitfullscreenchange', onExitFS);
                        if (placeholder) {
                            placeholder.style.display = 'flex';
                        }
                        video.pause();
                    }
                    video.addEventListener('webkitendfullscreen', onExitFS);
                    video.addEventListener('fullscreenchange', onExitFS);
                    document.addEventListener('fullscreenchange', onExitFS);
                    document.addEventListener('webkitfullscreenchange', onExitFS);

                    function enterFS() {
                        if (exited) return;
                        try {
                            if (typeof video.webkitEnterFullscreen === 'function') {
                                video.webkitEnterFullscreen();
                            } else if (typeof video.requestFullscreen === 'function') {
                                video.requestFullscreen().catch(function(){});
                            } else if (typeof video.webkitRequestFullscreen === 'function') {
                                video.webkitRequestFullscreen();
                            }
                        } catch(e) {}
                    }

                    function startMainPlaybackAndFS() {
                        if (exited) return;
                        video.muted = false;
                        video.playbackRate = 1.0;
                        if (video.readyState < 1) {
                            video.addEventListener('loadedmetadata', function onMeta() {
                                if (!exited && !isCurrentlyFullscreen()) {
                                    enterFS();
                                }
                            }, { once: true });
                        }
                        var p = video.play();
                        if (p !== undefined) {
                            p.then(enterFS).catch(enterFS);
                        } else {
                            enterFS();
                        }
                    }

                    skipAds();
                    if (findAdPlayer()) {
                        var waitAttempts = 0;
                        var adWaitTimer = setInterval(function() {
                            waitAttempts++;
                            skipAds();
                            if (!findAdPlayer() || waitAttempts >= 25) {
                                clearInterval(adWaitTimer);
                                startMainPlaybackAndFS();
                            }
                        }, 100);
                    } else {
                        startMainPlaybackAndFS();
                    }
                } else if (player && typeof player.playVideo === 'function') {
                    skipAds();
                    player.playVideo();
                }
            }

            function setupPlaceholder() {
                injectStyles();

                if (isShorts() || !isWatchPage()) {
                    var existing = document.querySelector('.yt-free-placeholder');
                    if (existing) existing.remove();
                    return;
                }

                var container = findPlayerContainer();
                if (!container) return;

                var pos = window.getComputedStyle(container).position;
                if (pos === 'static' || !pos) {
                    container.style.position = 'relative';
                }

                var watchKey = currentWatchVideoKey();
                var placeholder = container.querySelector(':scope > .yt-free-placeholder');
                if (!placeholder) {
                    var strays = document.querySelectorAll('.yt-free-placeholder');
                    strays.forEach(function(s) { s.remove(); });

                    placeholder = buildPlaceholderElement();
                    placeholder.dataset.ytFreeVid = watchKey;

                    placeholder.addEventListener('click', function(e) {
                        e.preventDefault();
                        e.stopPropagation();
                        launchNativePlayer(placeholder);
                    });

                    container.appendChild(placeholder);
                } else if (placeholder.dataset.ytFreeVid !== watchKey) {
                    placeholder.dataset.ytFreeVid = watchKey;
                    if (!document.fullscreenElement && !document.webkitFullscreenElement) {
                        placeholder.style.display = 'flex';
                    }
                }

                // Before user interaction, pause/mute video to prevent background ad audio
                var video = container.querySelector('video') || document.querySelector('video');
                if (video && placeholder.style.display !== 'none') {
                    if (!video.paused && !document.fullscreenElement && !document.webkitFullscreenElement && !video.webkitDisplayingFullscreen) {
                        video.muted = true;
                        video.pause();
                    }
                }
            }
        """ : """
            function hasActivePlaceholder() { return false; }

            function enforceYouTubeOnlyControls() {
                var videos = document.querySelectorAll('#movie_player video, .html5-video-player video');
                for (var i = 0; i < videos.length; i++) {
                    if (videos[i].hasAttribute('controls')) {
                        videos[i].removeAttribute('controls');
                    }
                }
            }

            function setupPlaceholder() {}
        """

        return """
        (function() {
            var hostname = (window.location.hostname || '').toLowerCase();
            var isYT = hostname === 'youtube.com' || hostname.endsWith('.youtube.com') ||
                       hostname === 'youtube-nocookie.com' || hostname.endsWith('.youtube-nocookie.com') ||
                       hostname === 'youtubekids.com' || hostname.endsWith('.youtubekids.com');
            if (!isYT) return;

            var origParse = JSON.parse;

            function stripAdKeys(obj) {
                if (!obj || typeof obj !== 'object') return obj;
                try {
                    if ('adPlacements' in obj) {
                        if (!delete obj.adPlacements) obj.adPlacements = [];
                    }
                    if ('playerAds' in obj) {
                        if (!delete obj.playerAds) obj.playerAds = [];
                    }
                    if ('adSlots' in obj) {
                        if (!delete obj.adSlots) obj.adSlots = [];
                    }
                    if ('adBreakHeartbeatParams' in obj) {
                        delete obj.adBreakHeartbeatParams;
                    }
                    if (obj.playerResponse && typeof obj.playerResponse === 'object') {
                        stripAdKeys(obj.playerResponse);
                    }
                    if (Array.isArray(obj.entries)) {
                        var filtered = [];
                        for (var i = 0; i < obj.entries.length; i++) {
                            var e = obj.entries[i];
                            if (e && e.command && e.command.reelWatchEndpoint && e.command.reelWatchEndpoint.adParams) {
                                continue;
                            }
                            if (e && e.playerResponse && typeof e.playerResponse === 'object') {
                                stripAdKeys(e.playerResponse);
                            }
                            filtered.push(e);
                        }
                        if (filtered.length !== obj.entries.length) {
                            obj.entries = filtered;
                        }
                    }
                    if (obj.auxiliaryUi && obj.auxiliaryUi.messageRenderers && typeof obj.auxiliaryUi.messageRenderers === 'object') {
                        if ('bkaEnforcementMessageViewModel' in obj.auxiliaryUi.messageRenderers) {
                            delete obj.auxiliaryUi.messageRenderers.bkaEnforcementMessageViewModel;
                        }
                        if ('enforcementMessageViewModel' in obj.auxiliaryUi.messageRenderers) {
                            delete obj.auxiliaryUi.messageRenderers.enforcementMessageViewModel;
                        }
                    }
                } catch (e) {}
                return obj;
            }

            function sanitizeYtPlayerConfig() {
                try {
                    if (window.ytplayer && window.ytplayer.config && window.ytplayer.config.args) {
                        var args = window.ytplayer.config.args;
                        if (args.raw_player_response && typeof args.raw_player_response === 'object') {
                            stripAdKeys(args.raw_player_response);
                        }
                        if (typeof args.player_response === 'string' && args.player_response.length > 0 && args.player_response[0] === '{') {
                            args.player_response = JSON.stringify(stripAdKeys(origParse(args.player_response)));
                        }
                    }
                } catch (e) {}
            }

            // Layer 1: Intercept initial player response before YouTube player scripts read it
            try {
                var _ipr = window.ytInitialPlayerResponse ? stripAdKeys(window.ytInitialPlayerResponse) : undefined;
                Object.defineProperty(window, 'ytInitialPlayerResponse', {
                    configurable: true,
                    enumerable: true,
                    get: function() { return _ipr; },
                    set: function(val) { _ipr = stripAdKeys(val); }
                });
            } catch (e) {}

            // Layer 2: Strip ad keys from JSON.parse (catches inline/embedded/arrayBuffer player responses)
            try {
                JSON.parse = function() {
                    var res = origParse.apply(this, arguments);
                    if (res && typeof res === 'object') {
                        if (Array.isArray(res)) {
                            for (var i = 0; i < res.length; i++) {
                                var item = res[i];
                                if (item && typeof item === 'object' && ('adPlacements' in item || 'playerAds' in item || 'adSlots' in item || 'adBreakHeartbeatParams' in item || 'playerResponse' in item || 'auxiliaryUi' in item)) {
                                    stripAdKeys(item);
                                }
                            }
                        } else if ('adPlacements' in res || 'playerAds' in res || 'adSlots' in res || 'adBreakHeartbeatParams' in res || 'playerResponse' in res || 'entries' in res || 'auxiliaryUi' in res) {
                            stripAdKeys(res);
                        }
                    }
                    return res;
                };
            } catch (e) {}

            // Layer 3: Intercept fetch & XMLHttpRequest for SPA player/reel responses
            function isPlayerAPIURL(url) {
                return url.indexOf('/youtubei/v1/player') !== -1 ||
                       url.indexOf('/youtubei/v1/next') !== -1 ||
                       url.indexOf('/youtubei/v1/reel/') !== -1;
            }

            function isAdEndpointURL(url) {
                return url.indexOf('/pagead/') !== -1 ||
                       url.indexOf('/api/stats/ads') !== -1 ||
                       url.indexOf('/get_midroll_info') !== -1 ||
                       url.indexOf('/ptracking') !== -1;
            }

            try {
                var origFetch = window.fetch;
                if (typeof origFetch === 'function') {
                    window.fetch = function(input) {
                        var url = (typeof input === 'string') ? input : (input && (input.url || input.href) ? String(input.url || input.href) : '');
                        if (url && isAdEndpointURL(url)) {
                            return Promise.resolve(new Response('{}', {
                                status: 200,
                                headers: { 'Content-Type': 'application/json' }
                            }));
                        }
                        return origFetch.apply(this, arguments).then(function(resp) {
                            if (!resp || !resp.ok || !url || !isPlayerAPIURL(url)) return resp;
                            var ct = (resp.headers && resp.headers.get('content-type')) || '';
                            if (ct.indexOf('json') === -1) return resp;
                            return resp.clone().text().then(function(text) {
                                try {
                                    var data = origParse(text);
                                    stripAdKeys(data);
                                    var headers = new Headers(resp.headers);
                                    headers.delete('content-length');
                                    headers.delete('content-encoding');
                                    var out = new Response(JSON.stringify(data), {
                                        status: resp.status,
                                        statusText: resp.statusText,
                                        headers: headers
                                    });
                                    try { Object.defineProperty(out, 'url', { value: resp.url }); } catch(e) {}
                                    return out;
                                } catch (e) {
                                    return resp;
                                }
                            }).catch(function() { return resp; });
                        });
                    };
                }
            } catch (e) {}

            try {
                var origOpen = XMLHttpRequest.prototype.open;
                var origSend = XMLHttpRequest.prototype.send;
                var rtDesc = Object.getOwnPropertyDescriptor(XMLHttpRequest.prototype, 'responseText');
                var rDesc = Object.getOwnPropertyDescriptor(XMLHttpRequest.prototype, 'response');

                XMLHttpRequest.prototype.open = function(method, url) {
                    this.__ytFreeURL = typeof url === 'string' ? url : String(url || '');
                    this.__ytFreeCachedRaw = null;
                    this.__ytFreeCachedClean = null;
                    return origOpen.apply(this, arguments);
                };

                XMLHttpRequest.prototype.send = function() {
                    var self = this;
                    var u = this.__ytFreeURL || '';
                    if (u && isPlayerAPIURL(u)) {
                        Object.defineProperty(this, 'responseText', {
                            configurable: true,
                            get: function() {
                                var raw = rtDesc && rtDesc.get ? rtDesc.get.call(self) : '';
                                if (typeof raw === 'string' && raw.length > 0 && raw[0] === '{') {
                                    if (self.__ytFreeCachedRaw === raw && self.__ytFreeCachedClean !== null) {
                                        return self.__ytFreeCachedClean;
                                    }
                                    try {
                                        var clean = JSON.stringify(stripAdKeys(origParse(raw)));
                                        self.__ytFreeCachedRaw = raw;
                                        self.__ytFreeCachedClean = clean;
                                        return clean;
                                    } catch (e) {}
                                }
                                return raw;
                            }
                        });
                        Object.defineProperty(this, 'response', {
                            configurable: true,
                            get: function() {
                                var raw = rDesc && rDesc.get ? rDesc.get.call(self) : null;
                                if (typeof raw === 'string' && raw.length > 0 && raw[0] === '{') {
                                    if (self.__ytFreeCachedRaw === raw && self.__ytFreeCachedClean !== null) {
                                        return self.__ytFreeCachedClean;
                                    }
                                    try {
                                        var clean = JSON.stringify(stripAdKeys(origParse(raw)));
                                        self.__ytFreeCachedRaw = raw;
                                        self.__ytFreeCachedClean = clean;
                                        return clean;
                                    } catch (e) {}
                                }
                                if (raw instanceof ArrayBuffer && typeof TextDecoder !== 'undefined' && typeof TextEncoder !== 'undefined') {
                                    try {
                                        var str = new TextDecoder().decode(raw);
                                        if (str.length > 0 && str[0] === '{') {
                                            var cleanBufStr = JSON.stringify(stripAdKeys(origParse(str)));
                                            return new TextEncoder().encode(cleanBufStr).buffer;
                                        }
                                    } catch (e) {}
                                }
                                if (raw && typeof raw === 'object' && !(raw instanceof ArrayBuffer) && !(raw instanceof Blob)) {
                                    return stripAdKeys(raw);
                                }
                                return raw;
                            }
                        });
                    }
                    return origSend.apply(this, arguments);
                };
            } catch (e) {}

            function injectStyles() {
                if (document.getElementById('yt-free-styles')) return;
                var target = document.head || document.documentElement;
                if (!target) return;
                var style = document.createElement('style');
                style.id = 'yt-free-styles';
                var rules = [
                    /* Ad blocking CSS rules */
                    '.video-ads, .ytp-ad-module, .ytp-ad-overlay-container,',
                    '.ytp-ad-player-overlay, .ytp-ad-player-overlay-layout,',
                    '.ytp-ad-text, .ytp-ad-image-overlay,',
                    '.ad-showing .ytp-ad-action-interstitial, .ad-container,',
                    '.ytp-ad-preview-container, .ytp-ad-skip-button-slot,',
                    '.ytp-ad-message-container, .ytp-ad-overlay-slot, .ytp-ad-survey-questions,',
                    'ytd-ad-slot-renderer, ytd-promoted-sparkles-web-renderer,',
                    'ytd-promoted-sparkles-text-search-renderer, ytd-display-ad-renderer,',
                    'ytd-in-feed-ad-layout-renderer, ytd-action-companion-ad-renderer,',
                    'ytd-companion-slot-renderer, ytd-banner-promo-renderer,',
                    'ytd-statement-banner-renderer, ytd-brand-video-shelf-renderer,',
                    'ytd-mealbar-promo-renderer, ytd-player-legacy-desktop-watch-ads-renderer,',
                    'ytd-enforcement-message-view-model,',
                    'ytd-engagement-panel-section-list-renderer[target-id="engagement-panel-ads"],',
                    '#masthead-ad, #player-ads,',
                    'ytm-ad-slot-renderer, ytm-promoted-sparkles-web-renderer,',
                    'ytm-promoted-video-renderer, ytm-companion-slot-renderer,',
                    '.ytp-pause-overlay, .ytp-ce-element, .ytp-endscreen-content {',
                    '    display: none !important;',
                    '}',
                    '.ad-showing video, .ad-interrupting video {',
                    '    opacity: 0 !important;',
                    '}',
                    'ytd-rich-item-renderer:has(ytd-ad-slot-renderer),',
                    'ytd-rich-section-renderer:has(ytd-statement-banner-renderer),',
                    'ytd-rich-section-renderer:has(ytd-brand-video-shelf-renderer),',
                    'ytd-reel-video-renderer:has(ytd-ad-slot-renderer),',
                    'ytm-reel-video-renderer:has(ytm-ad-slot-renderer) {',
                    '    display: none !important;',
                    '}'
                ];
                var extra = [
        \(placeholderCSS)
                ];
                if (extra.length > 0) {
                    rules = rules.concat(extra);
                }
                style.textContent = rules.join('\\n');
                target.appendChild(style);
            }

            function findAdPlayer() {
                var player = document.querySelector('.html5-video-player.ad-showing, .html5-video-player.ad-interrupting, #movie_player.ad-showing, #movie_player.ad-interrupting');
                if (player) return player;
                var overlays = document.querySelectorAll('#movie_player .ytp-ad-player-overlay, #movie_player .ytp-ad-player-overlay-layout, .html5-video-player .ytp-ad-player-overlay, .html5-video-player .ytp-ad-player-overlay-layout');
                for (var i = 0; i < overlays.length; i++) {
                    var ov = overlays[i];
                    if (ov.childElementCount > 0 && !ov.hidden && ov.style.display !== 'none' && ov.getAttribute('aria-hidden') !== 'true') {
                        if (ov.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, .ytp-ad-text, .ytp-ad-preview-container, .ytp-ad-duration-remaining, .ytp-ad-player-overlay-instream-info, .ytp-ad-button')) {
                            return ov.closest('.html5-video-player') || document.getElementById('movie_player');
                        }
                    }
                }
                return null;
            }

            // Layer 4: Reactive fallback ad skipper
            function skipAds() {
                var adPlayer = findAdPlayer();
                if (adPlayer) {
                    var video = adPlayer.querySelector('video') || document.querySelector('#movie_player video, video');
                    if (video) {
                        if (!video.__ytFreeSkipping) {
                            video.__ytFreeSkipping = true;
                            video.__ytFreeSavedMuted = video.muted;
                            video.__ytFreeSavedRate = (video.playbackRate && video.playbackRate !== 16) ? video.playbackRate : 1.0;
                        }
                        video.muted = true;
                        try { video.playbackRate = 16; } catch(e) {}
                        if (isFinite(video.duration) && video.duration > 0 && video.currentTime < video.duration - 0.1) {
                            try { video.currentTime = video.duration; } catch(e) {}
                        } else if (video.buffered && video.buffered.length > 0) {
                            try {
                                var bufEnd = video.buffered.end(video.buffered.length - 1);
                                if (isFinite(bufEnd) && bufEnd > video.currentTime + 0.2) {
                                    video.currentTime = bufEnd;
                                }
                            } catch(e) {}
                        }
                        if (video.paused && !hasActivePlaceholder()) {
                            try {
                                var p = video.play();
                                if (p && typeof p.catch === 'function') p.catch(function(){});
                            } catch(e) {}
                        }
                    }
                    var skipBtns = adPlayer.querySelectorAll('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, .ytp-ad-skip-button-container button, .ytp-ad-overlay-close-button');
                    if (!skipBtns.length) {
                        skipBtns = document.querySelectorAll('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, .ytp-ad-skip-button-container button, .ytp-ad-overlay-close-button');
                    }
                    skipBtns.forEach(function(btn) { btn.click(); });
                } else {
                    var videos = document.querySelectorAll('video');
                    for (var i = 0; i < videos.length; i++) {
                        var v = videos[i];
                        if (v.__ytFreeSkipping) {
                            v.__ytFreeSkipping = false;
                            v.muted = !!v.__ytFreeSavedMuted;
                            try { v.playbackRate = v.__ytFreeSavedRate || 1.0; } catch(e) {}
                        }
                    }
                    var closeBtn = document.querySelector('.ytp-ad-overlay-close-button');
                    if (closeBtn) closeBtn.click();
                }
            }

        \(placeholderJS)

            function runChecks() {
                try { sanitizeYtPlayerConfig(); } catch(e) {}
                try { injectStyles(); } catch(e) {}
                try { enforceYouTubeOnlyControls(); } catch(e) {}
                try { skipAds(); } catch(e) {}
                try { setupPlaceholder(); } catch(e) {}
            }

            var mediaEvents = ['loadstart', 'loadedmetadata', 'durationchange', 'canplay', 'canplaythrough', 'play', 'playing', 'ratechange', 'volumechange', 'timeupdate', 'ended'];
            mediaEvents.forEach(function(evt) {
                document.addEventListener(evt, function() {
                    try { skipAds(); } catch(e) {}
                }, true);
            });

            window.addEventListener('yt-navigate-finish', runChecks);
            window.addEventListener('yt-page-data-updated', runChecks);
            window.addEventListener('popstate', runChecks);

            var scheduled = false;
            function scheduleChecks() {
                if (scheduled) return;
                scheduled = true;
                setTimeout(function() {
                    scheduled = false;
                    runChecks();
                }, 50);
            }

            function start() {
                var root = document.documentElement;
                if (!root) {
                    document.addEventListener('DOMContentLoaded', start, { once: true });
                    return;
                }
                runChecks();
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', runChecks);
                }
                var obs = new MutationObserver(function(mutations) {
                    var needsImmediateSkip = false;
                    var needsControlStrip = false;
                    var needsScheduledCheck = false;
                    for (var i = 0; i < mutations.length; i++) {
                        var m = mutations[i];
                        if (m.type === 'attributes') {
                            if (m.attributeName === 'controls') {
                                needsControlStrip = true;
                            } else {
                                var t = m.target;
                                var oldVal = m.oldValue || '';
                                var hadAd = oldVal.indexOf('ad-showing') !== -1 || oldVal.indexOf('ad-interrupting') !== -1;
                                var isPlayer = t && (t.id === 'movie_player' || (t.classList && (t.classList.contains('html5-video-player') || t.classList.contains('ad-showing') || t.classList.contains('ad-interrupting'))));
                                if (hadAd || isPlayer) {
                                    needsImmediateSkip = true;
                                }
                            }
                        } else if (m.type === 'childList') {
                            needsScheduledCheck = true;
                        }
                    }
                    if (!document.getElementById('yt-free-styles')) {
                        try { injectStyles(); } catch(e) {}
                    }
                    if (needsControlStrip) {
                        try { enforceYouTubeOnlyControls(); } catch(e) {}
                    }
                    if (needsImmediateSkip || (needsScheduledCheck && findAdPlayer())) {
                        try { skipAds(); } catch(e) {}
                    }
                    if (needsScheduledCheck) {
                        scheduleChecks();
                    }
                });
                obs.observe(root, {
                    childList: true,
                    subtree: true,
                    attributes: true,
                    attributeFilter: ['class', 'controls'],
                    attributeOldValue: true
                });
            }

            start();
            setInterval(runChecks, 250);
        })();
        """
    }
}

// MARK: - Native YouTube Content Blocker

/// Compiles and caches WebKit content blocking rules for YouTube ad domains and ad endpoints,
/// matching Youtube-Free's targeted 9-rule blocklist without interfering with video playback/telemetry.
@MainActor
final class YouTubeContentBlocker {
    static let shared = YouTubeContentBlocker()

    static let ruleIdentifier = "fr.trevalim.isowebapps.youtube.adblock.v1"
    static let rulesJSON = """
    [
      {
        "trigger": { "url-filter": "^https?://([a-z0-9-]+\\\\.)?doubleclick\\\\.net/", "if-domain": ["*youtube.com", "*youtube-nocookie.com", "*youtubekids.com"] },
        "action": { "type": "block" }
      },
      {
        "trigger": { "url-filter": "^https?://([a-z0-9-]+\\\\.)?googlesyndication\\\\.com/", "if-domain": ["*youtube.com", "*youtube-nocookie.com", "*youtubekids.com"] },
        "action": { "type": "block" }
      },
      {
        "trigger": { "url-filter": "^https?://([a-z0-9-]+\\\\.)?googleadservices\\\\.com/", "if-domain": ["*youtube.com", "*youtube-nocookie.com", "*youtubekids.com"] },
        "action": { "type": "block" }
      },
      {
        "trigger": { "url-filter": "^https?://([a-z0-9-]+\\\\.)?2mdn\\\\.net/", "if-domain": ["*youtube.com", "*youtube-nocookie.com", "*youtubekids.com"] },
        "action": { "type": "block" }
      },
      {
        "trigger": { "url-filter": "^https?://([a-z0-9-]+\\\\.)?youtube\\\\.com/pagead/", "if-domain": ["*youtube.com", "*youtube-nocookie.com", "*youtubekids.com"] },
        "action": { "type": "block" }
      },
      {
        "trigger": { "url-filter": "^https?://([a-z0-9-]+\\\\.)?youtube\\\\.com/api/stats/ads", "if-domain": ["*youtube.com", "*youtube-nocookie.com", "*youtubekids.com"] },
        "action": { "type": "block" }
      },
      {
        "trigger": { "url-filter": "^https?://([a-z0-9-]+\\\\.)?youtube\\\\.com/ptracking", "if-domain": ["*youtube.com", "*youtube-nocookie.com", "*youtubekids.com"] },
        "action": { "type": "block" }
      },
      {
        "trigger": { "url-filter": "^https?://([a-z0-9-]+\\\\.)?youtube\\\\.com/get_midroll_info", "if-domain": ["*youtube.com", "*youtube-nocookie.com", "*youtubekids.com"] },
        "action": { "type": "block" }
      },
      {
        "trigger": { "url-filter": "^https?://([a-z0-9-]+\\\\.)?googlevideo\\\\.com/videoplayback.*[&?]oad=", "if-domain": ["*youtube.com", "*youtube-nocookie.com", "*youtubekids.com"] },
        "action": { "type": "block" }
      }
    ]
    """

    private(set) var ruleList: WKContentRuleList?
    var isLoaded: Bool { ruleList != nil }
    private var prepareTask: Task<WKContentRuleList?, Never>?

    private init() {}

    @discardableResult
    func prepare(store: WKContentRuleListStore = .default()) async -> WKContentRuleList? {
        let isDefaultStore = (store === WKContentRuleListStore.default())
        if isDefaultStore, let ruleList {
            return ruleList
        }
        if isDefaultStore, let prepareTask {
            return await prepareTask.value
        }

        let task = Task<WKContentRuleList?, Never> { @MainActor in
            let existing: WKContentRuleList? = await withCheckedContinuation { continuation in
                store.lookUpContentRuleList(forIdentifier: Self.ruleIdentifier) { list, _ in
                    continuation.resume(returning: list)
                }
            }
            if let existing {
                if isDefaultStore {
                    self.ruleList = existing
                }
                return existing
            }

            let compiled: WKContentRuleList? = await withCheckedContinuation { continuation in
                store.compileContentRuleList(
                    forIdentifier: Self.ruleIdentifier,
                    encodedContentRuleList: Self.rulesJSON
                ) { list, _ in
                    continuation.resume(returning: list)
                }
            }
            if isDefaultStore, let compiled {
                self.ruleList = compiled
            }
            return compiled
        }

        if isDefaultStore {
            prepareTask = task
            let result = await task.value
            prepareTask = nil
            return result
        }
        return await task.value
    }

    func applyToConfiguration(_ config: WKWebViewConfiguration) {
        let controller = config.userContentController
        controller.removeAllContentRuleLists()
        controller.removeAllUserScripts()

        let masterEnabled = UserDefaults.standard.object(forKey: "ublock_master_enabled") as? Bool ?? true
        guard masterEnabled else { return }

        if let ruleList {
            controller.add(ruleList)
        }
        controller.addUserScript(YouTubeFreeSupport.playerUserScript)
    }

    func releaseInMemoryCache() {
        prepareTask?.cancel()
        prepareTask = nil
        ruleList = nil
    }
}

// MARK: - Weak Script Message Handler

final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: (AnyObject & WKScriptMessageHandler)?

    init(_ delegate: AnyObject & WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - Native AVKit HLS Overlay

#if os(iOS)
struct YouTubeAVKitPlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        let item = AVPlayerItem(url: url)
        item.preferredPeakBitRate = 0
        item.preferredMaximumResolution = .zero
        let player = AVPlayer(playerItem: item)
        vc.player = player
        player.play()
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if let existing = (vc.player?.currentItem?.asset as? AVURLAsset)?.url, existing != url {
            let item = AVPlayerItem(url: url)
            item.preferredPeakBitRate = 0
            item.preferredMaximumResolution = .zero
            vc.player?.replaceCurrentItem(with: item)
            vc.player?.play()
        }
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        uiViewController.player?.pause()
        uiViewController.player = nil
    }
}
#elseif os(macOS)
struct YouTubeAVKitPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        let item = AVPlayerItem(url: url)
        item.preferredPeakBitRate = 0
        let player = AVPlayer(playerItem: item)
        view.player = player
        player.play()
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if let existing = (nsView.player?.currentItem?.asset as? AVURLAsset)?.url, existing != url {
            let item = AVPlayerItem(url: url)
            item.preferredPeakBitRate = 0
            nsView.player?.replaceCurrentItem(with: item)
            nsView.player?.play()
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}
#endif

struct YouTubeAVKitOverlayView: View {
    let url: URL
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            YouTubeAVKitPlayerView(url: url)
                .ignoresSafeArea()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .padding(12)
            }
            .buttonStyle(.plain)
            .help("Close native player")
        }
        .transition(.opacity)
    }
}
