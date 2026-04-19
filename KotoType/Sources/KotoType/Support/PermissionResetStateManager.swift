import Foundation

final class PermissionResetStateManager: @unchecked Sendable {
    static let shared = PermissionResetStateManager()

    private let defaults: UserDefaults
    private let attemptedInstallationTokenKey = "automaticPermissionResetAttemptedInstallationToken"
    private let lastResetCommandKey = "automaticPermissionResetCommand"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasAttemptedReset(for installationToken: String) -> Bool {
        defaults.string(forKey: attemptedInstallationTokenKey) == installationToken
    }

    func markResetAttempt(for installationToken: String, command: String) {
        defaults.set(installationToken, forKey: attemptedInstallationTokenKey)
        defaults.set(command, forKey: lastResetCommandKey)
    }

    var lastResetCommand: String? {
        defaults.string(forKey: lastResetCommandKey)
    }

    func clearResetAttempt() {
        defaults.removeObject(forKey: attemptedInstallationTokenKey)
        defaults.removeObject(forKey: lastResetCommandKey)
    }
}
