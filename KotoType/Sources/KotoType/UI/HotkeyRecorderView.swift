import SwiftUI

struct HotkeyRecorderView: NSViewRepresentable {
    var initialConfig: HotkeyConfiguration
    var onChange: (HotkeyConfiguration) -> Void

    func makeNSView(context: Context) -> HotkeyRecorder {
        HotkeyRecorder(initialConfig: initialConfig, onChange: onChange)
    }

    func updateNSView(_ nsView: HotkeyRecorder, context: Context) {
        if nsView.currentConfig != initialConfig {
            nsView.setConfig(initialConfig)
        }
    }
}
