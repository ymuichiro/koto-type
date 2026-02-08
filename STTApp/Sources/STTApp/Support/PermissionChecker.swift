import Foundation
@preconcurrency import ApplicationServices

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
}
