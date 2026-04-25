@testable import KotoType
import XCTest

final class BackendPreparationServiceTests: XCTestCase {
    func testPrepareStartsProcessAndCompletesWhenBackendStatusArrives() async {
        let mock = MockPreparationPythonProcessManager()
        let service = BackendPreparationService(processManager: mock)
        service.configure(scriptPath: "/tmp/whisper_server.py")

        let task = Task {
            await service.prepare(
                settings: AppSettings(gpuAccelerationEnabled: true),
                preloadModel: true,
                timeout: 5
            )
        }

        try? await Task.sleep(nanoseconds: 20_000_000)
        mock.emitOutput(
            PythonProcessManager.controlMessagePrefix
                + "{\"effectiveBackend\":\"mlx\",\"gpuRequested\":true,\"gpuAvailable\":true}"
        )

        let status = await task.value
        XCTAssertEqual(status?.effectiveBackend, .mlx)
        XCTAssertEqual(mock.startCallCount, 1)
        XCTAssertEqual(mock.sendBackendProbeCallCount, 1)
        XCTAssertEqual(mock.lastProbeGPUAccelerationEnabled, true)
        XCTAssertEqual(mock.lastProbePreloadModel, true)
        XCTAssertEqual(mock.stopCallCount, 1)
    }

    func testPrepareReturnsNilWhenProbeCannotBeSent() async {
        let mock = MockPreparationPythonProcessManager(sendBackendProbeSucceeds: false)
        let service = BackendPreparationService(processManager: mock)
        service.configure(scriptPath: "/tmp/whisper_server.py")

        let status = await service.prepare(
            settings: AppSettings(gpuAccelerationEnabled: true),
            preloadModel: true,
            timeout: 5
        )

        XCTAssertNil(status)
        XCTAssertEqual(mock.startCallCount, 1)
        XCTAssertEqual(mock.sendBackendProbeCallCount, 1)
        XCTAssertEqual(mock.stopCallCount, 1)
    }
}

private final class MockPreparationPythonProcessManager: PythonProcessManaging {
    var outputReceived: ((String) -> Void)?
    var processTerminated: ((Int32) -> Void)?

    private(set) var startCallCount = 0
    private(set) var sendInputCallCount = 0
    private(set) var sendBackendProbeCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastProbeGPUAccelerationEnabled: Bool?
    private(set) var lastProbePreloadModel: Bool?

    private let sendBackendProbeSucceeds: Bool
    private var running = false

    init(sendBackendProbeSucceeds: Bool = true) {
        self.sendBackendProbeSucceeds = sendBackendProbeSucceeds
    }

    func startPython(scriptPath: String) {
        startCallCount += 1
        running = true
    }

    func sendInput(
        _ text: String,
        language: String,
        autoPunctuation: Bool,
        qualityPreset: TranscriptionQualityPreset,
        gpuAccelerationEnabled: Bool,
        screenshotContext: String?
    ) -> Bool {
        sendInputCallCount += 1
        return true
    }

    func sendBackendProbe(gpuAccelerationEnabled: Bool, preloadModel: Bool) -> Bool {
        sendBackendProbeCallCount += 1
        lastProbeGPUAccelerationEnabled = gpuAccelerationEnabled
        lastProbePreloadModel = preloadModel
        return sendBackendProbeSucceeds
    }

    func isRunning() -> Bool {
        running
    }

    func stop() {
        stopCallCount += 1
        running = false
    }

    func emitOutput(_ output: String) {
        outputReceived?(output)
    }
}
