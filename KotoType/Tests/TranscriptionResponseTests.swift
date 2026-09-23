@testable import KotoType
import Foundation
import XCTest

func transcriptionTestResponse(requestID: String, text: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [
        "type": "transcription_result", "request_id": requestID, "text": text,
    ])
    return PythonProcessManager.controlMessagePrefix + String(data: data, encoding: .utf8)!
}

final class TranscriptionResponseTests: XCTestCase {
    func testUnicodeAndEmptySuccessArePreserved() {
        for text in ["日本語\n次の行", ""] {
            let response = TranscriptionResponse.parse(transcriptionTestResponse(requestID: "attempt-123", text: text))
            XCTAssertEqual(response?.request_id, "attempt-123")
            XCTAssertEqual(response?.text, text)
            XCTAssertNil(response?.error)
        }
    }

    func testMissingIdentityAndAmbiguousPayloadAreRejected() {
        for payload in [
            #"{"type":"transcription_result","text":"stale"}"#,
            #"{"type":"transcription_result","request_id":"abc","text":"","error":"backend_error"}"#,
            #"{"type":"transcription_result","request_id":"abc"}"#,
            #"{"type":"transcription_result","request_id":1,"text":"wrong type"}"#,
        ] {
            XCTAssertNil(TranscriptionResponse.parse(PythonProcessManager.controlMessagePrefix + payload))
        }
    }
}
