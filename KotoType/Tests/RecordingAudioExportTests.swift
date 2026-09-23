@testable import KotoType
import Foundation
import XCTest

final class RecordingAudioExportTests: XCTestCase {
    func testExplicitExportPreservesSourceAndParentPermissions() throws {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
        defer { try? files.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.wav")
        let destination = directory.appendingPathComponent("saved.wav")
        let bytes = Data([0, 1, 2, 3])
        try bytes.write(to: source)
        for overwrite in [false, true] {
            if overwrite { try Data([9]).write(to: destination) }
            try RecordingAudioExport.save(source: source, destination: destination)
            XCTAssertEqual(try Data(contentsOf: source), bytes)
            XCTAssertEqual(try Data(contentsOf: destination), bytes)
            XCTAssertEqual((try files.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            XCTAssertEqual((try files.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue, 0o755)
        }
        XCTAssertThrowsError(try RecordingAudioExport.save(source: source, destination: source))
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(Set(try files.contentsOfDirectory(atPath: directory.path)), ["source.wav", "saved.wav"])
    }

    func testFailedExportDoesNotRemoveSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.wav")
        try Data([7]).write(to: source)
        XCTAssertThrowsError(try RecordingAudioExport.save(source: source, destination: source.appendingPathComponent("impossible.wav")))
        XCTAssertEqual(try Data(contentsOf: source), Data([7]))
    }
}
