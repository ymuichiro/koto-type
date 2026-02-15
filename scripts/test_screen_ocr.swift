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
    static func captureImage(timeoutSeconds: TimeInterval = 3.0) async throws -> CGImage {
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

            output.start(stream: stream)

            stream.startCapture { error in
                if let error {
                    output.finish(throwing: error)
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                output.finish(throwing: NSError(domain: "test_screen_ocr", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for screen frame"]))
            }
        }
    }

    private final class SnapshotOutput: NSObject, SCStreamOutput {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<CGImage, Error>?
        private weak var stream: SCStream?

        init(continuation: CheckedContinuation<CGImage, Error>) {
            self.continuation = continuation
        }

        func start(stream: SCStream) {
            lock.lock()
            self.stream = stream
            lock.unlock()
        }

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
            guard outputType == .screen,
                  let pixelBuffer = sampleBuffer.imageBuffer else {
                return
            }

            let ciImage = CIImage(cvImageBuffer: pixelBuffer)
            let context = CIContext(options: nil)
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                finish(throwing: NSError(domain: "test_screen_ocr", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage from frame"]))
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
            let stream = self.stream
            lock.unlock()

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
            let stream = self.stream
            lock.unlock()

            stream?.stopCapture(completionHandler: { _ in })
            continuation.resume(throwing: error)
        }
    }
}
#endif

private func runOCR(on image: CGImage) throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    return (request.results ?? [])
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n")
}

private func captureWithLegacyCoreGraphics() -> CGImage? {
    if #available(macOS 10.15, *) {
        guard CGPreflightScreenCaptureAccess() else {
            fputs("Screen capture permission is not granted.\n", stderr)
            return nil
        }
    }

    return CGWindowListCreateImage(
        .infinite,
        .optionOnScreenOnly,
        kCGNullWindowID,
        [.boundsIgnoreFraming, .bestResolution]
    )
}

@main
struct TestScreenOCR {
    static func main() async {
        do {
            let image: CGImage

            #if canImport(ScreenCaptureKit)
            if #available(macOS 15.0, *) {
                image = try await ScreenCaptureKitSnapshot.captureImage()
                print("Capture backend: ScreenCaptureKit")
            } else {
                guard let legacyImage = captureWithLegacyCoreGraphics() else {
                    fputs("Failed to capture screen image with legacy backend.\n", stderr)
                    exit(1)
                }
                image = legacyImage
                print("Capture backend: CoreGraphics(CGWindowListCreateImage)")
            }
            #else
            guard let legacyImage = captureWithLegacyCoreGraphics() else {
                fputs("Failed to capture screen image with legacy backend.\n", stderr)
                exit(1)
            }
            image = legacyImage
            print("Capture backend: CoreGraphics(CGWindowListCreateImage)")
            #endif

            let text = try runOCR(on: image)
            print("=== OCR RESULT START ===")
            print(text)
            print("=== OCR RESULT END ===")
        } catch {
            fputs("OCR failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
