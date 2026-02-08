@testable import KotoType
import XCTest

final class AccessibilityDiagnosticsTests: XCTestCase {
    func testCollectIncludesPermissionStatusMapping() {
        let snapshot = AccessibilityDiagnostics.collect(
            executablePath: "/tmp/KotoType",
            processName: "KotoType",
            bundleIdentifier: "com.example.kototype",
            bundlePath: "/Applications/KotoType.app",
            resourcePath: "/Applications/KotoType.app/Contents/Resources",
            axIsProcessTrusted: true,
            permissionStatus: .granted
        )

        XCTAssertEqual(snapshot.permissionCheckerStatus, "granted")
        XCTAssertTrue(snapshot.axIsProcessTrusted)
        XCTAssertEqual(snapshot.bundleIdentifier, "com.example.kototype")
    }

    func testRenderJSONContainsCoreFields() {
        let snapshot = AccessibilityDiagnosticsSnapshot(
            executablePath: "/tmp/KotoType",
            processName: "KotoType",
            bundleIdentifier: "com.example.kototype",
            bundlePath: "/Applications/KotoType.app",
            resourcePath: "/Applications/KotoType.app/Contents/Resources",
            axIsProcessTrusted: false,
            permissionCheckerStatus: "denied"
        )

        let json = AccessibilityDiagnostics.renderJSON(snapshot)
        XCTAssertTrue(json.contains("\"permissionCheckerStatus\""))
        XCTAssertTrue(json.contains("\"denied\""))
        XCTAssertTrue(json.contains("\"axIsProcessTrusted\""))
    }

    func testCollectInitialSetupIncludesCanStartAndItemStatus() {
        let report = InitialSetupReport(
            items: [
                InitialSetupCheckItem(
                    id: "accessibility",
                    title: "アクセシビリティ権限",
                    detail: "許可済み",
                    status: .passed,
                    required: true
                ),
                InitialSetupCheckItem(
                    id: "ffmpeg",
                    title: "FFmpeg",
                    detail: "見つかりません",
                    status: .failed,
                    required: true
                ),
            ]
        )

        let snapshot = AccessibilityDiagnostics.collectInitialSetup(report: report)
        XCTAssertFalse(snapshot.canStartApplication)
        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertEqual(snapshot.items[0].status, "passed")
        XCTAssertEqual(snapshot.items[1].status, "failed")
    }

    func testRenderInitialSetupJSONContainsCanStartApplication() {
        let snapshot = InitialSetupDiagnosticsSnapshot(
            canStartApplication: false,
            items: []
        )

        let json = AccessibilityDiagnostics.renderJSON(snapshot)
        XCTAssertTrue(json.contains("\"canStartApplication\""))
        XCTAssertTrue(json.contains("false"))
    }
}
