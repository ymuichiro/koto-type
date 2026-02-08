@testable import KotoType
import XCTest

final class InitialSetupDiagnosticsServiceTests: XCTestCase {
    func testEvaluateReturnsReadyWhenAllRequirementsPass() {
        let service = InitialSetupDiagnosticsService(
            runtime: makeRuntime(
                accessibility: .granted,
                microphone: .granted,
                ffmpegPath: "/opt/homebrew/bin/ffmpeg",
                bundlePath: "/Applications/KotoType.app"
            )
        )

        let report = service.evaluate()
        XCTAssertTrue(report.canStartApplication)
        XCTAssertEqual(report.items.filter(\.required).count, 3)
        XCTAssertTrue(report.items.allSatisfy { $0.status == .passed })
    }

    func testEvaluateFailsWhenAccessibilityDenied() throws {
        let service = InitialSetupDiagnosticsService(
            runtime: makeRuntime(
                accessibility: .denied,
                microphone: .granted,
                ffmpegPath: "/usr/local/bin/ffmpeg",
                bundlePath: "/Applications/KotoType.app"
            )
        )

        let report = service.evaluate()
        XCTAssertFalse(report.canStartApplication)
        let accessibility = try XCTUnwrap(report.items.first { $0.id == "accessibility" })
        XCTAssertEqual(accessibility.status, .failed)
    }

    func testEvaluateFailsWhenMicrophoneDenied() throws {
        let service = InitialSetupDiagnosticsService(
            runtime: makeRuntime(
                accessibility: .granted,
                microphone: .denied,
                ffmpegPath: "/usr/local/bin/ffmpeg",
                bundlePath: "/Applications/KotoType.app"
            )
        )

        let report = service.evaluate()
        XCTAssertFalse(report.canStartApplication)
        let microphone = try XCTUnwrap(report.items.first { $0.id == "microphone" })
        XCTAssertEqual(microphone.status, .failed)
    }

    func testEvaluateFailsWhenFfmpegMissing() throws {
        let service = InitialSetupDiagnosticsService(
            runtime: makeRuntime(
                accessibility: .granted,
                microphone: .granted,
                ffmpegPath: nil,
                bundlePath: "/Applications/KotoType.app"
            )
        )

        let report = service.evaluate()
        XCTAssertFalse(report.canStartApplication)
        let ffmpeg = try XCTUnwrap(report.items.first { $0.id == "ffmpeg" })
        XCTAssertEqual(ffmpeg.status, .failed)
    }

    func testEvaluateAccessibilityDetailMentionsAppTranslocation() throws {
        let service = InitialSetupDiagnosticsService(
            runtime: makeRuntime(
                accessibility: .denied,
                microphone: .granted,
                ffmpegPath: "/usr/local/bin/ffmpeg",
                bundlePath: "/private/var/folders/xx/AppTranslocation/ABC/d/KotoType.app"
            )
        )

        let report = service.evaluate()
        let accessibility = try XCTUnwrap(report.items.first { $0.id == "accessibility" })
        XCTAssertEqual(accessibility.status, .failed)
        XCTAssertTrue(accessibility.detail.contains("AppTranslocation"))
        XCTAssertTrue(accessibility.detail.contains("/Applications"))
        XCTAssertTrue(accessibility.detail.contains("~/Applications"))
    }

    func testBundleExecutionLocationDetectsSystemApplications() {
        XCTAssertEqual(
            InitialSetupDiagnosticsService.bundleExecutionLocation(
                for: "/Applications/KotoType.app",
                homeDirectory: "/Users/tester"
            ),
            .systemApplications
        )
    }

    func testBundleExecutionLocationDetectsUserApplications() {
        XCTAssertEqual(
            InitialSetupDiagnosticsService.bundleExecutionLocation(
                for: "/Users/tester/Applications/KotoType.app",
                homeDirectory: "/Users/tester"
            ),
            .userApplications
        )
    }

    func testBundleExecutionLocationDetectsAppTranslocation() {
        XCTAssertEqual(
            InitialSetupDiagnosticsService.bundleExecutionLocation(
                for: "/private/var/folders/zz/yy/AppTranslocation/ABC/d/KotoType.app",
                homeDirectory: "/Users/tester"
            ),
            .appTranslocation
        )
    }

    private func makeRuntime(
        accessibility: PermissionChecker.PermissionStatus,
        microphone: PermissionChecker.PermissionStatus,
        ffmpegPath: String?,
        bundlePath: String
    ) -> InitialSetupDiagnosticsService.Runtime {
        return InitialSetupDiagnosticsService.Runtime(
            checkAccessibilityPermission: { accessibility },
            checkMicrophonePermission: { microphone },
            requestAccessibilityPermission: {},
            requestMicrophonePermission: { completion in completion(microphone) },
            findExecutable: { _ in ffmpegPath },
            currentBundlePath: { bundlePath }
        )
    }
}
