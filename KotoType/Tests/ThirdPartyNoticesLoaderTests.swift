import XCTest
@testable import KotoType

final class ThirdPartyNoticesLoaderTests: XCTestCase {
    func testLoadIncludesRequiredOpenSourceNoticeEntries() throws {
        let notices = try ThirdPartyNoticesLoader.load()
        let ids = Set(notices.map(\.id))

        XCTAssertTrue(ids.contains("openai-whisper"))
        XCTAssertTrue(ids.contains("faster-whisper"))
        XCTAssertTrue(ids.contains("ctranslate2"))
        XCTAssertTrue(ids.contains("mlx"))
        XCTAssertTrue(ids.contains("mlx-whisper"))
        XCTAssertTrue(ids.contains("mlx-community-whisper-large-v3-turbo"))
    }

    func testMLXModelNoticeIncludesPinnedRevisionAndUpstreamBaseModel() throws {
        let notices = try ThirdPartyNoticesLoader.load()
        let notice = try XCTUnwrap(
            notices.first(where: { $0.id == "mlx-community-whisper-large-v3-turbo" })
        )

        XCTAssertEqual(
            notice.revision,
            "a4aaeec0636e6fef84abdcbe3544cb2bf7e9f6fb"
        )
        XCTAssertEqual(notice.upstreamBaseModel, "openai/whisper-large-v3-turbo")
        XCTAssertTrue(notice.licenseName.hasPrefix("MIT"))
    }

    func testNoticeTextLoadsForEveryNoticeEntry() throws {
        let notices = try ThirdPartyNoticesLoader.load()

        for notice in notices {
            let text = try ThirdPartyNoticesLoader.noticeText(for: notice)
            XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
