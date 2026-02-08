import XCTest
@testable import STTApp

final class RealtimeRecorderTests: XCTestCase {
    var recorder: RealtimeRecorder!

    override func setUp() {
        super.setUp()
        recorder = RealtimeRecorder(
            batchInterval: 2.0,
            silenceThreshold: -40.0,
            silenceDuration: 0.5
        )
    }

    override func tearDown() {
        recorder = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertEqual(recorder.batchInterval, 2.0, accuracy: 0.001)
        XCTAssertEqual(recorder.silenceThreshold, -40.0, accuracy: 0.001)
        XCTAssertEqual(recorder.silenceDuration, 0.5, accuracy: 0.001)
    }

    func testStartRecording() {
        let result = recorder.startRecording()
        XCTAssertTrue(result, "Recording should start successfully")
    }

    func testStopRecording() {
        _ = recorder.startRecording()
        recorder.stopRecording()
        XCTAssertNil(recorder.recordingURL, "Recording URL should be nil after stop without content")
    }

    func testFileCreationCallback() {
        let expectation = XCTestExpectation(description: "File created callback")
        expectation.assertForOverFulfill = true
        expectation.isInverted = false

        recorder.onFileCreated = { url, index in
            expectation.fulfill()
            XCTAssertFalse(url.path.isEmpty, "File path should not be empty")
            XCTAssertGreaterThanOrEqual(index, 0, "File index should be non-negative")
        }

        _ = recorder.startRecording()
        usleep(300_000)
        recorder.stopRecording()

        let waiterResult = XCTWaiter.wait(for: [expectation], timeout: 1.0)

        if waiterResult == .timedOut {
            XCTAssertNil(
                recorder.recordingURL,
                "If callback is not triggered in a silent environment, recordingURL should remain nil"
            )
        } else {
            XCTAssertEqual(waiterResult, .completed)
            XCTAssertNotNil(recorder.recordingURL, "Callback completion should create a recording URL")
        }
    }

    func testParameterUpdate() {
        recorder.batchInterval = 15.0
        recorder.silenceThreshold = -50.0
        recorder.silenceDuration = 1.0

        XCTAssertEqual(recorder.batchInterval, 15.0, accuracy: 0.001)
        XCTAssertEqual(recorder.silenceThreshold, -50.0, accuracy: 0.001)
        XCTAssertEqual(recorder.silenceDuration, 1.0, accuracy: 0.001)
    }

    func testAppendSamplesPreservesWaveformSign() {
        let input: [Float] = [-0.25, 0.4, -0.1, 0.0, 0.15]
        var destination: [Float] = []

        let maxAmplitude = input.withUnsafeBufferPointer {
            RealtimeRecorder.appendSamples($0, to: &destination)
        }

        XCTAssertEqual(destination.count, input.count)
        for (actual, expected) in zip(destination, input) {
            XCTAssertEqual(actual, expected, accuracy: 0.000_001)
        }
        XCTAssertEqual(maxAmplitude, 0.4, accuracy: 0.000_001)
    }

    func testNormalizeSampleRate() {
        XCTAssertEqual(RealtimeRecorder.normalizeSampleRate(48_000.0), 48_000.0, accuracy: 0.001)
        XCTAssertEqual(RealtimeRecorder.normalizeSampleRate(0), 16_000.0, accuracy: 0.001)
        XCTAssertEqual(RealtimeRecorder.normalizeSampleRate(.nan), 16_000.0, accuracy: 0.001)
    }
}
