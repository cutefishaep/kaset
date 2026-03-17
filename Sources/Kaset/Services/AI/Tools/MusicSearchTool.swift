#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// A tool that allows the language model to search the YouTube Music catalog.
struct MusicSearchTool: Tool {
    var name: String = "music_search"
    var description: String = "Search for music on YouTube Music."
    
    func execute(query: String) async throws -> String {
        return "Search result"
    }
}
#endif
