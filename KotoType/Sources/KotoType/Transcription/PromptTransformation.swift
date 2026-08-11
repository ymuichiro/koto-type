import Foundation

struct PromptTransformationResult: Codable, Equatable, Sendable {
    let rawTranscript: String
    let promptMarkdown: String
    let usedFallback: Bool
}
