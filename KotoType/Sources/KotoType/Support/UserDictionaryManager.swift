import Foundation

struct UserDictionary: Codable {
    var words: [String]
}

struct UserDictionaryCSVImportResult: Equatable {
    let words: [String]
    let importedCount: Int
    let duplicateCount: Int
    let blankCount: Int
    let truncatedCount: Int
}

enum UserDictionaryCSVError: LocalizedError, Equatable {
    case invalidEncoding
    case invalidFormat(row: Int)

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "The CSV file must be UTF-8 encoded."
        case let .invalidFormat(row):
            return "CSV row \(row) must contain exactly one term column."
        }
    }
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

    var storageURL: URL {
        dictionaryURL
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

    func importWords(
        fromCSVData data: Data,
        existingWords: [String]
    ) throws -> UserDictionaryCSVImportResult {
        guard let csvString = String(data: data, encoding: .utf8) else {
            throw UserDictionaryCSVError.invalidEncoding
        }

        let rows = try Self.parseCSVRows(csvString)
        var words = Self.normalizedWords(existingWords)
        var seenKeys = Set(words.map(Self.normalizedKey))
        var importedCount = 0
        var duplicateCount = 0
        var blankCount = 0
        var truncatedCount = 0

        for (index, row) in rows.enumerated() {
            if row.isEmpty {
                blankCount += 1
                continue
            }

            guard row.count == 1 else {
                throw UserDictionaryCSVError.invalidFormat(row: index + 1)
            }

            let rawValue = Self.strippingLeadingByteOrderMark(
                row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if rawValue.isEmpty {
                blankCount += 1
                continue
            }

            if index == 0 && rawValue.caseInsensitiveCompare("term") == .orderedSame {
                continue
            }

            guard let normalizedWord = Self.normalizedDisplayWord(rawValue) else {
                blankCount += 1
                continue
            }

            let key = Self.normalizedKey(normalizedWord)
            if seenKeys.contains(key) {
                duplicateCount += 1
                continue
            }

            guard words.count < Self.maxWordCount else {
                truncatedCount += 1
                continue
            }

            seenKeys.insert(key)
            words.append(normalizedWord)
            importedCount += 1
        }

        return UserDictionaryCSVImportResult(
            words: words,
            importedCount: importedCount,
            duplicateCount: duplicateCount,
            blankCount: blankCount,
            truncatedCount: truncatedCount
        )
    }

    func csvData(for words: [String]) -> Data {
        let lines = ["term"] + Self.normalizedWords(words).map(Self.escapedCSVField)
        let csvString = lines.joined(separator: "\n") + "\n"
        return Data(csvString.utf8)
    }

    static func normalizedWords(_ words: [String]) -> [String] {
        var uniqueWords: [String] = []
        var seenKeys: Set<String> = []
        uniqueWords.reserveCapacity(min(words.count, maxWordCount))

        for word in words {
            guard let normalizedSpace = normalizedDisplayWord(word) else {
                continue
            }

            let key = normalizedKey(normalizedSpace)
            guard !seenKeys.contains(key) else { continue }

            seenKeys.insert(key)
            uniqueWords.append(normalizedSpace)

            if uniqueWords.count >= maxWordCount {
                break
            }
        }

        return uniqueWords
    }

    private static func normalizedDisplayWord(_ word: String) -> String? {
        let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return nil
        }

        let normalizedSpace = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return normalizedSpace.isEmpty ? nil : normalizedSpace
    }

    private static func normalizedKey(_ word: String) -> String {
        word.lowercased()
    }

    private static func strippingLeadingByteOrderMark(_ value: String) -> String {
        guard value.unicodeScalars.first == "\u{FEFF}" else {
            return value
        }
        return String(value.unicodeScalars.dropFirst())
    }

    private static func escapedCSVField(_ field: String) -> String {
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") || escaped.contains("\r") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    private static func parseCSVRows(_ csvString: String) throws -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var isInsideQuotes = false
        var index = csvString.startIndex

        while index < csvString.endIndex {
            let character = csvString[index]

            if character == "\"" {
                let nextIndex = csvString.index(after: index)
                if isInsideQuotes, nextIndex < csvString.endIndex, csvString[nextIndex] == "\"" {
                    currentField.append("\"")
                    index = csvString.index(after: nextIndex)
                    continue
                }

                isInsideQuotes.toggle()
                index = nextIndex
                continue
            }

            if !isInsideQuotes, character == "," {
                currentRow.append(currentField)
                currentField = ""
                index = csvString.index(after: index)
                continue
            }

            if !isInsideQuotes, character == "\n" || character == "\r" {
                currentRow.append(currentField)
                rows.append(currentRow)
                currentRow = []
                currentField = ""

                let nextIndex = csvString.index(after: index)
                if character == "\r", nextIndex < csvString.endIndex, csvString[nextIndex] == "\n" {
                    index = csvString.index(after: nextIndex)
                } else {
                    index = nextIndex
                }
                continue
            }

            currentField.append(character)
            index = csvString.index(after: index)
        }

        if isInsideQuotes {
            throw UserDictionaryCSVError.invalidFormat(row: rows.count + 1)
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return rows
    }
}
