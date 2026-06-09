import Foundation

enum RecordingRequestMode: String, Codable, CaseIterable, Equatable, Sendable {
    case transcribe
    case translate
}
