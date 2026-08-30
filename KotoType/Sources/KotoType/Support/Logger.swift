import Foundation
import os.log

final class Logger: @unchecked Sendable {
    static let shared = Logger()
    
    private let logger: OSLog
    private let logFile: URL
    private let fileWriteLock = NSLock()
    private var fileHandle: FileHandle?

    private static let quotedAbsolutePathRegex = try! NSRegularExpression(
        pattern: #"([\"'])(/(?!/)[^\"']*)\1"#
    )
    private static let smartQuotedAbsolutePathRegex = try! NSRegularExpression(
        pattern: #"([“‘])(/(?!/)[^”’]*)([”’])"#
    )
    private static let quotedFileURLRegex = try! NSRegularExpression(
        pattern: #"([\"'])(file://(?:localhost)?/(?!/)[^\"']*)\1"#
    )
    private static let smartQuotedFileURLRegex = try! NSRegularExpression(
        pattern: #"([“‘])(file://(?:localhost)?/(?!/)[^”’]*)([”’])"#
    )
    private static let unquotedFileURLRegex = try! NSRegularExpression(
        pattern: #"file://(?:localhost)?/(?!/)[^\s,;)\"'“”‘’]+"#
    )
    private static let unquotedAbsolutePathRegex = try! NSRegularExpression(
        pattern: #"(^|[\s:(=“‘])/(?!/)[^\s,;)\"'“”‘’]+"#
    )
    
    private init() {
        logger = OSLog(subsystem: "com.ymuichiro.kototype", category: "Main")
        
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let logDir = appSupportURL.appendingPathComponent("koto-type")
        
        do {
            try LocalFileProtection.ensurePrivateDirectory(at: logDir, fileManager: fileManager)
        } catch {
            print(Self.sanitizedMessage("Failed to prepare log directory: \(error)"))
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        logFile = logDir.appendingPathComponent("kototype_\(dateString).log")
        
        if !fileManager.fileExists(atPath: logFile.path) {
            fileManager.createFile(atPath: logFile.path, contents: nil)
        }
        do {
            try LocalFileProtection.tightenFilePermissionsIfPresent(
                at: logFile,
                fileManager: fileManager
            )
        } catch {
            print(Self.sanitizedMessage("Failed to tighten log file permissions: \(error)"))
        }
        
        do {
            fileHandle = try FileHandle(forWritingTo: logFile)
            fileHandle?.seekToEndOfFile()
        } catch {
            print(Self.sanitizedMessage("Failed to open log file: \(error)"))
        }
    }
    
    var logPath: String {
        return logFile.path
    }

    static func sanitizedMessage(_ message: String) -> String {
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        let quotedFileURLSanitized = quotedFileURLRegex.stringByReplacingMatches(
            in: message,
            range: range,
            withTemplate: "$1<path>$1"
        )
        let smartQuotedFileURLSanitized = smartQuotedFileURLRegex.stringByReplacingMatches(
            in: quotedFileURLSanitized,
            range: NSRange(quotedFileURLSanitized.startIndex..<quotedFileURLSanitized.endIndex, in: quotedFileURLSanitized),
            withTemplate: "$1<path>$3"
        )
        let fileURLSanitized = unquotedFileURLRegex.stringByReplacingMatches(
            in: smartQuotedFileURLSanitized,
            range: NSRange(smartQuotedFileURLSanitized.startIndex..<smartQuotedFileURLSanitized.endIndex, in: smartQuotedFileURLSanitized),
            withTemplate: "<path>"
        )
        let quotedSanitized = quotedAbsolutePathRegex.stringByReplacingMatches(
            in: fileURLSanitized,
            range: NSRange(fileURLSanitized.startIndex..<fileURLSanitized.endIndex, in: fileURLSanitized),
            withTemplate: "$1<path>$1"
        )
        let smartQuotedSanitized = smartQuotedAbsolutePathRegex.stringByReplacingMatches(
            in: quotedSanitized,
            range: NSRange(quotedSanitized.startIndex..<quotedSanitized.endIndex, in: quotedSanitized),
            withTemplate: "$1<path>$3"
        )
        let sanitizedRange = NSRange(smartQuotedSanitized.startIndex..<smartQuotedSanitized.endIndex, in: smartQuotedSanitized)
        return unquotedAbsolutePathRegex.stringByReplacingMatches(
            in: smartQuotedSanitized,
            range: sanitizedRange,
            withTemplate: "$1<path>"
        )
    }
    
    func log(_ message: String, level: LogLevel = .info) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let safeMessage = Self.sanitizedMessage(message)
        let logMessage = "[\(timestamp)] [\(level.rawValue)] \(safeMessage)\n"
        
        if let data = logMessage.data(using: .utf8) {
            fileWriteLock.lock()
            fileHandle?.write(data)
            fileWriteLock.unlock()
        }
        
        // Never mark logs as public to avoid exposing sensitive values in unified logging.
        os_log("%{private}@", log: logger, type: level.osLogType, safeMessage)
        
        print(logMessage, terminator: "")
    }
    
    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        
        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            }
        }
    }
}
