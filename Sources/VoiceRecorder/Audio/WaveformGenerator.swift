import Foundation
import AVFoundation

/// Reads an audio file and downsamples it into a fixed number of amplitude
/// bins for drawing a static waveform. Runs off the main thread.
enum WaveformGenerator {
    /// Generate one bar every `1/barsPerSecond` seconds so a long clip yields
    /// proportionally more bars — a constant zoom, matching the live recorder.
    static func generate(for url: URL, barsPerSecond: Double = 20,
                         completion: @escaping ([Float]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let samples = compute(url: url, barsPerSecond: barsPerSecond)
            DispatchQueue.main.async { completion(samples) }
        }
    }

    private static func compute(url: URL, barsPerSecond: Double) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let format = file.processingFormat
        let total = AVAudioFrameCount(file.length)
        guard total > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total)
        else { return [] }

        let duration = Double(total) / format.sampleRate
        let buckets = max(1, min(60_000, Int(duration * barsPerSecond)))

        do {
            try file.read(into: buffer)
        } catch {
            return []
        }

        guard let channelData = buffer.floatChannelData else { return [] }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return [] }

        let channels = Int(format.channelCount)
        let bucketSize = max(1, frames / buckets)
        var result: [Float] = []
        result.reserveCapacity(buckets)

        var index = 0
        while index < frames {
            let end = min(index + bucketSize, frames)
            var peak: Float = 0
            var i = index
            while i < end {
                var sample: Float = 0
                for c in 0..<channels {
                    sample += abs(channelData[c][i])
                }
                sample /= Float(channels)
                if sample > peak { peak = sample }
                i += 1
            }
            result.append(peak)
            index += bucketSize
        }

        // Normalize to 0...1 against the loudest bin.
        let maxPeak = result.max() ?? 1
        if maxPeak > 0 {
            result = result.map { min(1, $0 / maxPeak) }
        }
        return result
    }
}
