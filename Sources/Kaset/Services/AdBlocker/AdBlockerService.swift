import Foundation
import WebKit

// MARK: - AdBlockerService

/// Implements YouTube ad blocking via WKUserScript JavaScript injection.
/// This approach injects scripts at document start, before YouTube's own scripts load,
/// making detection harder than network-layer blocking.
enum AdBlockerService {

    // MARK: - Public API

    /// Creates and returns all ad-blocking WKUserScript objects to be injected.
    static func makeScripts() -> [WKUserScript] {
        [
            WKUserScript(
                source: Self.adBlockScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ),
            WKUserScript(
                source: Self.antiDetectionScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ),
        ]
    }

    // MARK: - Anti-Detection Script

    /// Patches YouTube's adblock detection mechanism before the page loads.
    /// Overrides the MutationObserver to auto-dismiss the "ad blocker detected" dialog,
    /// and stubs out the ad-serving pipeline.
    private static let antiDetectionScript = """
    (function() {
        'use strict';

        // Block the ytInitialPlayerResponse ad config from being read
        const originalDefineProperty = Object.defineProperty;
        Object.defineProperty = function(obj, prop, descriptor) {
            if (prop === 'adPlacements' || prop === 'adSlots' || prop === 'playerAds') {
                return obj;
            }
            return originalDefineProperty.call(this, obj, prop, descriptor);
        };

        // Auto-dismiss "ad blocker detected" dialog
        const dismissAdblockDialog = () => {
            // Button to dismiss "Allow ads" dialog
            const dismissSelectors = [
                '.yt-confirm-dialog-renderer .yt-spec-button-shape-next--filled',
                'tp-yt-paper-dialog .yt-confirm-dialog-renderer button',
                '[class*="ad-showing"] .ytp-ad-skip-button',
                '.ytp-ad-overlay-close-button',
                'button.ytp-ad-skip-button-modern',
                '.ytp-skip-ad-button',
            ];
            for (const sel of dismissSelectors) {
                const btn = document.querySelector(sel);
                if (btn) { btn.click(); }
            }

            // Hide ad containers
            const hideSelectors = [
                '.ad-showing',
                '.ytp-ad-module',
                '#player-ads',
                '#masthead-ad',
                '.ytd-banner-promo-renderer',
                '.ytd-statement-banner-renderer',
                'ytd-ad-slot-renderer',
                'ytd-in-feed-ad-layout-renderer',
                '.ytp-ad-image-overlay',
                '.ytp-ad-text-overlay',
                '.ytp-ad-player-overlay',
                'ytd-promoted-video-renderer',
                'ytd-promoted-sparkles-web-renderer',
            ];
            for (const sel of hideSelectors) {
                for (const el of document.querySelectorAll(sel)) {
                    el.style.display = 'none';
                    el.style.visibility = 'hidden';
                    el.remove();
                }
            }
        };

        // Run on DOM changes (catches dynamically injected ads)
        const observer = new MutationObserver(() => { dismissAdblockDialog(); });
        document.addEventListener('DOMContentLoaded', () => {
            observer.observe(document.body, { childList: true, subtree: true });
            dismissAdblockDialog();
        });
        // Also run early
        dismissAdblockDialog();

    })();
    """

    // MARK: - Core Ad Block Script

    /// Intercepts and blocks ad-related network requests before they can execute,
    /// and fast-forwards video ads automatically.
    private static let adBlockScript = """
    (function() {
        'use strict';

        // ── 1. Intercept XMLHttpRequest for ad endpoints ──────────────────────
        const adUrlPatterns = [
            /\\/pagead\\//,
            /\\/pagead2\\//,
            /doubleclick\\.net/,
            /googleads\\.g\\./,
            /\\/get_video_info.*adformat/,
            /adservice\\.google/,
            /\\/ptracking/,
            /\\/api\\/stats\\/ads/,
            /\\/aclk/,
        ];

        const isAdUrl = (url) => adUrlPatterns.some(p => p.test(url));

        const originalOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url, ...args) {
            if (isAdUrl(url)) {
                // Silently abort ad requests
                this._blocked = true;
                return originalOpen.call(this, method, 'about:blank', ...args);
            }
            return originalOpen.call(this, method, url, ...args);
        };

        // ── 2. Intercept fetch() for ad endpoints ─────────────────────────────
        const originalFetch = window.fetch;
        window.fetch = function(input, init) {
            const url = typeof input === 'string' ? input : input?.url || '';
            if (isAdUrl(url)) {
                return Promise.resolve(new Response('{}', { status: 200 }));
            }
            return originalFetch.call(this, input, init);
        };

        // ── 3. Auto-skip video ads ────────────────────────────────────────────
        const skipAds = () => {
            const video = document.querySelector('video');
            if (!video) return;

            // YouTube Music specific ad detection
            const ytMusicPlayerBar = document.querySelector('ytmusic-player-bar');
            const isAdPlaying = ytMusicPlayerBar && ytMusicPlayerBar.hasAttribute('is-ad-playing');
            const adOverlay = document.querySelector('.ad-showing, .ad-interrupting, .ytp-ad-module, .ytp-ad-player-overlay');
            
            if (isAdPlaying || adOverlay) {
                // Fast-forward to end to trigger skip
                if (isFinite(video.duration) && video.duration > 0 && video.currentTime < video.duration - 0.5) {
                    video.currentTime = video.duration - 0.1;
                    video.play(); // ensure playback finishes instantly
                }
                
                // Click any available skip button
                const skipBtn = document.querySelector(
                    '.ytp-ad-skip-button, .ytp-skip-ad-button, button.ytp-ad-skip-button-modern, .ytp-ad-overlay-close-button'
                );
                if (skipBtn) { 
                    skipBtn.click(); 
                }
            }
        };

        // Poll every 300ms — fast enough to be invisible to the user
        setInterval(skipAds, 300);

    })();
    """
}
