import Foundation

enum AppRelauncher {
    static func appBundlePath(fromResourcePath resourcePath: String?) -> String? {
        guard let resourcePath else { return nil }
        return URL(fileURLWithPath: resourcePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }

    static func relaunchTaskArguments(appPath: String, currentProcessID: Int32) -> [String] {
        [
            "-c",
            relaunchShellScript,
            "kototype-relaunch",
            "\(currentProcessID)",
            appPath,
        ]
    }

    @discardableResult
    static func relaunchCurrentApp(currentProcessID: Int32 = ProcessInfo.processInfo.processIdentifier) -> Bool {
        guard let appPath = appBundlePath(fromResourcePath: Bundle.main.resourcePath) else {
            Logger.shared.log("AppRelauncher: could not resolve current app bundle path", level: .error)
            return false
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = relaunchTaskArguments(appPath: appPath, currentProcessID: currentProcessID)

        do {
            try task.run()
            Logger.shared.log(
                "AppRelauncher: scheduled relaunch for \(appPath) after pid \(currentProcessID) exits",
                level: .info
            )
            return true
        } catch {
            Logger.shared.log("AppRelauncher: failed to schedule relaunch: \(error)", level: .error)
            return false
        }
    }

    private static let relaunchShellScript = """
    while kill -0 "$1" 2>/dev/null; do
      sleep 0.1
    done
    exec /usr/bin/open -n "$2"
    """
}
