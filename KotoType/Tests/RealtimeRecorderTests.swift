import AVFoundation
import XCTest
@testable import KotoType

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
        if result {
            XCTAssertNil(recorder.lastStartFailureReason)
            XCTAssertFalse((recorder.currentInputDeviceName ?? "").isEmpty)
        } else {
            XCTAssertEqual(recorder.lastStartFailureReason, .noInputDevice)
            XCTAssertNil(recorder.currentInputDeviceName)
        }
    }

    func testStopRecording() {
        let didStart = recorder.startRecording()
        recorder.stopRecording()
        XCTAssertNil(recorder.recordingURL, "Recording URL should be nil after stop without content")
        if didStart {
            XCTAssertNil(recorder.currentInputDeviceName)
        }
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

    func testNormalizedInputLevelReturnsZeroWhenSilent() {
        let level = RealtimeRecorder.normalizedInputLevel(maxAmplitude: 0, silenceThreshold: -40)
        XCTAssertEqual(level, 0, accuracy: 0.0001)
    }

    func testNormalizedInputLevelScalesBetweenSilenceAndFullScale() {
        let level = RealtimeRecorder.normalizedInputLevel(maxAmplitude: 0.1, silenceThreshold: -40)
        XCTAssertGreaterThan(level, 0)
        XCTAssertLessThan(level, 1)
    }

    func testNormalizedInputLevelClampsToOneForLoudInput() {
        let level = RealtimeRecorder.normalizedInputLevel(maxAmplitude: 1.0, silenceThreshold: -40)
        XCTAssertEqual(level, 1, accuracy: 0.0001)
    }

    func testHasUsableInputFormatForNormalMonoInput() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)
        XCTAssertNotNil(format)
        if let format {
            XCTAssertTrue(RealtimeRecorder.hasUsableInputFormat(format))
        }
    }

    func testShouldSplitChunkBySilenceAfterBatchInterval() {
        let shouldSplit = RealtimeRecorder.shouldSplitChunk(
            elapsedTime: 10.0,
            timeSinceLastSound: 0.6,
            batchInterval: 10.0,
            silenceDuration: 0.5
        )

        XCTAssertTrue(shouldSplit)
    }

    func testShouldNotSplitChunkWithoutSilenceAfterBatchInterval() {
        let shouldSplit = RealtimeRecorder.shouldSplitChunk(
            elapsedTime: 12.0,
            timeSinceLastSound: 0.05,
            batchInterval: 10.0,
            silenceDuration: 0.5
        )

        XCTAssertFalse(shouldSplit)
    }

    func testShouldNotSplitChunkBeforeBatchIntervalOrSilenceThreshold() {
        let shouldSplit = RealtimeRecorder.shouldSplitChunk(
            elapsedTime: 1.4,
            timeSinceLastSound: 0.05,
            batchInterval: 10.0,
            silenceDuration: 0.5
        )

        XCTAssertFalse(shouldSplit)
    }

    func testShouldAutoStopRecordingWhenElapsedTimeReachesMaximumDuration() {
        XCTAssertTrue(
            RealtimeRecorder.shouldAutoStopRecording(
                elapsedTime: 60.0,
                maxDuration: 60.0
            )
        )
    }

    func testShouldNotAutoStopRecordingBeforeMaximumDuration() {
        XCTAssertFalse(
            RealtimeRecorder.shouldAutoStopRecording(
                elapsedTime: 59.9,
                maxDuration: 60.0
            )
        )
    }
}
