import XCTest
@testable import KotoType

final class ThirdPartyNoticesLoaderTests: XCTestCase {
    func testResourceBundleFindsPackagedResourcesInsideAppBundle() throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let appBundleURL = temporaryRoot.appendingPathComponent("KotoType.app", isDirectory: true)
        let resourcesURL = appBundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let packagedBundleURL = resourcesURL.appendingPathComponent("KotoType_KotoType.bundle", isDirectory: true)

        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try makeInfoPlist(
            at: appBundleURL.appendingPathComponent("Contents/Info.plist"),
            packageType: "APPL"
        )
        try makeInfoPlist(
            at: packagedBundleURL.appendingPathComponent("Contents/Info.plist"),
            packageType: "BNDL"
        )

        let appBundle = try XCTUnwrap(Bundle(path: appBundleURL.path))
        let resolvedBundle = try XCTUnwrap(
            ThirdPartyNoticesLoader.resourceBundle(candidateBundles: [appBundle])
        )

        XCTAssertEqual(
            resolvedBundle.bundleURL.standardizedFileURL,
            packagedBundleURL.standardizedFileURL
        )
    }

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

    private func makeInfoPlist(at url: URL, packageType: String) throws {
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.\(UUID().uuidString)",
            "CFBundleName": url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent,
            "CFBundlePackageType": packageType,
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0",
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }
}
