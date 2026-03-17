import SwiftUI

/// Full-screen or expanded panel displaying synced lyrics for the current track.
@MainActor
struct LyricsView: View {
    @EnvironmentObject private var playerService: PlayerService

    let client: any YTMusicClientProtocol

    @State private var syncedLyrics: SyncedLyrics? = nil
    @State private var plainLyrics: Lyrics? = nil
    @State private var isLoading = false
    @State private var lastLoadedVideoId: String? = nil

    // To prevent manual scrolling from being overridden too aggressively
    @State private var userIsScrolling = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Lyrics")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)

            if self.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                Spacer()
            } else if let syncedLyrics = self.syncedLyrics, syncedLyrics.isAvailable {
                SyncedLyricsContentView(lyrics: syncedLyrics, progress: self.playerService.progress)
            } else if let plainLyrics = self.plainLyrics, plainLyrics.isAvailable {
                ScrollView {
                    Text(plainLyrics.text)
                        .font(.title3)
                        .fontWeight(.medium)
                        .lineSpacing(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                }
            } else {
                Spacer()
                Text("No lyrics available")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .frame(minWidth: 400, maxWidth: .infinity)
        .background(.regularMaterial)
        .onChange(of: self.playerService.currentTrack?.videoId) { newVideoId in
            if let videoId = newVideoId, let song = self.playerService.currentTrack {
                Task {
                    await self.loadLyrics(for: song)
                }
            }
        }
        .task {
            if let song = self.playerService.currentTrack {
                await self.loadLyrics(for: song)
            }
        }
    }

// Note: Since LyricsView is recreated when toggled, its @State resets.
// To fix the "reload reverts to plain text" bug without moving state to an ObservableObject, 
// we ensure the fetch logic is robust, or we skip resetting if the song hasn't changed.
// Better yet, caching is handled in `SyncedLyricsService` if needed, but for now we just 
// correctly map the API responses.

    private func loadLyrics(for song: Song) async {
        // If we already have synced lyrics for this song, don't re-fetch
        if let current = self.syncedLyrics, current.isAvailable, self.lastLoadedVideoId == song.videoId {
            return
        }
        
        self.isLoading = true
        self.lastLoadedVideoId = song.videoId
        self.syncedLyrics = nil
        self.plainLyrics = nil
        
        do {
            // Priority 1: Synced Lyrics (SimpMusic -> LRCLIB)
            let synced = try await SyncedLyricsService.shared.fetchLyrics(for: song)
            if synced.isAvailable {
                self.syncedLyrics = synced
            } else {
                // Priority 2: Fallback to plain lyrics from YTMusicClient
                self.plainLyrics = try await self.client.getLyrics(videoId: song.videoId)
            }
        } catch {
            // Error in synced service, fallback to plain
            do {
                self.plainLyrics = try await self.client.getLyrics(videoId: song.videoId)
            } catch {
                self.plainLyrics = nil
            }
        }
        self.isLoading = false
    }
}

// MARK: - SyncedLyricsContentView

@MainActor
private struct SyncedLyricsContentView: View {
    let lyrics: SyncedLyrics
    let progress: TimeInterval

    @Namespace private var scrollSpace

    var activeLineIndex: Int? {
        // Find the last line whose time is <= current progress
        // Adding a small offset (0.2s) to make appearance feel more responsive
        let adjustedProgress = progress + 0.2
        return lyrics.lines.lastIndex(where: { $0.time <= adjustedProgress })
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Padding block at top
                    Color.clear.frame(height: 60)

                    let baseFontSize = CGFloat(SettingsManager.shared.lyricsFontSize)

                    ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                        let isActive = index == activeLineIndex
                        let isPast = index < (activeLineIndex ?? -1)
                        
                        Text(line.text)
                            .font(.system(size: baseFontSize, weight: .bold, design: .default))
                            // Apple Music style: active is white, past/future is dimmed
                            .foregroundColor(isActive ? .primary : .primary.opacity(isPast ? 0.3 : 0.6))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isActive)
                            // Scale effect instead of animating font size for much better performance
                            .scaleEffect(isActive ? 1.05 : 0.95, anchor: .leading)
                    }

                    // Padding block at bottom
                    Color.clear.frame(height: 200)
                }
                .padding(.horizontal, 32)
            }
            .coordinateSpace(name: scrollSpace)
            .onChange(of: activeLineIndex) { newIndex in
                if let index = newIndex {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
            .onAppear {
                if let index = activeLineIndex {
                    // Initial scroll without animation
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }
}
