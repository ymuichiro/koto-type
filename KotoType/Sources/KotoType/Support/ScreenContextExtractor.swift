import Foundation
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

        let recognizedStrings = observations.compactMap { $0.topCandidates(1).first?.string }
        guard let compressed = compressRecognizedTextHints(recognizedStrings, maxLength: maxLength) else {
            return nil
        }

        Logger.shared.log("ScreenContextExtractor: captured text context (\(compressed.count) chars)", level: .info)
        return compressed
    }

    static func compressRecognizedTextHints(_ recognizedStrings: [String], maxLength: Int = 500) -> String? {
        let normalizedSegments = recognizedStrings
            .map(normalizeSegment(_:))
            .filter { !$0.isEmpty }

        guard !normalizedSegments.isEmpty else {
            return nil
        }

        let rankedHints = rankedHints(from: normalizedSegments)
        let hintSource = rankedHints.isEmpty ? fallbackHints(from: normalizedSegments) : rankedHints
        let compressed = joinHints(hintSource, maxLength: maxLength)
        return compressed.isEmpty ? nil : compressed
    }

    private static func normalizeSegment(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rankedHints(from segments: [String]) -> [String] {
        var scores: [String: Int] = [:]
        var displayValues: [String: String] = [:]

        for segment in segments {
            if shouldKeepWholeSegment(segment) {
                recordCandidate(
                    segment,
                    score: baseScore(for: segment) + 3,
                    scores: &scores,
                    displayValues: &displayValues
                )
            }

            for token in extractedTokens(from: segment) {
                recordCandidate(
                    token,
                    score: baseScore(for: token),
                    scores: &scores,
                    displayValues: &displayValues
                )
            }
        }

        return scores.keys.sorted { lhs, rhs in
            let leftScore = scores[lhs, default: 0]
            let rightScore = scores[rhs, default: 0]
            if leftScore != rightScore {
                return leftScore > rightScore
            }
            let leftText = displayValues[lhs, default: lhs]
            let rightText = displayValues[rhs, default: rhs]
            if leftText.count != rightText.count {
                return leftText.count < rightText.count
            }
            return leftText.localizedCaseInsensitiveCompare(rightText) == .orderedAscending
        }
        .compactMap { displayValues[$0] }
    }

    private static func recordCandidate(
        _ candidate: String,
        score: Int,
        scores: inout [String: Int],
        displayValues: inout [String: String]
    ) {
        let normalized = candidate
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !normalized.isEmpty else {
            return
        }
        scores[normalized, default: 0] += score
        if displayValues[normalized] == nil {
            displayValues[normalized] = candidate
        }
    }

    private static func baseScore(for candidate: String) -> Int {
        var score = 1
        if candidate.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil {
            score += 1
        }
        if candidate.rangeOfCharacter(from: CharacterSet.uppercaseLetters) != nil {
            score += 1
        }
        if candidate.rangeOfCharacter(from: CharacterSet(charactersIn: "/._-:#")) != nil {
            score += 2
        }
        if containsNonASCII(candidate) {
            score += 2
        }
        if hasMixedCase(candidate) {
            score += 1
        }
        return score
    }

    private static func shouldKeepWholeSegment(_ segment: String) -> Bool {
        guard segment.count <= 48 else {
            return false
        }
        if looksSentenceLike(segment) {
            return false
        }
        let words = segment.split(whereSeparator: \.isWhitespace)
        return words.count <= 6
    }

    private static func looksSentenceLike(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        if words.count >= 8 {
            return true
        }
        if containsNonASCII(text), text.count > 18 {
            return true
        }
        if text.count > 40, text.contains(",") {
            return true
        }
        if text.count > 32, text.contains("。") {
            return true
        }
        return false
    }

    private static func extractedTokens(from segment: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "[\\p{L}\\p{N}][\\p{L}\\p{N}._/+:#-]*", options: []) else {
            return []
        }

        let nsRange = NSRange(segment.startIndex..<segment.endIndex, in: segment)
        return regex.matches(in: segment, options: [], range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: segment) else {
                return nil
            }
            let token = String(segment[range]).trimmingCharacters(in: .punctuationCharacters)
            guard shouldKeepToken(token) else {
                return nil
            }
            return token
        }
    }

    private static func shouldKeepToken(_ token: String) -> Bool {
        guard token.count >= 2 else {
            return false
        }
        guard token.rangeOfCharacter(from: CharacterSet.letters.union(.decimalDigits)) != nil else {
            return false
        }
        let lowercased = token.lowercased()
        let stopwords: Set<String> = [
            "the", "and", "for", "with", "from", "this", "that", "your", "into",
            "menu", "window", "button", "click", "open", "close", "please"
        ]
        if stopwords.contains(lowercased) {
            return false
        }
        if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: token)) {
            return false
        }
        if containsNonASCII(token), token.count > 18 {
            return false
        }
        return true
    }

    private static func fallbackHints(from segments: [String]) -> [String] {
        Array(segments.prefix(6))
    }

    private static func joinHints(_ hints: [String], maxLength: Int) -> String {
        guard maxLength > 0 else {
            return ""
        }

        var result = ""
        var seen = Set<String>()
        for hint in hints {
            let normalized = hint.lowercased()
            guard seen.insert(normalized).inserted else {
                continue
            }
            let candidate = result.isEmpty ? hint : "\(result) | \(hint)"
            if candidate.count > maxLength {
                break
            }
            result = candidate
        }
        return result
    }

    private static func containsNonASCII(_ value: String) -> Bool {
        value.unicodeScalars.contains { $0.value > 127 }
    }

    private static func hasMixedCase(_ value: String) -> Bool {
        value.rangeOfCharacter(from: .lowercaseLetters) != nil
            && value.rangeOfCharacter(from: .uppercaseLetters) != nil
    }
}
