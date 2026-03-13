import Foundation
import ServiceManagement

final class LaunchAtLoginManager: @unchecked Sendable {
    static let shared = LaunchAtLoginManager()

    private init() {}

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else {
            Logger.shared.log("LaunchAtLoginManager: unsupported macOS version", level: .warning)
            return false
        }

        let service = SMAppService.mainApp
        let bundlePath = Bundle.main.bundlePath

        guard Self.canManageLaunchAtLogin(bundlePath: bundlePath) else {
            cleanupUnsupportedRuntimeRegistration(service: service, bundlePath: bundlePath)
            Logger.shared.log(
                "LaunchAtLoginManager: skipping login item management outside Applications for \(bundlePath)",
                level: .warning
            )
            return !enabled
        }

        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }

            Logger.shared.log("LaunchAtLoginManager: set enabled=\(enabled), status=\(statusDescription(service.status))")
            return service.status == (enabled ? .enabled : .notRegistered) || (!enabled && service.status != .enabled)
        } catch {
            Logger.shared.log(
                "LaunchAtLoginManager: failed to change login item state for \(bundlePath): \(error)",
                level: .error
            )
            return false
        }
    }

    func isEnabled() -> Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }

        return SMAppService.mainApp.status == .enabled
    }

    static func canManageLaunchAtLogin(bundlePath: String = Bundle.main.bundlePath) -> Bool {
        guard let appBundlePath = applicationBundlePath(from: bundlePath) else {
            return false
        }

        let normalizedPath = URL(fileURLWithPath: appBundlePath).standardizedFileURL.path
        let userApplicationsPath = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Applications", isDirectory: true)
            .path

        return normalizedPath.hasPrefix("/Applications/")
            || normalizedPath.hasPrefix("\(userApplicationsPath)/")
    }

    static func applicationBundlePath(from runtimePath: String) -> String? {
        let normalizedPath = URL(fileURLWithPath: runtimePath).standardizedFileURL.path
        var currentPath = ""

        for component in normalizedPath.split(separator: "/", omittingEmptySubsequences: true) {
            currentPath += "/\(component)"
            if component.hasSuffix(".app") {
                return currentPath
            }
        }

        return nil
    }

    @available(macOS 13.0, *)
    private func statusDescription(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            return "enabled"
        case .notRegistered:
            return "not_registered"
        case .requiresApproval:
            return "requires_approval"
        case .notFound:
            return "not_found"
        @unknown default:
            return "unknown"
        }
    }

    @available(macOS 13.0, *)
    private func cleanupUnsupportedRuntimeRegistration(service: SMAppService, bundlePath: String) {
        guard service.status == .enabled || service.status == .requiresApproval else {
            return
        }

        do {
            try service.unregister()
            Logger.shared.log(
                "LaunchAtLoginManager: removed stale login item registration for unsupported runtime \(bundlePath)",
                level: .warning
            )
        } catch {
            Logger.shared.log(
                "LaunchAtLoginManager: failed to remove unsupported runtime login item for \(bundlePath): \(error)",
                level: .error
            )
        }
    }
}
