@testable import KotoType
import Foundation
import XCTest

final class StorageManagementServiceTests: XCTestCase {
    private var tempRoot: URL!
    private var historyURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("storage-management-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        historyURL = tempRoot.appendingPathComponent("history.json")
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        historyURL = nil
        try super.tearDownWithError()
    }

    func testModelManagementServiceFetchesStatuses() async {
        let mock = MockPythonModelManager(
            responseOutput: PythonProcessManager.controlMessagePrefix
                + "{\"type\":\"managed_models\",\"models\":[{\"kind\":\"cpu\",\"displayName\":\"CPU model\",\"modelID\":\"large-v3-turbo\",\"directoryPath\":\"/tmp/cpu\",\"isDownloaded\":true,\"fileCount\":3,\"byteCount\":100}]}"
        )
        let service = TranscriptionModelManagementService(processManager: mock)
        service.configure(scriptPath: "/tmp/whisper_server.py")

        let models = await service.fetchStatuses(timeout: 2)

        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models.first?.kind, .cpu)
        XCTAssertEqual(mock.startCallCount, 1)
        XCTAssertEqual(mock.stopCallCount, 1)
        XCTAssertEqual(mock.lastAction, .statusAll)
        XCTAssertNil(mock.lastModelKind)
    }

    func testModelManagementServiceDownloadsSingleModel() async {
        let mock = MockPythonModelManager(
            responseOutput: PythonProcessManager.controlMessagePrefix
                + "{\"type\":\"managed_model\",\"model\":{\"kind\":\"mlx\",\"displayName\":\"MLX model\",\"modelID\":\"mlx-community/whisper-large-v3-turbo\",\"directoryPath\":\"/tmp/mlx\",\"isDownloaded\":true,\"fileCount\":5,\"byteCount\":200}}"
        )
        let service = TranscriptionModelManagementService(processManager: mock)
        service.configure(scriptPath: "/tmp/whisper_server.py")

        let model = await service.downloadModel(.mlx, timeout: 2)

        XCTAssertEqual(model?.kind, .mlx)
        XCTAssertEqual(model?.isDownloaded, true)
        XCTAssertEqual(mock.lastAction, .download)
        XCTAssertEqual(mock.lastModelKind, .mlx)
    }

    func testStorageManagementSnapshotIncludesHistoryAndCaches() async throws {
        let historyManager = TranscriptionHistoryManager(historyURL: historyURL, maxEntryCount: 10)
        historyManager.addEntry(text: "hello", source: .liveRecording)
        historyManager.addEntry(text: "world", source: .importedFile)

        let temporaryCacheURL = tempRoot.appendingPathComponent("temporary-cache", isDirectory: true)
        let downloadCacheURL = tempRoot.appendingPathComponent("download-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryCacheURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloadCacheURL, withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: temporaryCacheURL.appendingPathComponent("temp.wav"))
        try Data("xyz".utf8).write(to: downloadCacheURL.appendingPathComponent("hub.bin"))

        let mock = MockPythonModelManager(
            responseOutput: PythonProcessManager.controlMessagePrefix
                + "{\"type\":\"managed_models\",\"models\":[{\"kind\":\"cpu\",\"displayName\":\"CPU model\",\"modelID\":\"large-v3-turbo\",\"directoryPath\":\"/tmp/cpu\",\"isDownloaded\":false,\"fileCount\":0,\"byteCount\":0},{\"kind\":\"mlx\",\"displayName\":\"MLX model\",\"modelID\":\"mlx-community/whisper-large-v3-turbo\",\"directoryPath\":\"/tmp/mlx\",\"isDownloaded\":true,\"fileCount\":5,\"byteCount\":200}]}"
        )
        let modelService = TranscriptionModelManagementService(processManager: mock)
        let service = StorageManagementService(
            historyManager: historyManager,
            modelService: modelService,
            fileManager: .default,
            scriptPathProvider: { "/tmp/whisper_server.py" },
            temporaryCacheURL: temporaryCacheURL,
            managedDownloadCacheURL: downloadCacheURL
        )

        let snapshot = await service.snapshot()

        XCTAssertEqual(snapshot.historyEntryCount, 2)
        XCTAssertEqual(snapshot.caches.count, 2)
        XCTAssertEqual(snapshot.totalCacheFileCount, 2)
        XCTAssertEqual(snapshot.models.count, 2)
        XCTAssertEqual(snapshot.models.last?.kind, .mlx)
    }

    func testStorageManagementServiceClearsHistoryAndCaches() throws {
        let historyManager = TranscriptionHistoryManager(historyURL: historyURL, maxEntryCount: 10)
        historyManager.addEntry(text: "hello", source: .liveRecording)

        let temporaryCacheURL = tempRoot.appendingPathComponent("temporary-cache", isDirectory: true)
        let downloadCacheURL = tempRoot.appendingPathComponent("download-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryCacheURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloadCacheURL, withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: temporaryCacheURL.appendingPathComponent("temp.wav"))
        try Data("xyz".utf8).write(to: downloadCacheURL.appendingPathComponent("hub.bin"))

        let modelService = TranscriptionModelManagementService(processManager: MockPythonModelManager(responseOutput: nil))
        let service = StorageManagementService(
            historyManager: historyManager,
            modelService: modelService,
            fileManager: .default,
            scriptPathProvider: { "/tmp/whisper_server.py" },
            temporaryCacheURL: temporaryCacheURL,
            managedDownloadCacheURL: downloadCacheURL
        )

        service.clearHistory()
        service.clearCaches()

        XCTAssertTrue(historyManager.loadEntries().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryCacheURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloadCacheURL.path))
    }
}

private final class MockPythonModelManager: PythonModelManaging {
    var outputReceived: ((String) -> Void)?
    var processTerminated: ((Int32) -> Void)?

    private let responseOutput: String?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastAction: ManagedTranscriptionModelAction?
    private(set) var lastModelKind: ManagedTranscriptionModelKind?
    private var running = false

    init(responseOutput: String?) {
        self.responseOutput = responseOutput
    }

    func startPython(scriptPath: String) {
        startCallCount += 1
        running = true
    }

    func sendModelManagement(
        action: ManagedTranscriptionModelAction,
        modelKind: ManagedTranscriptionModelKind?
    ) -> Bool {
        lastAction = action
        lastModelKind = modelKind
        if let responseOutput {
            outputReceived?(responseOutput)
        }
        return true
    }

    func isRunning() -> Bool {
        running
    }

    func stop() {
        stopCallCount += 1
        running = false
    }
}
