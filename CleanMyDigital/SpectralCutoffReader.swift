//
//  SpectralCutoffReader.swift
//  CleanMyDigital
//

import AVFoundation
import CoreMedia
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
///
/// Decodes via `AVAssetReader` rather than `AVAudioFile` — confirmed
/// empirically that `AVAudioFile` goes through a lower-level Core Audio
/// path that fails under App Sandbox for some files on a network share
/// (a Core Audio permission-flavored error, even with the scanned
/// folder's security-scoped access already active), while the exact same
/// files decode fine via `AVAssetReader`, which rides the same
/// `AVURLAsset` pipeline already used successfully elsewhere in this app
/// for tag and duration reading.
enum SpectralCutoffReader {
    private static let sampleWindowSeconds = 6.0
    private static let sampleFractions: [Double] = [0.25, 0.5, 0.75]

    static func analyze(url: URL) async throws -> SpectralCutoffOutcome {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return .inconclusive
        }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { return .inconclusive }

        var samples: [Float] = []
        var sampleRate: Double?
        for fraction in sampleFractions {
            let start = duration * fraction
            guard start + sampleWindowSeconds <= duration,
                  let (windowSamples, rate) = try readPCMSamples(
                    asset: asset, track: track, start: start, duration: sampleWindowSeconds)
            else { continue }
            samples.append(contentsOf: windowSamples)
            if sampleRate == nil { sampleRate = rate }
        }

        guard !samples.isEmpty, let sampleRate,
              let hz = SpectralCutoffAnalyzer.highestSignificantFrequency(samples: samples, sampleRate: sampleRate)
        else { return .inconclusive }
        return .measured(hz: hz)
    }

    /// Decodes one time window to mono Float32 PCM. Requesting a single
    /// output channel lets `AVAssetReader` do the stereo-to-mono mixdown
    /// itself, and the real sample rate is read back from the delivered
    /// sample buffer's format description rather than assumed.
    private static func readPCMSamples(
        asset: AVURLAsset, track: AVAssetTrack, start: Double, duration: Double
    ) throws -> (samples: [Float], sampleRate: Double)? {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600))

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        guard reader.startReading() else { return nil }

        var samples: [Float] = []
        var sampleRate: Double?
        while let sampleBuffer = output.copyNextSampleBuffer() {
            if sampleRate == nil,
               let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
                sampleRate = asbd.pointee.mSampleRate
            }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = [UInt8](repeating: 0, count: length)
            guard let status = data.withUnsafeMutableBytes({ rawBuffer -> OSStatus? in
                guard let baseAddress = rawBuffer.baseAddress else { return nil }
                return CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
            }), status == noErr else { continue }
            data.withUnsafeBytes { raw in
                samples.append(contentsOf: raw.bindMemory(to: Float.self))
            }
        }

        guard reader.status != .failed, let finalRate = sampleRate else { return nil }
        return (samples, finalRate)
    }
}
