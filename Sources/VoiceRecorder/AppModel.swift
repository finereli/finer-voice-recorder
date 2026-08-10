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

    /// The set of selected recordings (supports multi-select). Loading the
    /// player is driven off changes here so it stays in sync.
    @Published var selection: Set<Recording.ID> = [] {
        didSet { if selection != oldValue { syncPlayerToSelection() } }
    }
    @Published var searchText: String = ""
    @Published var errorMessage: String?

    /// The language most recently chosen, remembered for new transcriptions.
    /// Defaults to automatic detection.
    @Published var preferredLanguage: String = autoLanguageCode

    private var pendingURL: URL?
    private var pendingFileName: String?
    private var cancellables = Set<AnyCancellable>()

    init() {
        transcriber.requestAuthorization()
        // Ask for the microphone up front so macOS shows its permission prompt
        // rather than silently handing us a muted input stream.
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        // Re-publish when any owned sub-object changes so views observing the
        // AppModel stay in sync with the recorder, player, devices, etc.
        for child in [store.objectWillChange, devices.objectWillChange,
                      recorder.objectWillChange, player.objectWillChange,
                      transcriber.objectWillChange] {
            child.sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    /// The single selected recording, or nil when zero or many are selected.
    var selectedID: Recording.ID? { selection.count == 1 ? selection.first : nil }

    var selected: Recording? {
        guard let selectedID else { return nil }
        return store.recordings.first { $0.id == selectedID }
    }

    /// Selected recordings in list order.
    var selectedRecordings: [Recording] {
        filteredRecordings.filter { selection.contains($0.id) }
    }

    /// Right-click targets: the whole selection when the clicked row is part of
    /// a multi-selection, otherwise just the clicked row.
    func contextTargets(for recording: Recording) -> [Recording] {
        if selection.contains(recording.id) && selection.count > 1 {
            return selectedRecordings
        }
        return [recording]
    }

    private func syncPlayerToSelection() {
        if let recording = selected {
            let url = store.fileURL(for: recording)
            if player.url != url { player.load(url) }
        } else {
            player.stop()
        }
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
        recorder.start(deviceID: devices.selectedDeviceID, to: url) { [weak self] error in
            guard let self, let error else { return }
            self.errorMessage = error.localizedDescription
            if let u = self.pendingURL { try? FileManager.default.removeItem(at: u) }
            self.pendingURL = nil
            self.pendingFileName = nil
        }
    }

    private func finishRecording() {
        recorder.stop { [weak self] duration in
            guard let self else { return }
            guard let url = self.pendingURL, let fileName = self.pendingFileName else { return }
            self.pendingURL = nil
            self.pendingFileName = nil

            // Discard empty/too-short recordings.
            guard duration >= 0.4 else {
                try? FileManager.default.removeItem(at: url)
                return
            }

            let title = self.store.nextDefaultTitle()
            let recording = Recording(title: title, fileName: fileName,
                                      duration: duration, languageCode: self.preferredLanguage)
            self.store.add(recording)
            self.selection = [recording.id]   // loads the player via didSet

            // Kick off transcription automatically.
            self.transcribe(recording)
        }
    }

    // MARK: - Transcription

    func transcribe(_ recording: Recording) {
        let lang = recording.languageCode ?? preferredLanguage
        let url = store.fileURL(for: recording)

        // Automatic detection: try candidate languages and keep the best.
        if lang == autoLanguageCode {
            let candidates = transcriber.autoCandidates(preferred: preferredLanguage)
            transcriber.autoTranscribe(url: url, candidates: candidates) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let (text, code)):
                    if var r = self.store.recordings.first(where: { $0.id == recording.id }) {
                        r.transcript = text
                        r.languageCode = code   // resolved to the detected language
                        self.store.update(r)
                    }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
            return
        }

        preferredLanguage = lang
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

    func setFavorite(_ recordings: [Recording], _ favorite: Bool) {
        for r in recordings where r.isFavorite != favorite {
            var updated = r
            updated.isFavorite = favorite
            store.update(updated)
        }
    }

    func delete(_ recording: Recording) {
        deleteMany([recording])
    }

    func deleteMany(_ recordings: [Recording]) {
        guard !recordings.isEmpty else { return }
        let ids = Set(recordings.map { $0.id })
        let affectsSelection = !selection.isDisjoint(with: ids)
        // Land on a sensible survivor so repeated deletes keep flowing.
        let survivor = affectsSelection ? nextSurvivor(deleting: ids, in: filteredRecordings) : nil

        for r in recordings { store.delete(r) }

        if affectsSelection {
            selection = survivor.map { [$0] } ?? []
        } else {
            selection = selection.subtracting(ids)
        }
    }

    /// After deleting `ids` from `list`, the id to select next: the first
    /// survivor after the deleted block, else the nearest one before it.
    private func nextSurvivor(deleting ids: Set<Recording.ID>, in list: [Recording]) -> Recording.ID? {
        guard let maxIdx = list.lastIndex(where: { ids.contains($0.id) }) else { return nil }
        if maxIdx + 1 < list.count { return list[maxIdx + 1].id }
        guard let minIdx = list.firstIndex(where: { ids.contains($0.id) }), minIdx > 0 else { return nil }
        return list[minIdx - 1].id
    }

    // MARK: - Export

    func revealInFinder(_ recording: Recording) {
        reveal([recording])
    }

    func reveal(_ recordings: [Recording]) {
        NSWorkspace.shared.activateFileViewerSelecting(recordings.map { store.fileURL(for: $0) })
    }

    /// Bulk export: pick one folder, then write each recording's audio (and
    /// transcript, if any) into it.
    func exportToFolder(_ recordings: [Recording]) {
        guard !recordings.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder to export \(recordings.count) recording\(recordings.count == 1 ? "" : "s")."
        panel.begin { [weak self] response in
            guard let self, response == .OK, let dir = panel.url else { return }
            var failed = 0
            for r in recordings {
                let base = self.safeName(r.title)
                let audioDest = self.uniqueURL(in: dir, base: base, ext: "m4a")
                do {
                    try FileManager.default.copyItem(at: self.store.fileURL(for: r), to: audioDest)
                } catch {
                    failed += 1
                }
                if let transcript = r.transcript, !transcript.isEmpty {
                    let txtDest = self.uniqueURL(in: dir, base: base, ext: "txt")
                    try? transcript.data(using: .utf8)?.write(to: txtDest)
                }
            }
            if failed > 0 {
                self.errorMessage = "Couldn't export \(failed) of \(recordings.count) recordings."
            }
        }
    }

    private func uniqueURL(in dir: URL, base: String, ext: String) -> URL {
        var candidate = dir.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
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

    func copyTranscript(_ recording: Recording) {
        guard let transcript = recording.transcript, !transcript.isEmpty else {
            errorMessage = "This recording has no transcript yet."
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)
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
