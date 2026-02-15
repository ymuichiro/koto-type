@testable import KotoType
import Foundation
import XCTest

final class ImportedAudioTranscriptionManagerTests: XCTestCase {
    func testDoesNotStartProcessUntilTranscribeIsCalled() {
        let mock = MockPythonProcessManager()
        let manager = ImportedAudioTranscriptionManager(processManager: mock)

        manager.configure(scriptPath: "/tmp/whisper_server.py")

        XCTAssertEqual(mock.startCallCount, 0)
    }

    func testTranscribeStartsProcessAndStopsAfterOutput() {
        let mock = MockPythonProcessManager()
        let manager = ImportedAudioTranscriptionManager(processManager: mock)
        manager.configure(scriptPath: "/tmp/whisper_server.py")

        let completionExpectation = expectation(description: "transcription completion")

        manager.transcribe(fileURL: URL(fileURLWithPath: "/tmp/audio.wav"), settings: AppSettings()) { result in
            if case let .success(text) = result {
                XCTAssertEqual(text, "こんにちは")
            } else {
                XCTFail("Expected success")
            }
            completionExpectation.fulfill()
        }

        XCTAssertEqual(mock.startCallCount, 1)
        XCTAssertEqual(mock.sendInputCallCount, 1)

        mock.emitOutput("こんにちは")

        wait(for: [completionExpectation], timeout: 1.0)
        XCTAssertEqual(mock.stopCallCount, 1)
    }

    func testTranscribeFailsWhenScriptPathNotConfigured() {
        let mock = MockPythonProcessManager()
        let manager = ImportedAudioTranscriptionManager(processManager: mock)

        let completionExpectation = expectation(description: "completion")

        manager.transcribe(fileURL: URL(fileURLWithPath: "/tmp/audio.wav"), settings: AppSettings()) { result in
            if case let .failure(error) = result {
                XCTAssertEqual(error, .scriptPathNotConfigured)
            } else {
                XCTFail("Expected failure")
            }
            completionExpectation.fulfill()
        }

        wait(for: [completionExpectation], timeout: 1.0)
        XCTAssertEqual(mock.startCallCount, 0)
        XCTAssertEqual(mock.sendInputCallCount, 0)
    }

    func testTranscribeReturnsBusyWhenAnotherRequestIsPending() {
        let mock = MockPythonProcessManager()
        let manager = ImportedAudioTranscriptionManager(processManager: mock)
        manager.configure(scriptPath: "/tmp/whisper_server.py")

        let firstCompletion = expectation(description: "first completion")
        let secondCompletion = expectation(description: "second completion")

        manager.transcribe(fileURL: URL(fileURLWithPath: "/tmp/audio1.wav"), settings: AppSettings()) { _ in
            firstCompletion.fulfill()
        }

        manager.transcribe(fileURL: URL(fileURLWithPath: "/tmp/audio2.wav"), settings: AppSettings()) { result in
            if case let .failure(error) = result {
                XCTAssertEqual(error, .managerBusy)
            } else {
                XCTFail("Expected busy error")
            }
            secondCompletion.fulfill()
        }

        mock.emitOutput("ok")

        wait(for: [firstCompletion, secondCompletion], timeout: 1.0)
    }

    func testTerminationDoesNotRestartProcessAutomatically() {
        let mock = MockPythonProcessManager()
        let manager = ImportedAudioTranscriptionManager(processManager: mock)
        manager.configure(scriptPath: "/tmp/whisper_server.py")

        let completionExpectation = expectation(description: "completion")

        manager.transcribe(fileURL: URL(fileURLWithPath: "/tmp/audio.wav"), settings: AppSettings()) { result in
            if case let .failure(error) = result {
                XCTAssertEqual(error, .processTerminated(status: 9))
            } else {
                XCTFail("Expected processTerminated")
            }
            completionExpectation.fulfill()
        }

        mock.emitTermination(status: 9)

        wait(for: [completionExpectation], timeout: 1.0)
        XCTAssertEqual(mock.startCallCount, 1)
    }
}

private final class MockPythonProcessManager: PythonProcessManaging {
    var outputReceived: ((String) -> Void)?
    var processTerminated: ((Int32) -> Void)?

    private(set) var startCallCount = 0
    private(set) var sendInputCallCount = 0
    private(set) var stopCallCount = 0

    var running = false

    func startPython(scriptPath: String) {
        startCallCount += 1
        running = true
    }

    func sendInput(
        _ text: String,
        language: String,
        temperature: Double,
        beamSize: Int,
        noSpeechThreshold: Double,
        compressionRatioThreshold: Double,
        task: String,
        bestOf: Int,
        vadThreshold: Double,
        autoPunctuation: Bool,
        autoGainEnabled: Bool,
        autoGainWeakThresholdDbfs: Double,
        autoGainTargetPeakDbfs: Double,
        autoGainMaxDb: Double,
        screenshotContext: String?
    ) -> Bool {
        sendInputCallCount += 1
        return true
    }

    func isRunning() -> Bool {
        running
    }

    func stop() {
        stopCallCount += 1
        running = false
    }

    func emitOutput(_ output: String) {
        outputReceived?(output)
    }

    func emitTermination(status: Int32) {
        processTerminated?(status)
    }
}
