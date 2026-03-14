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
        temperature: Double,
        beamSize: Int,
        noSpeechThreshold: Double,
        compressionRatioThreshold: Double,
        task: String,
        bestOf: Int,
        vadThreshold: Double,
        autoPunctuation: Bool,
        autoGainEnabled: Bool,
        autoGainWeakThresholdDbfs: Double,
        autoGainTargetPeakDbfs: Double,
        autoGainMaxDb: Double,
        screenshotContext: String?
    ) -> Bool {
        onSend?(self, text)
        onSendDetailed?(self, text, screenshotContext)
        return sendSucceeds
    }

    func isRunning() -> Bool {
        running
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
