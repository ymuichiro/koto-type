import AVFoundation
import CoreAudio

enum RecordingStartFailureReason: Equatable, Sendable {
    case noInputDevice
    case failedToGetInputNode
    case failedToStartAudioEngine
}

enum RecordingStopResult: Equatable, Sendable {
    case stopped
    case notRecording
    case timedOut
}

private final class SendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private final class StopCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didComplete = false
    private let completion: ((RecordingStopResult) -> Void)?

    init(completion: ((RecordingStopResult) -> Void)?) {
        self.completion = completion
    }

    func complete(_ result: RecordingStopResult) -> Bool {
        guard let completion else { return false }

        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return false
        }
        didComplete = true
        lock.unlock()

        completion(result)
        return true
    }
}

final class RealtimeRecorder: NSObject, @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private var fileCount = 0
    private var lastFileURL: URL?
    private var isRecording = false
    private var capturedSampleRate: Double = 16_000.0
    private let lock = NSLock()
    private let teardownQueue = DispatchQueue(
        label: "com.ymuichiro.kototype.realtime-recorder-teardown",
        qos: .userInitiated
    )
    private let stopTimeout: TimeInterval = 3.0
    private var audioConfigurationObserver: NSObjectProtocol?
    
    var recordingURL: URL? { lastFileURL }
    var onFileCreated: ((URL, Int) -> Void)?
    var onInputLevelChanged: ((Float) -> Void)?
    var onInputDeviceNameChanged: ((String?) -> Void)?
    var onMaximumDurationReached: (() -> Void)?
    var onAudioConfigurationChanged: (() -> Void)?
    private(set) var lastStartFailureReason: RecordingStartFailureReason?
    private(set) var currentInputDeviceName: String?
    private(set) var lastRecordingDuration: TimeInterval = 0
    private(set) var isAppleVoiceProcessingActive = false
    private(set) var lastAppleVoiceProcessingErrorDescription: String?

    var silenceThreshold: Float
    var maxRecordingDuration: TimeInterval?
    
    private var recordingStartTime: TimeInterval = 0
    private var hasRecordedContent = false
    private var lastReportedInputLevel: Float = 0
    private var lastReportedInputDeviceName: String?
    private var hasReachedMaximumDuration = false
    
    init(silenceThreshold: Float = -40.0) {
        self.silenceThreshold = silenceThreshold
        super.init()
        audioConfigurationObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVAudioEngineConfigurationChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleAudioConfigurationChange(notification)
        }
        Logger.shared.log("RealtimeRecorder: initialized with silenceThreshold=\(silenceThreshold)dB", level: .info)
    }

    deinit {
        if let audioConfigurationObserver {
            NotificationCenter.default.removeObserver(audioConfigurationObserver)
        }
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

        isAppleVoiceProcessingActive = false
        lastAppleVoiceProcessingErrorDescription = nil
        
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
        configureAppleVoiceProcessing(on: node)
        
        let recordingFormat = node.outputFormat(forBus: 0)
        capturedSampleRate = Self.normalizeSampleRate(recordingFormat.sampleRate)
        
        audioBuffer.removeAll()
        fileCount = 0
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
            isAppleVoiceProcessingActive = false
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine = nil
            reportInputDeviceName(nil, force: true)
            return false
        }
    }
    
    func stopRecording(
        discardPendingAudio: Bool = false,
        completion: ((RecordingStopResult) -> Void)? = nil
    ) {
        Logger.shared.log("RealtimeRecorder: stopRecording called", level: .info)

        let engine: AVAudioEngine?
        let samples: [Float]
        let sampleRate: Double
        let shouldCreateFile: Bool
        let fileIndex: Int
        let voiceProcessingActive: Bool
        let fileCreatedHandler: SendableBox<((URL, Int) -> Void)?>

        lock.lock()
        guard isRecording else {
            lock.unlock()
            Logger.shared.log("RealtimeRecorder: not recording", level: .warning)
            completion?(.notRecording)
            return
        }

        isRecording = false
        engine = audioEngine
        audioEngine = nil
        samples = discardPendingAudio ? [] : audioBuffer
        audioBuffer.removeAll(keepingCapacity: true)
        sampleRate = Self.normalizeSampleRate(capturedSampleRate)
        shouldCreateFile = !discardPendingAudio && hasRecordedContent && !samples.isEmpty
        fileIndex = fileCount
        if shouldCreateFile {
            fileCount += 1
        }
        voiceProcessingActive = isAppleVoiceProcessingActive
        fileCreatedHandler = SendableBox(onFileCreated)

        let stopTime = Date().timeIntervalSince1970
        lastRecordingDuration = max(0, stopTime - recordingStartTime)
        hasRecordedContent = false
        hasReachedMaximumDuration = false
        isAppleVoiceProcessingActive = false
        onMaximumDurationReached = nil
        currentInputDeviceName = nil
        reportInputLevel(0, force: true)
        reportInputDeviceName(nil, force: true)
        lock.unlock()

        let completionGate = StopCompletionGate(completion: completion)
        let engineBox = SendableBox(engine)
        let timeout = stopTimeout
        teardownQueue.async { [weak self] in
            Logger.shared.log("RealtimeRecorder: removing audio tap", level: .debug)
            engineBox.value?.inputNode.removeTap(onBus: 0)
            Logger.shared.log("RealtimeRecorder: stopping audio engine", level: .debug)
            engineBox.value?.stop()
            Logger.shared.log("RealtimeRecorder: audio engine stopped", level: .debug)

            if shouldCreateFile, let self {
                if let fileURL = self.createAudioFile(
                    samples: samples,
                    sampleRate: sampleRate,
                    fileIndex: fileIndex,
                    appleVoiceProcessing: voiceProcessingActive,
                    onFileCreated: fileCreatedHandler
                ) {
                    self.lock.lock()
                    self.lastFileURL = fileURL
                    self.lock.unlock()
                }
            }

            Logger.shared.log("RealtimeRecorder: recording stopped", level: .info)
            _ = completionGate.complete(.stopped)
        }

        guard completion != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            guard completionGate.complete(.timedOut) else { return }
            Logger.shared.log(
                "RealtimeRecorder: stop timed out after \(String(format: "%.1f", timeout))s; audio teardown is isolated",
                level: .error
            )
        }
    }
    
    // Live recording intentionally stays as one audio file. Earlier app-side
    // chunking was removed in Issue #65 because it added boundary/context and
    // per-chunk processing costs. Reintroduce it only with long-form quality
    // and latency evidence; do not call createAudioFile() from this callback.
    private func processAudio(buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        
        guard isRecording, let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        let samples = UnsafeBufferPointer(start: channelData, count: frameCount)
        let maxAmplitude = Self.appendSamples(samples, to: &audioBuffer)
        
        let amplitudeInDb = 20 * log10(max(maxAmplitude, 1e-10))
        reportInputLevel(Self.normalizedInputLevel(maxAmplitude: maxAmplitude, silenceThreshold: silenceThreshold))
        let elapsedTime = Date().timeIntervalSince1970 - recordingStartTime
        
        if amplitudeInDb > silenceThreshold {
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
    
    private func createAudioFile(
        samples: [Float],
        sampleRate: Double,
        fileIndex: Int,
        appleVoiceProcessing: Bool,
        onFileCreated: SendableBox<((URL, Int) -> Void)?>
    ) -> URL? {
        guard !samples.isEmpty else {
            Logger.shared.log("RealtimeRecorder: not enough audio data to create file", level: .debug)
            return nil
        }

        let totalSamples = samples.count
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalSamples))!
        buffer.frameLength = AVAudioFrameCount(totalSamples)
        
        if let channelData = buffer.floatChannelData?[0] {
            for i in 0..<totalSamples {
                channelData[i] = samples[i]
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
            return nil
        }

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let fileURL = tempBatchDirectory.appendingPathComponent(
            "batch_\(timestamp)_\(fileIndex)_\(UUID().uuidString).wav"
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
            
            Logger.shared.log(
                "RealtimeRecorder: created audio file: \(fileURL.path) (samples: \(totalSamples), sampleRate: \(Int(sampleRate)), fileCount: \(fileIndex), appleVoiceProcessing=\(appleVoiceProcessing))",
                level: .info
            )

            DispatchQueue.main.async {
                onFileCreated.value?(fileURL, fileIndex)
            }
            return fileURL
        } catch {
            Logger.shared.log("RealtimeRecorder: failed to create audio file: \(error)", level: .error)
            return nil
        }
    }

    private func handleAudioConfigurationChange(_ notification: Notification) {
        guard let changedEngine = notification.object as? AVAudioEngine else { return }

        lock.lock()
        let isCurrentEngine = changedEngine === audioEngine
        let recording = isRecording
        let handler = onAudioConfigurationChanged
        lock.unlock()

        guard isCurrentEngine, recording else { return }

        Logger.shared.log(
            "RealtimeRecorder: audio engine configuration changed while recording",
            level: .warning
        )
        DispatchQueue.main.async {
            handler?()
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

    static func shouldEnableAppleVoiceProcessing(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        !isTruthyEnvironmentValue(environment["KOTOTYPE_DISABLE_APPLE_VOICE_PROCESSING"])
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

    private func configureAppleVoiceProcessing(on node: AVAudioInputNode) {
        guard Self.shouldEnableAppleVoiceProcessing() else {
            Logger.shared.log(
                "RealtimeRecorder: Apple voice processing disabled via KOTOTYPE_DISABLE_APPLE_VOICE_PROCESSING",
                level: .info
            )
            return
        }

        do {
            try node.setVoiceProcessingEnabled(true)
            isAppleVoiceProcessingActive = true
            Logger.shared.log("RealtimeRecorder: Apple voice processing enabled", level: .info)
        } catch {
            let description = String(describing: error)
            lastAppleVoiceProcessingErrorDescription = description
            Logger.shared.log(
                "RealtimeRecorder: failed to enable Apple voice processing, continuing without it: \(description)",
                level: .warning
            )
        }
    }

    private static func isTruthyEnvironmentValue(_ value: String?) -> Bool {
        guard let value else {
            return false
        }

        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
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
