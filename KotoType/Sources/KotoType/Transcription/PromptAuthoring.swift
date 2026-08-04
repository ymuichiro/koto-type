import Foundation

enum PromptDraftFormat: String, CaseIterable, Codable, Equatable, Sendable {
    case cleanPrompt
    case structuredPrompt

    var displayName: String {
        switch self {
        case .cleanPrompt:
            return "Clean Prompt"
        case .structuredPrompt:
            return "Structured Prompt"
        }
    }
}

struct PromptDialogueTurn: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let rawTranscript: String
    let assistantResponse: String

    init(
        id: UUID = UUID(),
        rawTranscript: String,
        assistantResponse: String
    ) {
        self.id = id
        self.rawTranscript = rawTranscript
        self.assistantResponse = assistantResponse
    }
}

struct PromptAuthoringState: Equatable, Sendable {
    var format: PromptDraftFormat
    var rawTranscripts: [String]
    var dialogue: [PromptDialogueTurn]
    var draft: String
    var assistantResponse: String
    var pendingQuestion: String

    static func initial(format: PromptDraftFormat = .structuredPrompt) -> PromptAuthoringState {
        PromptAuthoringState(
            format: format,
            rawTranscripts: [],
            dialogue: [],
            draft: "",
            assistantResponse: "Speak a turn and I will help shape the prompt.",
            pendingQuestion: "What should the other AI accomplish?"
        )
    }
}

struct PromptAuthoringTurnResult: Equatable, Sendable {
    let state: PromptAuthoringState
    let acceptedTranscript: String?
    let validationPassed: Bool
}

enum PromptAuthoringEngine {
    private static let structuredSections = [
        ("Goal", "What should the other AI accomplish?"),
        ("Background", "What background, audience, or situation should it know?"),
        ("Constraints", "What constraints, exclusions, or required details matter?"),
        ("Inputs", "What inputs, examples, or source material will it receive?"),
        ("Expected Output", "What should the final answer look like?"),
        ("Unknowns", "What is still unknown or intentionally left open?"),
    ]

    private static let cleanQuestions = [
        "What should the other AI accomplish, and who is it for?",
        "What background or context should it know?",
        "What constraints, inputs, or examples should it respect?",
        "What should the final answer look like?",
    ]

    static func applyTurn(
        to state: PromptAuthoringState,
        transcript: String
    ) -> PromptAuthoringTurnResult {
        let normalizedTranscript = normalizeTranscript(transcript)
        guard !normalizedTranscript.isEmpty else {
            var unchanged = state
            unchanged.assistantResponse = "I did not receive a usable transcript. Please try that turn again."
            unchanged.pendingQuestion = state.pendingQuestion
            return PromptAuthoringTurnResult(
                state: unchanged,
                acceptedTranscript: nil,
                validationPassed: validate(unchanged)
            )
        }

        let rawTranscripts = state.rawTranscripts + [normalizedTranscript]
        let draft = buildDraft(format: state.format, rawTranscripts: rawTranscripts)
        let nextQuestion = nextQuestion(
            format: state.format,
            turnCount: rawTranscripts.count
        )
        let assistantResponse = nextQuestion
        let turn = PromptDialogueTurn(
            rawTranscript: normalizedTranscript,
            assistantResponse: assistantResponse
        )
        let nextState = PromptAuthoringState(
            format: state.format,
            rawTranscripts: rawTranscripts,
            dialogue: state.dialogue + [turn],
            draft: draft,
            assistantResponse: assistantResponse,
            pendingQuestion: nextQuestion
        )
        return PromptAuthoringTurnResult(
            state: nextState,
            acceptedTranscript: normalizedTranscript,
            validationPassed: validate(nextState)
        )
    }

    static func changingFormat(
        _ format: PromptDraftFormat,
        for state: PromptAuthoringState
    ) -> PromptAuthoringState {
        var updated = state
        updated.format = format
        updated.draft = buildDraft(format: format, rawTranscripts: state.rawTranscripts)
        updated.pendingQuestion = nextQuestion(format: format, turnCount: state.rawTranscripts.count)
        updated.assistantResponse = state.dialogue.last?.assistantResponse
            ?? PromptAuthoringState.initial(format: format).assistantResponse
        return updated
    }

    static func undoLastTurn(
        from state: PromptAuthoringState
    ) -> PromptAuthoringState {
        guard !state.rawTranscripts.isEmpty else {
            return .initial(format: state.format)
        }

        let remaining = state.rawTranscripts.dropLast()
        var rebuilt = PromptAuthoringState.initial(format: state.format)
        for transcript in remaining {
            rebuilt = applyTurn(to: rebuilt, transcript: transcript).state
        }
        return rebuilt
    }

    static func validate(_ state: PromptAuthoringState) -> Bool {
        guard !state.rawTranscripts.isEmpty, !state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        guard state.rawTranscripts.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return false
        }

        if state.format == .structuredPrompt {
            return structuredSections.allSatisfy { state.draft.contains("## \($0.0)") }
        }
        return true
    }

    static func normalizeTranscript(_ transcript: String) -> String {
        transcript
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func buildDraft(
        format: PromptDraftFormat,
        rawTranscripts: [String]
    ) -> String {
        switch format {
        case .cleanPrompt:
            return rawTranscripts
                .map(cleanSentence)
                .joined(separator: "\n\n")
        case .structuredPrompt:
            return structuredSections.enumerated().map { index, section in
                let value: String
                if index == structuredSections.count - 1, rawTranscripts.count > index + 1 {
                    value = rawTranscripts.dropFirst(index).map(cleanSentence).joined(separator: "\n")
                } else if index < rawTranscripts.count {
                    value = cleanSentence(rawTranscripts[index])
                } else {
                    value = "[Unknown]"
                }
                return "## \(section.0)\n\(value)"
            }
            .joined(separator: "\n\n")
        }
    }

    private static func nextQuestion(
        format: PromptDraftFormat,
        turnCount: Int
    ) -> String {
        switch format {
        case .cleanPrompt:
            guard turnCount < cleanQuestions.count else {
                return "Review the Clean Prompt, then confirm it when ready."
            }
            return cleanQuestions[turnCount]
        case .structuredPrompt:
            guard turnCount < structuredSections.count else {
                return "Review the Structured Prompt, then confirm it when ready."
            }
            return structuredSections[turnCount].1
        }
    }

    private static func cleanSentence(_ sentence: String) -> String {
        let normalized = normalizeTranscript(sentence)
        guard !normalized.isEmpty else { return "[Unknown]" }
        if ["。", "！", "？", ".", "!", "?"].contains(where: normalized.hasSuffix) {
            return normalized
        }
        return normalized + "。"
    }
}
