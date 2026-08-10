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

    // The borderless-button menu style measures its label at the label's
    // ideal size instead of proposing the available width, so any
    // `maxWidth: .infinity` inside the label collapses to content width and
    // the name hugs the mic icon. The menu style does honor an EXPLICIT
    // width, though. So: lay out a hidden copy of the label to claim the
    // full-width footprint (and its natural height), then overlay the real
    // Menu whose label is pinned to that width via GeometryReader.
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
            menuLabel
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
        .noFocusRing()
        .pointingHandCursor()
        .disabled(model.isRecording)
        .help(model.isRecording
              ? "Stop recording to change the input device"
              : "Choose which microphone to record from")
    }

    /// The pill: mic icon pinned left, chevron pinned right, name centered.
    /// `.menuStyle(.button)` + `.buttonStyle(.plain)` honors the width (unlike
    /// `.borderlessButton`, which collapses its label), so the name centers.
    private var menuLabel: some View {
        // Core Audio device names can carry stray padding; trim so the
        // centered text is truly centered.
        let name = (model.devices.selectedDevice?.name ?? "No Input")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ZStack {
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity)
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
