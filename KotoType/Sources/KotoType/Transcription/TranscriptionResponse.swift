import Foundation

struct TranscriptionResponse: Decodable {
    let type: String
    let request_id: String
    let text: String?
    let error: String?

    static func parse(_ line: String) -> TranscriptionResponse? {
        let prefix = PythonProcessManager.controlMessagePrefix
        guard line.hasPrefix(prefix),
              let data = String(line.dropFirst(prefix.count)).data(using: .utf8),
              let response = try? JSONDecoder().decode(Self.self, from: data),
              response.type == "transcription_result",
              !response.request_id.isEmpty,
              response.request_id.count <= 64,
              response.request_id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
              (response.text == nil) != (response.error == nil) else { return nil }
        return response
    }
}
