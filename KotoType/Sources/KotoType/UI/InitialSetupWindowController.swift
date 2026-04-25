import AppKit
import SwiftUI

final class InitialSetupWindowController: NSWindowController {
    private static let minimumContentSize = NSSize(width: 700, height: 620)
    private static let screenVerticalMargin: CGFloat = 120

    private static func maximumContentHeight(for window: NSWindow) -> CGFloat {
        guard let screen = window.screen ?? NSScreen.main else {
            return minimumContentSize.height
        }
        return max(minimumContentSize.height, screen.visibleFrame.height - screenVerticalMargin)
    }

    private static func applyPreferredContentHeight(_ preferredHeight: CGFloat, to window: NSWindow) {
        let currentContentSize = window.contentRect(forFrameRect: window.frame).size
        let targetHeight = min(
            max(preferredHeight, minimumContentSize.height),
            maximumContentHeight(for: window)
        )
        let targetSize = NSSize(
            width: max(currentContentSize.width, minimumContentSize.width),
            height: targetHeight
        )

        guard abs(currentContentSize.height - targetSize.height) > 1 else {
            return
        }
        window.setContentSize(targetSize)
    }

    convenience init(
        diagnosticsService: InitialSetupDiagnosticsService = InitialSetupDiagnosticsService(),
        ffmpegInstaller: FFmpegInstallerService = FFmpegInstallerService(),
        prepareBackend: @escaping @MainActor () async -> Bool = { true },
        automaticPermissionResetCommand: String? = PermissionResetStateManager.shared.lastResetCommand,
        onComplete: @escaping @MainActor () async -> Void
    ) {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.minimumContentSize.width,
                height: Self.minimumContentSize.height
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let content = InitialSetupView(
            diagnosticsService: diagnosticsService,
            ffmpegInstaller: ffmpegInstaller,
            prepareBackend: prepareBackend,
            automaticPermissionResetCommand: automaticPermissionResetCommand,
            onComplete: onComplete,
            onPreferredContentHeightChange: { [weak window] preferredHeight in
                guard let window else { return }
                Self.applyPreferredContentHeight(preferredHeight, to: window)
            }
        )
        let hostingController = NSHostingController(rootView: content)
        window.center()
        window.title = "Initial Setup"
        window.minSize = Self.minimumContentSize
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }
}

struct InitialSetupView: View {
    private let diagnosticsService: InitialSetupDiagnosticsService
    private let ffmpegInstaller: FFmpegInstallerService
    private let prepareBackend: @MainActor () async -> Bool
    private let automaticPermissionResetCommand: String?
    private let onComplete: @MainActor () async -> Void
    private let onPreferredContentHeightChange: (CGFloat) -> Void
    private let bannerImage: NSImage?

    @State private var report = InitialSetupReport(items: [])
    @State private var isRequestingMicrophone = false
    @State private var isRequestingScreenRecording = false
    @State private var isWaitingForAccessibilityUpdate = false
    @State private var shouldShowAccessibilityRestartHint = false
    @State private var isInstallingFFmpeg = false
    @State private var ffmpegActionMessage: String?
    @State private var ffmpegActionMessageIsError = false
    @State private var isCompletingSetup = false
    @State private var setupCompletionMessage: String?
    @State private var isPreparingInitialBackend = true
    @State private var initialBackendPreparationStarted = false
    @State private var backendPreparationNotice: String?
    @State private var accessibilityRefreshTask: Task<Void, Never>?
    @State private var lastReportedContentHeight: CGFloat = 0

    init(
        diagnosticsService: InitialSetupDiagnosticsService,
        ffmpegInstaller: FFmpegInstallerService = FFmpegInstallerService(),
        prepareBackend: @escaping @MainActor () async -> Bool = { true },
        automaticPermissionResetCommand: String?,
        onComplete: @escaping @MainActor () async -> Void,
        onPreferredContentHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.diagnosticsService = diagnosticsService
        self.ffmpegInstaller = ffmpegInstaller
        self.prepareBackend = prepareBackend
        self.automaticPermissionResetCommand = automaticPermissionResetCommand
        self.onComplete = onComplete
        self.onPreferredContentHeightChange = onPreferredContentHeightChange
        self.bannerImage = Self.loadBannerImage()
        _report = State(initialValue: diagnosticsService.evaluate())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                if isPreparingInitialBackend {
                    initialBackendPreparationSection
                } else {
                    setupContentSection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: InitialSetupContentHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
                }
            )
        }
        .frame(minWidth: 700, minHeight: 620, alignment: .topLeading)
        .onPreferenceChange(InitialSetupContentHeightPreferenceKey.self) { measuredHeight in
            guard measuredHeight.isFinite, measuredHeight > 0 else { return }
            let normalizedHeight = ceil(measuredHeight)
            guard abs(normalizedHeight - lastReportedContentHeight) > 1 else { return }
            lastReportedContentHeight = normalizedHeight
            onPreferredContentHeightChange(normalizedHeight)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshChecks()
        }
        .task {
            await runInitialBackendPreparationIfNeeded()
        }
        .onDisappear {
            accessibilityRefreshTask?.cancel()
            accessibilityRefreshTask = nil
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let bannerImage {
                HStack {
                    Spacer()
                    Image(nsImage: bannerImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 520)
                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("KotoType Initial Setup")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Before you start, confirm required permissions and FFmpeg availability.")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var initialBackendPreparationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preparing transcription backend")
                .font(.headline)
            Text("KotoType is checking GPU support and warming the first transcription model before you reach the permission steps. This keeps the first real dictation and the first Settings open from absorbing that one-time setup cost.")
                .font(.caption)
                .foregroundColor(.secondary)
            ProgressView()
                .controlSize(.regular)
            Text("This can take longer on the very first launch while runtime files and model caches are prepared.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var setupContentSection: some View {
        Group {
            if let backendPreparationNotice {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Backend preparation is still incomplete")
                        .font(.headline)
                    Text(backendPreparationNotice)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }

            if let nextRequiredItem {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Guided Setup")
                        .font(.headline)
                    Text("Next step: \(nextRequiredItem.title)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(guidedDetail(for: nextRequiredItem.id))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 10) {
                        Button(guidedActionTitle(for: nextRequiredItem.id)) {
                            runAction(for: nextRequiredItem.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(nextRequiredItem.id == "ffmpeg" && isInstallingFFmpeg)
                        if nextRequiredItem.id == "ffmpeg", let ffmpegActionMessage {
                            Text(ffmpegActionMessage)
                                .font(.caption)
                                .foregroundColor(ffmpegActionMessageIsError ? .orange : .green)
                        }
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(report.items, id: \.id) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.status == .passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(item.status == .passed ? .green : .red)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.title)
                                    .font(.headline)
                                if item.required {
                                    Text("Required")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            Text(item.detail)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 8)
                    if item.id != report.items.last?.id {
                        Divider()
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            if !failingRequiredItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick fixes")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    ForEach(failingRequiredItems, id: \.id) { item in
                        HStack(alignment: .top) {
                            Text("• \(item.title)")
                                .font(.caption)
                            Spacer()
                            Button(guidedActionTitle(for: item.id)) {
                                runAction(for: item.id)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }

            HStack(spacing: 10) {
                Button("Grant Accessibility") {
                    runAccessibilityFlow()
                }
                Button("Grant Microphone") {
                    runMicrophoneFlow()
                }
                .disabled(isRequestingMicrophone)
                Button("Grant Screen Recording") {
                    runScreenRecordingFlow()
                }
                .disabled(isRequestingScreenRecording)
                Button("Open System Settings") {
                    openAccessibilitySettings()
                }
                Spacer()
                Button("Re-check") {
                    refreshChecks()
                    shouldShowAccessibilityRestartHint = !isAccessibilityGranted
                }
                if !isAccessibilityGranted {
                    Button("Restart App") {
                        restartApp()
                    }
                }
            }

            if isWaitingForAccessibilityUpdate {
                Text("Checking whether accessibility permission changes have taken effect...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if shouldShowAccessibilityRestartHint && !isAccessibilityGranted {
                Text("Accessibility permission changes may take a few seconds to apply or may require a restart. After granting permission, click \"Restart App\".")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if let automaticPermissionResetCommand, !automaticPermissionResetCommand.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Permissions Reset Automatically")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("KotoType detected missing required permissions at launch, cleared all saved privacy decisions for this app, and relaunched. Grant Accessibility, Microphone, and Screen Recording again in System Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(automaticPermissionResetCommand)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("This app does not bundle FFmpeg. KotoType can install it automatically with Homebrew, and if Homebrew is missing it can bootstrap Homebrew first. Backend availability is checked before the permission walkthrough and again after startup or settings changes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if report.canStartApplication {
                VStack(alignment: .leading, spacing: 6) {
                    Text("After setup: next 3 actions")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("1. Click any text field.\n2. Hold hotkey while speaking.\n3. Release hotkey to transcribe.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Show first recording test steps") {
                        showFirstRecordingGuide()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }

            if isCompletingSetup {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView()
                        .controlSize(.regular)
                    Text(
                        setupCompletionMessage
                            ?? "Preparing the transcription backend for your first use..."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }

            HStack {
                Spacer()
                Button("Finish setup and start") {
                    completeSetup()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!report.canStartApplication || isCompletingSetup)
            }
        }
    }

    private var isAccessibilityGranted: Bool {
        report.items.first(where: { $0.id == "accessibility" })?.status == .passed
    }

    private var failingRequiredItems: [InitialSetupCheckItem] {
        report.items.filter { $0.required && $0.status == .failed }
    }

    private var nextRequiredItem: InitialSetupCheckItem? {
        failingRequiredItems.first
    }

    private func refreshChecks() {
        report = diagnosticsService.evaluate()
        if isAccessibilityGranted {
            isWaitingForAccessibilityUpdate = false
            shouldShowAccessibilityRestartHint = false
            accessibilityRefreshTask?.cancel()
            accessibilityRefreshTask = nil
        }
    }

    @MainActor
    private func runInitialBackendPreparationIfNeeded() async {
        guard !initialBackendPreparationStarted else { return }
        initialBackendPreparationStarted = true
        let prepared = await prepareBackend()
        if !prepared {
            backendPreparationNotice = "KotoType could not finish backend preparation before the permission walkthrough, so it will retry later during startup and when Settings-triggered reconfiguration runs."
        }
        isPreparingInitialBackend = false
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startAccessibilityPolling() {
        accessibilityRefreshTask?.cancel()
        shouldShowAccessibilityRestartHint = false
        isWaitingForAccessibilityUpdate = true

        accessibilityRefreshTask = Task { @MainActor in
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                refreshChecks()
                if isAccessibilityGranted {
                    return
                }
            }

            isWaitingForAccessibilityUpdate = false
            shouldShowAccessibilityRestartHint = !isAccessibilityGranted
            accessibilityRefreshTask = nil
        }
    }

    private func restartApp() {
        guard AppRelauncher.relaunchCurrentApp() else { return }
        NSApp.terminate(nil)
    }

    private func installFFmpeg() {
        guard !isInstallingFFmpeg else { return }
        isInstallingFFmpeg = true
        ffmpegActionMessageIsError = false
        ffmpegActionMessage = "Installing FFmpeg automatically..."
        let installer = ffmpegInstaller
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                installer.installFFmpeg()
            }.value

            isInstallingFFmpeg = false
            switch result {
            case let .success(installed):
                ffmpegActionMessageIsError = false
                ffmpegActionMessage = installed.homebrewInstalled
                    ? "Installed Homebrew and FFmpeg. Detected: \(installed.ffmpegPath)"
                    : "Installed FFmpeg. Detected: \(installed.ffmpegPath)"
                refreshChecks()
            case let .failure(error):
                ffmpegActionMessageIsError = true
                ffmpegActionMessage = error.errorDescription ?? "FFmpeg installation failed."
            }
        }
    }

    private func completeSetup() {
        guard report.canStartApplication else { return }
        guard !isCompletingSetup else { return }
        isCompletingSetup = true
        setupCompletionMessage = "Preparing the transcription backend for your first use. This can take a bit longer the first time while models are checked and warmed up."
        Task { @MainActor in
            await onComplete()
            isCompletingSetup = false
        }
    }

    private func runAccessibilityFlow() {
        diagnosticsService.requestAccessibilityPermission()
        openAccessibilitySettings()
        startAccessibilityPolling()
    }

    private func runMicrophoneFlow() {
        isRequestingMicrophone = true
        diagnosticsService.requestMicrophonePermission { _ in
            Task { @MainActor in
                isRequestingMicrophone = false
                refreshChecks()
            }
        }
        openMicrophoneSettings()
    }

    private func runScreenRecordingFlow() {
        isRequestingScreenRecording = true
        diagnosticsService.requestScreenRecordingPermission { _ in
            Task { @MainActor in
                isRequestingScreenRecording = false
                refreshChecks()
            }
        }
        openScreenRecordingSettings()
    }

    private func runAction(for itemID: String) {
        switch itemID {
        case "accessibility":
            runAccessibilityFlow()
        case "microphone":
            runMicrophoneFlow()
        case "screenRecording":
            runScreenRecordingFlow()
        case "ffmpeg":
            installFFmpeg()
        default:
            break
        }
    }

    private func guidedActionTitle(for itemID: String) -> String {
        switch itemID {
        case "accessibility":
            return "Grant Accessibility"
        case "microphone":
            return "Grant Microphone"
        case "screenRecording":
            return "Grant Screen Recording"
        case "ffmpeg":
            return isInstallingFFmpeg ? "Installing FFmpeg..." : "Install FFmpeg automatically"
        default:
            return "Open"
        }
    }

    private func guidedDetail(for itemID: String) -> String {
        switch itemID {
        case "accessibility":
            return "Enable KotoType in Accessibility, then come back and Re-check."
        case "microphone":
            return "Allow microphone permission when prompted."
        case "screenRecording":
            return "Enable KotoType in Screen Recording, then return to this window."
        case "ffmpeg":
            return "KotoType will use Homebrew to install FFmpeg, and can bootstrap Homebrew first if needed."
        default:
            return "Complete this check and continue."
        }
    }

    private func showFirstRecordingGuide() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "First recording test"
        alert.informativeText = """
        1. Click a text field in any app.
        2. Hold your hotkey (default: Command+Option) and speak.
        3. Release the hotkey and wait for inserted text.
        """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func loadBannerImage() -> NSImage? {
        AppImageLoader.loadPNG(named: "koto-tyoe_banner_transparent")
    }
}

private struct InitialSetupContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
