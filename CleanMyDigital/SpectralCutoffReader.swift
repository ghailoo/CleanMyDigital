//
//  SpectralCutoffReader.swift
//  CleanMyDigital
//

import AVFoundation
import CoreMedia
import Foundation

/// The result of one file's spectral-cutoff analysis.
nonisolated enum SpectralCutoffOutcome: Sendable {
    /// Highest frequency (Hz) with real signal energy, and what that
    /// means for this file's container and stated bitrate.
    case measured(hz: Double, verdict: QualityVerdict)
    /// The file was too short or too quiet to measure meaningfully.
    case inconclusive
    case failed(String)
}

/// Decodes a whole track to mono and hands it to `SpectralCutoffAnalyzer`,
/// then grades it with `QualityVerdict` — Spectro analyzes the full track
/// (5 segments plus a whole-track spectrum), so this does too.
///
/// ponytail: holds the whole decoded track in memory (~64MB for 6 min at
/// 44.1kHz, ~4x that at 192kHz); stream the STFT if hi-res batches run hot.
///
/// Decodes via `AVAssetReader` rather than `AVAudioFile` — confirmed
/// empirically that `AVAudioFile` goes through a lower-level Core Audio
/// path that fails under App Sandbox for some files on a network share
/// (a Core Audio permission-flavored error, even with the scanned
/// folder's security-scoped access already active), while the exact same
/// files decode fine via `AVAssetReader`, which rides the same
/// `AVURLAsset` pipeline already used successfully elsewhere in this app
/// for tag and duration reading.
nonisolated enum SpectralCutoffReader {
    /// `@concurrent` so the decode + FFT run off the main actor.
    @concurrent static func analyze(url: URL, bitrateKbps: Int?) async throws -> SpectralCutoffOutcome {
        guard let (samples, sampleRate) = try await decodeMono(url: url),
              let features = SpectralCutoffAnalyzer.analyze(samples: samples, sampleRate: sampleRate)
        else { return .inconclusive }
        let verdict = QualityVerdict.classify(features, fileExtension: url.pathExtension, bitrateKbps: bitrateKbps)
        return .measured(hz: features.cutoffHz, verdict: verdict)
    }

    /// The whole track as mono Float32 PCM and its sample rate.
    @concurrent static func decodeMono(url: URL) async throws -> (samples: [Float], sampleRate: Double)? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        return try readPCMSamples(asset: asset, track: track)
    }

    /// Decodes the track to mono Float32 PCM. Requesting a single
    /// output channel lets `AVAssetReader` do the stereo-to-mono mixdown
    /// itself, and the real sample rate is read back from the delivered
    /// sample buffer's format description rather than assumed.
    private static func readPCMSamples(
        asset: AVURLAsset, track: AVAssetTrack
    ) throws -> (samples: [Float], sampleRate: Double)? {
        let reader = try AVAssetReader(asset: asset)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            // Without this an AIFF source decodes big-endian (garbage/NaN as
            // native floats). Spectro omits it too, which is why it calls
            // some good AIFFs Fake.
            AVLinearPCMIsBigEndianKey: false,
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
