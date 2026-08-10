import Foundation
import AppKit

/// Owns the on-disk recordings directory and the manifest that indexes them.
/// Files live in ~/Library/Application Support/VoiceRecorder/ next to a
/// `recordings.json` manifest.
final class RecordingStore: ObservableObject {
    @Published private(set) var recordings: [Recording] = []

    let directory: URL
    private let manifestURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        directory = base.appendingPathComponent("VoiceRecorder", isDirectory: true)
        manifestURL = directory.appendingPathComponent("recordings.json")
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        load()
    }

    func fileURL(for recording: Recording) -> URL {
        directory.appendingPathComponent(recording.fileName)
    }

    /// A fresh, unique .m4a URL for a new recording.
    func newRecordingURL() -> (fileName: String, url: URL) {
        let name = "\(UUID().uuidString).m4a"
        return (name, directory.appendingPathComponent(name))
    }

    /// A default title like "New Recording", "New Recording 2", ...
    func nextDefaultTitle(base: String = "New Recording") -> String {
        let existing = Set(recordings.map { $0.title })
        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    func add(_ recording: Recording) {
        recordings.insert(recording, at: 0)
        save()
    }

    func update(_ recording: Recording) {
        guard let idx = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        recordings[idx] = recording
        save()
    }

    func delete(_ recording: Recording) {
        try? FileManager.default.removeItem(at: fileURL(for: recording))
        recordings.removeAll { $0.id == recording.id }
        save()
    }

    func toggleFavorite(_ recording: Recording) {
        var r = recording
        r.isFavorite.toggle()
        update(r)
    }

    // MARK: - Persistence

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(recordings)
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            NSLog("Failed to save manifest: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Recording].self, from: data) {
            // Drop any entries whose audio file went missing.
            recordings = decoded.filter {
                FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.fileName).path)
            }
        }
    }
}
