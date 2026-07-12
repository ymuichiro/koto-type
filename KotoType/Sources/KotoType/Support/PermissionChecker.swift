import Foundation
@preconcurrency import ApplicationServices
@preconcurrency import AVFoundation

enum PermissionChecker {
    enum PermissionStatus {
        case granted
        case denied
        case unknown
    }
    
    static func checkAccessibilityPermission() -> PermissionStatus {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options: CFDictionary = [promptKey: false] as CFDictionary
        let status = AXIsProcessTrustedWithOptions(options)
        return status ? .granted : .denied
    }
    
    static func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options: CFDictionary = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func checkMicrophonePermission() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    static func requestMicrophonePermission(completion: @escaping @Sendable (PermissionStatus) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            let status: PermissionStatus = granted ? .granted : checkMicrophonePermission()
            DispatchQueue.main.async {
                completion(status)
            }
        }
    }

    static func checkScreenRecordingPermission() -> PermissionStatus {
        guard #available(macOS 10.15, *) else {
            return .granted
        }
        return CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    static func requestScreenRecordingPermission(completion: @escaping @Sendable (PermissionStatus) -> Void) {
        guard #available(macOS 10.15, *) else {
            completion(.granted)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let granted = CGRequestScreenCaptureAccess()
            let status: PermissionStatus = granted && CGPreflightScreenCaptureAccess()
                ? .granted
                : checkScreenRecordingPermission()
            DispatchQueue.main.async {
                completion(status)
            }
        }
    }
}
