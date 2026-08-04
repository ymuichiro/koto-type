import Foundation
import MLX
import MLXSwiftWhisperSpikeCore

private let experimentalFlag = "KOTOTYPE_ENABLE_EXPERIMENTAL_SWIFT_ASR"

private func isEnabled() -> Bool {
    ProcessInfo.processInfo.environment[experimentalFlag] == "1"
}

private func writeJSON(_ payload: [String: Any]) {
    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload),
          let line = String(data: data, encoding: .utf8) else {
        return
    }
    print(line)
    fflush(stdout)
}

private func probe() {
    var payload: [String: Any] = [
        "featureFlag": experimentalFlag,
        "featureEnabled": isEnabled(),
        "platform": ProcessInfo.processInfo.operatingSystemVersionString,
        "architecture": "arm64",
        "whisperImplementation": "unavailable",
        "whisperImplementationReason": "official_mlx_swift_has_no_drop_in_whisper_decoder",
        "status": "blocked_before_asr_parity",
    ]

    guard isEnabled() else {
        payload["mlxRuntime"] = "not_probed_feature_disabled"
        writeJSON(payload)
        return
    }

    let probeArray = MLXArray.zeros([1], type: Float32.self)
    eval(probeArray)
    payload["mlxRuntime"] = "available"
    writeJSON(payload)
}

private func writeDiagnostic(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

if CommandLine.arguments.contains("--probe") {
    probe()
    exit(0)
}

writeDiagnostic(
    "mlx-swift-whisper-spike: experimental worker; "
        + "ASR is intentionally unavailable until a native Whisper decoder is supplied"
)

while let line = readLine() {
    do {
        guard let request = try SpikeProtocol.parse(line: line) else { continue }

        switch request {
        case let .healthCheck(token):
            print(SpikeProtocol.healthCheckResponsePrefix + token)
            fflush(stdout)
        case let .transcription(audioPath, mode):
            guard isEnabled() else {
                writeDiagnostic("swift ASR request ignored: feature flag is disabled")
                print("")
                fflush(stdout)
                continue
            }
            writeDiagnostic(
                "swift ASR request unsupported: mode=\(mode), "
                    + "audio_path=\(audioPath), reason=native_whisper_decoder_missing"
            )
            // Preserve the existing worker contract: unsupported requests complete with
            // an empty transcript so this executable cannot affect the default app path.
            print("")
            fflush(stdout)
        }
    } catch {
        writeDiagnostic("swift ASR protocol error: \(error)")
        print("")
        fflush(stdout)
    }
}
