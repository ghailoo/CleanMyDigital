//
//  QualityVerdict.swift
//  CleanMyDigital
//

import Foundation

/// Spectro.app's Fake / Medium / Lossless verdict, reproduced from its
/// decompiled decision tree (the function that writes "fake"/"medium"/
/// "lossless" after analysis). Inputs are `SpectralCutoffAnalyzer.Features`
/// plus the container and its real bitrate.
///
/// In plain terms:
/// - A lossy file (MP3/AAC/M4A) is never Lossless; at 160kbps or less an
///   MP3 is Fake; an AAC/M4A is never Fake (honestly lossy).
/// - A lossless file reaching (near) Nyquist is Lossless.
/// - Otherwise by cutoff: under 17kHz Fake (unless it's a naturally
///   balanced old master at 15-17kHz), 17-20kHz Medium (19-20kHz decided by
///   high-band "air" and the brickwall), 20kHz+ Lossless.
/// - Hi-res files whose content stops at the CD band are Medium (upsampled).
///
/// Pure — every input is a plain value, so it's unit-testable without audio.
nonisolated struct QualityVerdict: Sendable, Equatable {
    enum Grade: Int, Sendable, Comparable {
        case fake, medium, lossless

        var label: String {
            switch self {
            case .fake: "Fake"
            case .medium: "Medium"
            case .lossless: "Lossless"
            }
        }

        static func < (a: Grade, b: Grade) -> Bool { a.rawValue < b.rawValue }
    }

    let grade: Grade
    /// One plain-language sentence explaining the grade, for tooltips.
    let reason: String

    private static let lossyExtensions: Set<String> = ["mp3", "aac", "m4a", "ogg", "opus"]
    private static let losslessExtensions: Set<String> = ["wav", "wave", "aif", "aiff", "flac", "alac", "wv", "ape", "dsf"]

    static func classify(
        _ features: SpectralCutoffAnalyzer.Features, fileExtension: String, bitrateKbps: Int?
    ) -> QualityVerdict {
        let ext = fileExtension.lowercased()
        let kbps = bitrateKbps ?? 0
        let c = features.cutoffHz / 1000
        let air = features.airFraction
        let wall = features.hasBrickwall
        let nyquistKHz = features.sampleRate / 2000
        // An .m4a can be ALAC or AAC; only the rate tells them apart.
        let isALAC = ext == "m4a" && kbps >= 500
        let isLossyExt = lossyExtensions.contains(ext)
        let isLosslessCodec = losslessExtensions.contains(ext) || isALAC
        let honestlyLossy = isLossyExt && !isALAC

        var grade: Grade
        if !(isLosslessCodec || kbps > 160) {
            grade = .fake
        } else if !isALAC && !losslessExtensions.contains(ext) {
            // Lossy (or unknown) container: judged by cutoff, never above Medium.
            if isLossyExt && c >= 20 && air < 0.3 {
                grade = .medium
            } else {
                grade = c >= 20 ? .lossless : c >= 16 ? .medium : .fake
            }
        } else if features.isUpsampledFrom44k || (features.sampleRate > 88000 && (20...25).contains(c)) {
            grade = .medium
        } else if !(abs(c - nyquistKHz) > 0.5
                    && (features.sampleRate < 44100 || c >= 15 || c <= 0 || wall)) {
            grade = .lossless
        } else if features.balance >= 0.6 && c >= 15 && c < 17 {
            grade = .lossless
        } else if c < 17 {
            grade = .fake
        } else if c < 19 {
            grade = .medium
        } else if c < 20 {
            if air > 0.25 && !wall { grade = .lossless }
            else if air < 0.05 { grade = .fake }
            else { grade = wall ? .fake : .medium }
        } else {
            grade = .lossless
        }
        if honestlyLossy && grade == .lossless { grade = .medium }
        // "M4A holds AAC. Honestly lossy, not fake lossless."
        if honestlyLossy && (ext == "m4a" || ext == "aac") && grade == .fake { grade = .medium }

        return QualityVerdict(grade: grade, reason: explain(grade, features, ext: ext, kbps: kbps, honestlyLossy: honestlyLossy))
    }

    private static func explain(
        _ grade: Grade, _ f: SpectralCutoffAnalyzer.Features, ext: String, kbps: Int, honestlyLossy: Bool
    ) -> String {
        let kHz = String(format: "%.1f kHz", f.cutoffHz / 1000)
        if honestlyLossy {
            if ext == "m4a" || ext == "aac" { return "Native AAC container (lossy), cutoff \(kHz)" }
            if grade == .fake { return "Lossy \(ext.uppercased()) at \(kbps) kbps, cutoff \(kHz)" }
            return "Lossy \(ext.uppercased()), cutoff \(kHz)"
        }
        switch grade {
        case .lossless:
            return f.balance >= 0.6 && f.cutoffHz < 17000
                ? "Cutoff \(kHz), but a natural spectrum. Likely an old or lo-fi master"
                : "Cutoff \(kHz), expected for lossless"
        case .medium:
            if f.isUpsampledFrom44k || f.sampleRate > 88000 {
                return "\(Int(f.sampleRate / 1000)) kHz file, but content stops around \(kHz). Upsampled"
            }
            return "Cutoff/attenuation around \(kHz). Little energy above 19 kHz"
        case .fake:
            return f.hasBrickwall ? "Fake. Transcode detected: brickwall around \(kHz)"
                                  : "Fake. Transcode detected: cutoff around \(kHz)"
        }
    }
}
