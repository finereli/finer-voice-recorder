import Foundation
import Speech
import NaturalLanguage

/// Sentinel language code meaning "detect automatically".
let autoLanguageCode = "auto"

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
    private var autoTasks: [SFSpeechRecognitionTask] = []

    init() {
        loadLanguages()
    }

    /// Human-readable name for a language code, or "Automatic" for the sentinel.
    func name(for code: String) -> String {
        if code == autoLanguageCode { return "Automatic" }
        return availableLanguages.first { $0.id == code }?.name
            ?? Locale(identifier: "en_US").localizedString(forIdentifier: code)
            ?? code
    }

    private func baseCode(_ code: String) -> String {
        String(code.prefix(while: { $0 != "-" && $0 != "_" }))
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
        autoTasks.forEach { $0.cancel() }
        autoTasks = []
        isTranscribing = false
    }

    /// Candidate languages to try when detecting automatically: the preferred
    /// language, the system language, plus Hebrew and English as the two
    /// most-likely spoken languages here. Deduped and capped.
    func autoCandidates(preferred: String) -> [String] {
        var codes: [String] = []
        for c in [preferred, Locale.current.identifier, "he-IL", "en-US"] {
            let match = availableLanguages.first {
                $0.id == c || baseCode($0.id) == baseCode(c)
            }
            if let id = match?.id, !codes.contains(id) { codes.append(id) }
        }
        return Array(codes.prefix(4))
    }

    /// Best-effort automatic language detection: transcribes with each
    /// candidate recognizer, then picks the result whose text is the most
    /// coherent and whose detected language matches the recognizer used.
    /// Delivers `(text, resolvedLanguageCode)`.
    func autoTranscribe(url: URL, candidates: [String],
                        completion: @escaping (Result<(String, String), Error>) -> Void) {
        cancel()
        let usable = candidates.filter {
            guard let r = SFSpeechRecognizer(locale: Locale(identifier: $0)) else { return false }
            return r.isAvailable
        }
        guard !usable.isEmpty else {
            completion(.failure(Self.error("No speech languages are available.")))
            return
        }

        isTranscribing = true
        progressText = "Detecting language…"

        let group = DispatchGroup()
        var scored: [(code: String, text: String, score: Double)] = []
        let lock = NSLock()

        for code in usable {
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: code)) else { continue }
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            group.enter()
            var finished = false
            let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                    let score = self.score(text: text, expected: code,
                                           transcription: result.bestTranscription)
                    lock.lock()
                    if !finished { finished = true; scored.append((code, text, score)); group.leave() }
                    lock.unlock()
                } else if error != nil {
                    lock.lock()
                    if !finished { finished = true; group.leave() }
                    lock.unlock()
                }
            }
            autoTasks.append(task)
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isTranscribing = false
            self.autoTasks = []
            let nonEmpty = scored.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard let best = (nonEmpty.max { $0.score < $1.score }) ?? scored.max(by: { $0.score < $1.score }) else {
                completion(.failure(Self.error("Couldn't transcribe this recording.")))
                return
            }
            completion(.success((best.text, best.code)))
        }
    }

    /// Score how well a transcript fits the language it was produced in:
    /// longer coherent text scores higher, and text whose detected language
    /// matches the recognizer gets a strong bonus.
    private func score(text: String, expected: String,
                       transcription: SFTranscription) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        let lengthScore = min(1.0, Double(words) / 12.0)

        // Average per-segment confidence (populated for server recognition;
        // often 0 on-device, so treated as a bonus rather than the basis).
        let segs = transcription.segments
        let confidence = segs.isEmpty ? 0 : Double(segs.map { Double($0.confidence) }.reduce(0, +)) / Double(segs.count)

        // Does the detected language match the recognizer we used?
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let detected = recognizer.dominantLanguage?.rawValue ?? ""
        let matches = detected == baseCode(expected)

        return (matches ? 2.0 : 0.5) + lengthScore + confidence
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
