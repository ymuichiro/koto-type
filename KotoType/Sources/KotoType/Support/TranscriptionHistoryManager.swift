import Foundation

struct TranscriptionHistoryEntry: Codable, Identifiable, Equatable {
    enum Source: String, Codable {
        case liveRecording
        case importedFile

        var displayName: String {
            switch self {
            case .liveRecording:
                return "Live Recording"
            case .importedFile:
                return "Audio File"
            }
        }
    }

    let id: UUID
    let createdAt: Date
    let source: Source
    let audioFilePath: String?
    let text: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        source: Source,
        audioFilePath: String? = nil,
        text: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.audioFilePath = audioFilePath
        self.text = text
    }
}

final class TranscriptionHistoryManager: @unchecked Sendable {
    static let shared = TranscriptionHistoryManager()

    private let historyURL: URL
    private let lock = NSLock()
    private let maxEntryCount: Int

    init(historyURL: URL? = nil, maxEntryCount: Int = 200) {
        self.maxEntryCount = max(1, maxEntryCount)
        let fileManager = FileManager.default

        if let historyURL {
            self.historyURL = historyURL
            let directoryURL = historyURL.deletingLastPathComponent()
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            return
        }

        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let settingsDir = appSupportURL.appendingPathComponent("koto-type")
        try? fileManager.createDirectory(at: settingsDir, withIntermediateDirectories: true)
        self.historyURL = settingsDir.appendingPathComponent("transcription_history.json")
    }

    func loadEntries() -> [TranscriptionHistoryEntry] {
        lock.lock()
        defer { lock.unlock() }

        return readEntriesLocked()
    }

    func addEntry(text: String, source: TranscriptionHistoryEntry.Source, audioFilePath: String? = nil) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        var entries = readEntriesLocked()
        entries.insert(
            TranscriptionHistoryEntry(
                source: source,
                audioFilePath: audioFilePath,
                text: normalized
            ),
            at: 0
        )

        if entries.count > maxEntryCount {
            entries = Array(entries.prefix(maxEntryCount))
        }

        writeEntriesLocked(entries)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        writeEntriesLocked([])
    }

    private func readEntriesLocked() -> [TranscriptionHistoryEntry] {
        guard let data = try? Data(contentsOf: historyURL) else {
            return []
        }

        guard let entries = try? JSONDecoder().decode([TranscriptionHistoryEntry].self, from: data) else {
            Logger.shared.log("TranscriptionHistoryManager: invalid history format at \(historyURL.path)", level: .warning)
            return []
        }

        return entries
    }

    private func writeEntriesLocked(_ entries: [TranscriptionHistoryEntry]) {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: historyURL)
        } catch {
            Logger.shared.log("TranscriptionHistoryManager: failed to write history: \(error)", level: .error)
        }
    }
}
