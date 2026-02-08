import Foundation
import os.log

final class Logger {
    nonisolated(unsafe) static let shared = Logger()
    
    private let logger: OSLog
    private let logFile: URL
    private var fileHandle: FileHandle?
    
    private init() {
        logger = OSLog(subsystem: "com.ymuichiro.stt-simple", category: "Main")
        
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let logDir = appSupportURL.appendingPathComponent("stt-simple")
        
        try? fileManager.createDirectory(at: logDir, withIntermediateDirectories: true)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        logFile = logDir.appendingPathComponent("stt_simple_\(dateString).log")
        
        if !fileManager.fileExists(atPath: logFile.path) {
            fileManager.createFile(atPath: logFile.path, contents: nil)
        }
        
        do {
            fileHandle = try FileHandle(forWritingTo: logFile)
            fileHandle?.seekToEndOfFile()
        } catch {
            print("Failed to open log file: \(error)")
        }
    }
    
    var logPath: String {
        return logFile.path
    }
    
    func log(_ message: String, level: LogLevel = .info) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] [\(level.rawValue)] \(message)\n"
        
        if let data = logMessage.data(using: .utf8) {
            fileHandle?.write(data)
        }
        
        os_log("%{public}@", log: logger, type: level.osLogType, message)
        
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
