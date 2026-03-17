import Foundation
import CommonCrypto

// MARK: - SyncedLyricsService

@MainActor
final class SyncedLyricsService {
    static let shared = SyncedLyricsService()

    private let logger = DiagnosticsLogger.api
    private let urlSession: URLSession

    // In-memory cache to retain lyrics when view is closed and reopened
    private var cache: [String: SyncedLyrics] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.urlSession = URLSession(configuration: config)
    }

    /// Fetches synced lyrics for a given song.
    /// Uses the preferred provider from SettingsManager. Falls back to the alternative if it fails.
    func fetchLyrics(for song: Song) async throws -> SyncedLyrics {
        if let cached = self.cache[song.videoId] {
            self.logger.info("Returning cached synced lyrics for: \\(song.title)")
            return cached
        }

        self.logger.info("Fetching synced lyrics for: \\(song.title) (videoId: \\(song.videoId))")

        let preferredProvider = SettingsManager.shared.lyricsProvider
        let offset = SettingsManager.shared.lyricsOffset

        do {
            switch preferredProvider {
            case .simpmusic:
                if let lrc = try await self.fetchFromSimpMusic(videoId: song.videoId) {
                    self.logger.info("Successfully fetched lyrics from SimpMusic")
                    let parsed = SyncedLyrics.parse(lrc: lrc, offset: offset)
                    self.cache[song.videoId] = parsed
                    return parsed
                }
            case .lrclib:
                if let lrc = try await self.fetchFromLRCLIB(song: song) {
                    self.logger.info("Successfully fetched lyrics from LRCLIB")
                    let parsed = SyncedLyrics.parse(lrc: lrc, offset: offset)
                    self.cache[song.videoId] = parsed
                    return parsed
                }
            }
        } catch {
            self.logger.warning("\\(preferredProvider.rawValue) API failed: \\(error.localizedDescription), trying fallback")
        }

        // Fallback strategy
        if preferredProvider == .simpmusic {
            if let lrc = try? await self.fetchFromLRCLIB(song: song) {
                self.logger.info("Successfully fetched lyrics from LRCLIB (Fallback)")
                let parsed = SyncedLyrics.parse(lrc: lrc, offset: offset)
                self.cache[song.videoId] = parsed
                return parsed
            }
        } else {
            if let lrc = try? await self.fetchFromSimpMusic(videoId: song.videoId) {
                self.logger.info("Successfully fetched lyrics from SimpMusic (Fallback)")
                let parsed = SyncedLyrics.parse(lrc: lrc, offset: offset)
                self.cache[song.videoId] = parsed
                return parsed
            }
        }

        self.logger.info("No synced lyrics found for \\(song.title)")
        self.cache[song.videoId] = .unavailable
        return .unavailable
    }

    // MARK: - SimpMusic API

    private func fetchFromSimpMusic(videoId: String) async throws -> String? {
        let urlString = "https://api-lyrics.simpmusic.org/v1/lyrics/\\(videoId)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Kaset/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await self.urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode == 429 {
            throw URLError(.resourceUnavailable) // Trigger fallback
        } else if httpResponse.statusCode == 404 {
            return nil
        } else if httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }

        struct ResponseBody: Decodable {
            let syncedLyrics: String?
        }
        
        let decoder = JSONDecoder()
        do {
            let body = try decoder.decode(ResponseBody.self, from: data)
            return body.syncedLyrics
        } catch {
            // Also try plain string if API returns purely text (unlikely based on docs, but good to be safe)
            if let string = String(data: data, encoding: .utf8), string.contains("[") {
                return string
            }
            throw error
        }
    }

    // MARK: - LRCLIB API Fallback

    private func fetchFromLRCLIB(song: Song) async throws -> String? {
        // Need to construct URL components
        guard var components = URLComponents(string: "https://lrclib.net/api/get") else {
            return nil
        }
        
        var queryItems = [
            URLQueryItem(name: "track_name", value: song.title)
        ]
        
        if let artist = song.artists.first?.name {
            queryItems.append(URLQueryItem(name: "artist_name", value: artist))
        }
        
        if let album = song.album?.title {
            queryItems.append(URLQueryItem(name: "album_name", value: album))
        }
        
        if let duration = song.duration {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(duration))))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.setValue("Kaset (https://github.com/sertacozercan/Kaset)", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await self.urlSession.data(for: request)
        
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            return nil
        }
        
        struct LRCLIBResponse: Decodable {
            let syncedLyrics: String?
        }
        
        let decoded = try JSONDecoder().decode(LRCLIBResponse.self, from: data)
        return decoded.syncedLyrics
    }
}
