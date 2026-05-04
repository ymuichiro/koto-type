import AVFoundation
import CoreAudio

enum RecordingStartFailureReason: Equatable {
    case noInputDevice
    case failedToGetInputNode
    case failedToStartAudioEngine
}

final class RealtimeRecorder: NSObject, @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private var fileCount = 0
    private var lastFileURL: URL?
    private var isRecording = false
    private var capturedSampleRate: Double = 16_000.0
    private let lock = NSLock()
    
    var recordingURL: URL? { lastFileURL }
    var onFileCreated: ((URL, Int) -> Void)?
    var onInputLevelChanged: ((Float) -> Void)?
    var onInputDeviceNameChanged: ((String?) -> Void)?
    var onMaximumDurationReached: (() -> Void)?
    private(set) var lastStartFailureReason: RecordingStartFailureReason?
    private(set) var currentInputDeviceName: String?
    private(set) var lastRecordingDuration: TimeInterval = 0

    var batchInterval: TimeInterval
    var silenceThreshold: Float
    var silenceDuration: TimeInterval
    var maxRecordingDuration: TimeInterval?
    
    private var lastSoundTime: TimeInterval = 0
    private var recordingStartTime: TimeInterval = 0
    private var hasRecordedContent = false
    private var lastReportedInputLevel: Float = 0
    private var lastReportedInputDeviceName: String?
    private var hasReachedMaximumDuration = false
    
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
            currentInputDeviceName = nil
            reportInputDeviceName(nil, force: true)
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
            currentInputDeviceName = nil
            reportInputDeviceName(nil, force: true)
            return false
        }

        currentInputDeviceName = Self.currentDefaultInputDeviceName() ?? Self.unknownInputDeviceName
        reportInputDeviceName(currentInputDeviceName, force: true)
        
        let recordingFormat = node.outputFormat(forBus: 0)
        capturedSampleRate = Self.normalizeSampleRate(recordingFormat.sampleRate)
        
        audioBuffer.removeAll()
        fileCount = 0
        lastSoundTime = Date().timeIntervalSince1970
        recordingStartTime = Date().timeIntervalSince1970
        hasRecordedContent = false
        hasReachedMaximumDuration = false
        lastRecordingDuration = 0
        reportInputLevel(0, force: true)
        
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
            currentInputDeviceName = nil
            reportInputDeviceName(nil, force: true)
            return false
        }
    }
    
    func stopRecording(discardPendingAudio: Bool = false) {
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

        let stopTime = Date().timeIntervalSince1970
        lastRecordingDuration = max(0, stopTime - recordingStartTime)
        
        if !discardPendingAudio && hasRecordedContent && !audioBuffer.isEmpty {
            createAudioFile(force: true)
        }
        
        if discardPendingAudio {
            audioBuffer.removeAll()
        }
        hasRecordedContent = false
        hasReachedMaximumDuration = false
        isRecording = false
        audioEngine = nil
        onMaximumDurationReached = nil
        currentInputDeviceName = nil
        reportInputLevel(0, force: true)
        reportInputDeviceName(nil, force: true)
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
        reportInputLevel(Self.normalizedInputLevel(maxAmplitude: maxAmplitude, silenceThreshold: silenceThreshold))
        let currentTime = Date().timeIntervalSince1970
        let elapsedTime = currentTime - recordingStartTime
        
        if amplitudeInDb > silenceThreshold {
            lastSoundTime = currentTime
            hasRecordedContent = true
        }

        if let maxRecordingDuration,
           !hasReachedMaximumDuration,
           Self.shouldAutoStopRecording(
               elapsedTime: elapsedTime,
               maxDuration: maxRecordingDuration
           ) {
            hasReachedMaximumDuration = true
            Logger.shared.log(
                "RealtimeRecorder: maximum recording duration reached at \(String(format: "%.1f", elapsedTime))s (limit=\(String(format: "%.1f", maxRecordingDuration))s)",
                level: .info
            )
            let onMaximumDurationReached = onMaximumDurationReached
            DispatchQueue.main.async {
                onMaximumDurationReached?()
            }
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
        
        let tempBatchDirectory = KotoTypeStoragePaths.temporaryBatchDirectory()
        do {
            try LocalFileProtection.ensurePrivateDirectory(at: tempBatchDirectory)
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
            try LocalFileProtection.tightenFilePermissionsIfPresent(at: fileURL)
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

    static func normalizedInputLevel(maxAmplitude: Float, silenceThreshold: Float) -> Float {
        let clampedAmplitude = max(0, min(maxAmplitude, 1))
        guard clampedAmplitude > 0 else {
            return 0
        }

        let amplitudeDb = 20 * log10(clampedAmplitude)
        let floorDb = min(-1, silenceThreshold)
        let normalized = (amplitudeDb - floorDb) / -floorDb
        return max(0, min(normalized, 1))
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

    static func shouldAutoStopRecording(
        elapsedTime: TimeInterval,
        maxDuration: TimeInterval?
    ) -> Bool {
        guard let maxDuration else {
            return false
        }
        return max(0, elapsedTime) >= max(0.1, maxDuration)
    }

    private func reportInputLevel(_ level: Float, force: Bool = false) {
        let clamped = max(0, min(level, 1))
        if !force && abs(clamped - lastReportedInputLevel) < 0.015 {
            return
        }
        lastReportedInputLevel = clamped

        let handler = onInputLevelChanged
        DispatchQueue.main.async {
            handler?(clamped)
        }
    }

    private func reportInputDeviceName(_ name: String?, force: Bool = false) {
        if !force && lastReportedInputDeviceName == name {
            return
        }

        lastReportedInputDeviceName = name
        let handler = onInputDeviceNameChanged
        DispatchQueue.main.async {
            handler?(name)
        }
    }

    private static let unknownInputDeviceName = "Unknown input device"

    private static func currentDefaultInputDeviceName() -> String? {
        guard let deviceID = defaultInputDeviceID() else {
            return nil
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &name
        )

        guard status == noErr else {
            Logger.shared.log(
                "RealtimeRecorder: failed to read input device name (status=\(status))",
                level: .warning
            )
            return nil
        }

        let resolvedName = name?.takeUnretainedValue() as String? ?? ""
        let trimmed = resolvedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func defaultInputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID()
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else {
            Logger.shared.log(
                "RealtimeRecorder: failed to resolve default input device (status=\(status))",
                level: .warning
            )
            return nil
        }

        guard deviceID != AudioObjectID(kAudioObjectUnknown) else {
            return nil
        }

        return deviceID
    }
}
