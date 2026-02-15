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
            mock.onSend = { _ in
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

    func testStatus9DuringProcessingCompletesWithoutRetryAndSuppressesImmediateRecovery() {
        let sendAttempts = LockedInt()
        let completion = expectation(description: "segment completes with empty after fatal termination")
        var created: [MockMultiProcessPythonManager] = []

        let manager = MultiProcessManager {
            let mock = MockMultiProcessPythonManager(sendSucceeds: true)
            mock.onSend = { instance in
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
}

private final class MockMultiProcessPythonManager: PythonProcessManaging {
    var outputReceived: ((String) -> Void)?
    var processTerminated: ((Int32) -> Void)?

    private(set) var stopCallCount = 0
    private(set) var startCallCount = 0
    private var running = false
    private let sendSucceeds: Bool
    var onStart: ((MockMultiProcessPythonManager) -> Void)?
    var onSend: ((MockMultiProcessPythonManager) -> Void)?

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
        onSend?(self)
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
