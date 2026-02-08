import Foundation

struct InitialSetupCheckItem: Equatable {
    enum Status: Equatable {
        case passed
        case failed
    }

    let id: String
    let title: String
    let detail: String
    let status: Status
    let required: Bool
}

struct InitialSetupReport: Equatable {
    let items: [InitialSetupCheckItem]

    var canStartApplication: Bool {
        items.filter(\.required).allSatisfy { $0.status == .passed }
    }
}

final class InitialSetupDiagnosticsService: @unchecked Sendable {
    struct Runtime {
        var checkAccessibilityPermission: () -> PermissionChecker.PermissionStatus
        var checkMicrophonePermission: () -> PermissionChecker.PermissionStatus
        var requestAccessibilityPermission: () -> Void
        var requestMicrophonePermission: (@escaping @Sendable (PermissionChecker.PermissionStatus) -> Void) -> Void
        var resourcePath: () -> String?
        var backendScriptPath: () -> String
        var fileExists: (String) -> Bool
        var findExecutable: (String) -> String?
        var checkPythonDependencies: (String) -> Bool
    }

    private let runtime: Runtime

    init(runtime: Runtime = .live()) {
        self.runtime = runtime
    }

    func evaluate() -> InitialSetupReport {
        var items: [InitialSetupCheckItem] = []

        let accessibilityStatus = runtime.checkAccessibilityPermission()
        items.append(
            InitialSetupCheckItem(
                id: "accessibility",
                title: "アクセシビリティ権限",
                detail: accessibilityStatus == .granted
                    ? "許可済み"
                    : "キーボード入力シミュレーションに必要です",
                status: accessibilityStatus == .granted ? .passed : .failed,
                required: true
            )
        )

        let microphoneStatus = runtime.checkMicrophonePermission()
        items.append(
            InitialSetupCheckItem(
                id: "microphone",
                title: "マイク権限",
                detail: microphoneStatus == .granted
                    ? "許可済み"
                    : "録音機能に必要です",
                status: microphoneStatus == .granted ? .passed : .failed,
                required: true
            )
        )

        let bundledServerPath = runtime.resourcePath().map { "\($0)/whisper_server" }
        let bundledServerExists = bundledServerPath.map(runtime.fileExists) ?? false
        let scriptPath = runtime.backendScriptPath()
        let developmentScriptExists = runtime.fileExists(scriptPath)
        let scriptURL = URL(fileURLWithPath: scriptPath)
        let repositoryURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
        let developmentPythonPath = repositoryURL.appendingPathComponent(".venv/bin/python").path
        let developmentPythonExists = runtime.fileExists(developmentPythonPath)
        let backendAvailable = bundledServerExists || (developmentScriptExists && developmentPythonExists)

        items.append(
            InitialSetupCheckItem(
                id: "backend",
                title: "文字起こしバックエンド",
                detail: backendAvailable
                    ? (bundledServerExists
                        ? "同梱済みの whisper_server バイナリを使用"
                        : "開発環境の Python バックエンドを使用")
                    : "whisper_server バイナリ、または .venv/bin/python + python/whisper_server.py が必要です",
                status: backendAvailable ? .passed : .failed,
                required: true
            )
        )

        let ffmpegPath = runtime.findExecutable("ffmpeg")
        items.append(
            InitialSetupCheckItem(
                id: "ffmpeg",
                title: "FFmpeg",
                detail: ffmpegPath.map { "検出済み: \($0)" } ?? "ffmpeg コマンドが見つかりません",
                status: ffmpegPath == nil ? .failed : .passed,
                required: true
            )
        )

        let pythonDependenciesReady: Bool
        if bundledServerExists {
            pythonDependenciesReady = true
        } else if developmentPythonExists {
            pythonDependenciesReady = runtime.checkPythonDependencies(developmentPythonPath)
        } else {
            pythonDependenciesReady = false
        }
        items.append(
            InitialSetupCheckItem(
                id: "pythonDependencies",
                title: "Python依存関係",
                detail: pythonDependenciesReady
                    ? "faster-whisper / ffmpeg-python を利用可能"
                    : "必要な Python 依存関係が不足しています（`make install-deps`）",
                status: pythonDependenciesReady ? .passed : .failed,
                required: true
            )
        )

        return InitialSetupReport(items: items)
    }

    func requestAccessibilityPermission() {
        runtime.requestAccessibilityPermission()
    }

    func requestMicrophonePermission(completion: @escaping @Sendable (PermissionChecker.PermissionStatus) -> Void) {
        runtime.requestMicrophonePermission(completion)
    }
}

extension InitialSetupDiagnosticsService.Runtime {
    static func live() -> InitialSetupDiagnosticsService.Runtime {
        InitialSetupDiagnosticsService.Runtime(
            checkAccessibilityPermission: { PermissionChecker.shared.checkAccessibilityPermission() },
            checkMicrophonePermission: { PermissionChecker.shared.checkMicrophonePermission() },
            requestAccessibilityPermission: { PermissionChecker.shared.requestAccessibilityPermission() },
            requestMicrophonePermission: { completion in
                PermissionChecker.shared.requestMicrophonePermission(completion: completion)
            },
            resourcePath: { Bundle.main.resourcePath },
            backendScriptPath: { BackendLocator.serverScriptPath() },
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            findExecutable: { name in
                InitialSetupDiagnosticsService.findExecutable(named: name)
            },
            checkPythonDependencies: { pythonPath in
                InitialSetupDiagnosticsService.checkPythonDependencies(pythonPath: pythonPath)
            }
        )
    }
}

extension InitialSetupDiagnosticsService {
    static func findExecutable(named name: String) -> String? {
        let fallbackPaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        for path in fallbackPaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !output.isEmpty else {
                return nil
            }
            return output
        } catch {
            return nil
        }
    }

    static func checkPythonDependencies(pythonPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", "import faster_whisper, ffmpeg"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
