import Foundation

struct FFmpegInstallResult: Equatable {
    let ffmpegPath: String
    let homebrewInstalled: Bool
}

final class FFmpegInstallerService: @unchecked Sendable {
    struct Command: Equatable {
        let executablePath: String
        let arguments: [String]
        let environment: [String: String]
    }

    struct CommandResult: Equatable {
        let exitCode: Int32
        let standardOutput: String
        let standardError: String
    }

    enum InstallError: Error, LocalizedError, Equatable {
        case homebrewInstallFailed(String)
        case brewNotFoundAfterInstall
        case ffmpegInstallFailed(String)
        case ffmpegNotFoundAfterInstall

        var errorDescription: String? {
            switch self {
            case let .homebrewInstallFailed(message):
                return "Homebrew installation failed: \(message)"
            case .brewNotFoundAfterInstall:
                return "Homebrew finished without exposing a usable `brew` command."
            case let .ffmpegInstallFailed(message):
                return "FFmpeg installation failed: \(message)"
            case .ffmpegNotFoundAfterInstall:
                return "FFmpeg installation completed but `ffmpeg` is still not available."
            }
        }
    }

    struct Runtime {
        var findExecutable: (String) -> String?
        var run: (Command) -> CommandResult
    }

    private let runtime: Runtime

    init(runtime: Runtime = .live()) {
        self.runtime = runtime
    }

    func installFFmpeg() -> Result<FFmpegInstallResult, InstallError> {
        if let ffmpegPath = runtime.findExecutable("ffmpeg") {
            return .success(
                FFmpegInstallResult(
                    ffmpegPath: ffmpegPath,
                    homebrewInstalled: false
                )
            )
        }

        var homebrewInstalled = false
        var brewPath = runtime.findExecutable("brew")
        if brewPath == nil {
            let installResult = runtime.run(Self.bootstrapHomebrewCommand())
            guard installResult.exitCode == 0 else {
                return .failure(
                    .homebrewInstallFailed(Self.message(from: installResult))
                )
            }
            homebrewInstalled = true
            brewPath = runtime.findExecutable("brew")
        }

        guard let brewPath else {
            return .failure(.brewNotFoundAfterInstall)
        }

        let ffmpegInstallResult = runtime.run(
            Self.installFFmpegCommand(brewPath: brewPath)
        )
        guard ffmpegInstallResult.exitCode == 0 else {
            return .failure(
                .ffmpegInstallFailed(Self.message(from: ffmpegInstallResult))
            )
        }

        guard let ffmpegPath = runtime.findExecutable("ffmpeg") else {
            return .failure(.ffmpegNotFoundAfterInstall)
        }

        return .success(
            FFmpegInstallResult(
                ffmpegPath: ffmpegPath,
                homebrewInstalled: homebrewInstalled
            )
        )
    }

    static func bootstrapHomebrewCommand() -> Command {
        Command(
            executablePath: "/bin/bash",
            arguments: [
                "-c",
                #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
            ],
            environment: baseEnvironment()
        )
    }

    static func installFFmpegCommand(brewPath: String) -> Command {
        Command(
            executablePath: brewPath,
            arguments: ["install", "ffmpeg"],
            environment: baseEnvironment()
        )
    }

    private static func baseEnvironment() -> [String: String] {
        [
            "CI": "1",
            "HOMEBREW_NO_ANALYTICS": "1",
            "HOMEBREW_NO_ENV_HINTS": "1",
            "NONINTERACTIVE": "1",
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        ]
    }

    private static func message(from result: CommandResult) -> String {
        let output = [result.standardError, result.standardOutput]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty {
            return "exit code \(result.exitCode)"
        }
        return output
    }
}

extension FFmpegInstallerService.Runtime {
    static func live() -> FFmpegInstallerService.Runtime {
        FFmpegInstallerService.Runtime(
            findExecutable: { name in
                InitialSetupDiagnosticsService.findExecutable(named: name)
            },
            run: { command in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command.executablePath)
                process.arguments = command.arguments
                process.environment = command.environment
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                    process.waitUntilExit()
                    let standardOutput = String(
                        data: stdout.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""
                    let standardError = String(
                        data: stderr.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""
                    return FFmpegInstallerService.CommandResult(
                        exitCode: process.terminationStatus,
                        standardOutput: standardOutput,
                        standardError: standardError
                    )
                } catch {
                    return FFmpegInstallerService.CommandResult(
                        exitCode: 1,
                        standardOutput: "",
                        standardError: String(describing: error)
                    )
                }
            }
        )
    }
}
