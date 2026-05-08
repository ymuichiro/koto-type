@testable import KotoType
import XCTest

final class ScreenContextExtractorTests: XCTestCase {
    func testCompressRecognizedTextHintsKeepsTechnicalTermsWithoutLongSentenceNoise() {
        let hints = ScreenContextExtractor.compressRecognizedTextHints(
            [
                "GitHub Pull Requests",
                "Issue #123",
                "Repository: koto-type",
                "Review comments before merging the pull request into the main branch",
                "Whisper Turbo"
            ],
            maxLength: 200
        )

        XCTAssertNotNil(hints)
        XCTAssertTrue(hints?.contains("GitHub Pull Requests") == true)
        XCTAssertTrue(hints?.contains("Issue #123") == true)
        XCTAssertTrue(hints?.contains("koto-type") == true)
        XCTAssertFalse(hints?.contains("Review comments before merging") == true)
    }

    func testCompressRecognizedTextHintsPreservesShortNonEnglishLabels() {
        let hints = ScreenContextExtractor.compressRecognizedTextHints(
            [
                "設定",
                "音声入力",
                "最近使ったファイル",
                "保存",
                "このウインドウを閉じる前に変更を保存してください"
            ],
            maxLength: 120
        )

        XCTAssertNotNil(hints)
        XCTAssertTrue(hints?.contains("設定") == true)
        XCTAssertTrue(hints?.contains("音声入力") == true)
        XCTAssertTrue(hints?.contains("最近使ったファイル") == true)
        XCTAssertFalse(hints?.contains("このウインドウを閉じる前に変更を保存してください") == true)
    }

    func testCompressRecognizedTextHintsDeduplicatesAndRespectsMaxLength() {
        let hints = ScreenContextExtractor.compressRecognizedTextHints(
            [
                "GitHub",
                "GitHub",
                "Pull Request",
                "Pull Request",
                "Whisper Turbo",
                "Settings"
            ],
            maxLength: 30
        )

        XCTAssertNotNil(hints)
        XCTAssertLessThanOrEqual(hints?.count ?? 0, 30)
        XCTAssertEqual(hints?.components(separatedBy: "GitHub").count, 2)
    }
}
