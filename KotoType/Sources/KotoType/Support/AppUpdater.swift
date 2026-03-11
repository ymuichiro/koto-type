import AppKit
import Foundation
import Sparkle

@MainActor
final class AppUpdater {
    private let updaterController: SPUStandardUpdaterController?

    var isConfigured: Bool {
        updaterController != nil
    }

    init(bundle: Bundle = .main) {
        guard let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              !feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Logger.shared.log("Sparkle disabled: SUFeedURL is missing", level: .warning)
            updaterController = nil
            return
        }

        guard let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Logger.shared.log("Sparkle disabled: SUPublicEDKey is missing", level: .warning)
            updaterController = nil
            return
        }

        guard URL(string: feedURL) != nil else {
            Logger.shared.log("Sparkle disabled: SUFeedURL is invalid (\(feedURL))", level: .warning)
            updaterController = nil
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        Logger.shared.log("Sparkle updater initialized", level: .info)
    }

    func checkForUpdates() {
        guard let updaterController else {
            Logger.shared.log("Update check requested but Sparkle is not configured", level: .warning)
            return
        }
        updaterController.checkForUpdates(nil)
    }
}
