//
//  SpectralCutoffAnalyzer.swift
//  CleanMyDigital
//

import Accelerate
import Foundation

/// Detects the highest frequency still carrying real signal energy in a
/// decoded audio buffer — the same thing a spectrogram viewer like Spek
/// shows visually as a hard ceiling. A lossy encoder discards frequency
/// content above some threshold to hit its target bitrate (roughly 16kHz
/// for 128kbps MP3, ~19kHz for 192kbps, close to full range above
/// 256kbps). That ceiling is permanent — re-encoding a low-bitrate source
/// into FLAC or a higher-bitrate MP3 can't recreate frequencies that are
/// already gone, so a suspiciously low cutoff on a file that claims to be
/// high quality is the signature of a fake/transcoded file.
///
/// Pure and I/O-free — takes decoded samples directly, so it's fully
/// unit-testable with synthetic signals of a known frequency content.
enum SpectralCutoffAnalyzer {
    /// FFT window size in samples (power of 2). At a typical 44.1kHz
    /// sample rate this gives ~10.8Hz of frequency resolution per bin —
    /// plenty precise for distinguishing a 16kHz cutoff from a 19kHz one.
    private static let windowSize = 4096

    /// How far below the spectrum's peak magnitude a bin can fall before
    /// it's considered "no real energy" rather than quiet-but-present
    /// content. -50dB is deep enough to ignore quantization/dither noise
    /// floors, but well above where genuine musical content sits.
    private static let noiseFloorDB: Float = 50

    /// The highest frequency (Hz) with real signal energy across
    /// `samples`, or nil if there isn't enough signal to measure
    /// meaningfully (silence, or fewer samples than one FFT window).
    ///
    /// Chops `samples` into non-overlapping windows, Hann-windows and FFTs
    /// each one, and combines them by taking the *maximum* magnitude seen
    /// at each frequency bin across every window — so a brief cymbal hit
    /// or hi-hat that reaches high frequencies isn't washed out by quieter
    /// passages elsewhere in the sampled audio.
    static func highestSignificantFrequency(samples: [Float], sampleRate: Double) -> Double? {
        guard samples.count >= windowSize, sampleRate > 0 else { return nil }

        let log2n = vDSP_Length(log2(Float(windowSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var hannWindow = [Float](repeating: 0, count: windowSize)
        vDSP_hann_window(&hannWindow, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))

        var composite = [Float](repeating: 0, count: windowSize / 2)
        var offset = 0
        var windowCount = 0
        while offset + windowSize <= samples.count {
            let chunk = Array(samples[offset..<(offset + windowSize)])
            if let magnitudes = magnitudeSpectrum(chunk, hannWindow: hannWindow, log2n: log2n, fftSetup: fftSetup) {
                vDSP_vmax(composite, 1, magnitudes, 1, &composite, 1, vDSP_Length(composite.count))
                windowCount += 1
            }
            offset += windowSize
        }
        guard windowCount > 0 else { return nil }

        return cutoffFrequency(magnitudes: composite, sampleRate: sampleRate)
    }

    /// The linear-magnitude spectrum of one Hann-windowed real FFT.
    /// `vDSP_fft_zrip`'s packed real-FFT format stores the DC (0Hz) and
    /// Nyquist components together in bin 0's real/imaginary slots — that
    /// only affects bin 0 itself, far from the ~15-20kHz range this
    /// analysis cares about, so it's left as-is rather than unpacked.
    private static func magnitudeSpectrum(
        _ chunk: [Float], hannWindow: [Float], log2n: vDSP_Length, fftSetup: FFTSetup
    ) -> [Float]? {
        var windowed = [Float](repeating: 0, count: chunk.count)
        vDSP_vmul(chunk, 1, hannWindow, 1, &windowed, 1, vDSP_Length(chunk.count))

        let half = chunk.count / 2
        var realp = [Float](repeating: 0, count: half)
        var imagp = [Float](repeating: 0, count: half)

        return realp.withUnsafeMutableBufferPointer { realPtr -> [Float]? in
            imagp.withUnsafeMutableBufferPointer { imagPtr -> [Float]? in
                guard let realBase = realPtr.baseAddress, let imagBase = imagPtr.baseAddress else { return nil }
                var split = DSPSplitComplex(realp: realBase, imagp: imagBase)

                windowed.withUnsafeBufferPointer { windowedPtr in
                    windowedPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(half))
                    }
                }

                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                var squaredMagnitudes = [Float](repeating: 0, count: half)
                vDSP_zvmags(&split, 1, &squaredMagnitudes, 1, vDSP_Length(half))
                var magnitudes = [Float](repeating: 0, count: half)
                var n = Int32(half)
                vvsqrtf(&magnitudes, squaredMagnitudes, &n)
                return magnitudes
            }
        }
    }

    /// Scans a composite magnitude spectrum from the top frequency bin
    /// downward and returns the frequency of the first bin (smoothed over
    /// a few neighbors, to ignore single-bin noise spikes) that's within
    /// `noiseFloorDB` of the spectrum's peak — i.e. the highest frequency
    /// still carrying real content rather than near-silence.
    private static func cutoffFrequency(magnitudes: [Float], sampleRate: Double) -> Double? {
        guard let peak = magnitudes.max(), peak > 0 else { return nil }
        let threshold = peak * pow(10, -noiseFloorDB / 20)

        let smoothingRadius = 2
        func smoothed(_ index: Int) -> Float {
            let lowerBound = max(0, index - smoothingRadius)
            let upperBound = min(magnitudes.count - 1, index + smoothingRadius)
            let slice = magnitudes[lowerBound...upperBound]
            return slice.reduce(0, +) / Float(slice.count)
        }

        for index in stride(from: magnitudes.count - 1, through: 1, by: -1) where smoothed(index) > threshold {
            let binWidth = sampleRate / Double(windowSize)
            return Double(index) * binWidth
        }
        return nil
    }
}
