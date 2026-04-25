import Foundation

struct UserDictionary: Codable {
    var words: [String]
}

final class UserDictionaryManager: @unchecked Sendable {
    static let shared = UserDictionaryManager()

    private let dictionaryURL: URL
    private let lock = NSLock()
    static let maxWordCount = 200

    init(dictionaryURL: URL? = nil) {
        let fileManager = FileManager.default

        if let dictionaryURL {
            self.dictionaryURL = dictionaryURL
            let directoryURL = dictionaryURL.deletingLastPathComponent()
            try? LocalFileProtection.ensurePrivateDirectory(at: directoryURL, fileManager: fileManager)
            try? LocalFileProtection.tightenFilePermissionsIfPresent(
                at: dictionaryURL,
                fileManager: fileManager
            )
            return
        }

        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let settingsDir = appSupportURL.appendingPathComponent("koto-type")
        try? LocalFileProtection.ensurePrivateDirectory(at: settingsDir, fileManager: fileManager)
        self.dictionaryURL = settingsDir.appendingPathComponent("user_dictionary.json")
        try? LocalFileProtection.tightenFilePermissionsIfPresent(
            at: self.dictionaryURL,
            fileManager: fileManager
        )
    }

    var path: String {
        dictionaryURL.path
    }

    func loadWords() -> [String] {
        lock.lock()
        defer { lock.unlock() }

        guard let data = try? Data(contentsOf: dictionaryURL) else {
            return []
        }

        if let dictionary = try? JSONDecoder().decode(UserDictionary.self, from: data) {
            return Self.normalizedWords(dictionary.words)
        }

        if let words = try? JSONDecoder().decode([String].self, from: data) {
            return Self.normalizedWords(words)
        }

        Logger.shared.log("UserDictionaryManager.loadWords: invalid json format at \(dictionaryURL.path)", level: .warning)
        return []
    }

    func saveWords(_ words: [String]) {
        lock.lock()
        defer { lock.unlock() }

        let normalized = Self.normalizedWords(words)
        let payload = UserDictionary(words: normalized)

        do {
            let data = try JSONEncoder().encode(payload)
            try LocalFileProtection.writeProtectedData(data, to: dictionaryURL)
            Logger.shared.log("UserDictionaryManager.saveWords: saved \(normalized.count) words to \(dictionaryURL.path)")
        } catch {
            Logger.shared.log("UserDictionaryManager.saveWords: failed to save dictionary: \(error)", level: .error)
        }
    }

    static func normalizedWords(_ words: [String]) -> [String] {
        var uniqueWords: [String] = []
        var seenKeys: Set<String> = []
        uniqueWords.reserveCapacity(min(words.count, maxWordCount))

        for word in words {
            let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }

            let normalizedSpace = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let key = normalizedSpace.lowercased()
            guard !seenKeys.contains(key) else { continue }

            seenKeys.insert(key)
            uniqueWords.append(normalizedSpace)

            if uniqueWords.count >= maxWordCount {
                break
            }
        }

        return uniqueWords
    }
}
