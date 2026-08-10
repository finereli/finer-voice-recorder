import Foundation
import Speech

/// A language the user can transcribe into.
struct TranscriptionLanguage: Identifiable, Hashable {
    let id: String        // BCP-47 code, e.g. "he-IL"
    let name: String      // localized display name
    var locale: Locale { Locale(identifier: id) }
}

/// Wraps SFSpeechRecognizer for file-based transcription in a chosen language.
/// Prefers on-device recognition when the language supports it (offline, no
/// length limit), otherwise falls back to Apple's server recognition.
final class Transcriber: ObservableObject {
    @Published private(set) var availableLanguages: [TranscriptionLanguage] = []
    @Published private(set) var authorized = false
    @Published private(set) var isTranscribing = false
    @Published var progressText: String = ""

    private var task: SFSpeechRecognitionTask?

    init() {
        loadLanguages()
    }

    /// Curated, sensible ordering: Hebrew and English first, then the rest of
    /// what the system actually supports, alphabetically by display name.
    private func loadLanguages() {
        let supported = SFSpeechRecognizer.supportedLocales()
        let display = Locale(identifier: "en_US")
        var langs = supported.map { loc -> TranscriptionLanguage in
            let code = loc.identifier
            let name = display.localizedString(forIdentifier: code) ?? code
            return TranscriptionLanguage(id: code, name: name)
        }
        langs.sort { a, b in
            func rank(_ l: TranscriptionLanguage) -> Int {
                if l.id.hasPrefix("he") { return 0 }
                if l.id.hasPrefix("en") { return 1 }
                return 2
            }
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return a.name < b.name
        }
        availableLanguages = langs
    }

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.authorized = (status == .authorized)
            }
        }
    }

    var defaultLanguageCode: String {
        // Prefer the system language if it's supported, else Hebrew, else first.
        let current = Locale.current.identifier
        if availableLanguages.contains(where: { $0.id == current }) { return current }
        if let hePrefix = availableLanguages.first(where: { $0.id.hasPrefix("he") }) {
            return hePrefix.id
        }
        if let enPrefix = availableLanguages.first(where: { $0.id.hasPrefix("en") }) {
            return enPrefix.id
        }
        return availableLanguages.first?.id ?? "en-US"
    }

    func cancel() {
        task?.cancel()
        task = nil
        isTranscribing = false
    }

    /// Transcribe `url` in the given language. Delivers partial text via
    /// `partial` (on the main queue) and the final text via `completion`.
    func transcribe(url: URL, languageCode: String,
                    partial: @escaping (String) -> Void,
                    completion: @escaping (Result<String, Error>) -> Void) {
        cancel()

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageCode)) else {
            completion(.failure(Self.error("Language \(languageCode) isn't available on this Mac.")))
            return
        }
        guard recognizer.isAvailable else {
            completion(.failure(Self.error("Speech recognition is currently unavailable. Check your network connection.")))
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        isTranscribing = true
        progressText = ""

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.progressText = text
                    partial(text)
                }
                if result.isFinal {
                    DispatchQueue.main.async {
                        self.isTranscribing = false
                        self.task = nil
                        completion(.success(text))
                    }
                }
            }
            if let error {
                DispatchQueue.main.async {
                    // A cancel surfaces as an error; ignore it.
                    if (error as NSError).code == 203 || !self.isTranscribing {
                        self.isTranscribing = false
                        return
                    }
                    self.isTranscribing = false
                    self.task = nil
                    completion(.failure(error))
                }
            }
        }
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "VoiceRecorder.Transcriber", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
