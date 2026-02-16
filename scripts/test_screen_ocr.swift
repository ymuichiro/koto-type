import Foundation
import CoreGraphics
import CoreImage
import CoreMedia
import Vision
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

#if canImport(ScreenCaptureKit)
@available(macOS 12.3, *)
private struct ScreenCaptureKitSnapshot {
    static func captureImage(timeoutSeconds: TimeInterval = 10.0) async throws -> CGImage {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw NSError(domain: "test_screen_ocr", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 1

        return try await withCheckedThrowingContinuation { continuation in
            let output = SnapshotOutput(continuation: continuation)
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)

            do {
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "test_screen_ocr.sample"))
            } catch {
                continuation.resume(throwing: error)
                return
            }

            output.start(stream: stream, timeoutSeconds: timeoutSeconds)

            stream.startCapture { error in
                if let error {
                    output.finish(throwing: error)
                }
            }
        }
    }

    private final class SnapshotOutput: NSObject, SCStreamOutput, @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<CGImage, Error>?
        private var stream: SCStream?
        private var timeoutWorkItem: DispatchWorkItem?

        init(continuation: CheckedContinuation<CGImage, Error>) {
            self.continuation = continuation
        }

        func start(stream: SCStream, timeoutSeconds: TimeInterval) {
            lock.lock()
            self.stream = stream
            let timeoutWorkItem = DispatchWorkItem { [self] in
                finish(
                    throwing: NSError(
                        domain: "test_screen_ocr",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for screen frame"]
                    )
                )
            }
            self.timeoutWorkItem = timeoutWorkItem
            lock.unlock()

            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWorkItem)
        }

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
            guard outputType == .screen, let pixelBuffer = sampleBuffer.imageBuffer else {
                return
            }

            let ciImage = CIImage(cvImageBuffer: pixelBuffer)
            let context = CIContext(options: nil)
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                finish(
                    throwing: NSError(
                        domain: "test_screen_ocr",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage from frame"]
                    )
                )
                return
            }

            finish(with: cgImage)
        }

        func finish(with image: CGImage) {
            lock.lock()
            guard let continuation else {
                lock.unlock()
                return
            }
            self.continuation = nil
            let timeoutWorkItem = self.timeoutWorkItem
            self.timeoutWorkItem = nil
            let stream = self.stream
            self.stream = nil
            lock.unlock()

            timeoutWorkItem?.cancel()
            stream?.stopCapture(completionHandler: { _ in })
            continuation.resume(returning: image)
        }

        func finish(throwing error: Error) {
            lock.lock()
            guard let continuation else {
                lock.unlock()
                return
            }
            self.continuation = nil
            let timeoutWorkItem = self.timeoutWorkItem
            self.timeoutWorkItem = nil
            let stream = self.stream
            self.stream = nil
            lock.unlock()

            timeoutWorkItem?.cancel()
            stream?.stopCapture(completionHandler: { _ in })
            continuation.resume(throwing: error)
        }
    }
}
#endif

private func ensureScreenCapturePermission() -> Bool {
    if #available(macOS 10.15, *) {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        fputs("Screen capture permission is not granted. Requesting permission...\n", stderr)
        let granted = CGRequestScreenCaptureAccess()
        if granted && CGPreflightScreenCaptureAccess() {
            return true
        }

        fputs(
            """
            Screen capture permission is still unavailable.
            Open System Settings > Privacy & Security > Screen Recording, allow your terminal app, and run this command again.
            \n
            """,
            stderr
        )
        return false
    }
    return true
}

private func runOCRAuto(on image: CGImage) throws -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    if #available(macOS 13.0, *) {
        request.automaticallyDetectsLanguage = true
    } else {
        request.recognitionLanguages = try request.supportedRecognitionLanguages()
    }

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    return (request.results ?? [])
        .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func runTest() async -> Int32 {
    guard ensureScreenCapturePermission() else {
        return 1
    }

    do {
        #if canImport(ScreenCaptureKit)
        guard #available(macOS 12.3, *) else {
            fputs("ScreenCaptureKit is unavailable on this macOS version.\n", stderr)
            return 1
        }
        let startedAt = Date()
        let image = try await ScreenCaptureKitSnapshot.captureImage()
        let lines = try runOCRAuto(on: image)
        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        print("Capture backend: ScreenCaptureKit")
        print("OCR mode: single-pass auto-detect")
        print("Elapsed: \(elapsedMs) ms")
        #else
        fputs("ScreenCaptureKit is not available in this toolchain.\n", stderr)
        return 1
        #endif

        print("=== OCR RESULT START ===")
        print(lines.joined(separator: "\n"))
        print("=== OCR RESULT END ===")
        return 0
    } catch {
        fputs("OCR failed: \(error)\n", stderr)
        return 1
    }
}

let semaphore = DispatchSemaphore(value: 0)
var exitCode: Int32 = 1
Task {
    exitCode = await runTest()
    semaphore.signal()
}
semaphore.wait()
exit(exitCode)
