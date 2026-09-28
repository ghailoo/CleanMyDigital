//
//  WavPackMetadataReader.swift
//  CleanMyDigital
//

import Foundation

/// Reads a WavPack (.wv) file's embedded APEv2 tag, plus the stream-shape
/// info from its first block header needed to compute duration/bitrate —
/// natively, since AVFoundation cannot open WavPack at all (the same
/// "-11828 file format not recognized" gap `DSFMetadataReader` documents
/// for DSF, confirmed empirically for WavPack too). This is WavPack's
/// *only* source of metadata and playback info; there's no AVFoundation
/// reading to fall back to or merge with.
enum WavPackMetadataReader {
    struct Result {
        var metadata = NativeAudioMetadata()
        var duration: TimeInterval?
        var bitrateKbps: Int?
    }

    static func read(contentsOf url: URL) throws -> Result {
        let bytes = [UInt8](try Data(contentsOf: url))
        let header = try WavPackStream.parseFirstBlockHeader(in: bytes)
        let located = try APEv2Tag.locate(in: bytes)

        var result = Result()
        if let located {
            APEv2TagBuilder.fill(&result.metadata, from: located.items)
        }

        // Duration is only computable from the very first block in the
        // file (block_index == 0 — every other block's total_samples
        // field is meaningless, per the format spec's §2.0), only for a
        // known length, and only for one of the 15 standard (table-
        // indexed) sample rates — a non-standard rate needs the
        // ID_SAMPLE_RATE metadata sub-block, which `WavPackStream`
        // deliberately doesn't parse (no verified spec for its byte
        // layout — see its doc comment). DSD-flavored WavPack counts
        // samples differently than PCM, so it's excluded too. All three
        // are left nil rather than guessed at.
        let sampleRateIndex = WavPackStream.sampleRateIndex(fromFlags: header.flags)
        let isDSD = header.flags & WavPackStream.dsdFlag != 0
        let isKnownLength = header.totalSamples != WavPackStream.unknownSampleCount
        if header.blockIndex == 0, !isDSD, isKnownLength,
           sampleRateIndex < WavPackStream.standardSampleRates.count {
            let sampleRate = WavPackStream.standardSampleRates[sampleRateIndex]
            let duration = Double(header.totalSamples) / Double(sampleRate)
            result.duration = duration

            // No literal "bitrate" field exists — WavPack's lossless and
            // hybrid modes are both effectively CBR-per-encode but not
            // advertised anywhere in the header — so this is the same
            // "compressed bytes ÷ duration" average this app already uses
            // as its FLAC/WAV bitrate fallback (`LibraryScanner.
            // audioBitrateKbps`'s `fallbackAudioDataSize` path), just
            // computed here directly since there's no AVFoundation asset
            // to ask first. The audio prefix is every byte before the tag
            // (or the whole file, if there's no tag yet).
            let audioPrefixEnd = located?.range.lowerBound ?? bytes.count
            if duration > 0 {
                result.bitrateKbps = Int((Double(audioPrefixEnd) * 8 / duration / 1000).rounded())
            }
        }

        return result
    }

}
