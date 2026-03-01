import SwiftUI

enum IndicatorState {
    case recording
    case processing
    case completed
    case attention
}

struct RecordingIndicatorView: View {
    let state: IndicatorState
    let progressText: String?
    private static let outerPadding: CGFloat = 6

    init(state: IndicatorState, progressText: String? = nil) {
        self.state = state
        self.progressText = progressText
    }

    private static func frameSize(for state: IndicatorState, progressText: String?) -> CGSize {
        let hasProgress = {
            guard state == .recording || state == .processing else { return false }
            return !(progressText?.isEmpty ?? true)
        }()

        if hasProgress {
            return CGSize(width: 286, height: 70)
        }

        let width: CGFloat = (state == .recording || state == .processing) ? 92 : 124
        return CGSize(width: width, height: 68)
    }

    static func preferredContentSize(for state: IndicatorState, progressText: String?) -> CGSize {
        let frameSize = Self.frameSize(for: state, progressText: progressText)
        let padding = Self.outerPadding * 2
        return CGSize(width: frameSize.width + padding, height: frameSize.height + padding)
    }

    private var preferredFrameSize: CGSize {
        Self.frameSize(for: state, progressText: progressText)
    }

    var body: some View {
        ZStack {
            IndicatorBackground(state: state)

            switch state {
            case .recording:
                RecordingContent(progressText: progressText)
            case .processing:
                ProcessingContent(progressText: progressText)
            case .completed:
                CompletedContent()
            case .attention:
                AttentionContent()
            }
        }
        .frame(width: preferredFrameSize.width, height: preferredFrameSize.height)
        .padding(Self.outerPadding)
        .animation(.easeInOut(duration: 0.2), value: state)
        .animation(.easeInOut(duration: 0.2), value: progressText ?? "")
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
    let progressText: String?
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
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

                WaveformAnimation(color: .white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let progressText, !progressText.isEmpty {
                ProgressTextContent(text: progressText, accentColor: .red)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct WaveformAnimation: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(color.opacity(0.95))
                        .frame(width: 3, height: barHeight(index: index, time: t))
                }
            }
            .frame(width: 36, height: 26)
        }
    }

    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        let base: CGFloat = 8
        let amplitude: CGFloat = 12
        let value = sin((time * 5.2) + (Double(index) * 0.6))
        return base + CGFloat(abs(value)) * amplitude
    }
}

private struct ProcessingContent: View {
    let progressText: String?
    @State private var rotating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
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

            if let progressText, !progressText.isEmpty {
                ProgressTextContent(text: progressText, accentColor: .blue)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                rotating = true
            }
        }
    }
}

private struct ProgressTextContent: View {
    let text: String
    let accentColor: Color

    var body: some View {
        Text(text)
            .foregroundStyle(Color.white.opacity(0.95))
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(accentColor.opacity(0.16))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(accentColor.opacity(0.34), lineWidth: 0.8)
            )
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
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange.opacity(0.92))
                .font(.system(size: 14, weight: .semibold))
            Text("Check focus")
                .foregroundStyle(Color.white.opacity(0.95))
                .font(.system(size: 12, weight: .semibold))
        }
    }
}
