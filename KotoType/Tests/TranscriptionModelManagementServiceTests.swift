import Foundation
import XCTest
@testable import KotoType

final class TranscriptionModelManagementServiceTests: XCTestCase {
    func testConcurrentModelRequestsDoNotOverwritePendingContinuation() async {
        let manager = ConcurrentModelManager()
        let service = TranscriptionModelManagementService(processManager: manager)
        service.configure(scriptPath: "/tmp/whisper_server.py")

        let statusesTask = Task {
            await service.fetchStatuses(timeout: 0.2)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(manager.sendCount, 1)

        let downloadTask = Task {
            await service.downloadModel(.cpu, timeout: 0.2)
        }

        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(manager.sendCount, 1)

        manager.emit(
            managedModelsResponse(requestID: manager.requestIDs[0])
        )
        manager.emit(
            PythonProcessManager.controlMessagePrefix
                + "{\"type\":\"managed_model\",\"model\":{\"kind\":\"cpu\",\"displayName\":\"CPU model\",\"modelID\":\"large-v3-turbo\",\"directoryPath\":\"/tmp/cpu\",\"isDownloaded\":true,\"fileCount\":3,\"byteCount\":100}}"
        )

        let statuses = await statusesTask.value
        let downloaded = await downloadTask.value

        XCTAssertEqual(statuses.count, 1)
        XCTAssertNil(downloaded)
    }

    func testResponseWithoutRequestIDCannotFinishPendingRequest() async {
        let manager = ConcurrentModelManager()
        let scheduler = ManualTimeoutScheduler()
        let service = TranscriptionModelManagementService(
            processManager: manager,
            scheduleTimeout: scheduler.schedule
        )
        service.configure(scriptPath: "/tmp/whisper_server.py")

        let task = Task {
            await service.fetchStatuses(timeout: 60)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(manager.sendCount, 1)

        manager.emit(managedModelsResponse())
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(manager.stopCount, 0)

        scheduler.fire(index: 0)
        let result = await task.value
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(manager.stopCount, 1)
    }

    func testStaleTimeoutCannotFinishNewStatusRequest() async {
        let manager = ConcurrentModelManager()
        let scheduler = ManualTimeoutScheduler()
        let service = TranscriptionModelManagementService(
            processManager: manager,
            scheduleTimeout: scheduler.schedule
        )
        service.configure(scriptPath: "/tmp/whisper_server.py")

        let firstTask = Task {
            await service.fetchStatuses(timeout: 60)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(manager.sendCount, 1)
        XCTAssertEqual(scheduler.count, 1)

        manager.emit(managedModelsResponse(requestID: manager.requestIDs[0]))
        let firstStatuses = await firstTask.value
        XCTAssertEqual(firstStatuses.count, 1)

        let secondTask = Task {
            await service.fetchStatuses(timeout: 60)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(manager.sendCount, 2)
        XCTAssertEqual(scheduler.count, 2)

        scheduler.fire(index: 0)
        manager.emit(managedModelsResponse(requestID: manager.requestIDs[0]))
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(scheduler.count, 2)
        manager.emit(managedModelsResponse(requestID: manager.requestIDs[1]))

        let secondStatuses = await secondTask.value
        XCTAssertEqual(secondStatuses.count, 1)
    }
}

private func managedModelsResponse(requestID: UInt64? = nil) -> String {
    let requestField = requestID.map { ",\"request_id\":\($0)" } ?? ""
    return PythonProcessManager.controlMessagePrefix
        + "{\"type\":\"managed_models\",\"models\":[{\"kind\":\"cpu\",\"displayName\":\"CPU model\",\"modelID\":\"large-v3-turbo\",\"directoryPath\":\"/tmp/cpu\",\"isDownloaded\":true,\"fileCount\":3,\"byteCount\":100}]\(requestField)}"
}

private final class ManualTimeoutScheduler: @unchecked Sendable {
    private let lock = NSLock()
    private var operations: [@Sendable () -> Void] = []

    var count: Int {
        lock.withLock {
            operations.count
        }
    }

    func schedule(_: TimeInterval, operation: @escaping @Sendable () -> Void) {
        lock.withLock {
            operations.append(operation)
        }
    }

    func fire(index: Int) {
        let operation = lock.withLock {
            operations[index]
        }
        operation()
    }
}

private final class ConcurrentModelManager: PythonModelManaging, @unchecked Sendable {
    var outputReceived: ((String) -> Void)?
    var processTerminated: ((Int32) -> Void)?

    private let lock = NSLock()
    private var running = false
    private var sendCallCount = 0
    private var stopCallCount = 0
    private var sentRequestIDs: [UInt64] = []

    var sendCount: Int {
        lock.withLock {
            sendCallCount
        }
    }

    var requestIDs: [UInt64] {
        lock.withLock {
            sentRequestIDs
        }
    }

    var stopCount: Int {
        lock.withLock {
            stopCallCount
        }
    }

    func startPython(scriptPath: String) {
        lock.withLock {
            running = true
        }
    }

    func sendModelManagement(
        action: ManagedTranscriptionModelAction,
        modelKind: ManagedTranscriptionModelKind?,
        requestID: UInt64
    ) -> Bool {
        lock.withLock {
            sendCallCount += 1
            sentRequestIDs.append(requestID)
        }
        return true
    }

    func isRunning() -> Bool {
        lock.withLock {
            running
        }
    }

    func stop() {
        lock.withLock {
            stopCallCount += 1
            running = false
        }
    }

    func emit(_ output: String) {
        outputReceived?(output)
    }
}
