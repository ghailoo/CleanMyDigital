//
//  DSFStream.swift
//  CleanMyDigital
//

import Foundation

/// Low-level DSF (DSD Stream File) header parsing, per Sony's "DSF File
/// Format Specification" v1.01: a fixed-size 28-byte "DSD " chunk, followed
/// immediately by an "fmt " chunk describing the DSD stream, followed by a
/// "data" chunk holding the raw audio payload, optionally followed by a
/// standard ID3v2 tag (the file's only metadata — DSF doesn't define its
/// own tag format). Every multi-byte numeric field in the file is
/// little-endian ("LSB first", per the spec).
///
/// Unlike `RIFFStream`/`AIFFStream`, this isn't a generic chunk-list parser
/// — DSF's three audio chunks always appear in this fixed order at fixed
/// offsets (the DSD chunk's own size is spec-mandated to always be exactly
/// 28 bytes), so there's nothing to "walk". The only chunk this app ever
/// needs to locate or modify is the trailing metadata one; the DSD/fmt/data
/// chunks are always treated as one opaque prefix, preserved byte-for-byte.
enum DSFStream {
    /// Byte offset of the "fmt " chunk — always right after the DSD
    /// chunk's fixed 28-byte size.
    static let fmtChunkStart = 28

    /// The DSD chunk's own two mutable fields, plus where the fmt/data
    /// chunks (collectively "the audio prefix") end — either the existing
    /// metadata pointer, or the current file length if there's no metadata
    /// chunk yet.
    struct Header {
        let totalFileSize: Int
        /// Absolute byte offset of the ID3v2 metadata chunk, or nil if the
        /// file doesn't have one yet.
        let metadataPointer: Int?
        /// Absolute byte offset where the "data" chunk's payload begins —
        /// confirms the fmt chunk's declared size actually lines up with a
        /// real "data" chunk before any offset gets trusted further.
        let dataChunkStart: Int
    }

    /// Parses and validates the DSD + fmt chunk headers, without touching
    /// the (potentially huge) data chunk payload itself.
    static func parseHeader(in bytes: [UInt8]) throws -> Header {
        guard bytes.count >= fmtChunkStart, matches(bytes, at: 0, "DSD ") else {
            throw TagWriteError.malformedFile("Missing DSD chunk signature")
        }
        guard readUInt64LE(bytes, at: 4) == 28 else {
            throw TagWriteError.malformedFile("Unexpected DSD chunk size")
        }
        let totalFileSize = Int(readUInt64LE(bytes, at: 12))
        let rawPointer = Int(readUInt64LE(bytes, at: 20))

        guard bytes.count >= fmtChunkStart + 12, matches(bytes, at: fmtChunkStart, "fmt ") else {
            throw TagWriteError.malformedFile("Missing fmt chunk signature")
        }
        // The fmt chunk's own "size of this chunk" field (spec: "usually
        // 52 bytes", i.e. not contractually fixed) is what actually
        // determines where the data chunk begins — never hardcode 52.
        let fmtChunkSize = Int(readUInt64LE(bytes, at: fmtChunkStart + 4))
        guard fmtChunkSize >= 12 else {
            throw TagWriteError.malformedFile("Implausible fmt chunk size")
        }
        let dataChunkStart = fmtChunkStart + fmtChunkSize
        guard bytes.count >= dataChunkStart + 4, matches(bytes, at: dataChunkStart, "data") else {
            throw TagWriteError.malformedFile("Missing data chunk signature")
        }

        guard rawPointer == 0 || (rawPointer >= dataChunkStart && rawPointer <= bytes.count) else {
            throw TagWriteError.malformedFile("Metadata chunk pointer out of range")
        }

        return Header(totalFileSize: totalFileSize,
                      metadataPointer: rawPointer == 0 ? nil : rawPointer,
                      dataChunkStart: dataChunkStart)
    }

    /// The fmt chunk's stream-shape fields, fixed offsets relative to
    /// `fmtChunkStart` per the spec's field table (present regardless of
    /// the chunk's own declared size, which only affects where trailing
    /// chunks begin).
    struct FormatInfo {
        let channelNum: Int
        let samplingFrequency: Int
        let bitsPerSample: Int
        let sampleCount: Int
    }

    static func parseFormatInfo(in bytes: [UInt8]) throws -> FormatInfo {
        // fmt content starts at fmtChunkStart+12 (after the 4-byte magic +
        // 8-byte chunk-size field): version(4) id(4) channelType(4)
        // channelNum(4) samplingFreq(4) bitsPerSample(4) sampleCount(8) ...
        guard bytes.count >= fmtChunkStart + 12 + 28 else {
            throw TagWriteError.malformedFile("Truncated fmt chunk")
        }
        let base = fmtChunkStart + 12
        return FormatInfo(
            channelNum: Int(readUInt32LE(bytes, at: base + 12)),
            samplingFrequency: Int(readUInt32LE(bytes, at: base + 16)),
            bitsPerSample: Int(readUInt32LE(bytes, at: base + 20)),
            sampleCount: Int(readUInt64LE(bytes, at: base + 24)))
    }

    // MARK: - Byte helpers

    private static func matches(_ bytes: [UInt8], at offset: Int, _ signature: String) -> Bool {
        Array(bytes[offset..<(offset + 4)]) == Array(signature.utf8)
    }

    static func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<4 {
            value |= UInt32(bytes[offset + i]) << (8 * i)
        }
        return value
    }

    static func readUInt64LE(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(bytes[offset + i]) << (8 * i)
        }
        return value
    }

    /// Overwrites 8 bytes in place at `offset` — used to patch the DSD
    /// chunk's total-file-size/metadata-pointer fields after a write,
    /// without touching anything else in the (already-correctly-sized)
    /// buffer.
    static func writeUInt64LE(_ value: UInt64, into bytes: inout [UInt8], at offset: Int) {
        for i in 0..<8 {
            bytes[offset + i] = UInt8((value >> (8 * i)) & 0xFF)
        }
    }
}
