import SwiftUI

enum IndicatorState {
    case recording
    case processing
    case completed
    case attention
}

struct RecordingIndicatorView: View {
    let state: IndicatorState
    let attentionMessage: String?
    let recordingLevel: CGFloat
    private static let outerPadding: CGFloat = 6
    private static let contentClipCornerRadius: CGFloat = 13

    init(state: IndicatorState, attentionMessage: String? = nil, recordingLevel: CGFloat = 0) {
        self.state = state
        self.attentionMessage = attentionMessage
        self.recordingLevel = max(0, min(recordingLevel, 1))
    }

    private static func frameSize(for state: IndicatorState, attentionMessage: String?) -> CGSize {
        let hasAttentionMessage = state == .attention && !(attentionMessage?.isEmpty ?? true)
        if hasAttentionMessage {
            return CGSize(width: 260, height: 68)
        }

        let width: CGFloat = (state == .recording || state == .processing) ? 368 : 124
        return CGSize(width: width, height: 68)
    }

    static func preferredContentSize(for state: IndicatorState, attentionMessage: String?) -> CGSize {
        let frameSize = Self.frameSize(for: state, attentionMessage: attentionMessage)
        let padding = Self.outerPadding * 2
        return CGSize(width: frameSize.width + padding, height: frameSize.height + padding)
    }

    private var preferredFrameSize: CGSize {
        Self.frameSize(for: state, attentionMessage: attentionMessage)
    }

    var body: some View {
        ZStack {
            IndicatorBackground(state: state)

            stateContent
                .frame(width: preferredFrameSize.width, height: preferredFrameSize.height)
                .clipShape(RoundedRectangle(cornerRadius: Self.contentClipCornerRadius, style: .continuous))
        }
        .frame(width: preferredFrameSize.width, height: preferredFrameSize.height)
        .padding(Self.outerPadding)
        .animation(.easeInOut(duration: 0.2), value: state)
        .animation(.easeInOut(duration: 0.2), value: attentionMessage ?? "")
    }

    @ViewBuilder
    private var stateContent: some View {
        switch state {
        case .recording:
            RecordingContent(level: recordingLevel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        case .processing:
            ProcessingContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        case .completed:
            CompletedContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .attention:
            AttentionContent(message: attentionMessage)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct IndicatorBackground: View {
    let state: IndicatorState

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.85),
                        Color.black.opacity(0.72),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.03),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(1)
            )
            .shadow(color: accentColor.opacity(0.12), radius: 8, x: 0, y: 2)
            .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
    }

    private var accentColor: Color {
        switch state {
        case .recording:
            return .red
        case .processing:
            return .blue
        case .completed:
            return .green
        case .attention:
            return .orange
        }
    }
}

private struct RecordingContent: View {
    let level: CGFloat
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.92))
                    .frame(width: 12, height: 12)

                Circle()
                    .stroke(Color.red.opacity(0.45), lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .scaleEffect(pulse ? 1.28 : 0.86)
                    .opacity(pulse ? 0.08 : 0.7)
            }

            WaveformAnimation(color: .white, level: level)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct WaveformAnimation: View {
    let color: Color
    let level: CGFloat
    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 3
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 23
    private let updateInterval: TimeInterval = 1.0 / 20.0
    @State private var history: [CGFloat] = []
    @State private var timer = Timer.publish(every: 1.0 / 20.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            let barCount = Self.barCount(
                for: proxy.size.width,
                barWidth: barWidth,
                barSpacing: barSpacing
            )
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let sample = sampleValue(at: index, totalCount: barCount)
                    Capsule(style: .continuous)
                        .fill(color.opacity(0.95))
                        .frame(width: barWidth, height: barHeight(for: sample))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .onAppear {
                configureHistory(count: barCount)
                timer = Timer.publish(every: updateInterval, on: .main, in: .common).autoconnect()
            }
            .onChange(of: barCount) { newCount in
                configureHistory(count: newCount)
            }
            .onReceive(timer) { _ in
                appendSample(amplifiedLevel, maxCount: barCount)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26, alignment: .leading)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var amplifiedLevel: CGFloat {
        let clampedLevel = max(0, min(level, 1))
        return min(1, pow(clampedLevel, 0.5) * 1.85)
    }

    private static func barCount(for width: CGFloat, barWidth: CGFloat, barSpacing: CGFloat) -> Int {
        let safeWidth = max(0, width)
        let unit = barWidth + barSpacing
        guard unit > 0 else {
            return 1
        }
        return max(1, Int((safeWidth + barSpacing) / unit))
    }

    private func configureHistory(count: Int) {
        guard count > 0 else {
            history = []
            return
        }
        if history.count > count {
            history = Array(history.suffix(count))
        } else if history.count < count {
            history = Array(repeating: 0, count: count - history.count) + history
        }
    }

    private func appendSample(_ sample: CGFloat, maxCount: Int) {
        guard maxCount > 0 else {
            history = []
            return
        }
        let clamped = max(0, min(sample, 1))
        var updated = history
        updated.append(clamped)
        if updated.count > maxCount {
            updated.removeFirst(updated.count - maxCount)
        }
        history = updated
    }

    private func sampleValue(at index: Int, totalCount: Int) -> CGFloat {
        guard totalCount > 0 else {
            return 0
        }
        guard !history.isEmpty else {
            return 0
        }

        let missingPrefixCount = max(0, totalCount - history.count)
        if index < missingPrefixCount {
            return 0
        }

        let historyIndex = index - missingPrefixCount
        guard history.indices.contains(historyIndex) else {
            return 0
        }
        return history[historyIndex]
    }

    private func barHeight(for sample: CGFloat) -> CGFloat {
        minHeight + ((maxHeight - minHeight) * max(0, min(sample, 1)))
    }
}

private struct ProcessingContent: View {
    @State private var rotating = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.22), lineWidth: 2.5)
                    .frame(width: 20, height: 20)

                Circle()
                    .trim(from: 0.1, to: 0.78)
                    .stroke(
                        AngularGradient(
                            colors: [Color.blue.opacity(0.2), Color.blue.opacity(0.95)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 2.8, lineCap: .round)
                    )
                    .frame(width: 20, height: 20)
                    .rotationEffect(.degrees(rotating ? 360 : 0))
            }

            ProcessingDots()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                rotating = true
            }
        }
    }
}

private struct ProcessingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 18.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = max(0.2, (sin((t * 7.0) + (Double(index) * 1.1)) + 1) / 2)
                    Circle()
                        .fill(Color.blue.opacity(0.95))
                        .frame(width: 4, height: 4)
                        .opacity(phase)
                        .scaleEffect(0.8 + (phase * 0.35))
                }
            }
            .frame(width: 24, height: 12)
        }
    }
}

private struct CompletedContent: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green.opacity(0.9))
                .font(.system(size: 15, weight: .semibold))
            Text("Inserted")
                .foregroundStyle(Color.white.opacity(0.95))
                .font(.system(size: 12, weight: .semibold))
        }
    }
}

private struct AttentionContent: View {
    let message: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange.opacity(0.92))
                .font(.system(size: 14, weight: .semibold))
            Text(message ?? "Check focus")
                .foregroundStyle(Color.white.opacity(0.95))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
    }
}
