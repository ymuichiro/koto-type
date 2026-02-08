import Foundation
@preconcurrency import ApplicationServices
@preconcurrency import AVFoundation

final class PermissionChecker: @unchecked Sendable {
    
    static let shared = PermissionChecker()
    
    private init() {}
    
    enum PermissionStatus {
        case granted
        case denied
        case unknown
    }
    
    func checkAccessibilityPermission() -> PermissionStatus {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options: CFDictionary = [promptKey: false] as CFDictionary
        let status = AXIsProcessTrustedWithOptions(options)
        return status ? .granted : .denied
    }
    
    func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options: CFDictionary = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func checkMicrophonePermission() -> PermissionStatus {
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

    func requestMicrophonePermission(completion: @escaping @Sendable (PermissionStatus) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            let status: PermissionStatus = granted ? .granted : self.checkMicrophonePermission()
            DispatchQueue.main.async {
                completion(status)
            }
        }
    }
}
