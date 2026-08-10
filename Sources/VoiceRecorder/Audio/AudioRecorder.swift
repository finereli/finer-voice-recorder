import Foundation
import AVFoundation
import CoreAudio

/// Records from a chosen Core Audio input device to a compressed AAC `.m4a`
/// file using AVAudioEngine, publishing a live input level and a rolling
/// waveform for the UI.
final class AudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var level: Float = 0        // 0...1, smoothed
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var liveSamples: [Float] = [] // rolling meter history

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var startDate: Date?
    private var timer: Timer?
    private var lastSampleStamp: TimeInterval = 0
    // Engine start/stop and file finalization block for tens of ms, so they
    // run here instead of on the main thread.
    private let audioQueue = DispatchQueue(label: "com.finereli.voicerecorder.audio")

    /// Begin recording to `url` from `deviceID`. UI state flips immediately;
    /// the audio engine spins up off the main thread and reports back.
    func start(deviceID: AudioDeviceID, to url: URL, completion: @escaping (Error?) -> Void) {
        guard !isRecording else { completion(nil); return }

        // Instant UI feedback.
        liveSamples = []
        level = 0
        lastSampleStamp = 0
        startDate = Date()
        isRecording = true
        startTimer()

        audioQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configureAndStart(deviceID: deviceID, url: url)
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async {
                    self.stopTimer()
                    self.isRecording = false
                    self.startDate = nil
                    self.file = nil
                    completion(error)
                }
            }
        }
    }

    /// Heavy setup, run on `audioQueue`.
    private func configureAndStart(deviceID: AudioDeviceID, url: URL) throws {
        // Point the engine's input at the selected hardware device.
        if deviceID != 0, let unit = engine.inputNode.audioUnit {
            var dev = deviceID
            let err = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &dev,
                UInt32(MemoryLayout<AudioDeviceID>.size))
            if err != noErr {
                throw NSError(domain: "VoiceRecorder", code: Int(err), userInfo: [
                    NSLocalizedDescriptionKey: "Couldn't select input device (error \(err))."])
            }
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "VoiceRecorder", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "The selected input device isn't providing audio. Check microphone permission and that the device is connected."])
        }

        // Write compressed AAC into an .m4a, matching the tap's sample rate and
        // channel count so buffers pass straight through the encoder.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings)

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    /// Stop recording. UI flips immediately; the engine tears down off the
    /// main thread and reports the final duration back.
    func stop(completion: @escaping (TimeInterval) -> Void) {
        guard isRecording else { completion(elapsed); return }
        let duration = startDate.map { Date().timeIntervalSince($0) } ?? elapsed

        // Instant UI feedback.
        isRecording = false
        level = 0
        stopTimer()
        startDate = nil

        audioQueue.async { [weak self] in
            guard let self else { DispatchQueue.main.async { completion(duration) }; return }
            self.engine.inputNode.removeTap(onBus: 0)
            self.engine.stop()
            self.file = nil   // finalize and flush the .m4a
            DispatchQueue.main.async { completion(duration) }
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let start = self.startDate else { return }
            self.elapsed = Date().timeIntervalSince(start)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Buffer processing

    private func process(_ buffer: AVAudioPCMBuffer) {
        // Persist to disk.
        if let file {
            try? file.write(from: buffer)
        }

        // Compute RMS level for the meter.
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var sum: Float = 0
        for i in 0..<count {
            let s = channel[i]
            sum += s * s
        }
        let rms = sqrt(sum / Float(count))
        // Map RMS (roughly -60..0 dBFS) into a 0...1 scale for display.
        let db = 20 * log10(max(rms, 1e-7))
        let normalized = max(0, min(1, (db + 60) / 60))

        let stamp = startDate.map { Date().timeIntervalSince($0) } ?? 0
        DispatchQueue.main.async {
            // Smooth the meter a little.
            self.level = self.level * 0.6 + normalized * 0.4
            // Append to the rolling waveform ~20x/sec.
            if stamp - self.lastSampleStamp >= 0.05 {
                self.lastSampleStamp = stamp
                self.liveSamples.append(normalized)
                if self.liveSamples.count > 3000 {
                    self.liveSamples.removeFirst(self.liveSamples.count - 3000)
                }
            }
        }
    }
}
