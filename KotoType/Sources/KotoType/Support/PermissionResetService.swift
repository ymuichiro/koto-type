import Foundation

final class PermissionResetService: @unchecked Sendable {
    struct Command: Equatable {
        let executablePath: String
        let arguments: [String]

        var rendered: String {
            ([executablePath] + arguments).joined(separator: " ")
        }
    }

    struct CommandResult: Equatable {
        let exitCode: Int32
        let standardError: String
    }

    struct Runtime {
        var currentBundleIdentifier: () -> String?
        var currentBundlePath: () -> String
        var currentBundleVersion: () -> String
        var modificationDateForPath: (String) -> Date?
        var run: (Command) -> CommandResult
    }

    private let runtime: Runtime
    private let stateManager: PermissionResetStateManager

    init(
        runtime: Runtime = .live(),
        stateManager: PermissionResetStateManager = .shared
    ) {
        self.runtime = runtime
        self.stateManager = stateManager
    }

    @discardableResult
    func resetPermissionsIfNeeded(for report: InitialSetupReport) -> Bool {
        guard report.hasFailingRequiredPermissions else {
            stateManager.clearResetAttempt()
            return false
        }

        let bundlePath = runtime.currentBundlePath()
        let installationToken = Self.installationToken(
            bundlePath: bundlePath,
            bundleVersion: runtime.currentBundleVersion(),
            modificationDate: runtime.modificationDateForPath(bundlePath)
        )

        guard !stateManager.hasAttemptedReset(for: installationToken) else {
            Logger.shared.log(
                "PermissionResetService: automatic permission reset already attempted for installation token \(installationToken)",
                level: .debug
            )
            return false
        }

        guard let bundleIdentifier = runtime.currentBundleIdentifier(), !bundleIdentifier.isEmpty else {
            Logger.shared.log(
                "PermissionResetService: missing bundle identifier, skipping automatic permission reset",
                level: .warning
            )
            return false
        }

        let command = Self.makeResetCommand(bundleIdentifier: bundleIdentifier)
        let result = runtime.run(command)
        guard result.exitCode == 0 else {
            let detail = result.standardError.isEmpty ? "unknown error" : result.standardError
            Logger.shared.log(
                "PermissionResetService: automatic permission reset failed with exit code \(result.exitCode): \(detail)",
                level: .warning
            )
            return false
        }

        stateManager.markResetAttempt(for: installationToken, command: command.rendered)
        Logger.shared.log(
            "PermissionResetService: reset all TCC permissions with command: \(command.rendered)",
            level: .info
        )
        return true
    }

    static func makeResetCommand(bundleIdentifier: String) -> Command {
        Command(
            executablePath: "/usr/bin/tccutil",
            arguments: ["reset", "All", bundleIdentifier]
        )
    }

    static func installationToken(
        bundlePath: String,
        bundleVersion: String,
        modificationDate: Date?
    ) -> String {
        let normalizedBundlePath = URL(fileURLWithPath: bundlePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        let modifiedAt = modificationDate?.timeIntervalSince1970 ?? 0
        return "\(normalizedBundlePath)#\(bundleVersion)#\(Int64(modifiedAt))"
    }
}

extension PermissionResetService.Runtime {
    static func live() -> PermissionResetService.Runtime {
        PermissionResetService.Runtime(
            currentBundleIdentifier: { Bundle.main.bundleIdentifier },
            currentBundlePath: { Bundle.main.bundlePath },
            currentBundleVersion: {
                Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            },
            modificationDateForPath: { path in
                let attributes = try? FileManager.default.attributesOfItem(atPath: path)
                return attributes?[.modificationDate] as? Date
            },
            run: { command in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command.executablePath)
                process.arguments = command.arguments

                let standardOutput = Pipe()
                let standardError = Pipe()
                process.standardOutput = standardOutput
                process.standardError = standardError

                do {
                    try process.run()
                    process.waitUntilExit()

                    let standardErrorData = standardError.fileHandleForReading.readDataToEndOfFile()
                    let standardErrorText = String(data: standardErrorData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    return PermissionResetService.CommandResult(
                        exitCode: process.terminationStatus,
                        standardError: standardErrorText
                    )
                } catch {
                    return PermissionResetService.CommandResult(
                        exitCode: -1,
                        standardError: error.localizedDescription
                    )
                }
            }
        )
    }
}
