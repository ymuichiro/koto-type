import XCTest
@testable import KotoType

final class PromptAuthoringTests: XCTestCase {
    func testStructuredTurnsKeepRawDialogueAndExplicitUnknowns() {
        let first = PromptAuthoringEngine.applyTurn(
            to: .initial(format: .structuredPrompt),
            transcript: "Build a weekly release checklist"
        )
        let second = PromptAuthoringEngine.applyTurn(
            to: first.state,
            transcript: "It is for a small macOS team"
        )

        XCTAssertEqual(second.state.rawTranscripts, [
            "Build a weekly release checklist",
            "It is for a small macOS team",
        ])
        XCTAssertEqual(second.state.dialogue.count, 2)
        XCTAssertTrue(second.state.draft.contains("## Goal"))
        XCTAssertTrue(second.state.draft.contains("## Background"))
        XCTAssertTrue(second.state.draft.contains("## Constraints\n[Unknown]"))
        XCTAssertFalse(second.state.draft.contains(second.state.assistantResponse))
        XCTAssertTrue(second.validationPassed)
    }

    func testCleanPromptOnlyNormalizesSuppliedTranscript() {
        let result = PromptAuthoringEngine.applyTurn(
            to: .initial(format: .cleanPrompt),
            transcript: "Keep API v2, do not change the code"
        )

        XCTAssertEqual(result.state.draft, "Keep API v2, do not change the code。")
        XCTAssertTrue(result.state.draft.contains("API v2"))
        XCTAssertTrue(result.state.draft.contains("do not change"))
        XCTAssertTrue(result.state.pendingQuestion.contains("background") || result.state.pendingQuestion.contains("constraints"))
    }

    func testEmptyTurnDoesNotMutateRawTranscriptOrDraft() {
        let initial = PromptAuthoringState.initial(format: .structuredPrompt)
        let result = PromptAuthoringEngine.applyTurn(to: initial, transcript: "   \n\t")

        XCTAssertNil(result.acceptedTranscript)
        XCTAssertEqual(result.state.rawTranscripts, [])
        XCTAssertEqual(result.state.draft, "")
        XCTAssertFalse(result.validationPassed)
    }

    func testUndoRebuildsDraftWithoutInventingAReplacementTurn() {
        let first = PromptAuthoringEngine.applyTurn(
            to: .initial(),
            transcript: "Create a launch announcement"
        ).state
        let second = PromptAuthoringEngine.applyTurn(
            to: first,
            transcript: "Use a friendly tone"
        ).state

        let undone = PromptAuthoringEngine.undoLastTurn(from: second)

        XCTAssertEqual(undone.rawTranscripts, ["Create a launch announcement"])
        XCTAssertEqual(undone.dialogue.count, 1)
        XCTAssertFalse(undone.draft.contains("Use a friendly tone"))
        XCTAssertTrue(undone.draft.contains("Create a launch announcement"))
    }

    func testChangingFormatDoesNotDiscardRawTurns() {
        let state = PromptAuthoringEngine.applyTurn(
            to: .initial(format: .cleanPrompt),
            transcript: "Summarize the supplied meeting notes"
        ).state

        let changed = PromptAuthoringEngine.changingFormat(.structuredPrompt, for: state)

        XCTAssertEqual(changed.rawTranscripts, state.rawTranscripts)
        XCTAssertEqual(changed.dialogue, state.dialogue)
        XCTAssertTrue(changed.draft.contains("## Goal"))
    }

    func testStructuredDraftKeepsTurnsBeyondTheSectionCountInUnknowns() {
        var state = PromptAuthoringState.initial(format: .structuredPrompt)
        for index in 1...7 {
            state = PromptAuthoringEngine.applyTurn(
                to: state,
                transcript: "Turn \(index) detail"
            ).state
        }

        XCTAssertEqual(state.rawTranscripts.count, 7)
        XCTAssertTrue(state.draft.contains("Turn 6 detail"))
        XCTAssertTrue(state.draft.contains("Turn 7 detail"))
        XCTAssertTrue(PromptAuthoringEngine.validate(state))
    }
}
