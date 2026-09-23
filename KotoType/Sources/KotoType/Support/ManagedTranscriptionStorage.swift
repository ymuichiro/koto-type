import Foundation

enum ManagedTranscriptionModelKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case cpu
    case mlx

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cpu:
            return "CPU model"
        case .mlx:
            return "MLX model"
        }
    }

    var modelID: String {
        switch self {
        case .cpu:
            return "large-v3-turbo"
        case .mlx:
            return "mlx-community/whisper-large-v3-turbo"
        }
    }

    var storageDirectoryName: String {
        switch self {
        case .cpu:
            return "cpu-large-v3-turbo"
        case .mlx:
            return "mlx-whisper-large-v3-turbo"
        }
    }

    var summary: String {
        switch self {
        case .cpu:
            return "Used when GPU acceleration is off or unavailable."
        case .mlx:
            return "Used when MLX GPU acceleration is available."
        }
    }

    func assetsExist(at directoryURL: URL, fileManager: FileManager = .default) -> Bool {
        switch self {
        case .cpu:
            let configPath = directoryURL.appendingPathComponent("config.json").path
            let modelPath = directoryURL.appendingPathComponent("model.bin").path
            let tokenizerPath = directoryURL.appendingPathComponent("tokenizer.json").path
            return fileManager.fileExists(atPath: configPath)
                && fileManager.fileExists(atPath: modelPath)
                && fileManager.fileExists(atPath: tokenizerPath)
        case .mlx:
            let configPath = directoryURL.appendingPathComponent("config.json").path
            let safeTensorsPath = directoryURL.appendingPathComponent("weights.safetensors").path
            let npzPath = directoryURL.appendingPathComponent("weights.npz").path
            return fileManager.fileExists(atPath: configPath)
                && (fileManager.fileExists(atPath: safeTensorsPath) || fileManager.fileExists(atPath: npzPath))
        }
    }
}

enum ManagedTranscriptionModelAction: String, Sendable {
    case statusAll = "status_all"
    case download
    case delete
}

struct ManagedTranscriptionModelStatus: Codable, Equatable, Identifiable, Sendable {
    let kind: ManagedTranscriptionModelKind
    let displayName: String
    let modelID: String
    let directoryPath: String
    let isDownloaded: Bool
    let fileCount: Int
    let byteCount: Int64

    var id: ManagedTranscriptionModelKind { kind }
}

struct ManagedTranscriptionModelsResponse: Codable, Equatable, Sendable {
    let type: String
    let models: [ManagedTranscriptionModelStatus]
    let requestID: UInt64?

    enum CodingKeys: String, CodingKey {
        case type
        case models
        case requestID = "request_id"
    }
}

struct ManagedTranscriptionModelResponse: Codable, Equatable, Sendable {
    let type: String
    let model: ManagedTranscriptionModelStatus
    let requestID: UInt64?

    enum CodingKeys: String, CodingKey {
        case type
        case model
        case requestID = "request_id"
    }
}

enum KotoTypeStoragePaths {
    static let appDirectoryName = "koto-type"
    static let temporaryBatchDirectoryName = "koto-type-batch-recordings"

    static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(appDirectoryName, isDirectory: true)
    }

    static func modelStorageRoot(
        directoryPath: String? = SettingsManager.shared.load().modelStorageDirectoryPath,
        fileManager: FileManager = .default
    ) -> URL {
        guard let directoryPath,
              !directoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return applicationSupportDirectory(fileManager: fileManager)
        }
        return URL(fileURLWithPath: directoryPath, isDirectory: true).standardizedFileURL
    }

    static func managedModelsRoot(
        storageRootURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        (storageRootURL ?? modelStorageRoot(fileManager: fileManager))
            .appendingPathComponent("managed-models", isDirectory: true)
    }

    static func managedModelDirectory(
        for kind: ManagedTranscriptionModelKind,
        storageRootURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        managedModelsRoot(storageRootURL: storageRootURL, fileManager: fileManager)
            .appendingPathComponent(kind.storageDirectoryName, isDirectory: true)
    }

    static func managedModelCacheRoot(
        storageRootURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        (storageRootURL ?? modelStorageRoot(fileManager: fileManager))
            .appendingPathComponent("model-cache", isDirectory: true)
    }

    static func huggingFaceHome(
        storageRootURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        managedModelCacheRoot(storageRootURL: storageRootURL, fileManager: fileManager)
            .appendingPathComponent("huggingface", isDirectory: true)
    }

    static func huggingFaceHubCache(
        storageRootURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        huggingFaceHome(storageRootURL: storageRootURL, fileManager: fileManager)
            .appendingPathComponent("hub", isDirectory: true)
    }

    static func transcriptionHistoryFile(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("transcription_history.json")
    }

    static func temporaryBatchDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent(temporaryBatchDirectoryName, isDirectory: true)
    }

    static func managedModelEnvironment(
        storageRootURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> [String: String] {
        [
            "KOTOTYPE_CPU_MODEL_DIR": managedModelDirectory(
                for: .cpu,
                storageRootURL: storageRootURL,
                fileManager: fileManager
            ).path,
            "KOTOTYPE_MLX_MODEL_DIR": managedModelDirectory(
                for: .mlx,
                storageRootURL: storageRootURL,
                fileManager: fileManager
            ).path,
            "KOTOTYPE_MODEL_CACHE_DIR": managedModelCacheRoot(
                storageRootURL: storageRootURL,
                fileManager: fileManager
            ).path,
            "HF_HOME": huggingFaceHome(
                storageRootURL: storageRootURL,
                fileManager: fileManager
            ).path,
            "HUGGINGFACE_HUB_CACHE": huggingFaceHubCache(
                storageRootURL: storageRootURL,
                fileManager: fileManager
            ).path,
        ]
    }

    static func formattedByteCount(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

enum ModelStorageDirectoryAvailability: Equatable {
    case usesDefault
    case available
    case missing
    case notDirectory
    case notWritable
}

extension KotoTypeStoragePaths {
    static func modelStorageDirectoryAvailability(
        directoryPath: String?,
        fileManager: FileManager = .default
    ) -> ModelStorageDirectoryAvailability {
        guard let directoryPath else {
            return .usesDefault
        }
        let path = directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return .usesDefault }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .missing
        }
        guard isDirectory.boolValue else {
            return .notDirectory
        }
        guard fileManager.isWritableFile(atPath: path) else {
            return .notWritable
        }
        return .available
    }
}
