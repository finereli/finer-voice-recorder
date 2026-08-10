import Foundation
import AppKit
import AVFoundation
import Combine

/// Top-level coordinator wiring the store, recorder, player, transcriber and
/// device manager together, and holding UI selection state.
@MainActor
final class AppModel: ObservableObject {
    let store = RecordingStore()
    let devices = AudioDeviceManager()
    let recorder = AudioRecorder()
    let player = AudioPlayer()
    let transcriber = Transcriber()

    @Published var selectedID: Recording.ID?
    @Published var searchText: String = ""
    @Published var errorMessage: String?

    /// The language most recently chosen, remembered for new transcriptions.
    @Published var preferredLanguage: String = "he-IL"

    private var pendingURL: URL?
    private var pendingFileName: String?
    private var cancellables = Set<AnyCancellable>()

    init() {
        transcriber.requestAuthorization()
        // Ask for the microphone up front so macOS shows its permission prompt
        // rather than silently handing us a muted input stream.
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        preferredLanguage = transcriber.defaultLanguageCode

        // Re-publish when any owned sub-object changes so views observing the
        // AppModel stay in sync with the recorder, player, devices, etc.
        for child in [store.objectWillChange, devices.objectWillChange,
                      recorder.objectWillChange, player.objectWillChange,
                      transcriber.objectWillChange] {
            child.sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    var selected: Recording? {
        guard let selectedID else { return nil }
        return store.recordings.first { $0.id == selectedID }
    }

    var filteredRecordings: [Recording] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.recordings }
        return store.recordings.filter {
            $0.title.lowercased().contains(q) ||
            ($0.transcript?.lowercased().contains(q) ?? false)
        }
    }

    // MARK: - Recording

    var isRecording: Bool { recorder.isRecording }

    func toggleRecording() {
        recorder.isRecording ? finishRecording() : startRecording()
    }

    private func startRecording() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            errorMessage = "Microphone access is off. Enable it in System Settings ▸ Privacy & Security ▸ Microphone, then try again."
            return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.startRecording() }
                    else { self?.errorMessage = "Microphone access was denied." }
                }
            }
            return
        default:
            break
        }

        player.stop()
        let (fileName, url) = store.newRecordingURL()
        pendingURL = url
        pendingFileName = fileName
        do {
            try recorder.start(deviceID: devices.selectedDeviceID, to: url)
        } catch {
            errorMessage = error.localizedDescription
            pendingURL = nil
            pendingFileName = nil
        }
    }

    private func finishRecording() {
        let duration = recorder.stop()
        guard let url = pendingURL, let fileName = pendingFileName else { return }
        pendingURL = nil
        pendingFileName = nil

        // Discard empty/too-short recordings.
        guard duration >= 0.4 else {
            try? FileManager.default.removeItem(at: url)
            return
        }

        let title = store.nextDefaultTitle()
        let recording = Recording(title: title, fileName: fileName,
                                  duration: duration, languageCode: preferredLanguage)
        store.add(recording)
        selectedID = recording.id
        player.load(url)

        // Kick off transcription automatically.
        transcribe(recording)
    }

    // MARK: - Selection & playback

    func select(_ recording: Recording) {
        guard recording.id != selectedID else { return }
        selectedID = recording.id
        player.load(store.fileURL(for: recording))
    }

    // MARK: - Transcription

    func transcribe(_ recording: Recording) {
        let lang = recording.languageCode ?? preferredLanguage
        preferredLanguage = lang
        let url = store.fileURL(for: recording)
        transcriber.transcribe(url: url, languageCode: lang, partial: { [weak self] text in
            guard let self, var r = self.store.recordings.first(where: { $0.id == recording.id })
            else { return }
            r.transcript = text
            self.store.update(r)
        }, completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let text):
                if var r = self.store.recordings.first(where: { $0.id == recording.id }) {
                    r.transcript = text
                    r.languageCode = lang
                    self.store.update(r)
                }
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        })
    }

    /// Re-transcribe in a different language.
    func retranscribe(_ recording: Recording, language: String) {
        guard var r = store.recordings.first(where: { $0.id == recording.id }) else { return }
        r.languageCode = language
        r.transcript = nil
        store.update(r)
        preferredLanguage = language
        transcribe(r)
    }

    // MARK: - Editing

    func rename(_ recording: Recording, to title: String) {
        guard var r = store.recordings.first(where: { $0.id == recording.id }) else { return }
        r.title = title.isEmpty ? r.title : title
        store.update(r)
    }

    func toggleFavorite(_ recording: Recording) {
        store.toggleFavorite(recording)
    }

    func delete(_ recording: Recording) {
        if recording.id == selectedID {
            player.stop()
            selectedID = nil
        }
        store.delete(recording)
    }

    // MARK: - Export

    func revealInFinder(_ recording: Recording) {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL(for: recording)])
    }

    func export(_ recording: Recording) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(safeName(recording.title)).m4a"
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard let self, response == .OK, let dest = panel.url else { return }
            let src = self.store.fileURL(for: recording)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: src, to: dest)
            } catch {
                self.errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    func exportTranscript(_ recording: Recording) {
        guard let transcript = recording.transcript, !transcript.isEmpty else {
            errorMessage = "This recording has no transcript yet."
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(safeName(recording.title)).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let dest = panel.url else { return }
            do {
                try transcript.data(using: .utf8)?.write(to: dest)
            } catch {
                self?.errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func safeName(_ s: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return s.components(separatedBy: invalid).joined(separator: "-")
    }
}
