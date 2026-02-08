import Foundation

final class InitialSetupStateManager: @unchecked Sendable {
    static let shared = InitialSetupStateManager()

    private let defaults: UserDefaults
    private let completedKey = "initialSetupCompleted"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasCompletedInitialSetup: Bool {
        defaults.bool(forKey: completedKey)
    }

    func markCompleted() {
        defaults.set(true, forKey: completedKey)
    }
}
