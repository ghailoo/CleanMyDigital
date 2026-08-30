//
//  WavPackStream.swift
//  CleanMyDigital
//

import Foundation

/// Low-level WavPack (.wv) container parsing, per David Bryant's "WavPack 4
/// & 5 Binary File / Block Format" specification (wavpack.com, April 12
/// 2020 revision). A WavPack file is a sequence of "wvpk" blocks, each
/// self-describing its own size, optionally followed by tag data — an
/// APEv2 tag and/or a legacy ID3v1 tag — which must sit outside the blocks
/// entirely (before, between, or after them; this app only supports the
/// overwhelmingly common case of tags coming after every block).
///
/// Unlike `DSFStream` (which walks a small, fixed set of chunks to find
/// where the audio ends), this never walks the block chain at all: an
/// APEv2/ID3v1 tag is self-delimiting from the end of the file (see
/// `APEv2Tag.locate(in:)`, which scans backward from EOF independent of
/// what precedes it), so the entire run of "wvpk" blocks — however many
/// there are, and whatever they contain — is treated as one opaque audio
/// prefix, bounded by an existing tag's start offset or, if there's no tag
/// yet, simply the whole file. The only thing ever parsed here is the very
/// first block's fixed 32-byte header, for the stream-shape fields
/// (`FirstBlockHeader`) needed to compute duration; nothing about the
/// compressed audio itself, or any block after the first, is ever
/// inspected — so there's no risk of this app's own (quite partial)
/// understanding of the format ever touching the audio bitstream.
///
/// Tagging: WavPack's own recommended tag format is APEv2 (see
/// `APEv2Tag.swift`, a format-agnostic module reused as-is here) rather
/// than ID3 — the one significant structural difference from the
/// DSF/WAV/AIFF native paths, which all lean on the existing
/// `ID3TagBuilder`/`ID3TagEditor`.
enum WavPackStream {
    private static let blockSignature: [UInt8] = Array("wvpk".utf8)
    private static let headerSize = 32

    /// The fields this app needs from the very first block in the file —
    /// enough to compute duration, never anything about decoding audio.
    struct FirstBlockHeader {
        /// 40-bit index of this block's first sample within the file.
        /// `totalSamples` is only meaningful when this is exactly zero —
        /// i.e. this genuinely is the first block (see the spec's §2.0:
        /// "this is only valid if block_index == 0").
        let blockIndex: UInt64
        /// 40-bit total sample count for the *entire file* (not just this
        /// block) — or `0xFF_FFFF_FFFF` (all 40 bits set), the spec's
        /// sentinel for "length unknown".
        let totalSamples: UInt64
        let flags: UInt32
    }

    /// All 40 bits set — the spec's sentinel for "total length unknown"
    /// (e.g. a file created from a pipe with no seek available).
    static let unknownSampleCount: UInt64 = 0xFF_FFFF_FFFF

    /// Parses just the first block's 32-byte header. Throws if the file
    /// doesn't start with a "wvpk" block at all — this app doesn't support
    /// the (extremely rare) case of tag data placed *before* the first
    /// audio block.
    static func parseFirstBlockHeader(in bytes: [UInt8]) throws -> FirstBlockHeader {
        guard bytes.count >= headerSize, matches(bytes, at: 0, blockSignature) else {
            throw TagWriteError.malformedFile("Missing WavPack block signature")
        }
        // ckSize is "size of entire block minus 8" (the ckID+ckSize fields
        // themselves aren't counted) — sanity-check it against the actual
        // file length so a truncated/corrupt file is caught here rather
        // than read past the end of `bytes` later.
        let ckSize = Int(readUInt32LE(bytes, at: 4))
        guard ckSize >= headerSize - 8, ckSize <= bytes.count - 8 else {
            throw TagWriteError.malformedFile("Implausible WavPack block size")
        }

        let blockIndexU8 = UInt64(bytes[10])
        let totalSamplesU8 = UInt64(bytes[11])
        let totalSamplesLow = UInt64(readUInt32LE(bytes, at: 12))
        let blockIndexLow = UInt64(readUInt32LE(bytes, at: 16))
        let flags = readUInt32LE(bytes, at: 24)

        return FirstBlockHeader(
            blockIndex: (blockIndexU8 << 32) | blockIndexLow,
            totalSamples: (totalSamplesU8 << 32) | totalSamplesLow,
            flags: flags)
    }

    /// The 15 standard sample rates a WavPack block's flags can encode
    /// directly, indexed by bits 26-23 of `flags` (a 4-bit field). Index
    /// 15 itself means "unknown or non-standard", which needs a separate
    /// `ID_SAMPLE_RATE` metadata sub-block this app doesn't parse — its
    /// byte layout isn't documented in the block-format spec, and this
    /// codebase doesn't guess at undocumented formats (see
    /// `WavPackMetadataReader`, which leaves duration/bitrate nil for that
    /// case rather than assume one).
    static let standardSampleRates: [Int] = [
        6000, 8000, 9600, 11025, 12000, 16000, 22050, 24000,
        32000, 44100, 48000, 64000, 88200, 96000, 192000,
    ]

    /// Bit 31 of a block's flags: 0 = PCM audio, 1 = DSD audio (WavPack
    /// 5.0+, "DSD over WavPack"). DSD sample accounting doesn't follow the
    /// same "samples / sample rate" arithmetic as PCM, so
    /// `WavPackMetadataReader` leaves duration/bitrate nil rather than
    /// apply the PCM formula to a stream it isn't valid for.
    static let dsdFlag: UInt32 = 1 << 31

    /// Bits 26-23: sampling rate table index.
    static func sampleRateIndex(fromFlags flags: UInt32) -> Int {
        Int((flags >> 23) & 0xF)
    }

    // MARK: - Byte helpers

    private static func matches(_ bytes: [UInt8], at offset: Int, _ signature: [UInt8]) -> Bool {
        guard offset >= 0, offset + signature.count <= bytes.count else { return false }
        return Array(bytes[offset..<(offset + signature.count)]) == signature
    }

    private static func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<4 { value |= UInt32(bytes[offset + i]) << (8 * i) }
        return value
    }
}
