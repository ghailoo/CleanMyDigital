//
//  APEStream.swift
//  CleanMyDigital
//

import Foundation

/// Monkey's Audio (.ape) header parsing — just enough to confirm the file
/// really is one and to compute its duration. Tags live in a trailing
/// APEv2 block (`APEv2Tag`), exactly as in WavPack, so nothing here deals
/// with metadata.
enum APEStream {
    private static let signature: [UInt8] = Array("MAC ".utf8)
    /// 3.98 is where the current APE_DESCRIPTOR + APE_HEADER layout begins.
    /// Older files (3.97 and down) put a different, version-dependent
    /// header right after the signature; this reader doesn't decode those,
    /// so they parse as a valid file with no duration rather than a
    /// malformed one — the tags, which is what this app edits, are
    /// unaffected either way.
    private static let firstDescriptorVersion: UInt16 = 3980

    struct Header {
        let version: UInt16
        /// Nil for pre-3.98 files, whose header layout isn't parsed.
        let totalBlocks: UInt64?
        let sampleRate: UInt32?

        var duration: TimeInterval? {
            guard let totalBlocks, let sampleRate, sampleRate > 0, totalBlocks > 0 else { return nil }
            return Double(totalBlocks) / Double(sampleRate)
        }
    }

    static func parseHeader(in bytes: [UInt8]) throws -> Header {
        guard bytes.count >= 8, matches(bytes, at: 0, signature) else {
            throw TagWriteError.malformedFile("Missing Monkey's Audio signature")
        }
        let version = readUInt16LE(bytes, at: 4)
        guard version >= firstDescriptorVersion else {
            return Header(version: version, totalBlocks: nil, sampleRate: nil)
        }

        // APE_DESCRIPTOR: the header block starts `descriptorBytes` in.
        let descriptorBytes = Int(readUInt32LE(bytes, at: 8))
        guard descriptorBytes >= 52, bytes.count >= descriptorBytes + 24 else {
            throw TagWriteError.malformedFile("Truncated Monkey's Audio header")
        }

        // APE_HEADER, from its start: blocks per frame (+4), blocks in the
        // final frame (+8), frame count (+12), sample rate (+20).
        let blocksPerFrame = UInt64(readUInt32LE(bytes, at: descriptorBytes + 4))
        let finalFrameBlocks = UInt64(readUInt32LE(bytes, at: descriptorBytes + 8))
        let totalFrames = UInt64(readUInt32LE(bytes, at: descriptorBytes + 12))
        let sampleRate = readUInt32LE(bytes, at: descriptorBytes + 20)

        let totalBlocks = totalFrames == 0 ? 0 : (totalFrames - 1) * blocksPerFrame + finalFrameBlocks
        return Header(version: version, totalBlocks: totalBlocks, sampleRate: sampleRate)
    }

    private static func matches(_ bytes: [UInt8], at offset: Int, _ signature: [UInt8]) -> Bool {
        guard bytes.count >= offset + signature.count else { return false }
        return Array(bytes[offset..<(offset + signature.count)]) == signature
    }

    private static func readUInt16LE(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }
}
