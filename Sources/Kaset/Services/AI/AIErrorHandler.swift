#if canImport(FoundationModels)
import Foundation
import FoundationModels

// MARK: - AIError

/// User-friendly errors for AI operations.
enum AIError: LocalizedError {
    case general(String)
}

enum AIErrorHandler {
    static func handle(_ error: Error) -> AIError {
        .general(error.localizedDescription)
    }
}
#endif
