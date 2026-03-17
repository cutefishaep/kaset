#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// A tool that allows the language model to control the playback queue.
struct QueueTool: Tool {
    var name: String = "queue_control"
    var description: String = "Add songs to the queue."
    
    func execute(videoId: String) async throws -> String {
        return "Added to queue"
    }
}
#endif
