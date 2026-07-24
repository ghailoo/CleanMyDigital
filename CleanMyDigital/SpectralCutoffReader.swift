//
//  SpectralCutoffReader.swift
//  CleanMyDigital
//

import AVFoundation
import Foundation

/// The result of one file's spectral-cutoff analysis.
enum SpectralCutoffOutcome: Sendable {
    /// Highest frequency (Hz) with real signal energy.
    case measured(hz: Double)
    /// The file was too short or too quiet to measure meaningfully.
    case inconclusive
    case failed(String)
}

/// Reads a handful of representative samples from an audio file and hands
/// them to `SpectralCutoffAnalyzer`. Decoding and FFTing an entire track
/// for every file in a library would make this expensive to run
/// automatically during a scan, so instead it samples three ~6-second
/// windows from the middle of the track (skipping the first/last 10%,
/// which are often fades or silence) — enough to reliably catch a
/// transcode's frequency ceiling without decoding the whole file.
enum SpectralCutoffReader {
    private static let sampleWindowSeconds = 6.0
    private static let sampleFractions: [Double] = [0.25, 0.5, 0.75]

    static func analyze(url: URL) async throws -> SpectralCutoffOutcome {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = audioFile.length
        let windowFrames = AVAudioFrameCount(sampleWindowSeconds * sampleRate)

        guard totalFrames > 0, windowFrames > 0 else { return .inconclusive }

        var samples: [Float] = []
        for fraction in sampleFractions {
            let startFrame = AVAudioFramePosition(Double(totalFrames) * fraction)
            guard startFrame + AVAudioFramePosition(windowFrames) <= totalFrames,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: windowFrames)
            else { continue }

            audioFile.framePosition = startFrame
            try audioFile.read(into: buffer, frameCount: windowFrames)
            samples.append(contentsOf: monoSamples(from: buffer))
        }

        guard !samples.isEmpty,
              let hz = SpectralCutoffAnalyzer.highestSignificantFrequency(samples: samples, sampleRate: sampleRate)
        else { return .inconclusive }
        return .measured(hz: hz)
    }

    /// Averages every channel down to mono — the cutoff analysis only
    /// cares about frequency content, not stereo image.
    private static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channelCount > 0, frameLength > 0 else { return [] }

        var mono = [Float](repeating: 0, count: frameLength)
        for channel in 0..<channelCount {
            let channelPointer = channelData[channel]
            for frame in 0..<frameLength {
                mono[frame] += channelPointer[frame] / Float(channelCount)
            }
        }
        return mono
    }
}
