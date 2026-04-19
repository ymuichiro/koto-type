@testable import KotoType
import XCTest

final class PermissionResetServiceTests: XCTestCase {
    func testResetPermissionsIfNeededRunsBundleWideResetWhenPermissionIsMissing() {
        let defaults = UserDefaults(suiteName: "PermissionResetServiceTests-\(UUID().uuidString)")!
        let stateManager = PermissionResetStateManager(defaults: defaults)
        let commandRecorder = CommandRecorder()
        let service = makeService(
            stateManager: stateManager,
            commandRecorder: commandRecorder
        )

        let didReset = service.resetPermissionsIfNeeded(
            for: makeReport(accessibility: .failed)
        )

        XCTAssertTrue(didReset)
        XCTAssertEqual(
            commandRecorder.commands,
            [PermissionResetService.makeResetCommand(bundleIdentifier: "com.ymuichiro.kototype")]
        )
        XCTAssertEqual(
            stateManager.lastResetCommand,
            "/usr/bin/tccutil reset All com.ymuichiro.kototype"
        )
    }

    func testResetPermissionsIfNeededSkipsWhenOnlyFFmpegIsMissing() {
        let defaults = UserDefaults(suiteName: "PermissionResetServiceTests-\(UUID().uuidString)")!
        let stateManager = PermissionResetStateManager(defaults: defaults)
        let commandRecorder = CommandRecorder()
        let service = makeService(
            stateManager: stateManager,
            commandRecorder: commandRecorder
        )

        let didReset = service.resetPermissionsIfNeeded(
            for: makeReport(accessibility: .passed, microphone: .passed, screenRecording: .passed, ffmpeg: .failed)
        )

        XCTAssertFalse(didReset)
        XCTAssertTrue(commandRecorder.commands.isEmpty)
        XCTAssertNil(stateManager.lastResetCommand)
    }

    func testResetPermissionsIfNeededRunsOnlyOncePerInstallationToken() {
        let defaults = UserDefaults(suiteName: "PermissionResetServiceTests-\(UUID().uuidString)")!
        let stateManager = PermissionResetStateManager(defaults: defaults)
        let commandRecorder = CommandRecorder()
        let service = makeService(
            stateManager: stateManager,
            commandRecorder: commandRecorder
        )
        let report = makeReport(accessibility: .failed)

        XCTAssertTrue(service.resetPermissionsIfNeeded(for: report))
        XCTAssertFalse(service.resetPermissionsIfNeeded(for: report))
        XCTAssertEqual(commandRecorder.commands.count, 1)
    }

    func testResetPermissionsIfNeededClearsPreviousAttemptWhenPermissionsAreHealthy() {
        let defaults = UserDefaults(suiteName: "PermissionResetServiceTests-\(UUID().uuidString)")!
        let stateManager = PermissionResetStateManager(defaults: defaults)
        stateManager.markResetAttempt(
            for: "installation-token",
            command: "/usr/bin/tccutil reset All com.ymuichiro.kototype"
        )
        let commandRecorder = CommandRecorder()
        let service = makeService(
            stateManager: stateManager,
            commandRecorder: commandRecorder
        )

        let didReset = service.resetPermissionsIfNeeded(
            for: makeReport(accessibility: .passed, microphone: .passed, screenRecording: .passed, ffmpeg: .failed)
        )

        XCTAssertFalse(didReset)
        XCTAssertTrue(commandRecorder.commands.isEmpty)
        XCTAssertNil(stateManager.lastResetCommand)
    }

    func testInstallationTokenChangesWhenBundleModificationDateChanges() {
        let basePath = "/Applications/KotoType.app"
        let version = "1.0.0"
        let oldToken = PermissionResetService.installationToken(
            bundlePath: basePath,
            bundleVersion: version,
            modificationDate: Date(timeIntervalSince1970: 1_710_000_000)
        )
        let newToken = PermissionResetService.installationToken(
            bundlePath: basePath,
            bundleVersion: version,
            modificationDate: Date(timeIntervalSince1970: 1_720_000_000)
        )

        XCTAssertNotEqual(oldToken, newToken)
    }

    private func makeService(
        stateManager: PermissionResetStateManager,
        commandRecorder: CommandRecorder
    ) -> PermissionResetService {
        PermissionResetService(
            runtime: PermissionResetService.Runtime(
                currentBundleIdentifier: { "com.ymuichiro.kototype" },
                currentBundlePath: { "/Applications/KotoType.app" },
                currentBundleVersion: { "1.0.0" },
                modificationDateForPath: { _ in Date(timeIntervalSince1970: 1_710_000_000) },
                run: { command in
                    commandRecorder.commands.append(command)
                    return PermissionResetService.CommandResult(exitCode: 0, standardError: "")
                }
            ),
            stateManager: stateManager
        )
    }

    private func makeReport(
        accessibility: InitialSetupCheckItem.Status,
        microphone: InitialSetupCheckItem.Status = .passed,
        screenRecording: InitialSetupCheckItem.Status = .passed,
        ffmpeg: InitialSetupCheckItem.Status = .passed
    ) -> InitialSetupReport {
        InitialSetupReport(
            items: [
                InitialSetupCheckItem(
                    id: "accessibility",
                    title: "Accessibility Permission",
                    detail: "",
                    status: accessibility,
                    required: true
                ),
                InitialSetupCheckItem(
                    id: "microphone",
                    title: "Microphone Permission",
                    detail: "",
                    status: microphone,
                    required: true
                ),
                InitialSetupCheckItem(
                    id: "screenRecording",
                    title: "Screen Recording Permission",
                    detail: "",
                    status: screenRecording,
                    required: true
                ),
                InitialSetupCheckItem(
                    id: "ffmpeg",
                    title: "FFmpeg",
                    detail: "",
                    status: ffmpeg,
                    required: true
                ),
            ]
        )
    }
}

private final class CommandRecorder {
    var commands: [PermissionResetService.Command] = []
}
