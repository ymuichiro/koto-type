@testable import KotoType
import Foundation
import XCTest

final class MultiProcessManagerTests: XCTestCase {
    func testInitializeStopsExistingProcessesBeforeReinitialize() {
        var created: [MockMultiProcessPythonManager] = []
        let manager = MultiProcessManager {
            let mock = MockMultiProcessPythonManager(sendSucceeds: true)
            created.append(mock)
            return mock
        }

        manager.initialize(count: 1, scriptPath: "/tmp/whisper_server.py")
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created[0].stopCallCount, 0)

        manager.initialize(count: 1, scriptPath: "/tmp/whisper_server.py")
        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(created[0].stopCallCount, 1)
        XCTAssertEqual(created[1].stopCallCount, 0)
    }

    func testProcessFileRetriesAndCompletesWithEmptyOnRepeatedSendFailure() {
        let sendAttempts = LockedInt()
        let completion = expectation(description: "segment completes with empty")

        let manager = MultiProcessManager {
            let mock = MockMultiProcessPythonManager(sendSucceeds: false)
            mock.onSend = { _, _ in
                sendAttempts.increment()
            }
            return mock
        }

        manager.segmentComplete = { index, text in
            if index == 5 {
                XCTAssertEqual(text, "")
                completion.fulfill()
            }
        }

        manager.initialize(count: 1, scriptPath: "/tmp/whisper_server.py")
        manager.processFile(
            url: URL(fileURLWithPath: "/tmp/fake.wav"),
            index: 5,
            settings: AppSettings()
        )

        wait(for: [completion], timeout: 3.0)
        XCTAssertEqual(sendAttempts.value, 3)
    }

    func testSegmentTimeoutRetriesAndCompletesWithEmptyWhenNoOutputArrives() {
        let sendAttempts = LockedInt()
        let completion = expectation(description: "segment completes with empty after timeout retries")

        let manager = MultiProcessManager(
            processManagerFactory: {
                let mock = MockMultiProcessPythonManager(sendSucceeds: true)
                mock.onSend = { _, _ in
                    sendAttempts.increment()
                }
                return mock
            },
            segmentProcessingTimeoutSeconds: 0.2,
            watchdogIntervalSeconds: 0.05,
            healthCheckIntervalSeconds: 5.0,
            healthCheckTimeoutSeconds: 1.0,
            healthCheckStartupGraceSeconds: 5.0
        )

        manager.segmentComplete = { index, text in
            if index == 11 {
                XCTAssertEqual(text, "")
                completion.fulfill()
            }
        }

        manager.initialize(count: 1, scriptPath: "/tmp/whisper_server.py")
        manager.processFile(
            url: URL(fileURLWithPath: "/tmp/timeout.wav"),
            index: 11,
            settings: AppSettings()
        )

        wait(for: [completion], timeout: 4.0)
        XCTAssertEqual(sendAttempts.value, 3)
    }

    func testProcessFileUsesPerRequestTimeoutOverride() {
        let sendAttempts = LockedInt()
        let completion = expectation(description: "segment completes after override timeout")

        let manager = MultiProcessManager(
            processManagerFactory: {
                let mock = MockMultiProcessPythonManager(sendSucceeds: true)
                mock.onSend = { _, _ in
                    sendAttempts.increment()
                }
                return mock
            },
            segmentProcessingTimeoutSeconds: 1.0,
            watchdogIntervalSeconds: 0.02,
            healthCheckIntervalSeconds: 5.0,
            healthCheckTimeoutSeconds: 1.0,
            healthCheckStartupGraceSeconds: 5.0
        )

        manager.segmentComplete = { index, text in
            if index == 12 {
                XCTAssertEqual(text, "")
                completion.fulfill()
            }
        }

        manager.initialize(count: 1, scriptPath: "/tmp/whisper_server.py")
        manager.processFile(
            url: URL(fileURLWithPath: "/tmp/override-timeout.wav"),
            index: 12,
            settings: AppSettings(),
            processingTimeout: 0.05
        )

        wait(for: [completion], timeout: 4.0)
        XCTAssertEqual(sendAttempts.value, 3)
    }

    func testIdleHealthCheckRequestIsSentAndAccepted() {
        let healthCheckSeen = expectation(description: "health check request sent")
        healthCheckSeen.assertForOverFulfill = false
        let tokenPrefix = "__KOTOTYPE_HEALTHCHECK__:"
        let okPrefix = "__KOTOTYPE_HEALTHCHECK_OK__:"

        let manager = MultiProcessManager(
            processManagerFactory: {
                let mock = MockMultiProcessPythonManager(sendSucceeds: true)
                mock.onSend = { instance, inputText in
                    guard inputText.hasPrefix(tokenPrefix) else { return }
                    let token = String(inputText.dropFirst(tokenPrefix.count))
                    instance.outputReceived?("\(okPrefix)\(token)")
                    healthCheckSeen.fulfill()
                }
                return mock
            },
            segmentProcessingTimeoutSeconds: 60.0,
            watchdogIntervalSeconds: 0.05,
            healthCheckIntervalSeconds: 0.05,
            healthCheckTimeoutSeconds: 0.2,
            healthCheckStartupGraceSeconds: 0.01
        )

        manager.initialize(count: 1, scriptPath: "/tmp/whisper_server.py")
        wait(for: [healthCheckSeen], timeout: 2.0)
        XCTAssertEqual(manager.getProcessCount(), 1)
    }

    func testStatus9DuringProcessingCompletesWithoutRetryAndSuppressesImmediateRecovery() {
        let sendAttempts = LockedInt()
        let completion = expectation(description: "segment completes with empty after fatal termination")
        var created: [MockMultiProcessPythonManager] = []

        let manager = MultiProcessManager {
            let mock = MockMultiProcessPythonManager(sendSucceeds: true)
            mock.onSend = { instance, _ in
                sendAttempts.increment()
                instance.simulateTermination(status: 9)
            }
            created.append(mock)
            return mock
        }

        manager.segmentComplete = { index, text in
            if index == 7 {
                XCTAssertEqual(text, "")
                completion.fulfill()
            }
        }

        manager.initialize(count: 1, scriptPath: "/tmp/whisper_server.py")
        manager.processFile(
            url: URL(fileURLWithPath: "/tmp/fatal.wav"),
            index: 7,
            settings: AppSettings()
        )

        wait(for: [completion], timeout: 3.0)

        let settle = expectation(description: "no immediate recovery")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            settle.fulfill()
        }
        wait(for: [settle], timeout: 2.0)

        XCTAssertEqual(sendAttempts.value, 1)
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(manager.getProcessCount(), 0)
    }

    func testStatus9AtStartupDoesNotRestartImmediately() {
        var created: [MockMultiProcessPythonManager] = []
        let terminated = expectation(description: "startup process terminated with status 9")

        let manager = MultiProcessManager {
            let mock = MockMultiProcessPythonManager(sendSucceeds: true)
            mock.onStart = { instance in
                instance.simulateTermination(status: 9)
                terminated.fulfill()
            }
            created.append(mock)
            return mock
        }

        manager.initialize(count: 1, scriptPath: "/tmp/whisper_server.py")
        wait(for: [terminated], timeout: 2.0)

        let settle = expectation(description: "startup loop suppressed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            settle.fulfill()
        }
        wait(for: [settle], timeout: 2.0)

        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(manager.getProcessCount(), 0)
    }

    func testStatus0AtStartupDoesNotRestartImmediately() {
        var created: [MockMultiProcessPythonManager] = []
        let terminated = expectation(description: "startup process terminated with status 0")

        let manager = MultiProcessManager {
            let mock = MockMultiProcessPythonManager(sendSucceeds: true)
            mock.onStart = { instance in
                instance.simulateTermination(status: 0)
                terminated.fulfill()
            }
            created.append(mock)
            return mock
        }

        manager.initialize(count: 1, scriptPath: "/tmp/whisper_server.py")
        wait(for: [terminated], timeout: 2.0)

        let settle = expectation(description: "startup loop suppressed for status 0")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            settle.fulfill()
        }
        wait(for: [settle], timeout: 2.0)

        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(manager.getProcessCount(), 0)
    }

    func testStatus1AtStartupRecoversAutomatically() {
        var created: [MockMultiProcessPythonManager] = []
        let manager = MultiProcessManager {
            let mock = MockMultiProcessPythonManager(sendSucceeds: true)
            mock.onStart = { instance in
                instance.simulateTermination(status: 1)
            }
            created.append(mock)
            return mock
        }

        manager.initialize(count: 1, scriptPath: "/tmp/whisper_server.py")

        let settle = expectation(description: "wait for automatic recovery")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            settle.fulfill()
        }
        wait(for: [settle], timeout: 2.0)

        XCTAssertGreaterThanOrEqual(created.count, 2)
    }

    func testScreenshotContextIsDroppedAfterFirstSendAttempt() {
        let completion = expectation(description: "segment completes with empty")
        let capturedContexts = LockedOptionalStringArray()

        let manager = MultiProcessManager {
            let mock = MockMultiProcessPythonManager(sendSucceeds: false)
            mock.onSendDetailed = { _, _, screenshotContext in
                capturedContexts.append(screenshotContext)
            }
            return mock
        }

        manager.segmentComplete = { index, text in
            if index == 21 {
                XCTAssertEqual(text, "")
                completion.fulfill()
            }
        }

        manager.initialize(count: 1, scriptPath: "/tmp/whisper_server.py")
        manager.processFile(
            url: URL(fileURLWithPath: "/tmp/context.wav"),
            index: 21,
            settings: AppSettings(),
            screenshotContext: "sensitive screen context"
        )

        wait(for: [completion], timeout: 3.0)

        let values = capturedContexts.value
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values[0], "sensitive screen context")
        XCTAssertTrue(values.dropFirst().allSatisfy { $0 == nil })
    }

    func testBackendStatusControlMessageDoesNotCompleteSegment() {
        let completion = expectation(description: "segment completes with transcript")

        let manager = MultiProcessManager {
            let mock = MockMultiProcessPythonManager(sendSucceeds: true)
            mock.onSend = { instance, _ in
                instance.outputReceived?(
                    PythonProcessManager.controlMessagePrefix
                        + "{\"effectiveBackend\":\"cpu\",\"gpuRequested\":true,\"gpuAvailable\":false,\"fallbackReason\":\"mlx_runtime_import_failed\"}"
                )
                instance.outputReceived?("segment text")
            }
            return mock
        }

        manager.segmentComplete = { index, text in
            if index == 31 {
                XCTAssertEqual(text, "segment text")
                completion.fulfill()
            }
        }

        manager.initialize(count: 1, scriptPath: "/tmp/whisper_server.py")
        manager.processFile(
            url: URL(fileURLWithPath: "/tmp/control.wav"),
            index: 31,
            settings: AppSettings()
        )

        wait(for: [completion], timeout: 2.0)
    }

    func testBackendProbeTemporarilyMarksProcessBusyUntilStatusArrives() {
        let probeHandled = expectation(description: "probe handled")
        let segmentCompleted = expectation(description: "segment completed after probe")
        let sendOrder = LockedStringArray()
        let queuedURL = URL(fileURLWithPath: "/tmp/probe.wav")
        let queuedSettings = AppSettings()

        var manager: MultiProcessManager!
        manager = MultiProcessManager {
            let mock = MockMultiProcessPythonManager(sendSucceeds: true)
            mock.onSendBackendProbe = { instance, _, _ in
                sendOrder.append("probe")
                XCTAssertEqual(manager.getIdleProcessCount(), 0)
                manager.processFile(
                    url: queuedURL,
                    index: 41,
                    settings: queuedSettings
                )
                instance.outputReceived?(
                    PythonProcessManager.controlMessagePrefix
                        + "{\"type\":\"backend_preparation_progress\",\"step\":\"loading_mlx_model\",\"detail\":\"worker=0\"}"
                )
                XCTAssertEqual(manager.getIdleProcessCount(), 0)
                instance.outputReceived?(
                    PythonProcessManager.controlMessagePrefix
                        + "{\"effectiveBackend\":\"mlx\",\"gpuRequested\":true,\"gpuAvailable\":true}"
                )
                probeHandled.fulfill()
            }
            mock.onSend = { instance, _ in
                sendOrder.append("segment")
                instance.outputReceived?("ready")
            }
            return mock
        }

        manager.segmentComplete = { index, text in
            if index == 41 {
                XCTAssertEqual(text, "ready")
                segmentCompleted.fulfill()
            }
        }

        manager.initialize(count: 1, scriptPath: "/tmp/whisper_server.py")
        XCTAssertTrue(manager.requestBackendProbe(gpuAccelerationEnabled: true, preloadModel: true))

        wait(for: [probeHandled, segmentCompleted], timeout: 2.0)
        XCTAssertEqual(sendOrder.value, ["probe", "segment"])
    }

    func testBackendProbeUsesDedicatedTimeoutInsteadOfHealthCheckTimeout() {
        let createdCount = LockedInt()

        let manager = MultiProcessManager(
            processManagerFactory: {
                let mock = MockMultiProcessPythonManager(sendSucceeds: true)
                createdCount.increment()
                return mock
            },
            segmentProcessingTimeoutSeconds: 60.0,
            watchdogIntervalSeconds: 0.02,
            healthCheckIntervalSeconds: 5.0,
            healthCheckTimeoutSeconds: 0.05,
            backendProbeTimeoutSeconds: 0.25,
            healthCheckStartupGraceSeconds: 0.01
        )

        manager.initialize(count: 1, scriptPath: "/tmp/whisper_server.py")
        XCTAssertTrue(manager.requestBackendProbe(gpuAccelerationEnabled: true, preloadModel: true))

        Thread.sleep(forTimeInterval: 0.12)
        XCTAssertEqual(createdCount.value, 1)

        Thread.sleep(forTimeInterval: 0.33)
        XCTAssertGreaterThanOrEqual(createdCount.value, 2)
    }
}

private final class MockMultiProcessPythonManager: PythonProcessManaging {
    var outputReceived: ((String) -> Void)?
    var processTerminated: ((Int32) -> Void)?

    private(set) var stopCallCount = 0
    private(set) var startCallCount = 0
    private var running = false
    private let sendSucceeds: Bool
    var onStart: ((MockMultiProcessPythonManager) -> Void)?
    var onSend: ((MockMultiProcessPythonManager, String) -> Void)?
    var onSendDetailed: ((MockMultiProcessPythonManager, String, String?) -> Void)?
    var onSendBackendProbe: ((MockMultiProcessPythonManager, Bool, Bool) -> Void)?

    init(sendSucceeds: Bool) {
        self.sendSucceeds = sendSucceeds
    }

    func startPython(scriptPath: String) {
        startCallCount += 1
        running = true
        onStart?(self)
    }

    func sendInput(
        _ text: String,
        language: String,
        autoPunctuation: Bool,
        qualityPreset: TranscriptionQualityPreset,
        gpuAccelerationEnabled: Bool,
        screenshotContext: String?
    ) -> Bool {
        onSend?(self, text)
        onSendDetailed?(self, text, screenshotContext)
        return sendSucceeds
    }

    func isRunning() -> Bool {
        running
    }

    func sendBackendProbe(gpuAccelerationEnabled: Bool, preloadModel: Bool) -> Bool {
        onSendBackendProbe?(self, gpuAccelerationEnabled, preloadModel)
        return sendSucceeds
    }

    func stop() {
        stopCallCount += 1
        running = false
    }

    func simulateTermination(status: Int32) {
        running = false
        processTerminated?(status)
    }
}

private final class LockedStringArray {
    private let lock = NSLock()
    private var storage: [String] = []

    var value: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private final class LockedInt {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}

private final class LockedOptionalStringArray {
    private let lock = NSLock()
    private var storage: [String?] = []

    var value: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String?) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
