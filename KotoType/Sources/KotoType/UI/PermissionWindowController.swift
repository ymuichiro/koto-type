import AppKit
import SwiftUI

final class PermissionWindowController: NSWindowController {
    
    convenience init() {
        let content = PermissionView()
        let hostingController = NSHostingController(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 550),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Accessibility Permission Setup"
        window.contentViewController = hostingController
        self.init(window: window)
    }
}

struct PermissionView: View {
    @State private var permissionStatus: PermissionChecker.PermissionStatus = .unknown
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            Text("Accessibility permission is required")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("To use this application, the following permissions are required:")
                    .font(.body)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Accessibility - Simulate keyboard input")
                    }
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Microphone - Audio recording")
                    }
                }
                .font(.subheadline)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Setup steps:")
                    .font(.headline)

                Text("1. Click the button below to open System Settings")
                Text("2. Open [Privacy & Security] > [Accessibility]")
                Text("3. Enable KotoType (or Terminal)")
                Text("4. Click [Check Permission]")
                Text("5. Click [Restart App]")
            }
            .font(.subheadline)
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            
            Button(action: openSystemSettings) {
                HStack {
                    Image(systemName: "gear")
                    Text("Open System Settings")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Button(action: checkPermission) {
                Text("Check Permission")
            }
            
            if permissionStatus != .unknown {
                if permissionStatus == .granted {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Permission granted!")
                                .foregroundColor(.green)
                                .fontWeight(.medium)
                        }
                        
                        Button(action: restartApp) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Restart App")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Permission has not been granted yet. Allow the app in System Settings and restart.")
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(32)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
    }
    
    private func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    
    private func checkPermission() {
        permissionStatus = PermissionChecker.shared.checkAccessibilityPermission()
    }
    
    private func restartApp() {
        guard AppRelauncher.relaunchCurrentApp() else { return }
        NSApp.terminate(nil)
    }
}
