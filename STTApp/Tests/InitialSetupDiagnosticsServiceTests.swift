@testable import STTApp
import XCTest

final class InitialSetupDiagnosticsServiceTests: XCTestCase {
    func testEvaluateReturnsReadyWhenAllRequirementsPass() {
        let service = InitialSetupDiagnosticsService(
            runtime: makeRuntime(
                accessibility: .granted,
                microphone: .granted,
                bundledServerExists: true,
                backendScriptExists: false,
                developmentPythonExists: false,
                ffmpegPath: "/opt/homebrew/bin/ffmpeg",
                pythonDependenciesReady: true
            )
        )

        let report = service.evaluate()
        XCTAssertTrue(report.canStartApplication)
        XCTAssertEqual(report.items.filter(\.required).count, 5)
        XCTAssertTrue(report.items.allSatisfy { $0.status == .passed })
    }

    func testEvaluateFailsWhenAccessibilityDenied() throws {
        let service = InitialSetupDiagnosticsService(
            runtime: makeRuntime(
                accessibility: .denied,
                microphone: .granted,
                bundledServerExists: true,
                backendScriptExists: false,
                developmentPythonExists: false,
                ffmpegPath: "/usr/local/bin/ffmpeg",
                pythonDependenciesReady: true
            )
        )

        let report = service.evaluate()
        XCTAssertFalse(report.canStartApplication)
        let accessibility = try XCTUnwrap(report.items.first { $0.id == "accessibility" })
        XCTAssertEqual(accessibility.status, .failed)
    }

    func testEvaluateUsesDevelopmentPythonWhenBundledServerIsMissing() throws {
        let service = InitialSetupDiagnosticsService(
            runtime: makeRuntime(
                accessibility: .granted,
                microphone: .granted,
                bundledServerExists: false,
                backendScriptExists: true,
                developmentPythonExists: true,
                ffmpegPath: "/usr/local/bin/ffmpeg",
                pythonDependenciesReady: true
            )
        )

        let report = service.evaluate()
        XCTAssertTrue(report.canStartApplication)
        let backend = try XCTUnwrap(report.items.first { $0.id == "backend" })
        XCTAssertEqual(backend.status, .passed)
    }

    func testEvaluateFailsWhenFfmpegMissing() throws {
        let service = InitialSetupDiagnosticsService(
            runtime: makeRuntime(
                accessibility: .granted,
                microphone: .granted,
                bundledServerExists: true,
                backendScriptExists: false,
                developmentPythonExists: false,
                ffmpegPath: nil,
                pythonDependenciesReady: true
            )
        )

        let report = service.evaluate()
        XCTAssertFalse(report.canStartApplication)
        let ffmpeg = try XCTUnwrap(report.items.first { $0.id == "ffmpeg" })
        XCTAssertEqual(ffmpeg.status, .failed)
    }

    private func makeRuntime(
        accessibility: PermissionChecker.PermissionStatus,
        microphone: PermissionChecker.PermissionStatus,
        bundledServerExists: Bool,
        backendScriptExists: Bool,
        developmentPythonExists: Bool,
        ffmpegPath: String?,
        pythonDependenciesReady: Bool
    ) -> InitialSetupDiagnosticsService.Runtime {
        let scriptPath = "/tmp/stt-simple/python/whisper_server.py"
        let bundledPath = "/tmp/app/Resources/whisper_server"
        let developmentPythonPath = "/tmp/stt-simple/.venv/bin/python"

        return InitialSetupDiagnosticsService.Runtime(
            checkAccessibilityPermission: { accessibility },
            checkMicrophonePermission: { microphone },
            requestAccessibilityPermission: {},
            requestMicrophonePermission: { completion in completion(microphone) },
            resourcePath: { "/tmp/app/Resources" },
            backendScriptPath: { scriptPath },
            fileExists: { path in
                if path == bundledPath { return bundledServerExists }
                if path == scriptPath { return backendScriptExists }
                if path == developmentPythonPath { return developmentPythonExists }
                return false
            },
            findExecutable: { _ in ffmpegPath },
            checkPythonDependencies: { _ in pythonDependenciesReady }
        )
    }
}
