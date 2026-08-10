import SwiftUI

/// Left column: search, the recording list, the big record button, and the
/// input-device selector with its level meter.
struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var listFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $model.selection) {
                Section("All Recordings") {
                    ForEach(model.filteredRecordings) { recording in
                        RecordingRow(recording: recording)
                            .tag(recording.id)
                            .contextMenu { contextMenu(for: recording) }
                    }
                }
            }
            .focused($listFocused)
            .searchable(text: $model.searchText, placement: .sidebar,
                        prompt: "Titles, Transcripts")

            Divider()

            VStack(spacing: 12) {
                RecordButton()
                DeviceControls()
            }
            .padding(.vertical, 14)
        }
        .onAppear {
            // Default keyboard focus to the list so controls don't grab a ring.
            DispatchQueue.main.async { listFocused = true }
        }
    }

    /// Right-click menu. Acts on the whole selection when the clicked row is
    /// part of a multi-selection, otherwise on just that row.
    @ViewBuilder
    private func contextMenu(for recording: Recording) -> some View {
        let targets = model.contextTargets(for: recording)
        if targets.count > 1 {
            Button("Export \(targets.count) to Folder…") { model.exportToFolder(targets) }
            Button("Reveal in Finder") { model.reveal(targets) }
            Divider()
            Button("Favorite") { model.setFavorite(targets, true) }
            Button("Unfavorite") { model.setFavorite(targets, false) }
            Divider()
            Button("Delete \(targets.count)", role: .destructive) { model.deleteMany(targets) }
        } else {
            Button("Export Audio…") { model.export(recording) }
            Button("Export Transcript…") { model.exportTranscript(recording) }
            Button("Reveal in Finder") { model.revealInFinder(recording) }
            Divider()
            Button(recording.isFavorite ? "Unfavorite" : "Favorite") {
                model.toggleFavorite(recording)
            }
            Divider()
            Button("Delete", role: .destructive) { model.delete(recording) }
        }
    }
}

struct RecordingRow: View {
    @EnvironmentObject var model: AppModel
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(recording.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if recording.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
            }
            HStack(spacing: 6) {
                Text(Format.time(recording.createdAt))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if recording.transcript?.isEmpty == false {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Format.duration(recording.duration))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}

/// The red circular record / stop button, Voice-Memos style.
struct RecordButton: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Button {
            model.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 3)
                if model.isRecording {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.red)
                        .frame(width: 24, height: 24)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 46, height: 46)
                }
            }
            .frame(width: 58, height: 58)
            // Make the whole circle clickable, not just the stroke and shape.
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(model.isRecording ? "Stop recording" : "Start recording")
    }
}
