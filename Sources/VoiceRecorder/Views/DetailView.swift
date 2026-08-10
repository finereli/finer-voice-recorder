import SwiftUI

/// Right pane: live recording view, or playback + transcript for the selection.
struct DetailView: View {
    @EnvironmentObject var model: AppModel
    @State private var waveform: [Float] = []
    @State private var editingTitle = false
    @State private var titleDraft = ""

    var body: some View {
        Group {
            if model.isRecording {
                recordingView
            } else if let recording = model.selected {
                playbackView(recording)
            } else {
                emptyView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar { toolbarContent }
        .onChange(of: model.selectedID) { _ in loadWaveform() }
        .onAppear { loadWaveform() }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Select a recording, or press the red button to start")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Recording in progress

    private var recordingView: some View {
        VStack {
            Spacer()
            WaveformView(samples: model.recorder.liveSamples,
                         accent: .red, follow: .trailing)
                .frame(height: 180)
                .padding(.horizontal, 40)
            Spacer()
            Text(Format.timer(model.recorder.elapsed))
                .font(.system(size: 54, weight: .thin, design: .rounded))
                .monospacedDigit()
            Text("Recording from \(model.devices.selectedDevice?.name ?? "input")")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Spacer()
        }
    }

    // MARK: - Playback

    private func playbackView(_ recording: Recording) -> some View {
        VStack(spacing: 0) {
            titleHeader(recording)

            WaveformView(
                samples: waveform,
                progress: progress,
                follow: .playhead,
                onSeek: { frac in model.player.seek(to: frac * model.player.duration) }
            )
            .frame(height: 180)
            .padding(.horizontal, 30)
            .padding(.top, 20)

            timeRow

            Text(Format.timer(model.player.currentTime))
                .font(.system(size: 40, weight: .thin, design: .rounded))
                .monospacedDigit()
                .padding(.vertical, 10)

            transportControls

            Divider().padding(.top, 12)

            TranscriptPanel(recording: recording)
        }
    }

    private func titleHeader(_ recording: Recording) -> some View {
        HStack {
            if editingTitle {
                TextField("Title", text: $titleDraft, onCommit: {
                    model.rename(recording, to: titleDraft)
                    editingTitle = false
                })
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: 360)
            } else {
                Text(recording.title)
                    .font(.system(size: 18, weight: .semibold))
                    .onTapGesture(count: 2) {
                        titleDraft = recording.title
                        editingTitle = true
                    }
            }
            Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.top, 16)
    }

    private var timeRow: some View {
        HStack {
            Text(Format.duration(model.player.currentTime))
            Spacer()
            Text(Format.duration(model.player.duration))
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .padding(.horizontal, 30)
        .padding(.top, 6)
    }

    private var transportControls: some View {
        HStack(spacing: 44) {
            Button { model.player.skip(by: -15) } label: {
                Image(systemName: "gobackward.15").font(.system(size: 26))
            }.buttonStyle(.plain)

            Button { model.player.togglePlay() } label: {
                Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34))
            }.buttonStyle(.plain)

            Button { model.player.skip(by: 15) } label: {
                Image(systemName: "goforward.15").font(.system(size: 26))
            }.buttonStyle(.plain)
        }
        .foregroundStyle(.primary)
    }

    private var progress: Double {
        guard model.player.duration > 0 else { return 0 }
        return model.player.currentTime / model.player.duration
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let recording = model.selected, !model.isRecording {
            ToolbarItemGroup {
                Button { model.export(recording) } label: {
                    Image(systemName: "square.and.arrow.up")
                }.help("Export audio to the filesystem")

                Button { model.toggleFavorite(recording) } label: {
                    Image(systemName: recording.isFavorite ? "heart.fill" : "heart")
                }.help("Favorite")

                Button { model.revealInFinder(recording) } label: {
                    Image(systemName: "folder")
                }.help("Reveal in Finder")

                Button(role: .destructive) { model.delete(recording) } label: {
                    Image(systemName: "trash")
                }.help("Delete")
            }
        }
    }

    // MARK: - Helpers

    private func loadWaveform() {
        waveform = []
        guard let recording = model.selected else { return }
        WaveformGenerator.generate(for: model.store.fileURL(for: recording)) { samples in
            if model.selectedID == recording.id { waveform = samples }
        }
    }
}
