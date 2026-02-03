import AppKit
import Foundation
import os.log

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?
    var hotkeyManager: HotkeyManager?
    var audioRecorder: AudioRecorder?
    var pythonProcessManager: PythonProcessManager?
    var settingsWindowController: SettingsWindowController?
    var recordingIndicatorWindow: RecordingIndicatorWindow?
    var permissionWindowController: PermissionWindowController?
    var isRecording = false
    private var currentSettings: AppSettings = AppSettings()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.log("Application did finish launching", level: .info)
        
        let permissionStatus = PermissionChecker.shared.checkAccessibilityPermission()
        if permissionStatus == .denied {
            showPermissionWindow()
            return
        }
        
        continueSetup()
    }
    
    private func showPermissionWindow() {
        permissionWindowController = PermissionWindowController()
        permissionWindowController?.showWindow(nil)
        
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.permissionWindowController?.close()
        }
    }
    
    private func continueSetup() {
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController()
        Logger.shared.log("MenuBarController created", level: .debug)
        
        audioRecorder = AudioRecorder()
        Logger.shared.log("AudioRecorder created", level: .debug)
        pythonProcessManager = PythonProcessManager()
        Logger.shared.log("PythonProcessManager created", level: .debug)
        settingsWindowController = SettingsWindowController()
        recordingIndicatorWindow = RecordingIndicatorWindow()
        Logger.shared.log("RecordingIndicatorWindow created", level: .debug)
        
        menuBarController?.showSettings = { [weak self] in
            self?.settingsWindowController?.showSettings()
        }
        
        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        
        var workingDirectory = currentPath
        if currentPath.contains("STTApp") {
            workingDirectory = currentPath.replacingOccurrences(of: "/STTApp", with: "")
        }
        
        let scriptPath = "\(workingDirectory)/features/whisper_transcription/server.py"
        Logger.shared.log("Starting Python process at: \(scriptPath)", level: .info)
        pythonProcessManager?.startPython(scriptPath: scriptPath)
        
        pythonProcessManager?.outputReceived = { [weak self] output in
            guard let self = self else { return }
            Logger.shared.log("Transcription received: '\(output)'", level: .info)
            
            if output.isEmpty {
                Logger.shared.log("Empty transcription received, skipping", level: .warning)
                self.menuBarController?.updateStatus("Ready")
                self.recordingIndicatorWindow?.hide()
            } else {
                Logger.shared.log("Typing text into active window...", level: .info)
                KeystrokeSimulator.typeText(output)
                Logger.shared.log("Text typing completed", level: .info)
                self.menuBarController?.updateStatus("Ready")
                self.recordingIndicatorWindow?.hide()
            }
        }
        
        currentSettings = SettingsManager.shared.load()
        Logger.shared.log("Loaded settings: \(currentSettings)", level: .info)
        
        hotkeyManager = HotkeyManager()
        hotkeyManager?.hotkeyKeyDown = { [weak self] in
            self?.startRecording()
        }
        hotkeyManager?.hotkeyKeyUp = { [weak self] in
            self?.stopRecording()
        }
        
        NotificationCenter.default.addObserver(forName: .hotkeyConfigurationChanged, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            if let config = notification.object as? HotkeyConfiguration {
                Logger.shared.log("AppDelegate: Received hotkeyConfigurationChanged notification: \(config.description)")
            }
            self.currentSettings = SettingsManager.shared.load()
            Logger.shared.log("AppDelegate: Reloaded settings - language=\(self.currentSettings.language), temp=\(self.currentSettings.temperature), beam=\(self.currentSettings.beamSize)")
        }
    }
    
    func startRecording() {
        isRecording = true
        Logger.shared.log("Starting audio recording...", level: .info)
        guard let url = audioRecorder?.startRecording() else {
            Logger.shared.log("Failed to start recording", level: .error)
            isRecording = false
            return
        }
        Logger.shared.log("Recording started at: \(url.path)", level: .info)
        menuBarController?.updateStatus("Recording...")
        recordingIndicatorWindow?.show()
    }
    
    func stopRecording() {
        isRecording = false
        Logger.shared.log("Stopping audio recording...", level: .info)
        guard let recordingURL = audioRecorder?.recordingURL else {
            Logger.shared.log("No recording URL available", level: .error)
            return
        }
        audioRecorder?.stopRecording()
        Logger.shared.log("Recording stopped at: \(recordingURL.path)", level: .info)
        Logger.shared.log("Sending audio path to Python: \(recordingURL.path)", level: .info)
        
        currentSettings = SettingsManager.shared.load()
        pythonProcessManager?.sendInput(
            recordingURL.path,
            language: currentSettings.language,
            temperature: currentSettings.temperature,
            beamSize: currentSettings.beamSize
        )
        
        Logger.shared.log("Audio path sent to Python, waiting for transcription...", level: .info)
        menuBarController?.updateStatus("Processing...")
        recordingIndicatorWindow?.showProcessing()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.cleanup()
        pythonProcessManager?.stop()
    }
}

@main
struct Main {
    static func main() {
        print("Main: Starting application")
        let app = NSApplication.shared
        print("Main: Application created")
        app.setActivationPolicy(.accessory)
        print("Main: Activation policy set to accessory")
        
        let delegate = AppDelegate()
        print("Main: AppDelegate created")
        app.delegate = delegate
        print("Main: Delegate assigned")
        
        print("Main: Running application")
        app.run()
    }
}
