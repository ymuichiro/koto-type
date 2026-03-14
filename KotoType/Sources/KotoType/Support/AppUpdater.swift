import AppKit
import Foundation
import Sparkle

@MainActor
final class AppUpdater {
    private var updaterController: SPUStandardUpdaterController?
    private let isUpdaterConfigurationValid: Bool
    private static let automaticChecksDefaultsKey = "SUEnableAutomaticChecks"
    private static let automaticallyUpdateDefaultsKey = "SUAutomaticallyUpdate"

    var isConfigured: Bool {
        isUpdaterConfigurationValid
    }

    init(bundle: Bundle = .main) {
        // Manual update mode:
        // - never auto-check for updates
        // - never auto-install updates
        UserDefaults.standard.set(false, forKey: Self.automaticChecksDefaultsKey)
        UserDefaults.standard.set(false, forKey: Self.automaticallyUpdateDefaultsKey)

        guard let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              !feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Logger.shared.log("Sparkle disabled: SUFeedURL is missing", level: .warning)
            isUpdaterConfigurationValid = false
            return
        }

        guard let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Logger.shared.log("Sparkle disabled: SUPublicEDKey is missing", level: .warning)
            isUpdaterConfigurationValid = false
            return
        }

        guard URL(string: feedURL) != nil else {
            Logger.shared.log("Sparkle disabled: SUFeedURL is invalid (\(feedURL))", level: .warning)
            isUpdaterConfigurationValid = false
            return
        }

        isUpdaterConfigurationValid = true
        Logger.shared.log("Sparkle updater configured (manual check only)", level: .info)
    }

    private func ensureUpdaterController() -> SPUStandardUpdaterController {
        if let updaterController {
            return updaterController
        }

        // Create the updater lazily so no update network activity can occur before
        // the user explicitly requests "Check for Updates".
        let created = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = created
        Logger.shared.log("Sparkle updater initialized for manual check", level: .info)
        return created
    }

    func checkForUpdates() {
        guard isUpdaterConfigurationValid else {
            Logger.shared.log("Update check requested but Sparkle is not configured", level: .warning)
            return
        }
        let updaterController = ensureUpdaterController()
        updaterController.checkForUpdates(nil)
    }
}
