import XCTest
import AVFoundation
@testable import STTApp

final class IntegrationTests: XCTestCase {
    var multiProcessManager: MultiProcessManager!
    var batchTranscriptionManager: BatchTranscriptionManager!
    var realtimeRecorder: RealtimeRecorder!

    override func setUp() async throws {
        try await super.setUp()
        multiProcessManager = MultiProcessManager()
        batchTranscriptionManager = BatchTranscriptionManager()
        realtimeRecorder = RealtimeRecorder()
    }

    override func tearDown() async throws {
        multiProcessManager?.stop()
        multiProcessManager = nil
        batchTranscriptionManager = nil
        realtimeRecorder = nil
        try await super.tearDown()
    }

    func testMultiProcessManagerInitialization() {
        let scriptPath = BackendLocator.serverScriptPath()
        multiProcessManager.initialize(count: 2, scriptPath: scriptPath)

        XCTAssertEqual(multiProcessManager.getProcessCount(), 2, "Should have 2 processes")
        XCTAssertEqual(multiProcessManager.getIdleProcessCount(), 2, "All processes should be idle initially")
    }

    func testBatchTranscriptionManagerIntegration() {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let fileName = "test_integration_\(UUID().uuidString).wav"
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
        } catch {
            XCTFail("Failed to create test audio file: \(error)")
            return
        }

        batchTranscriptionManager.addSegment(url: fileURL, index: 0)
        batchTranscriptionManager.completeSegment(index: 0, text: "Test")

        XCTAssertTrue(batchTranscriptionManager.isComplete(), "Manager should be complete")
    }

    func testRealtimeRecorderIntegration() {
        realtimeRecorder.batchInterval = 2.0
        realtimeRecorder.silenceThreshold = -40.0
        realtimeRecorder.silenceDuration = 0.5

        let result = realtimeRecorder.startRecording()
        XCTAssertTrue(result, "Recording should start successfully")

        usleep(100000)  // Wait 100ms

        realtimeRecorder.stopRecording()
    }

    func testFullFlow() {
        let scriptPath = BackendLocator.serverScriptPath()
        multiProcessManager.initialize(count: 2, scriptPath: scriptPath)

        realtimeRecorder.batchInterval = 2.0
        realtimeRecorder.silenceThreshold = -40.0
        realtimeRecorder.silenceDuration = 0.5

        realtimeRecorder.onFileCreated = { [weak self] url, index in
            guard let self = self else { return }
            self.batchTranscriptionManager.addSegment(url: url, index: index)
            self.multiProcessManager.processFile(url: url, index: index, settings: AppSettings())
        }

        batchTranscriptionManager.onTranscriptionComplete = { text in
            XCTAssertFalse(text.isEmpty, "Transcription should not be empty")
        }

        multiProcessManager.outputReceived = { processIndex, output in
            XCTAssertFalse(output.isEmpty, "Output should not be empty")
        }

        _ = realtimeRecorder.startRecording()

        usleep(200000)  // Wait 200ms

        realtimeRecorder.stopRecording()
    }

    func testBatchProcessingWithMultipleFiles() {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]

        var testFiles: [URL] = []
        for i in 0..<3 {
            let fileName = "test_batch_\(i)_\(UUID().uuidString).wav"
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

                for j in 0..<16000 {
                    if let channelData = buffer.floatChannelData?[0] {
                        channelData[j] = Float.random(in: -0.1...0.1)
                    }
                }

            try file.write(from: buffer)
                testFiles.append(fileURL)
            } catch {
                XCTFail("Failed to create test audio file: \(error)")
                return
            }
        }

        for (index, fileURL) in testFiles.enumerated() {
            batchTranscriptionManager.addSegment(url: fileURL, index: index)
        }

        for index in testFiles.indices {
            batchTranscriptionManager.completeSegment(index: index, text: "Segment \(index) ")
        }

        XCTAssertTrue(batchTranscriptionManager.isComplete(), "Manager should be complete")

        let result = batchTranscriptionManager.finalize()
        XCTAssertEqual(result, "Segment 0 Segment 1 Segment 2 ", "All segments should be combined")
    }

    func testMultiProcessManagerParallelism() {
        let scriptPath = BackendLocator.serverScriptPath()
        multiProcessManager.initialize(count: 3, scriptPath: scriptPath)

        XCTAssertEqual(multiProcessManager.getProcessCount(), 3, "Should have 3 processes")
        XCTAssertEqual(multiProcessManager.getIdleProcessCount(), 3, "All processes should be idle initially")
    }

    func testRealtimeRecorderParameterUpdate() {
        realtimeRecorder.batchInterval = 15.0
        realtimeRecorder.silenceThreshold = -50.0
        realtimeRecorder.silenceDuration = 1.0

        XCTAssertEqual(realtimeRecorder.batchInterval, 15.0, accuracy: 0.001)
        XCTAssertEqual(realtimeRecorder.silenceThreshold, -50.0, accuracy: 0.001)
        XCTAssertEqual(realtimeRecorder.silenceDuration, 1.0, accuracy: 0.001)
    }
}
