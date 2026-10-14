//
//  SpectralCutoffAnalyzer.swift
//  CleanMyDigital
//

import Accelerate
import Foundation

/// Measures the spectral features Spectro.app grades a file on, using the
/// same pipeline its binary uses (recovered by decompiling it): a 2048-point
/// Hann-windowed DFT every 1024 samples, power in "dB" clipped to -120...0,
/// then an averaged and a max-hold spectrum of 1024 bins.
///
/// - **Cutoff** — the first frequency between 12 and 20kHz where the next
///   1kHz is nearly empty (< -83dB) and at least 20dB below the 500Hz just
///   under it: a lossy encoder's lowpass "brickwall". With no such cliff it
///   falls back to the highest max-hold bin above the noise floor. Measured
///   on 5 segments (quiet ones dropped) and combined, so one dark passage
///   can't fake a low cutoff.
/// - **Air** — the share of frames with energy above -60dB from 19kHz up.
/// - **Upsampled from 44.1** — a 48kHz file with a wall at 22.05kHz.
/// - **Balance** — whether the lows and mids sit near the overall level,
///   which marks a naturally narrow (old/lo-fi) master rather than a transcode.
///
/// Pure and I/O-free — takes decoded mono samples directly.
nonisolated enum SpectralCutoffAnalyzer {
    struct Features: Equatable {
        let cutoffHz: Double
        /// The whole-track spectrum shows a lossy brickwall at some cutoff.
        let hasBrickwall: Bool
        let airFraction: Double
        let isUpsampledFrom44k: Bool
        /// 0, 0.6 or 0.8 — Spectro's natural-spectrum score.
        let balance: Double
        let sampleRate: Double
    }

    private static let fftSize = 2048
    private static let hop = 1024
    private static let bins = 1024

    static func analyze(samples: [Float], sampleRate: Double) -> Features? {
        // Silence has nothing to grade (Spectro: "insufficient non-silent samples").
        guard sampleRate > 0, let whole = spectrum(samples[...]), whole.maxHold.contains(where: { $0 > -120 })
        else { return nil }
        let rate = Float(sampleRate)
        let wholeCutoff = cutoff(of: whole, sampleRate: rate)
        let cutoffKHz = segmentCutoffKHz(samples, sampleRate: rate) ?? wholeCutoff.kHz
        return Features(
            cutoffHz: Double(cutoffKHz) * 1000,
            hasBrickwall: wholeCutoff.isBrickwall,
            airFraction: Double(airFraction(whole, sampleRate: rate)),
            isUpsampledFrom44k: isUpsampledFrom44k(whole.maxHold, sampleRate: rate),
            balance: Double(balance(whole.average, sampleRate: rate)),
            sampleRate: sampleRate)
    }

    /// Back-compat for callers that only want the cutoff.
    static func highestSignificantFrequency(samples: [Float], sampleRate: Double) -> Double? {
        analyze(samples: samples, sampleRate: sampleRate)?.cutoffHz
    }

    // MARK: - STFT

    private struct Spectrum {
        var average: [Float]
        var maxHold: [Float]
        /// Per bin, how many frames were louder than -60dB.
        var loudFrames: [Float]
        var frames: Int
    }

    /// One 2048-point frame → 1024 bins of clipped "dB". Holds the DFT
    /// setup and scratch buffers so they're reused across frames.
    private final class FrameTransform {
        let setup: vDSP_DFT_Setup
        var window = [Float](repeating: 0, count: fftSize)
        var realIn = [Float](repeating: 0, count: fftSize)
        let imagIn = [Float](repeating: 0, count: fftSize)
        var realOut = [Float](repeating: 0, count: fftSize)
        var imagOut = [Float](repeating: 0, count: fftSize)
        var power = [Float](repeating: 0, count: bins)
        var dB = [Float](repeating: 0, count: bins)

        init?() {
            guard let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD) else { return nil }
            self.setup = setup
            vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        }

        deinit { vDSP_DFT_DestroySetup(setup) }

        /// `frame` must hold exactly `fftSize` samples.
        func dB(_ frame: ArraySlice<Float>) -> [Float] {
            frame.withUnsafeBufferPointer {
                vDSP_vmul($0.baseAddress!, 1, window, 1, &realIn, 1, vDSP_Length(fftSize))
            }
            vDSP_DFT_Execute(setup, realIn, imagIn, &realOut, &imagOut)
            realOut.withUnsafeMutableBufferPointer { re in
                imagOut.withUnsafeMutableBufferPointer { im in
                    var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                    vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(bins))
                }
            }
            var floor: Float = 1e-12, one: Float = 1, low: Float = -120, high: Float = 0
            vDSP_vthr(power, 1, &floor, &power, 1, vDSP_Length(bins))
            // Flag 10 (not 0) = 20·log10 of *power* — Spectro's own quirk;
            // every threshold here (-60/-70/-83dB…) is on this doubled scale.
            vDSP_vdbcon(power, 1, &one, &dB, 1, vDSP_Length(bins), 10)
            vDSP_vclip(dB, 1, &low, &high, &dB, 1, vDSP_Length(bins))
            return dB
        }
    }

    private static func spectrum(_ samples: ArraySlice<Float>) -> Spectrum? {
        guard samples.count >= fftSize, let transform = FrameTransform() else { return nil }
        var result = Spectrum(average: .init(repeating: 0, count: bins),
                              maxHold: .init(repeating: -120, count: bins),
                              loudFrames: .init(repeating: 0, count: bins), frames: 0)
        var start = samples.startIndex
        while start + fftSize <= samples.endIndex {
            let dB = transform.dB(samples[start..<(start + fftSize)])
            vDSP_vadd(result.average, 1, dB, 1, &result.average, 1, vDSP_Length(bins))
            vDSP_vmax(result.maxHold, 1, dB, 1, &result.maxHold, 1, vDSP_Length(bins))
            for bin in 0..<bins where dB[bin] > -60 { result.loudFrames[bin] += 1 }
            result.frames += 1
            start += hop
        }
        guard result.frames > 0 else { return nil }
        var count = Float(result.frames)
        vDSP_vsdiv(result.average, 1, &count, &result.average, 1, vDSP_Length(bins))
        return result
    }

    /// A downsampled spectrogram for display: `columns` evenly spaced frames,
    /// each reduced to `rows` bands (max of the bins in the band), values
    /// -120...0 on the same scale as the analysis. Row 0 is the lowest band.
    static func spectrogram(samples: [Float], columns: Int, rows: Int) -> [[Float]] {
        guard samples.count >= fftSize, columns > 0, rows > 0, let transform = FrameTransform() else { return [] }
        let lastStart = samples.count - fftSize
        let perRow = max(1, bins / rows)
        return (0..<columns).map { column in
            let start = columns == 1 ? 0 : lastStart * column / (columns - 1)
            let dB = transform.dB(samples[start..<(start + fftSize)])
            return (0..<rows).map { row in dB[(row * perRow)..<min(bins, (row + 1) * perRow)].max() ?? -120 }
        }
    }

    // MARK: - Cutoff

    private static func binHz(_ spectrum: [Float], _ sampleRate: Float) -> Float {
        sampleRate * 0.5 / Float(spectrum.count)
    }

    private static func mean(_ values: ArraySlice<Float>) -> Float {
        values.isEmpty ? 0 : values.reduce(0, +) / Float(values.count)
    }

    /// Mean of bins covering `lo...hi` Hz, nil when the band is out of range.
    private static func bandMean(_ spectrum: [Float], _ lo: Float, _ hi: Float, _ sampleRate: Float) -> Float? {
        band(spectrum, lo, hi, sampleRate).map(mean)
    }

    private static func band(_ spectrum: [Float], _ lo: Float, _ hi: Float, _ sampleRate: Float) -> ArraySlice<Float>? {
        guard lo < hi, hi < sampleRate * 0.5 else { return nil }
        let width = binHz(spectrum, sampleRate)
        let first = max(0, Int(lo / width)), last = min(Int(hi / width), spectrum.count - 1)
        return first <= last ? spectrum[first...last] : nil
    }

    /// The lossy-lowpass detector: kHz of the first cliff, or nil.
    private static func brickwallKHz(_ average: [Float], sampleRate: Float) -> Float? {
        let width = binHz(average, sampleRate)
        let w = max(1, Int(500 / width))
        let first = Int(12000 / width)
        let last = min(Int(20000 / width), average.count - 2 * w - 1)
        guard first - w >= 0, first <= last else { return nil }
        for bin in first...last {
            let below = mean(average[(bin - w)..<bin])
            let above = mean(average[bin..<min(bin + 2 * w, average.count)])
            if above < -83, below - above >= 20 { return width * Float(bin) / 1000 }
        }
        return nil
    }

    /// No cliff: highest max-hold bin above the noise floor. A hi-res file
    /// whose content stops at 22.05kHz is judged as the 44.1kHz master it is.
    private static func fallbackKHz(_ maxHold: [Float], sampleRate: Float) -> Float {
        var spectrum = maxHold, rate = sampleRate
        if sampleRate >= 88200 {
            let edge = Int(Float(maxHold.count) * 22050 / (sampleRate * 0.5))
            if edge > 0, edge < maxHold.count,
               mean(maxHold[..<edge]) - mean(maxHold[edge...]) > 35 {
                spectrum = Array(maxHold[..<edge])
                rate = 44100
            }
        }
        let floor = max(-120, noiseFloor(spectrum, sampleRate: rate))
        let top = spectrum.lastIndex { $0 >= floor } ?? 0
        return binHz(spectrum, rate) * Float(top) / 1000
    }

    /// Median of the 2-8kHz band minus 35dB, kept within -75...-25dB.
    private static func noiseFloor(_ spectrum: [Float], sampleRate: Float) -> Float {
        guard let slice = band(spectrum, 2000, 8000, sampleRate) else { return -75 }
        let sorted = slice.sorted()
        return min(max(sorted[sorted.count / 2] - 35, -75), -25)
    }

    private static func cutoff(of spectrum: Spectrum, sampleRate: Float) -> (kHz: Float, isBrickwall: Bool) {
        if let kHz = brickwallKHz(spectrum.average, sampleRate: sampleRate) { return (kHz, true) }
        return (fallbackKHz(spectrum.maxHold, sampleRate: sampleRate), false)
    }

    /// Cutoff over 5 equal segments, skipping quiet ones (2-8kHz level
    /// under -70dB). Agreeing segments are averaged; disagreeing ones (spread
    /// over 2kHz) take a high percentile, capped by the brickwall segments.
    private static func segmentCutoffKHz(_ samples: [Float], sampleRate: Float) -> Float? {
        guard samples.count >> 10 > 54 else { return nil }
        let length = samples.count / 5
        var found: [(kHz: Float, isBrickwall: Bool)] = []
        for index in 0..<5 {
            let start = index * length
            let end = index == 4 ? samples.count : start + length
            guard end - start >= fftSize, let segment = spectrum(samples[start..<end]), segment.frames >= 10,
                  (bandMean(segment.average, 2000, 8000, sampleRate) ?? -120) >= -70
            else { continue }
            found.append(cutoff(of: segment, sampleRate: sampleRate))
        }
        guard !found.isEmpty else { return nil }

        let values = found.map(\.kHz)
        let average = mean(values[...])
        let variance = values.reduce(0) { $0 + ($1 - average) * ($1 - average) } / Float(values.count)
        guard variance > 4 else { return average }

        let sorted = values.sorted()
        let walls = found.filter(\.isBrickwall).map(\.kHz).sorted()
        var robust: Float
        switch sorted.count {
        case 1: robust = sorted[0]
        case 2: robust = walls.isEmpty ? (sorted[0] + sorted[1]) / 2 : sorted[0]
        default: robust = sorted[Int(Float(sorted.count - 1) * 0.75)]
        }
        if !walls.isEmpty {
            let median = walls.count % 2 == 0
                ? (walls[walls.count / 2 - 1] + walls[walls.count / 2]) * 0.5 : walls[walls.count / 2]
            robust = min(robust, median)
        }
        return robust
    }

    // MARK: - Other features

    private static func airFraction(_ spectrum: Spectrum, sampleRate: Float) -> Float {
        guard sampleRate * 0.5 > 19000 else { return 1 }
        let first = Int(19000 * Float(bins) / (sampleRate * 0.5))
        guard first < bins else { return 1 }
        return mean(spectrum.loudFrames[first...]) / Float(spectrum.frames)
    }

    private static func isUpsampledFrom44k(_ maxHold: [Float], sampleRate: Float) -> Bool {
        guard abs(sampleRate - 48000) <= 100,
              let below = bandMean(maxHold, 19000, 22000, sampleRate),
              let above = bandMean(maxHold, 22000, 22500, sampleRate)
        else { return false }
        return below - above > 25
    }

    private static func balance(_ average: [Float], sampleRate: Float) -> Float {
        let overall = mean(average[...])
        guard let lows = bandMean(average, 20, 200, sampleRate), abs(lows - overall) < 15 else { return 0 }
        guard let mids = band(average, 200, 2000, sampleRate), abs(mean(mids) - overall) < 15 else { return 0.6 }
        let m = mean(mids)
        let variance = mids.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Float(mids.count)
        return variance < 50 ? 0.8 : 0.6
    }
}
