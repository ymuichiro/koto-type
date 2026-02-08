@testable import STTApp
import XCTest
import Foundation

final class PermissionCheckerTests: XCTestCase {
    func testSharedInstance() throws {
        let checker1 = PermissionChecker.shared
        let checker2 = PermissionChecker.shared
        
        XCTAssertTrue(checker1 === checker2, "PermissionChecker.shared should return the same instance")
    }

    func testCheckAccessibilityPermission() throws {
        let checker = PermissionChecker.shared
        let status = checker.checkAccessibilityPermission()
        
        XCTAssertTrue(status == .granted || status == .denied, "Permission status should be either granted or denied")
    }

    func testRequestAccessibilityPermission() throws {
        let checker = PermissionChecker.shared
        
        let expectation = XCTestExpectation(description: "Request permission should complete")
        
        DispatchQueue.main.async {
            checker.requestAccessibilityPermission()
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }

    func testPermissionStatusEquality() throws {
        let grantedStatus = PermissionChecker.PermissionStatus.granted
        let deniedStatus = PermissionChecker.PermissionStatus.denied
        let unknownStatus = PermissionChecker.PermissionStatus.unknown
        
        XCTAssertNotEqual(grantedStatus, deniedStatus)
        XCTAssertNotEqual(grantedStatus, unknownStatus)
        XCTAssertNotEqual(deniedStatus, unknownStatus)
        
        XCTAssertEqual(grantedStatus, PermissionChecker.PermissionStatus.granted)
        XCTAssertEqual(deniedStatus, PermissionChecker.PermissionStatus.denied)
        XCTAssertEqual(unknownStatus, PermissionChecker.PermissionStatus.unknown)
    }

    func testMultiplePermissionChecks() throws {
        let checker = PermissionChecker.shared
        
        let status1 = checker.checkAccessibilityPermission()
        let status2 = checker.checkAccessibilityPermission()
        let status3 = checker.checkAccessibilityPermission()
        
        XCTAssertEqual(status1, status2, "Multiple permission checks should return the same result")
        XCTAssertEqual(status2, status3, "Multiple permission checks should return the same result")
    }

    func testPermissionStatusEnumValues() throws {
        let statuses: [PermissionChecker.PermissionStatus] = [
            .granted,
            .denied,
            .unknown
        ]
        
        XCTAssertEqual(statuses.count, 3)
        XCTAssertEqual(statuses[0], .granted)
        XCTAssertEqual(statuses[1], .denied)
        XCTAssertEqual(statuses[2], .unknown)
    }
}
