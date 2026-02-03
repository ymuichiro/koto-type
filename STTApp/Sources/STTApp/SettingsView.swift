import SwiftUI
import AppKit

struct SettingsView: View {
    @State private var hotkeyConfig: HotkeyConfiguration
    @State private var language: String
    @State private var temperature: Double
    @State private var beamSize: Int
    @Binding var isPresented: Bool
    
    let onHotkeyChanged: (HotkeyConfiguration) -> Void
    let onSettingsChanged: (() -> Void)?
    
    @State private var pendingHotkeyConfig: HotkeyConfiguration
    @State private var pendingLanguage: String
    @State private var pendingTemperature: Double
    @State private var pendingBeamSize: Int
    
    let availableLanguages = [
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
        self._hotkeyConfig = State(initialValue: settings.hotkeyConfig)
        self._language = State(initialValue: settings.language)
        self._temperature = State(initialValue: settings.temperature)
        self._beamSize = State(initialValue: settings.beamSize)
        
        self._pendingHotkeyConfig = State(initialValue: settings.hotkeyConfig)
        self._pendingLanguage = State(initialValue: settings.language)
        self._pendingTemperature = State(initialValue: settings.temperature)
        self._pendingBeamSize = State(initialValue: settings.beamSize)
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
            
            debugSettings
                .tabItem {
                    Label("デバッグ", systemImage: "ladybug")
                }
        }
        .frame(width: 500, height: 450)
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
        Logger.shared.log("SettingsView.saveSettings called: hotkey=\(hotkeyConfig.description)")
        let settings = AppSettings(
            hotkeyConfig: hotkeyConfig,
            language: language,
            temperature: temperature,
            beamSize: beamSize
        )
        SettingsManager.shared.save(settings)
    }
    
    private func applySettings() {
        Logger.shared.log("SettingsView.applySettings called: hotkey=\(pendingHotkeyConfig.description)")
        hotkeyConfig = pendingHotkeyConfig
        language = pendingLanguage
        temperature = pendingTemperature
        beamSize = pendingBeamSize
        
        saveSettings()
        onHotkeyChanged(hotkeyConfig)
        onSettingsChanged?()
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
