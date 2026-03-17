import Combine
import Foundation

/// View model for a moods/genres category detail view.
@MainActor
final class MoodCategoryViewModel: ObservableObject {
    /// Current loading state.
    @Published private(set) var loadingState: LoadingState = .idle

    /// Sections of content for this category.
    @Published private(set) var sections: [HomeSection] = []

    /// The category being displayed.
    let category: MoodCategory

    /// The API client.
    let client: any YTMusicClientProtocol
    private let logger = DiagnosticsLogger.api

    init(category: MoodCategory, client: any YTMusicClientProtocol) {
        self.category = category
        self.client = client
    }

    /// Loads the category content.
    func load() async {
        guard self.loadingState != .loading else { return }

        self.loadingState = .loading
        let title = self.category.title
        self.logger.info("Loading mood category: \(title)")

        do {
            let response = try await client.getMoodCategory(
                browseId: self.category.browseId,
                params: self.category.params
            )
            self.sections = response.sections
            self.loadingState = .loaded
            let sectionCount = self.sections.count
            self.logger.info("Mood category '\(title)' loaded: \(sectionCount) sections")
        } catch is CancellationError {
            self.logger.kasetDebug("Mood category load cancelled")
            self.loadingState = .idle
        } catch {
            self.logger.error("Failed to load mood category: \(error.localizedDescription)")
            self.loadingState = .error(LoadingError(from: error))
        }
    }

    /// Refreshes the category content.
    func refresh() async {
        self.sections = []
        await self.load()
    }
}
