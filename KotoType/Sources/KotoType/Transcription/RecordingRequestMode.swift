import Foundation

enum RecordingRequestMode: String, Codable, CaseIterable, Equatable, Sendable {
    case transcribe
    case faithful
    case prompt
    case translate

    var displayName: String {
        switch self {
        case .transcribe:
            return "Fast transcription"
        case .faithful:
            return "Faithful transcription"
        case .prompt:
            return "AI Markdown prompt"
        case .translate:
            return "Translation"
        }
    }

    var summary: String {
        switch self {
        case .transcribe:
            return "Fast, lightly punctuated text inserted directly."
        case .faithful:
            return "Preserves the spoken wording and disables punctuation rewriting."
        case .prompt:
            return "Converts the transcript into editable Markdown for another AI."
        case .translate:
            return "Translates the spoken content into the configured target language."
        }
    }
}
