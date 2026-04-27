@testable import KotoType
import XCTest

final class AppRelauncherTests: XCTestCase {
    func testAppBundlePathFromResourcePath() {
        let resourcePath = "/Applications/KotoType.app/Contents/Resources"
        let bundlePath = AppRelauncher.appBundlePath(fromResourcePath: resourcePath)

        XCTAssertEqual(bundlePath, "/Applications/KotoType.app")
    }

    func testAppBundlePathReturnsNilWhenResourcePathMissing() {
        XCTAssertNil(AppRelauncher.appBundlePath(fromResourcePath: nil))
    }

    func testRelaunchTaskArgumentsWaitForCurrentProcessExitBeforeOpen() {
        let arguments = AppRelauncher.relaunchTaskArguments(
            appPath: "/Applications/KotoType.app",
            currentProcessID: 4321
        )

        XCTAssertEqual(arguments[0], "-c")
        XCTAssertTrue(arguments[1].contains("kill -0 \"$1\""))
        XCTAssertTrue(arguments[1].contains("open -n \"$2\""))
        XCTAssertEqual(arguments[3], "4321")
        XCTAssertEqual(arguments[4], "/Applications/KotoType.app")
    }
}
