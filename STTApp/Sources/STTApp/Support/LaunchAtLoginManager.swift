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
            Logger.shared.log("LaunchAtLoginManager: failed to change login item state: \(error)", level: .error)
            return false
        }
    }

    func isEnabled() -> Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }

        return SMAppService.mainApp.status == .enabled
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
}
