import AppKit
import XCTest
@testable import KotoType

@MainActor
final class SettingsWindowControllerLayoutTests: XCTestCase {
    func testWindowUsesMinimumSizeAndResizableStyle() throws {
        let controller = SettingsWindowController()
        let window: NSWindow = try XCTUnwrap(controller.window)

        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))
        XCTAssertGreaterThanOrEqual(window.minSize.width, 600)
        XCTAssertGreaterThanOrEqual(window.minSize.height, 600)
    }
}
