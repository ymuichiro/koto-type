import SwiftUI

enum IndicatorState {
    case recording
    case processing
}

struct RecordingIndicatorView: View {
    let state: IndicatorState
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.8))
                .frame(width: 60, height: 40)
            
            WaveformView(color: barColor)
        }
        .frame(width: 70, height: 50)
    }
    
    private var barColor: Color {
        switch state {
        case .recording:
            return .white
        case .processing:
            return .blue
        }
    }
}

struct WaveformView: View {
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<6) { i in
                WaveformBar(
                    offset: Double(i) * 0.3,
                    color: color
                )
                .frame(width: 2, height: 24)
            }
        }
        .frame(width: 30, height: 30)
    }
}

struct WaveformBar: View {
    let offset: Double
    let color: Color
    
    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: 2, height: height)
    }
    
    private var height: CGFloat {
        let baseHeight: CGFloat = 10
        let amplitude: CGFloat = 4
        return baseHeight + abs(amplitude * sin(offset))
    }
}
