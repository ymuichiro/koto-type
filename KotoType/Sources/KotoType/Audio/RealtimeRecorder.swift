import AVFoundation

enum RecordingStartFailureReason: Equatable {
    case noInputDevice
    case failedToGetInputNode
    case failedToStartAudioEngine
}

final class RealtimeRecorder: NSObject, @unchecked Sendable {
    private static let tempBatchDirectoryName = "koto-type-batch-recordings"
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private var fileCount = 0
    private var lastFileURL: URL?
    private var isRecording = false
    private var capturedSampleRate: Double = 16_000.0
    private let lock = NSLock()
    
    var recordingURL: URL? { lastFileURL }
    var onFileCreated: ((URL, Int) -> Void)?
    private(set) var lastStartFailureReason: RecordingStartFailureReason?

    var batchInterval: TimeInterval
    var silenceThreshold: Float
    var silenceDuration: TimeInterval
    
    private var lastSoundTime: TimeInterval = 0
    private var recordingStartTime: TimeInterval = 0
    private var hasRecordedContent = false
    
    init(batchInterval: TimeInterval = 10.0, silenceThreshold: Float = -40.0, silenceDuration: TimeInterval = 0.5) {
        self.batchInterval = batchInterval
        self.silenceThreshold = silenceThreshold
        self.silenceDuration = silenceDuration
        super.init()
        Logger.shared.log("RealtimeRecorder: initialized with batchInterval=\(batchInterval), silenceThreshold=\(silenceThreshold)dB, silenceDuration=\(silenceDuration)s", level: .info)
    }
    
    func startRecording() -> Bool {
        Logger.shared.log("RealtimeRecorder: startRecording called", level: .info)
        lock.lock()
        defer { lock.unlock() }
        lastStartFailureReason = nil
        
        guard !isRecording else {
            Logger.shared.log("RealtimeRecorder: already recording", level: .warning)
            return true
        }
        
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine?.inputNode
        guard let node = inputNode else {
            Logger.shared.log("RealtimeRecorder: failed to get input node", level: .error)
            lastStartFailureReason = .failedToGetInputNode
            return false
        }

        let inputFormat = node.inputFormat(forBus: 0)
        guard Self.hasUsableInputFormat(inputFormat) else {
            Logger.shared.log(
                "RealtimeRecorder: no usable microphone input format (channels=\(inputFormat.channelCount), sampleRate=\(inputFormat.sampleRate))",
                level: .warning
            )
            audioEngine = nil
            lastStartFailureReason = .noInputDevice
            return false
        }
        
        let recordingFormat = node.outputFormat(forBus: 0)
        capturedSampleRate = Self.normalizeSampleRate(recordingFormat.sampleRate)
        
        audioBuffer.removeAll()
        fileCount = 0
        lastSoundTime = Date().timeIntervalSince1970
        recordingStartTime = Date().timeIntervalSince1970
        hasRecordedContent = false
        
        node.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            self?.processAudio(buffer: buffer)
        }
        
        do {
            try audioEngine?.start()
            isRecording = true
            Logger.shared.log("RealtimeRecorder: recording started", level: .info)
            return true
        } catch {
            Logger.shared.log("RealtimeRecorder: failed to start audio engine: \(error)", level: .error)
            lastStartFailureReason = .failedToStartAudioEngine
            return false
        }
    }
    
    func stopRecording() {
        Logger.shared.log("RealtimeRecorder: stopRecording called", level: .info)
        lock.lock()
        defer { lock.unlock() }
        
        guard isRecording else {
            Logger.shared.log("RealtimeRecorder: not recording", level: .warning)
            return
        }
        
        audioEngine?.stop()
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
        }
        
        if hasRecordedContent && !audioBuffer.isEmpty {
            createAudioFile(force: true)
        }
        
        isRecording = false
        audioEngine = nil
        Logger.shared.log("RealtimeRecorder: recording stopped", level: .info)
    }
    
    private func processAudio(buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        let samples = UnsafeBufferPointer(start: channelData, count: frameCount)
        let maxAmplitude = Self.appendSamples(samples, to: &audioBuffer)
        
        let amplitudeInDb = 20 * log10(max(maxAmplitude, 1e-10))
        let currentTime = Date().timeIntervalSince1970
        let elapsedTime = currentTime - recordingStartTime
        
        if amplitudeInDb > silenceThreshold {
            lastSoundTime = currentTime
            hasRecordedContent = true
        }
        
        let timeSinceLastSound = currentTime - lastSoundTime
        let shouldSplit = Self.shouldSplitChunk(
            elapsedTime: elapsedTime,
            timeSinceLastSound: timeSinceLastSound,
            batchInterval: batchInterval,
            silenceDuration: silenceDuration
        )
        
        if shouldSplit && hasRecordedContent && audioBuffer.count >= 4096 {
            Logger.shared.log("RealtimeRecorder: splitting batch - elapsedTime=\(String(format: "%.1f", elapsedTime))s, timeSinceLastSound=\(String(format: "%.1f", timeSinceLastSound))s", level: .debug)
            createAudioFile()
            lastSoundTime = currentTime
            recordingStartTime = currentTime
            hasRecordedContent = false
        }
    }
    
    private func createAudioFile(force: Bool = false) {
        guard force || audioBuffer.count >= 4096 else {
            Logger.shared.log("RealtimeRecorder: not enough audio data to create file", level: .debug)
            return
        }
        
        let sampleRate = Self.normalizeSampleRate(capturedSampleRate)
        let totalSamples = audioBuffer.count
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalSamples))!
        buffer.frameLength = AVAudioFrameCount(totalSamples)
        
        if let channelData = buffer.floatChannelData?[0] {
            for i in 0..<totalSamples {
                channelData[i] = audioBuffer[i]
            }
        }
        
        let tempBatchDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.tempBatchDirectoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: tempBatchDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            Logger.shared.log(
                "RealtimeRecorder: failed to create temporary batch directory \(tempBatchDirectory.path): \(error)",
                level: .error
            )
            return
        }

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let fileURL = tempBatchDirectory.appendingPathComponent(
            "batch_\(timestamp)_\(fileCount)_\(UUID().uuidString).wav"
        )
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        do {
            let file = try AVAudioFile(forWriting: fileURL, settings: settings)
            try file.write(from: buffer)
            lastFileURL = fileURL
            let currentFileCount = fileCount
            fileCount += 1
            
            Logger.shared.log(
                "RealtimeRecorder: created audio file: \(fileURL.path) (samples: \(totalSamples), sampleRate: \(Int(sampleRate)), fileCount: \(currentFileCount))",
                level: .info
            )

            let onFileCreatedHandler = onFileCreated
            DispatchQueue.main.async { [weak self] in
                guard self != nil else { return }
                onFileCreatedHandler?(fileURL, currentFileCount)
            }
            
            audioBuffer.removeAll()
        } catch {
            Logger.shared.log("RealtimeRecorder: failed to create audio file: \(error)", level: .error)
        }
    }

    static func appendSamples(_ samples: UnsafeBufferPointer<Float>, to destination: inout [Float]) -> Float {
        destination.reserveCapacity(destination.count + samples.count)
        var maxAmplitude: Float = 0

        for sample in samples {
            maxAmplitude = max(maxAmplitude, abs(sample))
            destination.append(sample)
        }

        return maxAmplitude
    }

    static func normalizeSampleRate(_ sampleRate: Double) -> Double {
        guard sampleRate.isFinite, sampleRate > 0 else {
            return 16_000.0
        }
        return sampleRate
    }

    static func hasUsableInputFormat(_ format: AVAudioFormat) -> Bool {
        format.channelCount > 0 && format.sampleRate.isFinite && format.sampleRate > 0
    }

    static func shouldSplitChunk(
        elapsedTime: TimeInterval,
        timeSinceLastSound: TimeInterval,
        batchInterval: TimeInterval,
        silenceDuration: TimeInterval
    ) -> Bool {
        let normalizedElapsed = max(0, elapsedTime)
        let normalizedSilence = max(0, timeSinceLastSound)
        let normalizedBatchInterval = max(0.1, batchInterval)
        let normalizedSilenceDuration = max(0, silenceDuration)

        return normalizedElapsed >= normalizedBatchInterval &&
            normalizedSilence >= normalizedSilenceDuration
    }
}
