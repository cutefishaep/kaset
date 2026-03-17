import Combine
import Foundation

/// Manages user preferences persisted via UserDefaults.
@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // MARK: - Settings Keys

    private enum Keys {
        static let showNowPlayingNotifications = "settings.showNowPlayingNotifications"
        static let defaultLaunchPage = "settings.defaultLaunchPage"
        static let hapticFeedbackEnabled = "settings.hapticFeedbackEnabled"
        static let rememberPlaybackSettings = "settings.rememberPlaybackSettings"
        static let lastFMEnabled = "settings.lastFMEnabled"
        static let enabledServices = "settings.enabledServices"
        static let scrobblePercentThreshold = "settings.scrobblePercentThreshold"
        static let scrobbleMinSeconds = "settings.scrobbleMinSeconds"

        // Lyrics & AdBlock
        static let adBlockEnabled = "settings.adBlockEnabled"
        static let lyricsProvider = "settings.lyricsProvider"
        static let lyricsOffset = "settings.lyricsOffset"
        static let lyricsFontSize = "settings.lyricsFontSize"
    }

    // MARK: - Providers

    enum LyricsProvider: String, CaseIterable, Identifiable {
        case simpmusic = "SimpMusic"
        case lrclib = "LRCLIB"
        
        var id: String { rawValue }
    }

    // MARK: - Launch Page Options

    /// Available pages to launch the app with.
    enum LaunchPage: String, CaseIterable, Identifiable {
        case home
        case explore
        case charts
        case moodsAndGenres
        case newReleases
        case likedMusic
        case playlists
        case lastUsed

        var id: String {
            rawValue
        }

        var displayName: String {
            switch self {
            case .home: "Home"
            case .explore: "Explore"
            case .charts: "Charts"
            case .moodsAndGenres: "Moods & Genres"
            case .newReleases: "New Releases"
            case .likedMusic: "Liked Music"
            case .playlists: "Playlists"
            case .lastUsed: "Last Used"
            }
        }

        /// Converts LaunchPage to NavigationItem for navigation.
        var navigationItem: NavigationItem {
            switch self {
            case .home: .home
            case .explore: .explore
            case .charts: .charts
            case .moodsAndGenres: .moodsAndGenres
            case .newReleases: .newReleases
            case .likedMusic: .likedMusic
            case .playlists: .library
            case .lastUsed: .home // Fallback, actual value comes from lastUsedPage
            }
        }
    }

    // MARK: - Settings Properties

    /// Whether to show system notifications when the track changes.
    @Published var showNowPlayingNotifications: Bool {
        didSet {
            UserDefaults.standard.set(self.showNowPlayingNotifications, forKey: Keys.showNowPlayingNotifications)
        }
    }

    /// The default page to show when the app launches.
    @Published var defaultLaunchPage: LaunchPage {
        didSet {
            UserDefaults.standard.set(self.defaultLaunchPage.rawValue, forKey: Keys.defaultLaunchPage)
        }
    }

    /// Whether haptic feedback is enabled.
    @Published var hapticFeedbackEnabled: Bool {
        didSet {
            UserDefaults.standard.set(self.hapticFeedbackEnabled, forKey: Keys.hapticFeedbackEnabled)
        }
    }

    /// Whether to remember shuffle/repeat settings across app restarts.
    @Published var rememberPlaybackSettings: Bool {
        didSet {
            UserDefaults.standard.set(self.rememberPlaybackSettings, forKey: Keys.rememberPlaybackSettings)
            // Clear stale values when setting is disabled to prevent unexpected restoration
            if !self.rememberPlaybackSettings {
                UserDefaults.standard.removeObject(forKey: "playerShuffleEnabled")
                UserDefaults.standard.removeObject(forKey: "playerRepeatMode")
            }
        }
    }

    /// Per-service enabled flags stored as a dictionary.
    @Published private var enabledServices: [String: Bool] {
        didSet {
            UserDefaults.standard.set(self.enabledServices, forKey: Keys.enabledServices)
        }
    }

    /// Whether a specific scrobbling service is enabled by name.
    func isServiceEnabled(_ serviceName: String) -> Bool {
        self.enabledServices[serviceName] ?? false
    }

    /// Sets the enabled state for a specific scrobbling service by name.
    func setServiceEnabled(_ serviceName: String, _ enabled: Bool) {
        self.enabledServices[serviceName] = enabled
    }

    /// Whether Last.fm scrobbling is enabled (backward-compatible convenience).
    var lastFMEnabled: Bool {
        get { self.isServiceEnabled("Last.fm") }
        set { self.setServiceEnabled("Last.fm", newValue) }
    }

    /// Percentage of track duration required before scrobbling (0.0–1.0).
    @Published var scrobblePercentThreshold: Double {
        didSet {
            UserDefaults.standard.set(self.scrobblePercentThreshold, forKey: Keys.scrobblePercentThreshold)
        }
    }

    /// Minimum seconds of play time before scrobbling (overrides percentage for long tracks).
    @Published var scrobbleMinSeconds: TimeInterval {
        didSet {
            UserDefaults.standard.set(self.scrobbleMinSeconds, forKey: Keys.scrobbleMinSeconds)
        }
    }

    /// The last page the user was on (for "Last Used" option).
    @Published var lastUsedPage: LaunchPage = .home

    // MARK: - New Settings 
    
    @Published var adBlockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(self.adBlockEnabled, forKey: Keys.adBlockEnabled)
        }
    }

    @Published var lyricsProvider: LyricsProvider {
        didSet {
            UserDefaults.standard.set(self.lyricsProvider.rawValue, forKey: Keys.lyricsProvider)
        }
    }

    @Published var lyricsOffset: Double {
        didSet {
            UserDefaults.standard.set(self.lyricsOffset, forKey: Keys.lyricsOffset)
        }
    }

    /// Size of the lyrics font
    @Published var lyricsFontSize: Double {
        didSet {
            UserDefaults.standard.set(self.lyricsFontSize, forKey: Keys.lyricsFontSize)
        }
    }

    // MARK: - Initialization

    private init() {
        // Load persisted settings or use defaults
        self.showNowPlayingNotifications = UserDefaults.standard.object(forKey: Keys.showNowPlayingNotifications) as? Bool ?? true
        self.hapticFeedbackEnabled = UserDefaults.standard.object(forKey: Keys.hapticFeedbackEnabled) as? Bool ?? true
        self.rememberPlaybackSettings = UserDefaults.standard.object(forKey: Keys.rememberPlaybackSettings) as? Bool ?? false

        // Load per-service enabled flags, migrating from legacy lastFMEnabled if needed
        if let stored = UserDefaults.standard.dictionary(forKey: Keys.enabledServices) as? [String: Bool] {
            self.enabledServices = stored
        } else if let legacyEnabled = UserDefaults.standard.object(forKey: Keys.lastFMEnabled) as? Bool {
            // Migrate from single-service flag to dictionary
            self.enabledServices = ["Last.fm": legacyEnabled]
        } else {
            self.enabledServices = [:]
        }
        self.scrobblePercentThreshold = UserDefaults.standard.object(forKey: Keys.scrobblePercentThreshold) as? Double ?? 0.5
        self.scrobbleMinSeconds = UserDefaults.standard.object(forKey: Keys.scrobbleMinSeconds) as? Double ?? 240

        if let rawValue = UserDefaults.standard.string(forKey: Keys.defaultLaunchPage),
           let page = LaunchPage(rawValue: rawValue)
        {
            self.defaultLaunchPage = page
        } else {
            self.defaultLaunchPage = .home
        }

        self.adBlockEnabled = UserDefaults.standard.object(forKey: Keys.adBlockEnabled) as? Bool ?? true
        
        if let providerRaw = UserDefaults.standard.string(forKey: Keys.lyricsProvider),
           let provider = LyricsProvider(rawValue: providerRaw) {
            self.lyricsProvider = provider
        } else {
            self.lyricsProvider = .simpmusic
        }

        self.lyricsOffset = UserDefaults.standard.object(forKey: Keys.lyricsOffset) as? Double ?? -1.5
        self.lyricsFontSize = UserDefaults.standard.object(forKey: Keys.lyricsFontSize) as? Double ?? 28.0

        // Persist migration from legacy lastFMEnabled key (must run after all properties initialized)
        if UserDefaults.standard.object(forKey: Keys.enabledServices) == nil,
           UserDefaults.standard.object(forKey: Keys.lastFMEnabled) != nil
        {
            UserDefaults.standard.set(self.enabledServices, forKey: Keys.enabledServices)
            UserDefaults.standard.removeObject(forKey: Keys.lastFMEnabled)
        }
    }

    // MARK: - Computed Properties

    /// Returns the page to navigate to on launch based on settings.
    var launchPage: LaunchPage {
        switch self.defaultLaunchPage {
        case .lastUsed:
            self.lastUsedPage
        default:
            self.defaultLaunchPage
        }
    }

    /// Returns the NavigationItem to use on app launch.
    var launchNavigationItem: NavigationItem {
        self.launchPage.navigationItem
    }
}
