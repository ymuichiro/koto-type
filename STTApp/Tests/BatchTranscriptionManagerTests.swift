import XCTest
import AVFoundation
@testable import STTApp

final class BatchTranscriptionManagerTests: XCTestCase {
    var manager: BatchTranscriptionManager!
    var testFiles: [URL] = []

    override func setUp() async throws {
        try await super.setUp()
        manager = BatchTranscriptionManager()
    }

    override func tearDown() async throws {
        manager = nil
        for file in testFiles {
            try? FileManager.default.removeItem(at: file)
        }
        testFiles.removeAll()
        try await super.tearDown()
    }

    private func createTestAudioFile(index: Int) -> URL {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let fileName = "test_batch_\(index)_\(UUID().uuidString).wav"
        let filePath = (documentsPath as NSString).appendingPathComponent(fileName)
        let fileURL = URL(fileURLWithPath: filePath)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            let file = try AVAudioFile(forWriting: fileURL, settings: settings)
            let format = AVAudioFormat(standardFormatWithSampleRate: 16000.0, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000)!
            buffer.frameLength = 16000

            for i in 0..<16000 {
                if let channelData = buffer.floatChannelData?[0] {
                    channelData[i] = Float.random(in: -0.1...0.1)
                }
            }

            try file.write(from: buffer)
            testFiles.append(fileURL)
        } catch {
            XCTFail("Failed to create test audio file: \(error)")
        }

        return fileURL
    }

    func testAddSegment() {
        let file1 = createTestAudioFile(index: 0)
        manager.addSegment(url: file1, index: 0)

        XCTAssertFalse(manager.isComplete(), "Manager should not be complete with pending segment")
    }

    func testCompleteSegment() {
        let file1 = createTestAudioFile(index: 0)
        manager.addSegment(url: file1, index: 0)
        manager.completeSegment(index: 0, text: "Hello")

        XCTAssertTrue(manager.isComplete(), "Manager should be complete after segment completion")
    }

    func testMultipleSegments() {
        let file1 = createTestAudioFile(index: 0)
        let file2 = createTestAudioFile(index: 1)
        let file3 = createTestAudioFile(index: 2)

        manager.addSegment(url: file1, index: 0)
        manager.addSegment(url: file2, index: 1)
        manager.addSegment(url: file3, index: 2)

        XCTAssertFalse(manager.isComplete(), "Manager should not be complete with pending segments")

        manager.completeSegment(index: 0, text: "Hello")
        XCTAssertFalse(manager.isComplete(), "Manager should not be complete with pending segments")

        manager.completeSegment(index: 2, text: "World")
        XCTAssertFalse(manager.isComplete(), "Manager should not be complete with missing segment")

        manager.completeSegment(index: 1, text: " ")
        XCTAssertTrue(manager.isComplete(), "Manager should be complete after all segments")
    }

    func testFinalize() {
        let file1 = createTestAudioFile(index: 0)
        let file2 = createTestAudioFile(index: 1)

        manager.addSegment(url: file1, index: 0)
        manager.addSegment(url: file2, index: 1)

        manager.completeSegment(index: 0, text: "Hello")
        manager.completeSegment(index: 1, text: " World")

        let result = manager.finalize()
        XCTAssertEqual(result, "Hello World", "Finalized text should match expected")
    }

    func testFinalizeEmpty() {
        let result = manager.finalize()
        XCTAssertNil(result, "Finalize should return nil when no segments")
    }

    func testOutOfOrderCompletion() {
        let file1 = createTestAudioFile(index: 0)
        let file2 = createTestAudioFile(index: 1)
        let file3 = createTestAudioFile(index: 2)

        manager.addSegment(url: file1, index: 0)
        manager.addSegment(url: file2, index: 1)
        manager.addSegment(url: file3, index: 2)

        XCTAssertFalse(manager.isComplete(), "Manager should not be complete")

        manager.completeSegment(index: 1, text: " ")
        XCTAssertFalse(manager.isComplete(), "Manager should not be complete with missing index 0")

        manager.completeSegment(index: 0, text: "Hello")
        XCTAssertFalse(manager.isComplete(), "Manager should not be complete with missing index 2")

        manager.completeSegment(index: 2, text: "World")
        XCTAssertTrue(manager.isComplete(), "Manager should be complete")
    }

    func testOnTranscriptionCompleteFlushesInOrder() {
        let file1 = createTestAudioFile(index: 0)
        let file2 = createTestAudioFile(index: 1)
        let file3 = createTestAudioFile(index: 2)

        manager.addSegment(url: file1, index: 0)
        manager.addSegment(url: file2, index: 1)
        manager.addSegment(url: file3, index: 2)

        let expectation = XCTestExpectation(description: "Ordered flush callbacks")
        expectation.expectedFulfillmentCount = 2

        var emitted: [String] = []
        manager.onTranscriptionComplete = { text in
            emitted.append(text)
            expectation.fulfill()
        }

        manager.completeSegment(index: 2, text: "C")
        manager.completeSegment(index: 0, text: "A")
        manager.completeSegment(index: 1, text: "B")

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(emitted, ["A", "BC"])
    }
}
