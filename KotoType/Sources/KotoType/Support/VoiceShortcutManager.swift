import Foundation

enum VoiceShortcutActionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case insertText
    case keyCommand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .insertText:
            return "Insert Text"
        case .keyCommand:
            return "Key Command"
        }
    }
}

struct VoiceShortcut: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var triggerPhrase: String
    var actionKind: VoiceShortcutActionKind
    var insertText: String
    var keyCommand: HotkeyConfiguration?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        triggerPhrase: String,
        actionKind: VoiceShortcutActionKind,
        insertText: String = "",
        keyCommand: HotkeyConfiguration? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.triggerPhrase = triggerPhrase
        self.actionKind = actionKind
        self.insertText = insertText
        self.keyCommand = keyCommand
        self.isEnabled = isEnabled
    }

    var actionSummary: String {
        switch actionKind {
        case .insertText:
            return "Insert \(insertText.count) characters"
        case .keyCommand:
            let commandDescription = keyCommand?.description ?? ""
            return commandDescription.isEmpty ? "Record key command" : commandDescription
        }
    }
}

final class VoiceShortcutManager: @unchecked Sendable {
    static let shared = VoiceShortcutManager()
    static let maxShortcutCount = 100
    private static let normalizationLocale = Locale(identifier: "en_US_POSIX")

    private let storageURL: URL
    private let lock = NSLock()

    init(storageURL: URL? = nil) {
        let fileManager = FileManager.default

        if let storageURL {
            self.storageURL = storageURL
            let directoryURL = storageURL.deletingLastPathComponent()
            try? LocalFileProtection.ensurePrivateDirectory(at: directoryURL, fileManager: fileManager)
            try? LocalFileProtection.tightenFilePermissionsIfPresent(
                at: storageURL,
                fileManager: fileManager
            )
            return
        }

        let directoryURL = KotoTypeStoragePaths.applicationSupportDirectory(fileManager: fileManager)
        try? LocalFileProtection.ensurePrivateDirectory(at: directoryURL, fileManager: fileManager)
        self.storageURL = directoryURL.appendingPathComponent("shortcuts.json")
        try? LocalFileProtection.tightenFilePermissionsIfPresent(
            at: self.storageURL,
            fileManager: fileManager
        )
    }

    var path: String {
        storageURL.path
    }

    func loadShortcuts() -> [VoiceShortcut] {
        lock.lock()
        defer { lock.unlock() }

        guard let data = try? Data(contentsOf: storageURL) else {
            return []
        }

        guard let shortcuts = try? JSONDecoder().decode([VoiceShortcut].self, from: data) else {
            Logger.shared.log(
                "VoiceShortcutManager.loadShortcuts: invalid json format at \(storageURL.path)",
                level: .warning
            )
            return []
        }

        return Self.normalizedShortcuts(shortcuts)
    }

    func saveShortcuts(_ shortcuts: [VoiceShortcut]) {
        lock.lock()
        defer { lock.unlock() }

        let normalized = Self.normalizedShortcuts(shortcuts)

        do {
            let data = try JSONEncoder().encode(normalized)
            try LocalFileProtection.writeProtectedData(data, to: storageURL)
            Logger.shared.log(
                "VoiceShortcutManager.saveShortcuts: saved \(normalized.count) shortcuts to \(storageURL.path)"
            )
        } catch {
            Logger.shared.log(
                "VoiceShortcutManager.saveShortcuts: failed to save shortcuts: \(error)",
                level: .error
            )
        }
    }

    func resolve(input: String) -> VoiceShortcut? {
        let normalizedInput = Self.normalizedTrigger(input)
        guard !normalizedInput.isEmpty else {
            return nil
        }

        return loadShortcuts().first { shortcut in
            shortcut.isEnabled && Self.normalizedTrigger(shortcut.triggerPhrase) == normalizedInput
        }
    }

    static func normalizedTrigger(_ trigger: String) -> String {
        var normalized = trigger.precomposedStringWithCompatibilityMapping
        normalized = normalized.replacingOccurrences(of: "\u{3000}", with: " ")
        normalized = collapseWhitespace(in: normalized)
        normalized = stripEnclosingPairs(from: normalized)
        normalized = stripEdgeSymbols(from: normalized)
        normalized = stripTrailingSentencePunctuation(from: normalized)
        normalized = stripEnclosingPairs(from: normalized)
        normalized = stripEdgeSymbols(from: normalized)
        normalized = collapseWhitespace(in: normalized)

        return normalized
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: normalizationLocale
            )
            .lowercased()
    }

    static func emptyKeyCommand() -> HotkeyConfiguration {
        HotkeyConfiguration(
            useCommand: false,
            useOption: false,
            useControl: false,
            useShift: false,
            commandSide: .either,
            optionSide: .either,
            controlSide: .either,
            shiftSide: .either,
            keyCode: 0
        )
    }

    static func normalizedShortcuts(_ shortcuts: [VoiceShortcut]) -> [VoiceShortcut] {
        var normalizedShortcuts: [VoiceShortcut] = []
        var seenTriggers: Set<String> = []
        normalizedShortcuts.reserveCapacity(min(shortcuts.count, maxShortcutCount))

        for var shortcut in shortcuts {
            let cleanedTrigger = cleanedDisplayTrigger(shortcut.triggerPhrase)
            let normalizedTrigger = normalizedTrigger(cleanedTrigger)
            guard !normalizedTrigger.isEmpty else {
                continue
            }

            shortcut.triggerPhrase = cleanedTrigger

            switch shortcut.actionKind {
            case .insertText:
                let cleanedInsertText = shortcut.insertText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanedInsertText.isEmpty else {
                    continue
                }
                shortcut.insertText = cleanedInsertText
                shortcut.keyCommand = nil
            case .keyCommand:
                guard let keyCommand = shortcut.keyCommand, keyCommand.keyCode > 0 else {
                    continue
                }
                shortcut.insertText = ""
                shortcut.keyCommand = keyCommand
            }

            guard seenTriggers.insert(normalizedTrigger).inserted else {
                continue
            }

            normalizedShortcuts.append(shortcut)
            if normalizedShortcuts.count >= maxShortcutCount {
                break
            }
        }

        return normalizedShortcuts
    }

    private static func cleanedDisplayTrigger(_ trigger: String) -> String {
        collapseWhitespace(in: trigger.precomposedStringWithCompatibilityMapping)
    }

    private static func collapseWhitespace(in string: String) -> String {
        string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func stripTrailingSentencePunctuation(from string: String) -> String {
        let punctuationScalars = CharacterSet(charactersIn: "。．.!！?？,、")
        var value = string

        while let lastScalar = value.unicodeScalars.last, punctuationScalars.contains(lastScalar) {
            value = String(value.unicodeScalars.dropLast())
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return value
    }

    private static func stripEdgeSymbols(from string: String) -> String {
        let edgeCharacterSet = CharacterSet.punctuationCharacters
            .union(.symbols)
            .union(.whitespacesAndNewlines)
        var value = string

        while let first = value.first, shouldStripEdgeCharacter(first, using: edgeCharacterSet) {
            value.removeFirst()
        }

        while let last = value.last, shouldStripEdgeCharacter(last, using: edgeCharacterSet) {
            value.removeLast()
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldStripEdgeCharacter(
        _ character: Character,
        using characterSet: CharacterSet
    ) -> Bool {
        character.unicodeScalars.allSatisfy { characterSet.contains($0) }
    }

    private static func stripEnclosingPairs(from string: String) -> String {
        let pairs = [
            ("\"", "\""),
            ("'", "'"),
            ("“", "”"),
            ("‘", "’"),
            ("「", "」"),
            ("『", "』"),
            ("(", ")"),
            ("（", "）"),
            ("[", "]"),
            ("［", "］"),
            ("【", "】"),
            ("<", ">"),
            ("〈", "〉"),
            ("《", "》"),
        ]

        var value = string.trimmingCharacters(in: .whitespacesAndNewlines)

        while true {
            var removedPair = false
            for (opening, closing) in pairs {
                guard value.hasPrefix(opening), value.hasSuffix(closing) else {
                    continue
                }

                value.removeFirst(opening.count)
                value.removeLast(closing.count)
                value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                removedPair = true
                break
            }

            if !removedPair {
                return value
            }
        }
    }
}

enum VoiceShortcutExecutor {
    static func execute(_ shortcut: VoiceShortcut) -> Bool {
        switch shortcut.actionKind {
        case .insertText:
            guard !shortcut.insertText.isEmpty else {
                return false
            }
            KeystrokeSimulator.typeText(shortcut.insertText)
            return true
        case .keyCommand:
            guard let keyCommand = shortcut.keyCommand, keyCommand.keyCode > 0 else {
                return false
            }
            KeystrokeSimulator.executeKeyCommand(keyCommand)
            return true
        }
    }
}
