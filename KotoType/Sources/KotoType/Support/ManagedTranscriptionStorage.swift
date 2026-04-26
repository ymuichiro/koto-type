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
}

struct ManagedTranscriptionModelResponse: Codable, Equatable, Sendable {
    let type: String
    let model: ManagedTranscriptionModelStatus
}

enum KotoTypeStoragePaths {
    static let appDirectoryName = "koto-type"
    static let temporaryBatchDirectoryName = "koto-type-batch-recordings"

    static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(appDirectoryName, isDirectory: true)
    }

    static func managedModelsRoot(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("managed-models", isDirectory: true)
    }

    static func managedModelDirectory(
        for kind: ManagedTranscriptionModelKind,
        fileManager: FileManager = .default
    ) -> URL {
        managedModelsRoot(fileManager: fileManager)
            .appendingPathComponent(kind.storageDirectoryName, isDirectory: true)
    }

    static func managedModelCacheRoot(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("model-cache", isDirectory: true)
    }

    static func huggingFaceHome(fileManager: FileManager = .default) -> URL {
        managedModelCacheRoot(fileManager: fileManager)
            .appendingPathComponent("huggingface", isDirectory: true)
    }

    static func huggingFaceHubCache(fileManager: FileManager = .default) -> URL {
        huggingFaceHome(fileManager: fileManager)
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

    static func managedModelEnvironment(fileManager: FileManager = .default) -> [String: String] {
        [
            "KOTOTYPE_CPU_MODEL_DIR": managedModelDirectory(for: .cpu, fileManager: fileManager).path,
            "KOTOTYPE_MLX_MODEL_DIR": managedModelDirectory(for: .mlx, fileManager: fileManager).path,
            "KOTOTYPE_MODEL_CACHE_DIR": managedModelCacheRoot(fileManager: fileManager).path,
            "HF_HOME": huggingFaceHome(fileManager: fileManager).path,
            "HUGGINGFACE_HUB_CACHE": huggingFaceHubCache(fileManager: fileManager).path,
        ]
    }

    static func formattedByteCount(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}
