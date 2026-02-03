import AppKit
import SwiftUI

final class PermissionWindowController: NSWindowController {
    
    convenience init() {
        let content = PermissionView()
        let hostingController = NSHostingController(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
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
    @State private var hasPermission = false
    
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
                Text("3. ターミナル（または使用しているターミナルアプリ）にチェックを入れる")
                Text("4. アプリケーションを再起動する")
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
            
            if hasPermission {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("権限が付与されました！アプリを再起動してください。")
                        .foregroundColor(.green)
                }
            }
        }
        .padding(32)
        .frame(width: 600, height: 450)
    }
    
    private func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    
    private func checkPermission() {
        hasPermission = PermissionChecker.shared.checkAccessibilityPermission() == .granted
    }
}
