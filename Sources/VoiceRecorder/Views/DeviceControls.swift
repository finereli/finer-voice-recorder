import SwiftUI

/// Input-device selector plus live level meter, sized to sit under the record
/// button in the sidebar. The device is chosen from a compact popup menu
/// (QuickTime-style) rather than a boxed dropdown.
struct DeviceControls: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            deviceMenu
            LevelMeter(level: model.recorder.level, active: model.isRecording)
                .frame(height: 6)
        }
        .padding(.horizontal, 16)
    }

    private var deviceMenu: some View {
        Menu {
            if model.devices.devices.isEmpty {
                Text("No input devices found")
            }
            ForEach(model.devices.devices) { device in
                Button {
                    model.devices.selectedDeviceID = device.id
                } label: {
                    if device.id == model.devices.selectedDeviceID {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
            Divider()
            Button {
                model.devices.refresh()
            } label: {
                Label("Rescan Devices", systemImage: "arrow.clockwise")
            }
        } label: {
            ZStack {
                // Name stays centered; the icons are pinned to the edges so
                // they don't shift it.
                Text(model.devices.selectedDevice?.name ?? "No Input")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 22)
                HStack {
                    Image(systemName: "mic.fill").font(.system(size: 12))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                }
            }
            .foregroundStyle(model.isRecording ? .secondary : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        // Force the menu to fill the sidebar width so the label can center;
        // a borderless menu otherwise hugs its content on the left.
        .frame(maxWidth: .infinity)
        .noFocusRing()
        .pointingHandCursor()
        .disabled(model.isRecording)
        .help(model.isRecording
              ? "Stop recording to change the input device"
              : "Choose which microphone to record from")
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
