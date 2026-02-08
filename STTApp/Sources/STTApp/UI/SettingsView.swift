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
    @State private var dictionaryWords: [String]
    @Binding var isPresented: Bool
    
    let onHotkeyChanged: (HotkeyConfiguration) -> Void
    let onSettingsChanged: (() -> Void)?
    
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
    @State private var pendingDictionaryWords: [String]
    @State private var pendingDictionaryEntry: String
    
    let availableLanguages = [
        ("auto", "自動判定"),
        ("ja", "日本語"),
        ("en", "英語"),
        ("zh", "中国語"),
        ("ko", "韓国語"),
        ("es", "スペイン語"),
        ("fr", "フランス語"),
        ("de", "ドイツ語"),
    ]
    
    init(isPresented: Binding<Bool>, onHotkeyChanged: @escaping (HotkeyConfiguration) -> Void, onSettingsChanged: (() -> Void)? = nil) {
        self._isPresented = isPresented
        self.onHotkeyChanged = onHotkeyChanged
        self.onSettingsChanged = onSettingsChanged
        
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
        self._pendingDictionaryWords = State(initialValue: userDictionaryWords)
        self._pendingDictionaryEntry = State(initialValue: "")
    }
    
    var body: some View {
        TabView {
            hotkeySettings
                .tabItem {
                    Label("ホットキー", systemImage: "keyboard")
                }
            
            transcriptionSettings
                .tabItem {
                    Label("文字起こし", systemImage: "waveform")
                }
            
            batchSettings
                .tabItem {
                    Label("バッチ処理", systemImage: "arrow.triangle.2.circlepath")
                }
            
            debugSettings
                .tabItem {
                    Label("デバッグ", systemImage: "ladybug")
                }
        }
        .frame(width: 600, height: 600)
    }
    
    private var hotkeySettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ホットキー設定")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("録音の開始・終了:")
                    .font(.subheadline)
                
                HotkeyRecorderView(initialConfig: hotkeyConfig, onChange: { config in
                    pendingHotkeyConfig = config
                })
                .frame(height: 40)
                
                Text("現在: \(hotkeyConfig.description.isEmpty ? "未設定" : hotkeyConfig.description)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("変更中: \(pendingHotkeyConfig.description.isEmpty ? "未設定" : pendingHotkeyConfig.description)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            
            Divider()
            
            Text("プリセット:")
                .font(.subheadline)
            
            VStack(alignment: .leading, spacing: 8) {
                Button("⌘+⌥ (デフォルト)") {
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
                Button("保存") {
                    applySettings()
                }
                .keyboardShortcut(.defaultAction)
                Button("キャンセル") {
                    isPresented = false
                }
            }
        }
        .padding()
    }
    
    private var transcriptionSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("文字起こし設定")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("言語:")
                        .font(.subheadline)

                    Picker("", selection: $pendingLanguage) {
                        ForEach(availableLanguages, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("タスク:")
                        .font(.subheadline)

                    Picker("", selection: $pendingTask) {
                        Text("文字起こし").tag("transcribe")
                        Text("翻訳").tag("translate")
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("句読点を自動補正する", isOn: $pendingAutoPunctuation)

                    Text("有効時は句読点の正規化と文末補完を行います")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("精度 (Temperature): \(String(format: "%.1f", pendingTemperature))")
                        .font(.subheadline)

                    Slider(value: $pendingTemperature, in: 0.0...1.0, step: 0.1)

                    Text("値が低いほど精度が高くなります")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Beam Size: \(pendingBeamSize)")
                        .font(.subheadline)

                    Picker("", selection: $pendingBeamSize) {
                        Text("1 (高速)").tag(1)
                        Text("5 (標準)").tag(5)
                        Text("10 (高精度)").tag(10)
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

                    Text("無音とみなす閾値")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Compression Ratio Threshold: \(String(format: "%.1f", pendingCompressionRatioThreshold))")
                        .font(.subheadline)

                    Slider(value: $pendingCompressionRatioThreshold, in: 1.0...5.0, step: 0.1)

                    Text("圧縮率の閾値")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("VAD Threshold: \(String(format: "%.2f", pendingVadThreshold))")
                        .font(.subheadline)

                    Slider(value: $pendingVadThreshold, in: 0.0...1.0, step: 0.1)

                    Text("音声検出の閾値")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("専門用語辞書")
                        .font(.subheadline)

                    HStack {
                        TextField("例: ctranslate2, Whisper large-v3-turbo", text: $pendingDictionaryEntry)
                            .onSubmit {
                                addDictionaryWord()
                            }
                        Button("追加") {
                            addDictionaryWord()
                        }
                        .disabled(pendingDictionaryEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if pendingDictionaryWords.isEmpty {
                        Text("登録された用語はありません")
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
                            Button("すべて削除", role: .destructive) {
                                pendingDictionaryWords.removeAll()
                            }
                        }
                    }

                    Text("最大200語まで。保存後、次回の文字起こしから反映されます。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Spacer()
                    Button("保存") {
                        applySettings()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("キャンセル") {
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
                Text("バッチ処理設定")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("分割間隔 (秒): \(String(format: "%.0f", pendingBatchInterval))")
                        .font(.subheadline)

                    Slider(value: $pendingBatchInterval, in: 5.0...30.0, step: 1.0)

                    Text("この時間ごとに無音検出でファイル分割します")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("無音検出閾値 (dB): \(String(format: "%.0f", pendingSilenceThreshold))")
                        .font(.subheadline)

                    Slider(value: $pendingSilenceThreshold, in: (-60.0)...(-20.0), step: 5.0)

                    Text("このレベル以下を無音とみなします")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("無音持続時間 (秒): \(String(format: "%.1f", pendingSilenceDuration))")
                        .font(.subheadline)

                    Slider(value: $pendingSilenceDuration, in: 0.3...2.0, step: 0.1)

                    Text("この時間以上無音が続くとファイル分割します")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("並列プロセス数: \(pendingParallelism)")
                        .font(.subheadline)

                    Picker("", selection: $pendingParallelism) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                        Text("4").tag(4)
                    }
                    .pickerStyle(.segmented)

                    Text("同時に処理するプロセス数")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Spacer()
                    Button("保存") {
                        applySettings()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("キャンセル") {
                        isPresented = false
                    }
                }
            }
            .padding()
        }
    }
    
    private var debugSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("デバッグ")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("ログファイル:")
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
                Button("ログファイルを開く") {
                    openLogFile()
                }
                
                Button("ログディレクトリを開く") {
                    openLogDirectory()
                }
            }
            
            Text("ログは問題の診断に役立ちます")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Spacer()
                Button("キャンセル") {
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
            parallelism: parallelism
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
        dictionaryWords = pendingDictionaryWords

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
