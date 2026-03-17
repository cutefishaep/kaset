#if canImport(FoundationModels)
import FoundationModels
#endif
import SwiftUI

// MARK: - FoundationModelsService

/// Service for managing Apple Foundation Models integration.
@MainActor
final class FoundationModelsService: ObservableObject {
    static let shared = FoundationModelsService()

    @Published private(set) var isWarmedUp: Bool = false
    @Published var isDisabledByUser: Bool = false {
        didSet {
            UserDefaults.standard.set(self.isDisabledByUser, forKey: Self.disabledKey)
            NotificationCenter.default.post(name: .intelligenceAvailabilityChanged, object: nil)
        }
    }

    var isAvailable: Bool {
        #if canImport(FoundationModels)
        guard !self.isDisabledByUser else { return false }
        // Simplification for Swift 5.8 - we'll just check if it can be imported for now
        // A real implementation would check system availability
        return true
        #else
        return false
        #endif
    }

    private let logger = DiagnosticsLogger.ai
    private static let disabledKey = "intelligence.disabled"

    private init() {
        self.isDisabledByUser = UserDefaults.standard.bool(forKey: Self.disabledKey)
    }

    func warmup() async {
        self.logger.info("Starting Foundation Models warmup (stub for macOS 13)")
        self.isWarmedUp = true
    }

    #if canImport(FoundationModels)
    func createCommandSession(instructions: String, tools: [any Tool]) -> LanguageModelSession? {
        guard self.isAvailable else { return nil }
        return LanguageModelSession(tools: tools, instructions: instructions)
    }
    #endif
}
