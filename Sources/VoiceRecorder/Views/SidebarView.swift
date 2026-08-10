import SwiftUI

/// Left column: search, the recording list, and the big record button.
struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { model.selectedID },
                set: { id in
                    if let id, let r = model.store.recordings.first(where: { $0.id == id }) {
                        model.select(r)
                    }
                }
            )) {
                Section("All Recordings") {
                    ForEach(model.filteredRecordings) { recording in
                        RecordingRow(recording: recording)
                            .tag(recording.id)
                            .contextMenu {
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
            }
            .searchable(text: $model.searchText, placement: .sidebar,
                        prompt: "Titles, Transcripts")

            Divider()
            RecordButton()
                .padding(.vertical, 14)
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
                    .frame(width: 58, height: 58)
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
        }
        .buttonStyle(.plain)
        .help(model.isRecording ? "Stop recording" : "Start recording")
    }
}
