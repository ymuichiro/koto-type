import CoreGraphics
import Vision

enum ScreenContextExtractor {
    static func captureScreenTextContext(maxLength: Int = 500) -> String? {
        if #available(macOS 10.15, *) {
            guard CGPreflightScreenCaptureAccess() else {
                Logger.shared.log("ScreenContextExtractor: screen capture permission is not granted", level: .warning)
                return nil
            }
        }

        guard let image = CGWindowListCreateImage(
            .infinite,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            Logger.shared.log("ScreenContextExtractor: failed to capture screen image", level: .warning)
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        do {
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
        } catch {
            Logger.shared.log("ScreenContextExtractor: text recognition failed: \(error)", level: .warning)
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else {
            Logger.shared.log("ScreenContextExtractor: no text found in screenshot", level: .debug)
            return nil
        }

        let rawText = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")

        let normalized = rawText
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return nil
        }

        let clipped = String(normalized.prefix(maxLength))
        Logger.shared.log("ScreenContextExtractor: captured text context (\(clipped.count) chars)", level: .info)
        return clipped
    }
}
