//
//  SpectralCutoffAnalyzerTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

struct SpectralCutoffAnalyzerTests {
    @Test func detectsCutoffOfBandLimitedSignal() throws {
        let sampleRate = 44100.0
        let samples = Self.sineSum(frequencies: [1000, 5000, 10000, 15000], sampleRate: sampleRate, duration: 2)

        let cutoff = SpectralCutoffAnalyzer.highestSignificantFrequency(samples: samples, sampleRate: sampleRate)
        let value = try #require(cutoff)
        #expect(abs(value - 15000) < 300)
    }

    @Test func detectsNearFullRangeForBroadbandSignal() throws {
        let sampleRate = 44100.0
        let frequencies = stride(from: 500.0, through: 20000.0, by: 500.0).map { $0 }
        let samples = Self.sineSum(frequencies: frequencies, sampleRate: sampleRate, duration: 2)

        let cutoff = SpectralCutoffAnalyzer.highestSignificantFrequency(samples: samples, sampleRate: sampleRate)
        let value = try #require(cutoff)
        #expect(value > 19000)
    }

    @Test func lowCutoffStaysLowEvenWithMoreSamples() throws {
        // A 128kbps-style band-limited signal shouldn't read as full-range
        // just because there's more audio to analyze.
        let sampleRate = 44100.0
        let samples = Self.sineSum(frequencies: [200, 1000, 4000, 8000, 16000], sampleRate: sampleRate, duration: 3)

        let cutoff = SpectralCutoffAnalyzer.highestSignificantFrequency(samples: samples, sampleRate: sampleRate)
        let value = try #require(cutoff)
        #expect(abs(value - 16000) < 300)
        #expect(value < 18000)
    }

    @Test func bandLimitedSignalShowsBrickwall() throws {
        // Dense content up to 16kHz, nothing above: a lossy lowpass shape.
        let sampleRate = 44100.0
        let frequencies = stride(from: 500.0, through: 16000.0, by: 250.0).map { $0 }
        let samples = Self.sineSum(frequencies: frequencies, sampleRate: sampleRate, duration: 2)

        let features = try #require(SpectralCutoffAnalyzer.analyze(samples: samples, sampleRate: sampleRate))
        #expect(features.hasBrickwall)
        #expect(abs(features.cutoffHz - 16000) < 300)
    }

    @Test func noBrickwallWhenContentReachesNyquist() throws {
        let sampleRate = 44100.0
        let frequencies = stride(from: 500.0, through: 21800.0, by: 250.0).map { $0 }
        let samples = Self.sineSum(frequencies: frequencies, sampleRate: sampleRate, duration: 2)

        let features = try #require(SpectralCutoffAnalyzer.analyze(samples: samples, sampleRate: sampleRate))
        #expect(!features.hasBrickwall)
        #expect(features.cutoffHz > 21000)
    }

    @Test func returnsNilForSilence() {
        let samples = [Float](repeating: 0, count: 44100 * 2)
        #expect(SpectralCutoffAnalyzer.highestSignificantFrequency(samples: samples, sampleRate: 44100) == nil)
    }

    @Test func returnsNilWhenFewerSamplesThanOneWindow() {
        let samples = [Float](repeating: 1, count: 100)
        #expect(SpectralCutoffAnalyzer.highestSignificantFrequency(samples: samples, sampleRate: 44100) == nil)
    }

    // MARK: - Fixture

    private static func sineSum(frequencies: [Double], sampleRate: Double, duration: Double) -> [Float] {
        let sampleCount = Int(duration * sampleRate)
        var samples = [Float](repeating: 0, count: sampleCount)
        for frequency in frequencies {
            let angularFrequency = 2 * Double.pi * frequency / sampleRate
            for i in 0..<sampleCount {
                samples[i] += Float(sin(angularFrequency * Double(i)))
            }
        }
        let peak = samples.map { abs($0) }.max() ?? 1
        if peak > 0 {
            for i in 0..<sampleCount { samples[i] /= peak }
        }
        return samples
    }
}
