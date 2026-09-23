import Foundation
import XCTest

final class RecordingStopOrderingTests: XCTestCase {
    func testStopSnapshotsAudioBeforeSynchronousOCR() throws {
        // Source-wiring regression only; hardware stop/GUI latency need live tests.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("Sources/KotoType/App/AppDelegate.swift"), encoding: .utf8)
        let start = try XCTUnwrap(app.range(of: "    func stopRecording() {"))
        let end = try XCTUnwrap(app.range(of: "    private func completeRecordingStop(", range: start.upperBound..<app.endIndex))
        let body = String(app[start.lowerBound..<end.lowerBound])
        let stop = try XCTUnwrap(body.range(of: "recorder.stopRecording {"))
        let capture = try XCTUnwrap(body.range(of: "ScreenContextExtractor.captureScreenTextContext()"))
        XCTAssertLessThan(stop.lowerBound, capture.lowerBound,
                          "OCR must not extend the microphone capture interval")
        let stopCallEnd = try XCTUnwrap(body.range(of: "\n        }\n", range: stop.upperBound..<capture.lowerBound))
        XCTAssertLessThan(stopCallEnd.lowerBound, capture.lowerBound,
                          "OCR must start after the recorder stop request returns")
        let recorder = try String(contentsOf: root.appendingPathComponent("Sources/KotoType/Audio/RealtimeRecorder.swift"), encoding: .utf8)
        let snapshot = try XCTUnwrap(recorder.range(of: "samples = discardPendingAudio ? [] : audioBuffer"))
        let teardown = try XCTUnwrap(recorder.range(of: "teardownQueue.async"))
        XCTAssertLessThan(snapshot.lowerBound, teardown.lowerBound)
    }
}
