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
        window.title = "アクセシビリティ権限の設定"
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
            
            Text("アクセシビリティ権限が必要です")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("このアプリケーションを動作させるには、以下の権限が必要です：")
                    .font(.body)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("アクセシビリティ - キーボード入力のシミュレート")
                    }
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("マイク - 音声録音")
                    }
                }
                .font(.subheadline)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("設定手順：")
                    .font(.headline)

                Text("1. 以下のボタンをクリックしてシステム設定を開く")
                Text("2. [プライバシーとセキュリティ] > [アクセシビリティ] を開く")
                Text("3. STTApp（またはターミナル）にチェックを入れる")
                Text("4. [権限を確認] ボタンをクリックする")
                Text("5. [アプリを再起動] ボタンをクリックする")
            }
            .font(.subheadline)
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            
            Button(action: openSystemSettings) {
                HStack {
                    Image(systemName: "gear")
                    Text("システム設定を開く")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Button(action: checkPermission) {
                Text("権限を確認")
            }
            
            if permissionStatus != .unknown {
                if permissionStatus == .granted {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("権限が付与されました！")
                                .foregroundColor(.green)
                                .fontWeight(.medium)
                        }
                        
                        Button(action: restartApp) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("アプリを再起動")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("権限がまだ付与されていません。システム設定でアプリを許可し、再起動してください。")
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
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().path
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()

        NSApp.terminate(nil)
    }
}
