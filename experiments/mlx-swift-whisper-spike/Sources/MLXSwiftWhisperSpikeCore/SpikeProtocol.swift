import Foundation

public enum SpikeRequest: Equatable {
    case healthCheck(token: String)
    case transcription(audioPath: String, mode: String)
}

public enum SpikeProtocolError: Error, Equatable {
    case malformedJSON
    case unsupportedRequestType
}

public enum SpikeProtocol {
    public static let healthCheckRequestPrefix = "__KOTOTYPE_HEALTHCHECK__:"
    public static let healthCheckResponsePrefix = "__KOTOTYPE_HEALTHCHECK_OK__:"

    public static func parse(line: String) throws -> SpikeRequest? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix(healthCheckRequestPrefix) {
            return .healthCheck(token: String(trimmed.dropFirst(healthCheckRequestPrefix.count)))
        }

        guard let data = trimmed.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = payload["type"] as? String else {
            throw SpikeProtocolError.malformedJSON
        }

        guard type == "transcription_request" else {
            throw SpikeProtocolError.unsupportedRequestType
        }

        return .transcription(
            audioPath: payload["audio_path"] as? String ?? "",
            mode: payload["mode"] as? String ?? "transcribe"
        )
    }
}
