import Foundation

enum BackendLocator {
    static let serverRelativePath = "python/whisper_server.py"

    static func repositoryRoot(currentPath: String = FileManager.default.currentDirectoryPath) -> String {
        guard let range = currentPath.range(of: "/STTApp") else {
            return currentPath
        }
        return String(currentPath[..<range.lowerBound])
    }

    static func serverScriptPath(currentPath: String = FileManager.default.currentDirectoryPath) -> String {
        let root = repositoryRoot(currentPath: currentPath)
        return "\(root)/\(serverRelativePath)"
    }
}
