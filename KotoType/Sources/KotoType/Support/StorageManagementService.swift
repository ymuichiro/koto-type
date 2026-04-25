import Foundation

struct ManagedStorageDirectoryStatus: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let path: String
    let fileCount: Int
    let byteCount: Int64

    var isEmpty: Bool {
        fileCount == 0 || byteCount == 0
    }
}

struct StorageManagementSnapshot: Equatable, Sendable {
    let historyEntryCount: Int
    let historyPath: String
    let historyByteCount: Int64
    let caches: [ManagedStorageDirectoryStatus]
    let models: [ManagedTranscriptionModelStatus]

    var totalCacheFileCount: Int {
        caches.reduce(0) { $0 + $1.fileCount }
    }

    var totalCacheByteCount: Int64 {
        caches.reduce(0) { $0 + $1.byteCount }
    }
}

final class StorageManagementService: @unchecked Sendable {
    private let historyManager: TranscriptionHistoryManager
    private let modelService: TranscriptionModelManagementService
    private let fileManager: FileManager
    private let scriptPathProvider: () -> String
    private let temporaryCacheURL: URL?
    private let managedDownloadCacheURL: URL?

    init(
        historyManager: TranscriptionHistoryManager = .shared,
        modelService: TranscriptionModelManagementService = TranscriptionModelManagementService(),
        fileManager: FileManager = .default,
        scriptPathProvider: @escaping () -> String = { BackendLocator.serverScriptPath() },
        temporaryCacheURL: URL? = nil,
        managedDownloadCacheURL: URL? = nil
    ) {
        self.historyManager = historyManager
        self.modelService = modelService
        self.fileManager = fileManager
        self.scriptPathProvider = scriptPathProvider
        self.temporaryCacheURL = temporaryCacheURL
        self.managedDownloadCacheURL = managedDownloadCacheURL
    }

    func snapshot() async -> StorageManagementSnapshot {
        modelService.configure(scriptPath: scriptPathProvider())

        let historyEntries = historyManager.loadEntries()
        let historyPath = historyManager.storageURL.path
        let historyByteCount = fileSize(at: historyManager.storageURL)
        let models = await modelService.fetchStatuses()
        let caches = [
            directoryStatus(
                id: "temporary-audio-cache",
                title: "Temporary audio cache",
                url: resolvedTemporaryCacheURL
            ),
            directoryStatus(
                id: "managed-download-cache",
                title: "Managed download cache",
                url: resolvedManagedDownloadCacheURL
            ),
        ]

        return StorageManagementSnapshot(
            historyEntryCount: historyEntries.count,
            historyPath: historyPath,
            historyByteCount: historyByteCount,
            caches: caches,
            models: models.sorted { $0.kind.rawValue < $1.kind.rawValue }
        )
    }

    func clearHistory() {
        historyManager.clear()
    }

    func clearCaches() {
        removeItemIfPresent(at: resolvedTemporaryCacheURL)
        removeItemIfPresent(at: resolvedManagedDownloadCacheURL)
    }

    func downloadModel(_ kind: ManagedTranscriptionModelKind) async -> ManagedTranscriptionModelStatus? {
        modelService.configure(scriptPath: scriptPathProvider())
        return await modelService.downloadModel(kind)
    }

    func deleteModel(_ kind: ManagedTranscriptionModelKind) async -> ManagedTranscriptionModelStatus? {
        modelService.configure(scriptPath: scriptPathProvider())
        return await modelService.deleteModel(kind)
    }

    private func directoryStatus(id: String, title: String, url: URL) -> ManagedStorageDirectoryStatus {
        let summary = directorySummary(at: url)
        return ManagedStorageDirectoryStatus(
            id: id,
            title: title,
            path: url.path,
            fileCount: summary.fileCount,
            byteCount: summary.byteCount
        )
    }

    private var resolvedTemporaryCacheURL: URL {
        temporaryCacheURL ?? KotoTypeStoragePaths.temporaryBatchDirectory(fileManager: fileManager)
    }

    private var resolvedManagedDownloadCacheURL: URL {
        managedDownloadCacheURL ?? KotoTypeStoragePaths.managedModelCacheRoot(fileManager: fileManager)
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let number = attributes[.size] as? NSNumber else {
            return 0
        }
        return number.int64Value
    }

    private func directorySummary(at url: URL) -> (fileCount: Int, byteCount: Int64) {
        guard fileManager.fileExists(atPath: url.path) else {
            return (0, 0)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }

        var fileCount = 0
        var byteCount: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            fileCount += 1
            byteCount += Int64(values.fileSize ?? 0)
        }

        return (fileCount, byteCount)
    }

    private func removeItemIfPresent(at url: URL) {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            Logger.shared.log("StorageManagementService: failed to remove \(url.path): \(error)", level: .warning)
        }
    }
}
