import SwiftUI

// MARK: - MainWindow

/// Main application window with sidebar navigation and player bar.
struct MainWindow: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var playerService: PlayerService
    @EnvironmentObject private var webKitManager: WebKitManager
    @EnvironmentObject private var accountService: AccountService
    @Environment(\.showCommandBar) private var showCommandBar

    /// Binding to navigation selection for keyboard shortcut control from parent.
    @Binding var navigationSelection: NavigationItem?

    /// Shared API client used by all views and services.
    let client: any YTMusicClientProtocol

    @State private var showLoginSheet = false
    @State private var showCommandBarSheet = false

    // MARK: - Cached ViewModels (persist across tab switches)

    @State private var homeViewModel: HomeViewModel?
    @State private var exploreViewModel: ExploreViewModel?
    @State private var searchViewModel: SearchViewModel?
    @State private var chartsViewModel: ChartsViewModel?
    @State private var moodsAndGenresViewModel: MoodsAndGenresViewModel?
    @State private var newReleasesViewModel: NewReleasesViewModel?
    @State private var podcastsViewModel: PodcastsViewModel?
    @State private var likedMusicViewModel: LikedMusicViewModel?
    @State private var libraryViewModel: LibraryViewModel?

    /// Column visibility state for NavigationSplitView - persisted to fix restoration from dock.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init(navigationSelection: Binding<NavigationItem?>, client: any YTMusicClientProtocol) {
        self._navigationSelection = navigationSelection
        self.client = client
        _homeViewModel = State(initialValue: HomeViewModel(client: client))
        _exploreViewModel = State(initialValue: ExploreViewModel(client: client))
        _searchViewModel = State(initialValue: SearchViewModel(client: client))
        _chartsViewModel = State(initialValue: ChartsViewModel(client: client))
        _moodsAndGenresViewModel = State(initialValue: MoodsAndGenresViewModel(client: client))
        _newReleasesViewModel = State(initialValue: NewReleasesViewModel(client: client))
        _podcastsViewModel = State(initialValue: PodcastsViewModel(client: client))
        _likedMusicViewModel = State(initialValue: LikedMusicViewModel(client: client))
        _libraryViewModel = State(initialValue: LibraryViewModel(client: client))
    }

    /// Access to the app delegate for persistent WebView.
    private var appDelegate: AppDelegate? {
        NSApplication.shared.delegate as? AppDelegate
    }

    var body: some View {

        ZStack(alignment: .bottomTrailing) {
            Group {
                if self.authService.state.isInitializing {
                    // Show loading while checking login status to avoid onboarding flash
                    self.initializingView
                } else if self.authService.state.isLoggedIn {
                    self.mainContent
                } else {
                    OnboardingView()
                }
            }

            // Persistent WebView - always present once a video has been requested
            // Uses a SINGLETON WebView instance that persists for the app lifetime
            // Compact size (120x68) for first-time interaction, then hidden (1x1)
            if let videoId = playerService.pendingPlayVideoId {
                ZStack(alignment: .topTrailing) {
                    PersistentPlayerView(videoId: videoId, isExpanded: self.playerService.showMiniPlayer)
                        .frame(
                            width: self.playerService.showMiniPlayer ? 120 : 1,
                            height: self.playerService.showMiniPlayer ? 68 : 1
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .opacity(self.playerService.showMiniPlayer ? 0.95 : 0)

                    if self.playerService.showMiniPlayer {
                        Button {
                            self.playerService.confirmPlaybackStarted()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.8))
                                .shadow(radius: 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                        .padding(3)
                    }
                }
                .shadow(color: self.playerService.showMiniPlayer ? .black.opacity(0.2) : .clear, radius: 6, y: 3)
                .padding(.trailing, self.playerService.showMiniPlayer ? 12 : 0)
                .padding(.bottom, self.playerService.showMiniPlayer ? 76 : 0)
                .allowsHitTesting(self.playerService.showMiniPlayer)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: self.playerService.showMiniPlayer)
        .sheet(isPresented: self.$showLoginSheet) {
            LoginSheet()
        }
        .overlay {
            // Command bar overlay - dismisses when clicking outside
            if self.showCommandBarSheet {
                ZStack {
                    // Background tap area to dismiss
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            self.showCommandBarSheet = false
                        }

                    // Command bar centered
                    CommandBarView(client: self.client, isPresented: self.$showCommandBarSheet)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                .animation(.easeInOut(duration: 0.15), value: self.showCommandBarSheet)
            }
        }
        .overlay(alignment: .top) {
            // Error toast for account switching failures
            AccountErrorToast()
                .padding(.top, 60)
        }
        .onChange(of: self.showCommandBar.wrappedValue) { newValue in
            if newValue {
                self.showCommandBarSheet = true
                self.showCommandBar.wrappedValue = false
            }
        }
        .onChange(of: self.authService.state) { newState in
            self.handleAuthStateChange(oldState: self.authService.state, newState: newState)
        }
        .onChange(of: self.authService.needsReauth) { needsReauth in
            if needsReauth {
                self.showLoginSheet = true
            }
        }
        .onChange(of: self.playerService.isPlaying) { isPlaying in
            // Auto-hide the WebView once playback starts
            if isPlaying, self.playerService.showMiniPlayer {
                self.playerService.confirmPlaybackStarted()
            }
        }
        .onChange(of: self.playerService.showVideo) { showVideo in
            DiagnosticsLogger.player.debug("showVideo onChange triggered: \(showVideo)")
            if showVideo {
                VideoWindowController.shared.show(
                    playerService: self.playerService,
                    webKitManager: self.webKitManager
                )
            } else {
                VideoWindowController.shared.close()
            }
        }
        .onChange(of: self.accountService.currentAccount?.id) { newAccountId in
            // Refresh all content when user switches accounts
            guard newAccountId != nil else { return }
            DiagnosticsLogger.auth.info("Account switched, refreshing content...")
            // Clear API cache to ensure fresh data for new account
            Task { @MainActor in
                APICache.shared.invalidateAll()
                URLCache.shared.removeAllCachedResponses()
                await self.refreshAllContent()
            }
        }
        .task {
            NowPlayingManager.shared.configure(playerService: self.playerService)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ZStack(alignment: .trailing) {
            // Main navigation content
            NavigationSplitView(columnVisibility: self.$columnVisibility) {
                Sidebar(selection: self.$navigationSelection)
            } detail: {
                ZStack(alignment: .bottom) {
                    self.detailView(for: self.navigationSelection, client: self.client)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            Color.clear.frame(height: 76) // Space for PlayerBar
                        }

                    if self.playerService.showLyrics {
                        LyricsView(client: self.client)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(1)
                    }

                    PlayerBar()
                        .zIndex(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                // Ensure sidebar is visible when window becomes key (e.g., restored from dock)
                if self.columnVisibility != .all {
                    self.columnVisibility = .all
                }
            }

            // Right sidebar overlay - ONLY queue now
            self.rightSidebarOverlay(client: self.client)
        }
        .animation(.easeInOut(duration: 0.25), value: self.playerService.showLyrics)
        .animation(.easeInOut(duration: 0.25), value: self.playerService.showQueue)
        .frame(minWidth: 900, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    self.showCommandBarSheet = true
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                }
                .keyboardShortcut("k", modifiers: .command)
                .help("Ask AI (⌘K)")
                .accessibilityIdentifier(AccessibilityID.MainWindow.aiButton)
                .requiresIntelligence()
            }
        }
    }

    /// Right sidebar overlay showing queue as a glass panel.
    @ViewBuilder
    private func rightSidebarOverlay(client: any YTMusicClientProtocol) -> some View {
        if self.playerService.showQueue {
            VStack(spacing: 0) {
                Group {
                    if self.playerService.queueDisplayMode == .sidepanel {
                        QueueSidePanelView()
                    } else {
                        QueueView()
                    }
                }
                .frame(maxHeight: .infinity)
                .transition(.move(edge: .trailing).combined(with: .opacity))

                // Space for PlayerBar so the queue doesn't underlap
                Color.clear.frame(height: 76)
            }
            .frame(maxWidth: 400) // Constrain width to prevent covering the left navigation sidebar
        }
    }

    private func detailView(for item: NavigationItem?, client _: any YTMusicClientProtocol) -> some View {
        Group {
            if let item {
                self.viewForNavigationItem(item)
            } else {
                Text("Select an item from the sidebar")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Returns the view for a specific navigation item.
    private func viewForNavigationItem(_ item: NavigationItem) -> some View { // swiftlint:disable:this cyclomatic_complexity
        Group {
            switch item {
            case .home:
                if let vm = homeViewModel { HomeView(viewModel: vm) }
            case .explore:
                if let vm = exploreViewModel { ExploreView(viewModel: vm) }
            case .search:
                if let vm = searchViewModel { SearchView(viewModel: vm) }
            case .charts:
                if let vm = chartsViewModel { ChartsView(viewModel: vm) }
            case .moodsAndGenres:
                if let vm = moodsAndGenresViewModel { MoodsAndGenresView(viewModel: vm) }
            case .newReleases:
                if let vm = newReleasesViewModel { NewReleasesView(viewModel: vm) }
            case .podcasts:
                if let vm = podcastsViewModel { PodcastsView(viewModel: vm) }
            case .likedMusic:
                if let vm = likedMusicViewModel { LikedMusicView(viewModel: vm) }
            case .library:
                if let vm = libraryViewModel { LibraryView(viewModel: vm) }
            }
        }
        .environmentObject(self.libraryViewModel!)
    }

    /// View shown while checking initial login status.
    private var initializingView: some View {
        VStack(spacing: 16) {
            CassetteIcon(size: 60)
                .foregroundStyle(.tint)
            ProgressView()
                .controlSize(.regular)
                .frame(width: 20, height: 20)
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func handleAuthStateChange(oldState: AuthService.State, newState: AuthService.State) {
        switch newState {
        case .initializing:
            // Still checking login status, do nothing
            break
        case .loggedOut:
            // Onboarding view handles login, no need to auto-show sheet
            self.accountService.clearAccounts()
        case .loggingIn:
            self.showLoginSheet = true
        case .loggedIn:
            self.showLoginSheet = false
            Task {
                await self.accountService.fetchAccounts()
            }
            // If we just completed login (transitioning from loggingIn), refresh content
            // This handles the case where cookies weren't ready during initial load
            if case .loggingIn = oldState {
                Task {
                    // Brief delay to ensure cookies are fully propagated in WebKit
                    try? await Task.sleep(for: .milliseconds(500))

                    // Parallel initial data fetch for ~40% faster app launch
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask { await self.homeViewModel?.refresh() }
                        group.addTask { await self.exploreViewModel?.refresh() }
                        group.addTask { await self.libraryViewModel?.load() }
                    }
                }
            }
        }
    }

    /// Refreshes all content when switching accounts.
    ///
    /// This method is called when the user switches between their primary account
    /// and brand accounts, ensuring all views display content for the new account.
    private func refreshAllContent() async {
        // Parallel refresh of all content views
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.homeViewModel?.refresh() }
            group.addTask { await self.exploreViewModel?.refresh() }
            group.addTask { await self.chartsViewModel?.refresh() }
            group.addTask { await self.moodsAndGenresViewModel?.refresh() }
            group.addTask { await self.newReleasesViewModel?.refresh() }
            group.addTask { await self.podcastsViewModel?.refresh() }
            group.addTask { await self.likedMusicViewModel?.refresh() }
            group.addTask { await self.libraryViewModel?.refresh() }
        }
    }
}

// MARK: - NavigationItem

enum NavigationItem: String, Hashable, CaseIterable, Identifiable {
    case home = "Home"
    case explore = "Explore"
    case search = "Search"
    case charts = "Charts"
    case moodsAndGenres = "Moods & Genres"
    case newReleases = "New Releases"
    case podcasts = "Podcasts"
    case likedMusic = "Liked Music"
    case library = "Library"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .home:
            "house"
        case .explore:
            "globe"
        case .search:
            "magnifyingglass"
        case .charts:
            "chart.line.uptrend.xyaxis"
        case .moodsAndGenres:
            "theatermask.and.paintbrush"
        case .newReleases:
            "sparkles"
        case .podcasts:
            "mic.fill"
        case .likedMusic:
            "heart.fill"
        case .library:
            "square.stack.fill"
        }
    }
}


#if false
#if false
#Preview {
    let authService = AuthService()
    let ytMusicClient = YTMusicClient(authService: authService)
    let accountService = AccountService(ytMusicClient: ytMusicClient, authService: authService)
    return MainWindow(navigationSelection: .constant(.home), client: ytMusicClient)
        .environmentObject(authService)
        .environmentObject(PlayerService())
        .environmentObject(WebKitManager.shared)
        .environmentObject(accountService)
}
#endif
#endif
