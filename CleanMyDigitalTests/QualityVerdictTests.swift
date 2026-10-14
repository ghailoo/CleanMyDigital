//
//  QualityVerdictTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

/// Branches of Spectro's decompiled decision tree.
struct QualityVerdictTests {
    private func grade(
        _ cutoffKHz: Double, rate: Double = 44100, wall: Bool = false, air: Double = 0.5,
        upsampled: Bool = false, balance: Double = 0, ext: String, kbps: Int?
    ) -> QualityVerdict.Grade {
        let features = SpectralCutoffAnalyzer.Features(
            cutoffHz: cutoffKHz * 1000, hasBrickwall: wall, airFraction: air,
            isUpsampledFrom44k: upsampled, balance: balance, sampleRate: rate)
        return QualityVerdict.classify(features, fileExtension: ext, bitrateKbps: kbps).grade
    }

    @Test func flacReachingNyquistIsLossless() {
        #expect(grade(21.8, ext: "flac", kbps: 900) == .lossless)
    }

    @Test func flacAbove20kIsLossless() {
        #expect(grade(21.4, ext: "flac", kbps: 900) == .lossless)
    }

    @Test func hiResWithCDBandContentIsMedium() {
        #expect(grade(22.0, rate: 192_000, ext: "wav", kbps: 9216) == .medium)
    }

    @Test func fortyEightKFromCDMasterIsMedium() {
        #expect(grade(21.9, rate: 48_000, upsampled: true, ext: "flac", kbps: 1000) == .medium)
    }

    @Test func flacBelow17kIsFake() {
        #expect(grade(16.0, wall: true, ext: "flac", kbps: 800) == .fake)
    }

    @Test func balancedOldMasterAt16kIsLossless() {
        #expect(grade(16.0, balance: 0.8, ext: "flac", kbps: 800) == .lossless)
    }

    @Test func flacBetween17And19kIsMedium() {
        #expect(grade(18.0, ext: "flac", kbps: 800) == .medium)
    }

    @Test func the19To20kZoneUsesAirAndBrickwall() {
        #expect(grade(19.5, air: 0.4, ext: "flac", kbps: 800) == .lossless)
        #expect(grade(19.5, air: 0.02, ext: "flac", kbps: 800) == .fake)
        #expect(grade(19.5, wall: true, air: 0.1, ext: "flac", kbps: 800) == .fake)
        #expect(grade(19.5, air: 0.1, ext: "flac", kbps: 800) == .medium)
    }

    @Test func mp3IsNeverLosslessAndLowBitrateIsFake() {
        #expect(grade(20.5, ext: "mp3", kbps: 320) == .medium)
        #expect(grade(19.0, ext: "mp3", kbps: 192) == .medium)
        #expect(grade(15.0, ext: "mp3", kbps: 320) == .fake)
        #expect(grade(16.0, ext: "mp3", kbps: 128) == .fake)
    }

    @Test func aacIsHonestlyLossyNeverFake() {
        #expect(grade(15.0, ext: "m4a", kbps: 128) == .medium)
        #expect(grade(21.0, ext: "m4a", kbps: 256) == .medium)
    }

    @Test func alacInM4AIsJudgedAsLossless() {
        #expect(grade(21.8, ext: "m4a", kbps: 900) == .lossless)
        #expect(grade(16.0, ext: "m4a", kbps: 900) == .fake)
    }
}
