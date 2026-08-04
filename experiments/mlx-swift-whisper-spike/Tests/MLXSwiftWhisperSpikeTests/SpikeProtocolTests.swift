import XCTest
@testable import MLXSwiftWhisperSpikeCore

final class SpikeProtocolTests: XCTestCase {
    func testHealthCheckUsesExistingWorkerPrefixContract() throws {
        let request = try SpikeProtocol.parse(
            line: "__KOTOTYPE_HEALTHCHECK__:test-token"
        )

        XCTAssertEqual(request, .healthCheck(token: "test-token"))
        XCTAssertEqual(
            SpikeProtocol.healthCheckResponsePrefix,
            "__KOTOTYPE_HEALTHCHECK_OK__:"
        )
    }

    func testTranscriptionRequestKeepsAudioPathAndMode() throws {
        let request = try SpikeProtocol.parse(
            line: #"{"type":"transcription_request","audio_path":"/tmp/input.wav","mode":"transcribe"}"#
        )

        XCTAssertEqual(
            request,
            .transcription(audioPath: "/tmp/input.wav", mode: "transcribe")
        )
    }

    func testBlankLinesAreIgnoredAndOtherRequestsAreRejected() throws {
        XCTAssertNil(try SpikeProtocol.parse(line: "  \n"))
        XCTAssertThrowsError(
            try SpikeProtocol.parse(line: #"{"type":"backend_probe"}"#)
        ) { error in
            XCTAssertEqual(error as? SpikeProtocolError, .unsupportedRequestType)
        }
    }
}
