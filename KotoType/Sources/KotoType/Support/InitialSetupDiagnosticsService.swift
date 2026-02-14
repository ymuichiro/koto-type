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
    enum BundleExecutionLocation: Equatable {
        case appTranslocation
        case systemApplications
        case userApplications
        case outsideApplications
    }

    struct Runtime {
        var checkAccessibilityPermission: () -> PermissionChecker.PermissionStatus
        var checkMicrophonePermission: () -> PermissionChecker.PermissionStatus
        var requestAccessibilityPermission: () -> Void
        var requestMicrophonePermission: (@escaping @Sendable (PermissionChecker.PermissionStatus) -> Void) -> Void
        var findExecutable: (String) -> String?
        var currentBundlePath: () -> String
    }

    private let runtime: Runtime

    init(runtime: Runtime = .live()) {
        self.runtime = runtime
    }

    func evaluate() -> InitialSetupReport {
        var items: [InitialSetupCheckItem] = []

        let accessibilityStatus = runtime.checkAccessibilityPermission()
        let bundleExecutionLocation = Self.bundleExecutionLocation(for: runtime.currentBundlePath())
        let accessibilityDetail: String
        if accessibilityStatus == .granted {
            accessibilityDetail = "Granted"
        } else if bundleExecutionLocation == .appTranslocation {
            accessibilityDetail = "Running from App Translocation may prevent permission changes from applying. Move the app to Applications (/Applications or ~/Applications) and relaunch."
        } else if bundleExecutionLocation == .outsideApplications {
            accessibilityDetail = "To avoid recurring permission issues, launch the app from Applications (/Applications or ~/Applications)."
        } else {
            accessibilityDetail = "Required to simulate keyboard input"
        }
        items.append(
            InitialSetupCheckItem(
                id: "accessibility",
                title: "Accessibility Permission",
                detail: accessibilityDetail,
                status: accessibilityStatus == .granted ? .passed : .failed,
                required: true
            )
        )

        let microphoneStatus = runtime.checkMicrophonePermission()
        items.append(
            InitialSetupCheckItem(
                id: "microphone",
                title: "Microphone Permission",
                detail: microphoneStatus == .granted
                    ? "Granted"
                    : "Required for recording",
                status: microphoneStatus == .granted ? .passed : .failed,
                required: true
            )
        )

        let ffmpegPath = runtime.findExecutable("ffmpeg")
        items.append(
            InitialSetupCheckItem(
                id: "ffmpeg",
                title: "FFmpeg",
                detail: ffmpegPath.map { "Detected: \($0)" } ?? "ffmpeg command not found",
                status: ffmpegPath == nil ? .failed : .passed,
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
            findExecutable: { name in
                InitialSetupDiagnosticsService.findExecutable(named: name)
            },
            currentBundlePath: { Bundle.main.bundlePath }
        )
    }
}

extension InitialSetupDiagnosticsService {
    static func bundleExecutionLocation(
        for rawBundlePath: String,
        homeDirectory: String = NSHomeDirectory()
    ) -> BundleExecutionLocation {
        let normalizedBundlePath = URL(fileURLWithPath: rawBundlePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path

        if normalizedBundlePath.contains("/AppTranslocation/") {
            return .appTranslocation
        }

        if normalizedBundlePath.hasPrefix("/Applications/") {
            return .systemApplications
        }

        let userApplicationsRoot = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL
            .path

        if normalizedBundlePath == userApplicationsRoot || normalizedBundlePath.hasPrefix(userApplicationsRoot + "/") {
            return .userApplications
        }

        return .outsideApplications
    }

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

}
