import SwiftUI
import WebKit

// MARK: - VideoPlayerWindow

/// Floating window for video playback.

struct VideoPlayerWindow: View {
    @EnvironmentObject private var playerService: PlayerService

    var body: some View {
        // Video content (WebView container) with native HTML5 controls
        VideoWebViewContainer()
            .background(.black)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(minWidth: 320, minHeight: 180)
            .accessibilityIdentifier(AccessibilityID.VideoWindow.container)
    }
}

// MARK: - VideoWebViewContainer

/// NSViewRepresentable container for the video WebView.

struct VideoWebViewContainer: NSViewRepresentable {
    func makeNSView(context _: Context) -> VideoContainerView {
        DiagnosticsLogger.player.info("VideoWebViewContainer.makeNSView called")
        let container = VideoContainerView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        
        // Reparent immediately to ensure it works on macOS versions where updateNSView is deferred
        SingletonPlayerWebView.shared.ensureInHierarchy(container: container)
        
        return container
    }

    func updateNSView(_ nsView: VideoContainerView, context _: Context) {
        DiagnosticsLogger.player.debug("VideoWebViewContainer.updateNSView called")
        // Reparent the WebView into this container for video display
        SingletonPlayerWebView.shared.ensureInHierarchy(container: nsView)
    }
}

// MARK: - VideoContainerView

/// Custom NSView that observes frame changes and re-injects CSS.

final class VideoContainerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.frameDidChange),
            name: NSView.frameDidChangeNotification,
            object: self
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func frameDidChange(_: Notification) {
        // Immediately update container size (no debounce for instant feedback)
        Task { @MainActor in
            if SingletonPlayerWebView.shared.displayMode == .video {
                SingletonPlayerWebView.shared.refreshVideoModeCSS()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Preview


#if false
#if false
#Preview {
    VideoPlayerWindow()
        .environmentObject(PlayerService())
        .frame(width: 480, height: 270)
}
#endif
#endif
