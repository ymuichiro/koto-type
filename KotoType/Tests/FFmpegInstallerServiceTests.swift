@testable import KotoType
import XCTest

final class FFmpegInstallerServiceTests: XCTestCase {
    func testInstallFFmpegReturnsExistingBinaryWithoutRunningCommands() {
        let recorder = InstallerCommandRecorder(
            findExecutable: { name in
                if name == "ffmpeg" {
                    return "/opt/homebrew/bin/ffmpeg"
                }
                return nil
            }
        )
        let service = FFmpegInstallerService(
            runtime: .init(
                findExecutable: recorder.findExecutable,
                run: recorder.run
            )
        )

        let result = service.installFFmpeg()

        XCTAssertEqual(
            result,
            .success(
                FFmpegInstallResult(
                    ffmpegPath: "/opt/homebrew/bin/ffmpeg",
                    homebrewInstalled: false
                )
            )
        )
        XCTAssertTrue(recorder.commands.isEmpty)
    }

    func testInstallFFmpegUsesExistingHomebrew() {
        let recorder = InstallerCommandRecorder()
        recorder.brewPath = "/opt/homebrew/bin/brew"
        recorder.ffmpegPath = nil
        recorder.commandResults = [
            FFmpegInstallerService.CommandResult(
                exitCode: 0,
                standardOutput: "installed",
                standardError: ""
            )
        ]
        recorder.afterCommand = { _, index in
            if index == 0 {
                recorder.ffmpegPath = "/opt/homebrew/bin/ffmpeg"
            }
        }
        let service = FFmpegInstallerService(
            runtime: .init(
                findExecutable: recorder.findExecutable,
                run: recorder.run
            )
        )

        let result = service.installFFmpeg()

        XCTAssertEqual(
            result,
            .success(
                FFmpegInstallResult(
                    ffmpegPath: "/opt/homebrew/bin/ffmpeg",
                    homebrewInstalled: false
                )
            )
        )
        XCTAssertEqual(
            recorder.commands,
            [FFmpegInstallerService.installFFmpegCommand(brewPath: "/opt/homebrew/bin/brew")]
        )
    }

    func testInstallFFmpegBootstrapsHomebrewBeforeInstalling() {
        let recorder = InstallerCommandRecorder()
        recorder.commandResults = [
            FFmpegInstallerService.CommandResult(
                exitCode: 0,
                standardOutput: "homebrew installed",
                standardError: ""
            ),
            FFmpegInstallerService.CommandResult(
                exitCode: 0,
                standardOutput: "ffmpeg installed",
                standardError: ""
            ),
        ]
        recorder.afterCommand = { _, index in
            if index == 0 {
                recorder.brewPath = "/opt/homebrew/bin/brew"
            }
            if index == 1 {
                recorder.ffmpegPath = "/opt/homebrew/bin/ffmpeg"
            }
        }
        let service = FFmpegInstallerService(
            runtime: .init(
                findExecutable: recorder.findExecutable,
                run: recorder.run
            )
        )

        let result = service.installFFmpeg()

        XCTAssertEqual(
            result,
            .success(
                FFmpegInstallResult(
                    ffmpegPath: "/opt/homebrew/bin/ffmpeg",
                    homebrewInstalled: true
                )
            )
        )
        XCTAssertEqual(
            recorder.commands,
            [
                FFmpegInstallerService.bootstrapHomebrewCommand(),
                FFmpegInstallerService.installFFmpegCommand(brewPath: "/opt/homebrew/bin/brew"),
            ]
        )
    }
}

private final class InstallerCommandRecorder {
    var brewPath: String?
    var ffmpegPath: String?
    var commandResults: [FFmpegInstallerService.CommandResult] = []
    var commands: [FFmpegInstallerService.Command] = []
    var afterCommand: ((FFmpegInstallerService.Command, Int) -> Void)?

    init(findExecutable: ((String) -> String?)? = nil) {
        self.customFindExecutable = findExecutable
    }

    private let customFindExecutable: ((String) -> String?)?

    lazy var findExecutable: (String) -> String? = { [weak self] name in
        guard let self else { return nil }
        if let custom = self.customFindExecutable {
            return custom(name)
        }
        switch name {
        case "brew":
            return self.brewPath
        case "ffmpeg":
            return self.ffmpegPath
        default:
            return nil
        }
    }

    lazy var run: (FFmpegInstallerService.Command) -> FFmpegInstallerService.CommandResult = { [weak self] command in
        guard let self else {
            return .init(exitCode: 1, standardOutput: "", standardError: "recorder released")
        }
        let index = self.commands.count
        self.commands.append(command)
        self.afterCommand?(command, index)
        if index < self.commandResults.count {
            return self.commandResults[index]
        }
        return .init(exitCode: 0, standardOutput: "", standardError: "")
    }
}
