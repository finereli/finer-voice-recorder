import SwiftUI

/// Always-visible input-device selector with a live level meter. This spans
/// the full width at the top of the window so the recording source is never
/// more than a glance away.
struct DeviceBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 13, weight: .semibold))

            Text("Input")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { model.devices.selectedDeviceID },
                set: { model.devices.selectedDeviceID = $0 })) {
                ForEach(model.devices.devices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 320)
            .disabled(model.isRecording)
            .help(model.isRecording
                  ? "Stop recording to change the input device"
                  : "Choose which microphone to record from")

            Button {
                model.devices.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Rescan for input devices")

            Spacer(minLength: 16)

            LevelMeter(level: model.recorder.level, active: model.isRecording)
                .frame(width: 160, height: 10)

            if model.isRecording {
                Text("REC")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// A segmented horizontal level meter (green → yellow → red).
struct LevelMeter: View {
    var level: Float          // 0...1
    var active: Bool
    private let segments = 20

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let w = (geo.size.width - gap * CGFloat(segments - 1)) / CGFloat(segments)
            let lit = Int((Float(segments) * level).rounded())
            HStack(spacing: gap) {
                ForEach(0..<segments, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color(for: i, lit: lit))
                        .frame(width: w)
                }
            }
        }
    }

    private func color(for index: Int, lit: Int) -> Color {
        guard active, index < lit else { return Color.secondary.opacity(0.18) }
        let frac = Double(index) / Double(segments)
        if frac > 0.85 { return .red }
        if frac > 0.65 { return .yellow }
        return .green
    }
}
