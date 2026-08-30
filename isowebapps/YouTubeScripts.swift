import Foundation

enum YouTubeScripts {
    static let ytPlaceholderAndAdBlockScript = """
(function() {
    var hostname = window.location.hostname;
    if (!hostname.includes('youtube.com')) return;

    function injectStyles() {
        if (document.getElementById('yt-free-styles')) return;
        var style = document.createElement('style');
        style.id = 'yt-free-styles';
        style.textContent = [
            /* Ad blocking CSS rules */
            '.video-ads, .ytp-ad-module, .ytp-ad-overlay-container,',
            '.ytp-ad-player-overlay, .ytp-ad-text, .ytp-ad-image-overlay,',
            '.ad-showing .ytp-ad-action-interstitial, .ad-container,',
            '.ytp-ad-preview-container, .ytp-ad-skip-button-slot,',
            '.ytp-ad-message-container, ytd-ad-slot-renderer,',
            '#player-ads, ytm-promoted-sparkles-web-renderer,',
            '.ytp-pause-overlay, .ytp-ce-element, .ytp-endscreen-content {',
            '    display: none !important;',
            '}',
            /* Native player placeholder overlay */
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
        ].join('\\n');
        (document.head || document.documentElement).appendChild(style);
    }

    function isShorts() {
        var path = window.location.pathname || '';
        return path.startsWith('/shorts') || window.location.href.includes('/shorts/');
    }

    function isWatchPage() {
        if (isShorts()) return false;
        var path = window.location.pathname || '';
        return path.startsWith('/watch') || window.location.search.includes('v=');
    }

    function skipAds() {
        var video = document.querySelector('video');
        var adShowing = document.querySelector('.ad-showing, .ad-interrupting, .ytp-ad-player-overlay, ytm-promoted-sparkles-web-renderer');
        if (adShowing && video) {
            video.muted = true;
            video.playbackRate = 16;
            if (isFinite(video.duration) && video.duration > 0) {
                video.currentTime = video.duration;
            }
            var skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, .ytp-ad-overlay-close-button');
            if (skipBtn) skipBtn.click();
        }
    }

    function findPlayerContainer() {
        return document.getElementById('player-container-id') ||
               document.getElementById('player') ||
               document.getElementById('movie_player') ||
               document.getElementById('ytd-player') ||
               document.querySelector('.player-container') ||
               document.querySelector('.html5-video-player') ||
               (document.querySelector('video') && document.querySelector('video').parentElement);
    }

    function launchNativePlayer(placeholder) {
        skipAds();

        var video = document.querySelector('video');
        var player = document.getElementById('movie_player');

        if (video) {
            video.muted = false;
            video.playbackRate = 1.0;
            video.removeAttribute('playsinline');
            video.removeAttribute('webkit-playsinline');

            function enterFS() {
                if (typeof video.webkitEnterFullscreen === 'function') {
                    video.webkitEnterFullscreen();
                } else if (typeof video.requestFullscreen === 'function') {
                    video.requestFullscreen().catch(function(){});
                } else if (typeof video.webkitRequestFullscreen === 'function') {
                    video.webkitRequestFullscreen();
                }
            }

            var p = video.play();
            if (p !== undefined) {
                p.then(enterFS).catch(enterFS);
            } else {
                enterFS();
            }

            function onExitFS() {
                video.removeEventListener('webkitendfullscreen', onExitFS);
                video.removeEventListener('fullscreenchange', onExitFS);
                if (placeholder) {
                    placeholder.style.display = 'flex';
                }
                video.pause();
            }
            video.addEventListener('webkitendfullscreen', onExitFS);
            video.addEventListener('fullscreenchange', onExitFS);
        } else if (player && typeof player.playVideo === 'function') {
            player.playVideo();
        }

        if (placeholder) {
            placeholder.style.display = 'none';
        }
    }

    function setupPlaceholder() {
        injectStyles();

        if (!isWatchPage()) {
            var existing = document.getElementById('yt-free-overlay');
            if (existing) existing.remove();
            return;
        }

        var container = findPlayerContainer();
        if (!container) return;

        var placeholder = document.getElementById('yt-free-overlay');
        if (!placeholder) {
            placeholder = document.createElement('div');
            placeholder.id = 'yt-free-overlay';
            placeholder.className = 'yt-free-placeholder';

            var btn = document.createElement('div');
            btn.className = 'yt-free-btn';
            btn.innerHTML = '<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>';
            
            var label = document.createElement('div');
            label.className = 'yt-free-label';
            label.innerText = 'Tap to Play';
            
            var badge = document.createElement('div');
            badge.className = 'yt-free-badge';
            badge.innerText = 'NATIVE PLAYER';

            placeholder.appendChild(btn);
            placeholder.appendChild(label);
            placeholder.appendChild(badge);
            
            placeholder.addEventListener('click', function(e) {
                e.stopPropagation();
                e.preventDefault();
                launchNativePlayer(placeholder);
            });
            
            container.appendChild(placeholder);
        }
        
        placeholder.style.display = 'flex';
        
        var video = document.querySelector('video');
        if (video && !video.paused) {
            video.pause();
        }
    }

    var observer = new MutationObserver(function(mutations) {
        skipAds();
        
        var urlChanged = false;
        mutations.forEach(function(m) {
            if (m.type === 'childList') {
                if (document.querySelector('.ad-showing, .ad-interrupting')) {
                    skipAds();
                }
            }
        });
        
        if (window.location.href !== window._lastYtUrl) {
            window._lastYtUrl = window.location.href;
            setTimeout(setupPlaceholder, 300);
        }
    });

    observer.observe(document.body || document.documentElement, {
        childList: true,
        subtree: true,
        attributes: false
    });

    window._lastYtUrl = window.location.href;
    
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() {
            setTimeout(setupPlaceholder, 500);
        });
    } else {
        setTimeout(setupPlaceholder, 500);
    }
})();
"""

    static let ytNativeControlsScript = """
(function() {
    var hostname = window.location.hostname;
    if (!hostname.includes('youtube.com')) return;

    function applyControls() {
        var videos = document.getElementsByTagName('video');
        for (var i = 0; i < videos.length; i++) {
            var v = videos[i];
            if (!v.hasAttribute('controls')) {
                v.setAttribute('controls', 'controls');
            }
            v.removeAttribute('playsinline');
            v.removeAttribute('webkit-playsinline');
        }
    }
    
    applyControls();
    
    var observer = new MutationObserver(function() {
        applyControls();
    });
    observer.observe(document.body || document.documentElement, {
        childList: true,
        subtree: true
    });
})();
"""
}
