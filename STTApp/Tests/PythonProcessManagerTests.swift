import XCTest
@testable import STTApp

final class PythonProcessManagerTests: XCTestCase {
    func testExtractOutputLinesHandlesChunkBoundaries() {
        var buffer = ""

        let lines1 = PythonProcessManager.extractOutputLines(buffer: &buffer, chunk: "hel")
        XCTAssertTrue(lines1.isEmpty)
        XCTAssertEqual(buffer, "hel")

        let lines2 = PythonProcessManager.extractOutputLines(buffer: &buffer, chunk: "lo\nwor")
        XCTAssertEqual(lines2, ["hello"])
        XCTAssertEqual(buffer, "wor")

        let lines3 = PythonProcessManager.extractOutputLines(buffer: &buffer, chunk: "ld\n")
        XCTAssertEqual(lines3, ["world"])
        XCTAssertEqual(buffer, "")
    }

    func testExtractOutputLinesHandlesMultipleAndEmptyLines() {
        var buffer = ""

        let lines1 = PythonProcessManager.extractOutputLines(buffer: &buffer, chunk: "one\ntwo\n\nthr")
        XCTAssertEqual(lines1, ["one", "two", ""])
        XCTAssertEqual(buffer, "thr")

        let lines2 = PythonProcessManager.extractOutputLines(buffer: &buffer, chunk: "ee\r\n")
        XCTAssertEqual(lines2, ["three"])
        XCTAssertEqual(buffer, "")
    }

    func testExtractOutputLinesPreservesWhitespaceInsideLine() {
        var buffer = ""

        let lines = PythonProcessManager.extractOutputLines(buffer: &buffer, chunk: "  padded text  \n")
        XCTAssertEqual(lines, ["  padded text  "])
        XCTAssertEqual(buffer, "")
    }
}
