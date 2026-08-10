import SwiftUI

/// How the waveform scrolls relative to its content when the content is wider
/// than the view.
enum WaveformFollow {
    case none        // left-aligned, no scrolling
    case trailing    // pin the newest sample to the right edge (recording)
    case playhead    // keep the playhead centered (playback)
}

/// Draws a bar waveform at a *constant zoom* (fixed pixels per bar) and scrolls
/// horizontally rather than squeezing every sample into the window. Supports
/// click/drag to seek.
struct WaveformView: View {
    var samples: [Float]
    var progress: Double = 0           // 0...1 playhead position
    var pixelsPerBar: CGFloat = 4      // constant zoom: bar + gap
    var accent: Color = .accentColor
    var follow: WaveformFollow = .none
    var onSeek: ((Double) -> Void)? = nil

    private var spacing: CGFloat { 1.5 }
    private var barWidth: CGFloat { max(1, pixelsPerBar - spacing) }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { context, canvasSize in
                draw(in: &context, size: canvasSize)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let onSeek else { return }
                        let frac = fraction(atX: value.location.x, viewWidth: size.width)
                        onSeek(max(0, min(1, frac)))
                    }
            )
        }
    }

    // MARK: - Geometry

    private func contentWidth() -> CGFloat {
        CGFloat(samples.count) * pixelsPerBar
    }

    /// Horizontal offset applied to the content so the right region is visible.
    private func offsetX(viewWidth: CGFloat) -> CGFloat {
        let content = contentWidth()
        guard content > viewWidth else { return 0 }
        switch follow {
        case .none:
            return 0
        case .trailing:
            return viewWidth - content
        case .playhead:
            let playX = CGFloat(progress) * content
            let desired = viewWidth / 2 - playX
            // Don't scroll past either end.
            return min(0, max(viewWidth - content, desired))
        }
    }

    private func fraction(atX x: CGFloat, viewWidth: CGFloat) -> Double {
        let content = contentWidth()
        guard content > 0 else { return 0 }
        let contentX = x - offsetX(viewWidth: viewWidth)
        return Double(contentX / content)
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard !samples.isEmpty else { return }
        let offset = offsetX(viewWidth: size.width)
        let midY = size.height / 2
        let content = contentWidth()
        let playX = CGFloat(progress) * content + offset

        for (i, sample) in samples.enumerated() {
            let x = CGFloat(i) * pixelsPerBar + offset
            if x + barWidth < 0 || x > size.width { continue } // cull off-screen
            let h = max(2, CGFloat(sample) * (size.height * 0.9))
            let rect = CGRect(x: x, y: midY - h / 2, width: barWidth, height: h)
            let played = follow == .playhead ? (x <= playX) : true
            let color = played ? accent : accent.opacity(0.35)
            context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
        }

        // Playhead line.
        let lineX: CGFloat?
        switch follow {
        case .playhead: lineX = playX
        case .trailing: lineX = min(size.width, content + offset)
        case .none:     lineX = progress > 0 ? playX : nil
        }
        if let lineX, lineX >= 0, lineX <= size.width {
            var line = Path()
            line.move(to: CGPoint(x: lineX, y: 0))
            line.addLine(to: CGPoint(x: lineX, y: size.height))
            context.stroke(line, with: .color(accent), lineWidth: 1.5)
        }
    }
}
