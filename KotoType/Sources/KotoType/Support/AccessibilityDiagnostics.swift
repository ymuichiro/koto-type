import Foundation
@preconcurrency import ApplicationServices

struct AccessibilityDiagnosticsSnapshot: Codable, Equatable {
    let executablePath: String
    let processName: String
    let bundleIdentifier: String?
    let bundlePath: String
    let resourcePath: String?
    let axIsProcessTrusted: Bool
    let permissionCheckerStatus: String
}

struct InitialSetupDiagnosticsItemSnapshot: Codable, Equatable {
    let id: String
    let title: String
    let detail: String
    let status: String
    let required: Bool
}

struct InitialSetupDiagnosticsSnapshot: Codable, Equatable {
    let canStartApplication: Bool
    let items: [InitialSetupDiagnosticsItemSnapshot]
}

enum AccessibilityDiagnostics {
    static func collect(
        executablePath: String = CommandLine.arguments.first ?? "",
        processName: String = ProcessInfo.processInfo.processName,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        bundlePath: String = Bundle.main.bundlePath,
        resourcePath: String? = Bundle.main.resourcePath,
        axIsProcessTrusted: Bool = AXIsProcessTrusted(),
        permissionStatus: PermissionChecker.PermissionStatus = PermissionChecker.shared.checkAccessibilityPermission()
    ) -> AccessibilityDiagnosticsSnapshot {
        AccessibilityDiagnosticsSnapshot(
            executablePath: executablePath,
            processName: processName,
            bundleIdentifier: bundleIdentifier,
            bundlePath: bundlePath,
            resourcePath: resourcePath,
            axIsProcessTrusted: axIsProcessTrusted,
            permissionCheckerStatus: statusString(permissionStatus)
        )
    }

    static func renderJSON(_ snapshot: AccessibilityDiagnosticsSnapshot) -> String {
        renderCodableJSON(snapshot)
    }

    static func collectInitialSetup(
        report: InitialSetupReport = InitialSetupDiagnosticsService().evaluate()
    ) -> InitialSetupDiagnosticsSnapshot {
        let items = report.items.map { item in
            InitialSetupDiagnosticsItemSnapshot(
                id: item.id,
                title: item.title,
                detail: item.detail,
                status: item.status == .passed ? "passed" : "failed",
                required: item.required
            )
        }

        return InitialSetupDiagnosticsSnapshot(
            canStartApplication: report.canStartApplication,
            items: items
        )
    }

    static func renderJSON(_ snapshot: InitialSetupDiagnosticsSnapshot) -> String {
        renderCodableJSON(snapshot)
    }

    private static func renderCodableJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"failed to encode diagnostics\"}"
        }
        return json
    }

    private static func statusString(_ status: PermissionChecker.PermissionStatus) -> String {
        switch status {
        case .granted:
            return "granted"
        case .denied:
            return "denied"
        case .unknown:
            return "unknown"
        }
    }
}
