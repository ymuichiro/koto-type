@testable import KotoType
import AppKit
import ApplicationServices
import XCTest

@MainActor
final class WindowFocusRestorerTests: XCTestCase {
    func testRestoreIfNeededSkipsWhenTheCapturedWindowIsStillFocused() {
        let window = AXUIElementCreateApplication(1)
        let target = makeTarget(processIdentifier: 1, window: window, identifier: "window-a")
        var activationCount = 0
        var raiseCount = 0

        let result = WindowFocusRestorer.restoreIfNeeded(
            target,
            runtime: WindowFocusRestorer.Runtime(
                currentTarget: { target },
                activateApplication: { _ in
                    activationCount += 1
                    return true
                },
                raiseWindow: { _ in
                    raiseCount += 1
                    return .success
                }
            )
        )

        XCTAssertEqual(result, .unchanged)
        XCTAssertEqual(activationCount, 0)
        XCTAssertEqual(raiseCount, 0)
    }

    func testRestoreIfNeededRaisesCapturedWindowWhenFocusChanged() {
        let target = makeTarget(processIdentifier: 1, window: AXUIElementCreateApplication(1), identifier: "window-a")
        let current = makeTarget(processIdentifier: 1, window: AXUIElementCreateApplication(2), identifier: "window-b")
        var activatedProcessIdentifiers: [pid_t] = []
        var raiseCount = 0

        let result = WindowFocusRestorer.restoreIfNeeded(
            target,
            runtime: WindowFocusRestorer.Runtime(
                currentTarget: { current },
                activateApplication: { processIdentifier in
                    activatedProcessIdentifiers.append(processIdentifier)
                    return true
                },
                raiseWindow: { _ in
                    raiseCount += 1
                    return .success
                }
            )
        )

        XCTAssertEqual(result, .restored)
        XCTAssertTrue(activatedProcessIdentifiers.isEmpty)
        XCTAssertEqual(raiseCount, 1)
    }

    func testRestoreIfNeededActivatesTheApplicationWhenFocusMovedToAnotherApplication() {
        let target = makeTarget(processIdentifier: 1, window: AXUIElementCreateApplication(1), identifier: "window-a")
        let current = makeTarget(processIdentifier: 2, window: AXUIElementCreateApplication(2), identifier: "window-b")
        var activatedProcessIdentifiers: [pid_t] = []
        var raiseCount = 0

        let result = WindowFocusRestorer.restoreIfNeeded(
            target,
            runtime: WindowFocusRestorer.Runtime(
                currentTarget: { current },
                activateApplication: { processIdentifier in
                    activatedProcessIdentifiers.append(processIdentifier)
                    return true
                },
                raiseWindow: { _ in
                    raiseCount += 1
                    return .success
                }
            )
        )

        XCTAssertEqual(result, .restored)
        XCTAssertEqual(activatedProcessIdentifiers, [1])
        XCTAssertEqual(raiseCount, 1)
    }

    func testRestoreIfNeededUsesCurrentFocusWhenWindowRestorationFails() {
        let target = makeTarget(processIdentifier: 1, window: AXUIElementCreateApplication(1), identifier: "window-a")
        let current = makeTarget(processIdentifier: 1, window: AXUIElementCreateApplication(2), identifier: "window-b")
        var activationCount = 0
        var raiseCount = 0

        let result = WindowFocusRestorer.restoreIfNeeded(
            target,
            runtime: WindowFocusRestorer.Runtime(
                currentTarget: { current },
                activateApplication: { _ in
                    activationCount += 1
                    return true
                },
                raiseWindow: { _ in
                    raiseCount += 1
                    return .cannotComplete
                }
            )
        )

        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(activationCount, 0)
        XCTAssertEqual(raiseCount, 1)
    }

    func testRestoreIfNeededDoesNotRaiseWhenApplicationActivationFails() {
        let target = makeTarget(processIdentifier: 1, window: AXUIElementCreateApplication(1), identifier: "window-a")
        let current = makeTarget(processIdentifier: 2, window: AXUIElementCreateApplication(2), identifier: "window-b")
        var raiseCount = 0

        let result = WindowFocusRestorer.restoreIfNeeded(
            target,
            runtime: WindowFocusRestorer.Runtime(
                currentTarget: { current },
                activateApplication: { _ in false },
                raiseWindow: { _ in
                    raiseCount += 1
                    return .success
                }
            )
        )

        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(raiseCount, 0)
    }

    func testIdentityWithoutStableAttributesDoesNotClaimTwoWindowsMatch() {
        let first = WindowFocusIdentity(
            identifier: nil,
            title: nil,
            role: "AXWindow",
            subrole: "AXStandardWindow",
            document: nil,
            position: nil,
            size: nil
        )
        let second = first

        XCTAssertFalse(first.matches(second))
    }

    private func makeTarget(
        processIdentifier: pid_t,
        window: AXUIElement,
        identifier: String
    ) -> WindowFocusTarget {
        WindowFocusTarget(
            processIdentifier: processIdentifier,
            window: window,
            identity: WindowFocusIdentity(
                identifier: identifier,
                title: nil,
                role: "AXWindow",
                subrole: "AXStandardWindow",
                document: nil,
                position: nil,
                size: nil
            )
        )
    }
}
