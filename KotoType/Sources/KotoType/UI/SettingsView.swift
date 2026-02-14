import SwiftUI
import AppKit

struct SettingsView: View {
    @State private var hotkeyConfig: HotkeyConfiguration
    @State private var language: String
    @State private var autoPunctuation: Bool
    @State private var temperature: Double
    @State private var beamSize: Int
    @State private var noSpeechThreshold: Double
    @State private var compressionRatioThreshold: Double
    @State private var task: String
    @State private var bestOf: Int
    @State private var vadThreshold: Double
    @State private var batchInterval: Double
    @State private var silenceThreshold: Double
    @State private var silenceDuration: Double
    @State private var parallelism: Int
    @State private var launchAtLogin: Bool
    @State private var autoGainEnabled: Bool
    @State private var autoGainWeakThresholdDbfs: Double
    @State private var autoGainTargetPeakDbfs: Double
    @State private var autoGainMaxDb: Double
    @State private var dictionaryWords: [String]
    @Binding var isPresented: Bool
    
    let onHotkeyChanged: (HotkeyConfiguration) -> Void
    let onSettingsChanged: (() -> Void)?
    let onImportAudioRequested: (() -> Void)?
    let onShowHistoryRequested: (() -> Void)?
    
    @State private var pendingHotkeyConfig: HotkeyConfiguration
    @State private var pendingLanguage: String
    @State private var pendingAutoPunctuation: Bool
    @State private var pendingTemperature: Double
    @State private var pendingBeamSize: Int
    @State private var pendingNoSpeechThreshold: Double
    @State private var pendingCompressionRatioThreshold: Double
    @State private var pendingTask: String
    @State private var pendingBestOf: Int
    @State private var pendingVadThreshold: Double
    @State private var pendingBatchInterval: Double
    @State private var pendingSilenceThreshold: Double
    @State private var pendingSilenceDuration: Double
    @State private var pendingParallelism: Int
    @State private var pendingLaunchAtLogin: Bool
    @State private var pendingAutoGainEnabled: Bool
    @State private var pendingAutoGainWeakThresholdDbfs: Double
    @State private var pendingAutoGainTargetPeakDbfs: Double
    @State private var pendingAutoGainMaxDb: Double
    @State private var pendingDictionaryWords: [String]
    @State private var pendingDictionaryEntry: String
    
    let availableLanguages = [
        ("auto", "Auto Detect"),
        ("ja", "Japanese"),
        ("en", "English"),
        ("zh", "Chinese"),
        ("ko", "Korean"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
    ]
    
    init(
        isPresented: Binding<Bool>,
        onHotkeyChanged: @escaping (HotkeyConfiguration) -> Void,
        onSettingsChanged: (() -> Void)? = nil,
        onImportAudioRequested: (() -> Void)? = nil,
        onShowHistoryRequested: (() -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self.onHotkeyChanged = onHotkeyChanged
        self.onSettingsChanged = onSettingsChanged
        self.onImportAudioRequested = onImportAudioRequested
        self.onShowHistoryRequested = onShowHistoryRequested
        
        let settings = SettingsManager.shared.load()
        let userDictionaryWords = UserDictionaryManager.shared.loadWords()
        self._hotkeyConfig = State(initialValue: settings.hotkeyConfig)
        self._language = State(initialValue: settings.language)
        self._autoPunctuation = State(initialValue: settings.autoPunctuation)
        self._temperature = State(initialValue: settings.temperature)
        self._beamSize = State(initialValue: settings.beamSize)
        self._noSpeechThreshold = State(initialValue: settings.noSpeechThreshold)
        self._compressionRatioThreshold = State(initialValue: settings.compressionRatioThreshold)
        self._task = State(initialValue: settings.task)
        self._bestOf = State(initialValue: settings.bestOf)
        self._vadThreshold = State(initialValue: settings.vadThreshold)
        self._batchInterval = State(initialValue: settings.batchInterval)
        self._silenceThreshold = State(initialValue: settings.silenceThreshold)
        self._silenceDuration = State(initialValue: settings.silenceDuration)
        self._parallelism = State(initialValue: settings.parallelism)
        self._launchAtLogin = State(initialValue: settings.launchAtLogin)
        self._autoGainEnabled = State(initialValue: settings.autoGainEnabled)
        self._autoGainWeakThresholdDbfs = State(initialValue: settings.autoGainWeakThresholdDbfs)
        self._autoGainTargetPeakDbfs = State(initialValue: settings.autoGainTargetPeakDbfs)
        self._autoGainMaxDb = State(initialValue: settings.autoGainMaxDb)
        self._dictionaryWords = State(initialValue: userDictionaryWords)
        self.hotkeyConfig = settings.hotkeyConfig
        self.language = settings.language
        self.autoPunctuation = settings.autoPunctuation
        self.temperature = settings.temperature
        self.beamSize = settings.beamSize
        self.noSpeechThreshold = settings.noSpeechThreshold
        self.compressionRatioThreshold = settings.compressionRatioThreshold
        self.task = settings.task
        self.bestOf = settings.bestOf
        self.vadThreshold = settings.vadThreshold
        self.batchInterval = settings.batchInterval
        self.silenceThreshold = settings.silenceThreshold
        self.silenceDuration = settings.silenceDuration
        self.parallelism = settings.parallelism
        self.launchAtLogin = settings.launchAtLogin
        self.autoGainEnabled = settings.autoGainEnabled
        self.autoGainWeakThresholdDbfs = settings.autoGainWeakThresholdDbfs
        self.autoGainTargetPeakDbfs = settings.autoGainTargetPeakDbfs
        self.autoGainMaxDb = settings.autoGainMaxDb
        self.dictionaryWords = userDictionaryWords
        
        self._pendingHotkeyConfig = State(initialValue: settings.hotkeyConfig)
        self._pendingLanguage = State(initialValue: settings.language)
        self._pendingAutoPunctuation = State(initialValue: settings.autoPunctuation)
        self._pendingTemperature = State(initialValue: settings.temperature)
        self._pendingBeamSize = State(initialValue: settings.beamSize)
        self._pendingNoSpeechThreshold = State(initialValue: settings.noSpeechThreshold)
        self._pendingCompressionRatioThreshold = State(initialValue: settings.compressionRatioThreshold)
        self._pendingTask = State(initialValue: settings.task)
        self._pendingBestOf = State(initialValue: settings.bestOf)
        self._pendingVadThreshold = State(initialValue: settings.vadThreshold)
        self._pendingBatchInterval = State(initialValue: settings.batchInterval)
        self._pendingSilenceThreshold = State(initialValue: settings.silenceThreshold)
        self._pendingSilenceDuration = State(initialValue: settings.silenceDuration)
        self._pendingParallelism = State(initialValue: settings.parallelism)
        self._pendingLaunchAtLogin = State(initialValue: settings.launchAtLogin)
        self._pendingAutoGainEnabled = State(initialValue: settings.autoGainEnabled)
        self._pendingAutoGainWeakThresholdDbfs = State(initialValue: settings.autoGainWeakThresholdDbfs)
        self._pendingAutoGainTargetPeakDbfs = State(initialValue: settings.autoGainTargetPeakDbfs)
        self._pendingAutoGainMaxDb = State(initialValue: settings.autoGainMaxDb)
        self._pendingDictionaryWords = State(initialValue: userDictionaryWords)
        self._pendingDictionaryEntry = State(initialValue: "")
    }
    
    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            hotkeySettings
                .tabItem {
                    Label("Hotkey", systemImage: "keyboard")
                }
            
            transcriptionSettings
                .tabItem {
                    Label("Transcription", systemImage: "waveform")
                }
            
            batchSettings
                .tabItem {
                    Label("Batch", systemImage: "arrow.triangle.2.circlepath")
                }
            
            debugSettings
                .tabItem {
                    Label("Debug", systemImage: "ladybug")
                }
        }
        .frame(width: 600, height: 600)
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Launch at login", isOn: $pendingLaunchAtLogin)
                Text("When enabled, KotoType launches automatically when you sign in to macOS.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Quick Actions")
                    .font(.subheadline)

                Button("Import audio file...") {
                    onImportAudioRequested?()
                }
                .disabled(onImportAudioRequested == nil)

                Button("Open transcription history...") {
                    onShowHistoryRequested?()
                }
                .disabled(onShowHistoryRequested == nil)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Save") {
                    applySettings()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel") {
                    isPresented = false
                }
            }
        }
        .padding()
    }
    
    private var hotkeySettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Hotkey Settings")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Start / stop recording:")
                    .font(.subheadline)
                
                HotkeyRecorderView(initialConfig: hotkeyConfig, onChange: { config in
                    pendingHotkeyConfig = config
                })
                .frame(height: 40)
                
                Text("Current: \(hotkeyConfig.description.isEmpty ? "Not set" : hotkeyConfig.description)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Pending: \(pendingHotkeyConfig.description.isEmpty ? "Not set" : pendingHotkeyConfig.description)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            
            Divider()
            
            Text("Presets:")
                .font(.subheadline)
            
            VStack(alignment: .leading, spacing: 8) {
                Button("⌘+⌥ (Default)") {
                    pendingHotkeyConfig = HotkeyConfiguration(useCommand: true, useOption: true, useControl: false, useShift: false, keyCode: 0)
                }
                Button("⌃+⌥+Space") {
                    pendingHotkeyConfig = HotkeyConfiguration(useCommand: false, useOption: true, useControl: true, useShift: false, keyCode: 0x31)
                }
                Button("⌘+⌥+Space") {
                    pendingHotkeyConfig = HotkeyConfiguration(useCommand: true, useOption: true, useControl: false, useShift: false, keyCode: 0x31)
                }
                Button("⌃+⌥+B") {
                    pendingHotkeyConfig = HotkeyConfiguration(useCommand: false, useOption: true, useControl: true, useShift: false, keyCode: 0x0B)
                }
            }
            
            HStack {
                Spacer()
                Button("Save") {
                    applySettings()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel") {
                    isPresented = false
                }
            }
        }
        .padding()
    }
    
    private var transcriptionSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Transcription Settings")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Language:")
                        .font(.subheadline)

                    Picker("", selection: $pendingLanguage) {
                        ForEach(availableLanguages, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Task:")
                        .font(.subheadline)

                    Picker("", selection: $pendingTask) {
                        Text("Transcribe").tag("transcribe")
                        Text("Translate").tag("translate")
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Automatically improve punctuation", isOn: $pendingAutoPunctuation)

                    Text("When enabled, punctuation is normalized and sentence endings are completed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Accuracy (Temperature): \(String(format: "%.1f", pendingTemperature))")
                        .font(.subheadline)

                    Slider(value: $pendingTemperature, in: 0.0...1.0, step: 0.1)

                    Text("Lower values generally improve accuracy.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Beam Size: \(pendingBeamSize)")
                        .font(.subheadline)

                    Picker("", selection: $pendingBeamSize) {
                        Text("1 (Fast)").tag(1)
                        Text("5 (Standard)").tag(5)
                        Text("10 (High accuracy)").tag(10)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Best Of: \(pendingBestOf)")
                        .font(.subheadline)

                    Picker("", selection: $pendingBestOf) {
                        Text("1").tag(1)
                        Text("5").tag(5)
                        Text("10").tag(10)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("No Speech Threshold: \(String(format: "%.2f", pendingNoSpeechThreshold))")
                        .font(.subheadline)

                    Slider(value: $pendingNoSpeechThreshold, in: 0.1...1.0, step: 0.1)

                    Text("Threshold treated as silence")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Compression Ratio Threshold: \(String(format: "%.1f", pendingCompressionRatioThreshold))")
                        .font(.subheadline)

                    Slider(value: $pendingCompressionRatioThreshold, in: 1.0...5.0, step: 0.1)

                    Text("Compression ratio threshold")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("VAD Threshold: \(String(format: "%.2f", pendingVadThreshold))")
                        .font(.subheadline)

                    Slider(value: $pendingVadThreshold, in: 0.0...1.0, step: 0.1)

                    Text("Voice activity detection threshold")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Automatically amplify quiet input", isOn: $pendingAutoGainEnabled)

                    Text("Only low-level input is amplified before transcription.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Auto Gain weak-input threshold (dBFS): \(String(format: "%.1f", pendingAutoGainWeakThresholdDbfs))")
                        .font(.subheadline)

                    Slider(value: $pendingAutoGainWeakThresholdDbfs, in: (-40.0)...(-6.0), step: 1.0)
                        .disabled(!pendingAutoGainEnabled)

                    Text("Input lower than this value is amplified.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Auto Gain target peak (dBFS): \(String(format: "%.1f", pendingAutoGainTargetPeakDbfs))")
                        .font(.subheadline)

                    Slider(value: $pendingAutoGainTargetPeakDbfs, in: (-20.0)...(-1.0), step: 1.0)
                        .disabled(!pendingAutoGainEnabled)

                    Text("Target peak level after amplification")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Auto Gain max amplification (dB): \(String(format: "%.0f", pendingAutoGainMaxDb))")
                        .font(.subheadline)

                    Slider(value: $pendingAutoGainMaxDb, in: 3.0...30.0, step: 1.0)
                        .disabled(!pendingAutoGainEnabled)

                    Text("Upper limit to prevent excessive amplification")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Custom terminology dictionary")
                        .font(.subheadline)

                    HStack {
                        TextField("e.g. ctranslate2, Whisper large-v3-turbo", text: $pendingDictionaryEntry)
                            .onSubmit {
                                addDictionaryWord()
                            }
                        Button("Add") {
                            addDictionaryWord()
                        }
                        .disabled(pendingDictionaryEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if pendingDictionaryWords.isEmpty {
                        Text("No terms registered")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(pendingDictionaryWords, id: \.self) { word in
                                    HStack {
                                        Text(word)
                                            .lineLimit(1)
                                        Spacer()
                                        Button {
                                            removeDictionaryWord(word)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)

                        HStack {
                            Spacer()
                            Button("Remove all", role: .destructive) {
                                pendingDictionaryWords.removeAll()
                            }
                        }
                    }

                    Text("Up to 200 terms. Changes apply from the next transcription after saving.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Spacer()
                    Button("Save") {
                        applySettings()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .padding()
        }
    }
    
    private var batchSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Batch Processing Settings")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Split interval (seconds): \(String(format: "%.0f", pendingBatchInterval))")
                        .font(.subheadline)

                    Slider(value: $pendingBatchInterval, in: 5.0...30.0, step: 1.0)

                    Text("Files are split using silence detection at this interval.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Silence detection threshold (dB): \(String(format: "%.0f", pendingSilenceThreshold))")
                        .font(.subheadline)

                    Slider(value: $pendingSilenceThreshold, in: (-60.0)...(-20.0), step: 5.0)

                    Text("Audio below this level is treated as silence.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Silence duration (seconds): \(String(format: "%.1f", pendingSilenceDuration))")
                        .font(.subheadline)

                    Slider(value: $pendingSilenceDuration, in: 0.3...2.0, step: 0.1)

                    Text("Files are split when silence lasts longer than this duration.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Parallel process count: \(pendingParallelism)")
                        .font(.subheadline)

                    Picker("", selection: $pendingParallelism) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                        Text("4").tag(4)
                    }
                    .pickerStyle(.segmented)

                    Text("Number of processes running concurrently")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Spacer()
                    Button("Save") {
                        applySettings()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .padding()
        }
    }
    
    private var debugSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Debug")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Log file:")
                    .font(.subheadline)
                
                Text(Logger.shared.logPath)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
            }
            
            HStack {
                Button("Open log file") {
                    openLogFile()
                }
                
                Button("Open log directory") {
                    openLogDirectory()
                }
            }
            
            Text("Logs are useful for troubleshooting")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
    
    private func isValidKeyCode(_ keyCode: UInt32) -> Bool {
        if keyCode == 0 { return true }
        switch keyCode {
        case 0x00...0x0F, 0x10...0x2F, 0x31:
            return true
        default:
            return false
        }
    }
    
    private func saveSettings() {
        Logger.shared.log("SettingsView.saveSettings called: hotkey=\(hotkeyConfig.description), dictionaryWords=\(dictionaryWords.count)")
        let settings = AppSettings(
            hotkeyConfig: hotkeyConfig,
            language: language,
            autoPunctuation: autoPunctuation,
            temperature: temperature,
            beamSize: beamSize,
            noSpeechThreshold: noSpeechThreshold,
            compressionRatioThreshold: compressionRatioThreshold,
            task: task,
            bestOf: bestOf,
            vadThreshold: vadThreshold,
            batchInterval: batchInterval,
            silenceThreshold: silenceThreshold,
            silenceDuration: silenceDuration,
            parallelism: parallelism,
            launchAtLogin: launchAtLogin,
            autoGainEnabled: autoGainEnabled,
            autoGainWeakThresholdDbfs: autoGainWeakThresholdDbfs,
            autoGainTargetPeakDbfs: autoGainTargetPeakDbfs,
            autoGainMaxDb: autoGainMaxDb
        )
        SettingsManager.shared.save(settings)
        UserDictionaryManager.shared.saveWords(dictionaryWords)
    }

    private func applySettings() {
        Logger.shared.log("SettingsView.applySettings called: hotkey=\(pendingHotkeyConfig.description)")
        hotkeyConfig = pendingHotkeyConfig
        language = pendingLanguage
        autoPunctuation = pendingAutoPunctuation
        temperature = pendingTemperature
        beamSize = pendingBeamSize
        noSpeechThreshold = pendingNoSpeechThreshold
        compressionRatioThreshold = pendingCompressionRatioThreshold
        task = pendingTask
        bestOf = pendingBestOf
        vadThreshold = pendingVadThreshold
        batchInterval = pendingBatchInterval
        silenceThreshold = pendingSilenceThreshold
        silenceDuration = pendingSilenceDuration
        parallelism = pendingParallelism
        launchAtLogin = pendingLaunchAtLogin
        autoGainEnabled = pendingAutoGainEnabled
        autoGainWeakThresholdDbfs = pendingAutoGainWeakThresholdDbfs
        autoGainTargetPeakDbfs = pendingAutoGainTargetPeakDbfs
        autoGainMaxDb = pendingAutoGainMaxDb
        dictionaryWords = pendingDictionaryWords

        if autoGainTargetPeakDbfs <= autoGainWeakThresholdDbfs {
            autoGainTargetPeakDbfs = min(-1.0, autoGainWeakThresholdDbfs + 1.0)
            pendingAutoGainTargetPeakDbfs = autoGainTargetPeakDbfs
        }

        _ = LaunchAtLoginManager.shared.setEnabled(launchAtLogin)
        saveSettings()
        let reloadedWords = UserDictionaryManager.shared.loadWords()
        dictionaryWords = reloadedWords
        pendingDictionaryWords = reloadedWords
        pendingDictionaryEntry = ""
        onHotkeyChanged(hotkeyConfig)
        onSettingsChanged?()
    }

    private func addDictionaryWord() {
        let cleaned = pendingDictionaryEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        pendingDictionaryWords = UserDictionaryManager.normalizedWords(pendingDictionaryWords + [cleaned])
        pendingDictionaryEntry = ""
    }

    private func removeDictionaryWord(_ word: String) {
        pendingDictionaryWords.removeAll { $0 == word }
    }
    
    private func openLogFile() {
        let logPath = Logger.shared.logPath
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }
    
    private func openLogDirectory() {
        let logPath = Logger.shared.logPath
        let logDir = (logPath as NSString).deletingLastPathComponent
        NSWorkspace.shared.open(URL(fileURLWithPath: logDir))
    }
}

struct HotkeyRecorderView: NSViewRepresentable {
    let initialConfig: HotkeyConfiguration
    let onChange: (HotkeyConfiguration) -> Void
    
    func makeNSView(context: Context) -> HotkeyRecorder {
        HotkeyRecorder(initialConfig: initialConfig, onChange: onChange)
    }
    
    func updateNSView(_ nsView: HotkeyRecorder, context: Context) {
        if nsView.currentConfig != initialConfig {
            nsView.setConfig(initialConfig)
        }
    }
}
