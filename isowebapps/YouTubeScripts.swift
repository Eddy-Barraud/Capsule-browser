import Foundation

enum YouTubeScripts {
    /// Lightweight, non-intrusive YouTube cosmetic ad-hiding and automatic ad-skipper script.
    /// Does not overlay, pause, or hijack the native YouTube HTML5 video player.
    static let adBlockScript = """
(function() {
    if (window.__ytCapsuleAdBlockActive) return;
    var hostname = window.location.hostname || '';
    if (!hostname.includes('youtube.com')) return;
    window.__ytCapsuleAdBlockActive = true;

    function injectStyles() {
        if (document.getElementById('yt-capsule-adblock-styles')) return;
        var style = document.createElement('style');
        style.id = 'yt-capsule-adblock-styles';
        style.textContent = [
            'ytd-ad-slot-renderer,',
            'ytd-in-feed-ad-layout-renderer,',
            'ytd-banner-promo-renderer,',
            'ytd-statement-banner-renderer,',
            'ytd-engagement-panel-section-list-renderer[target-id="engagement-panel-ads"],',
            'ytd-display-ad-renderer,',
            'ytd-promoted-sparkles-web-renderer,',
            'ytd-promoted-video-renderer,',
            'ytd-compact-promoted-video-renderer,',
            'ytm-promoted-sparkles-web-renderer,',
            'ytm-companion-ad-renderer,',
            '#masthead-ad,',
            '#player-ads,',
            '#panels > ytd-engagement-panel-section-list-renderer[target-id="engagement-panel-ads"],',
            '.ytp-ad-overlay-container,',
            '.ytp-ad-message-container,',
            '.ytp-ad-image-overlay,',
            '.ytp-ad-text-overlay,',
            'ytd-merch-shelf-renderer {',
            '    display: none !important;',
            '}'
        ].join('\\n');
        (document.head || document.documentElement).appendChild(style);
    }

    var wasAdShowing = false;
    var userMutedBeforeAd = false;

    function handleAds() {
        if (!window.__ytCapsuleAdBlockActive) return;
        injectStyles();

        var skipButtons = document.querySelectorAll(
            '.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, .ytp-ad-overlay-close-button, .ytp-ad-survey-answer-button'
        );
        for (var i = 0; i < skipButtons.length; i++) {
            var btn = skipButtons[i];
            if (btn && typeof btn.click === 'function') {
                try { btn.click(); } catch (e) {}
            }
        }

        var player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
        var video = player ? player.querySelector('video.html5-main-video, video') : document.querySelector('video');
        if (!player || !video) return;

        var isAdShowing = player.classList.contains('ad-showing') || player.classList.contains('ad-interrupting');

        if (isAdShowing) {
            if (!wasAdShowing) {
                wasAdShowing = true;
                userMutedBeforeAd = video.muted;
            }
            video.muted = true;
            if (isFinite(video.duration) && video.duration > 0.5 && video.currentTime < video.duration - 0.1) {
                try {
                    video.currentTime = video.duration;
                } catch (e) {
                    video.playbackRate = 16;
                }
            } else {
                try {
                    video.playbackRate = 16;
                } catch (e) {}
            }
        } else if (wasAdShowing) {
            wasAdShowing = false;
            video.muted = userMutedBeforeAd;
            if (video.playbackRate > 2) {
                video.playbackRate = 1;
            }
        }
    }

    injectStyles();
    handleAds();

    var observer = new MutationObserver(function() {
        handleAds();
    });

    observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['class']
    });

    window.__ytCapsuleAdBlockCleanup = function() {
        window.__ytCapsuleAdBlockActive = false;
        try { observer.disconnect(); } catch (e) {}
        var style = document.getElementById('yt-capsule-adblock-styles');
        if (style) style.remove();
    };
})();
"""

    /// Removes injected YouTube ad-block styles and disconnects the observer when toggled off.
    static let cleanupScript = """
(function() {
    if (typeof window.__ytCapsuleAdBlockCleanup === 'function') {
        window.__ytCapsuleAdBlockCleanup();
    }
})();
"""
}
