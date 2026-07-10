//
//  FLACStream.swift
//  CleanMyDigital
//

import Foundation

/// A parsed FLAC METADATA_BLOCK: type (last-block flag already stripped)
/// plus its raw data.
struct FLACMetadataBlock {
    let type: UInt8
    let data: [UInt8]
}

enum FLACBlockType {
    static let streamInfo: UInt8 = 0
    static let padding: UInt8 = 1
    static let vorbisComment: UInt8 = 4
    static let picture: UInt8 = 6
    static let frontCoverPictureType = 3
}

/// Shared low-level FLAC parsing: locating the "fLaC" signature (skipping a
/// nonstandard prepended ID3v2 tag some rips have) and walking the
/// METADATA_BLOCK chain. Used by both `FLACTagWriter` (writing) and
/// `FLACMetadataReader` (scanning), so the two never drift apart on what
/// counts as a valid FLAC stream.
enum FLACStream {
    /// Locates where the FLAC stream ("fLaC" + metadata blocks) begins in
    /// `bytes`, skipping a leading ID3v2 tag if present. Throws
    /// `TagWriteError.malformedFile` if there's no "fLaC" signature at that
    /// position.
    static func streamStart(in bytes: [UInt8]) throws -> Int {
        let start = id3PrefixLength(in: bytes) ?? 0
        guard bytes.count >= start + 4,
              bytes[start] == 0x66, bytes[start + 1] == 0x4C,
              bytes[start + 2] == 0x61, bytes[start + 3] == 0x43
        else {
            throw TagWriteError.malformedFile("Missing fLaC signature")
        }
        return start
    }

    /// Parses the METADATA_BLOCK chain starting right after the "fLaC"
    /// signature at `streamStart`. Returns the blocks in file order and the
    /// byte offset where the audio frames begin.
    static func parseBlocks(
        in bytes: [UInt8], streamStart: Int
    ) throws -> (blocks: [FLACMetadataBlock], audioStart: Int) {
        var blocks: [FLACMetadataBlock] = []
        var offset = streamStart + 4
        while offset + 4 <= bytes.count {
            let headerByte = bytes[offset]
            let isLast = (headerByte & 0x80) != 0
            let type = headerByte & 0x7F
            let length = Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let dataStart = offset + 4
            let dataEnd = dataStart + length
            guard dataEnd <= bytes.count else {
                throw TagWriteError.malformedFile("Truncated metadata block")
            }
            blocks.append(FLACMetadataBlock(type: type, data: Array(bytes[dataStart..<dataEnd])))
            offset = dataEnd
            if isLast {
                return (blocks, offset)
            }
        }
        throw TagWriteError.malformedFile("Metadata block chain never terminated")
    }

    /// If `bytes` starts with "ID3", returns the byte length of that ID3v2
    /// tag (header + content + optional footer) so the FLAC stream can be
    /// located right after it. Returns nil for a standard file that starts
    /// straight with "fLaC".
    static func id3PrefixLength(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 10, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 else {
            return nil
        }
        // bytes[3...4] = version, unused here since we never parse the content.
        let flags = bytes[5]
        let hasFooter = (flags & 0x10) != 0
        // Tag size is a syncsafe 28-bit integer: 4 bytes, 7 significant bits each.
        let size = bytes[6...9].reduce(0) { ($0 << 7) | Int($1 & 0x7F) }
        let length = 10 + size + (hasFooter ? 10 : 0)
        guard length >= 10, bytes.count >= length else { return nil }
        return length
    }

    /// The picture-type field (first 4 bytes, big-endian) of a PICTURE block.
    static func pictureType(of block: [UInt8]) -> Int? {
        guard block.count >= 4 else { return nil }
        return Int(block[0]) << 24 | Int(block[1]) << 16 | Int(block[2]) << 8 | Int(block[3])
    }

    // MARK: - VORBIS_COMMENT (little-endian, unlike the rest of FLAC)

    /// Parses a VORBIS_COMMENT block's vendor string and "FIELD=value"
    /// comment strings.
    static func parseVorbisComment(_ data: [UInt8]) -> (vendor: [UInt8], comments: [String]) {
        var offset = 0
        func readUInt32LE() -> Int {
            guard offset + 4 <= data.count else { return 0 }
            let value = Int(data[offset]) | Int(data[offset + 1]) << 8
                | Int(data[offset + 2]) << 16 | Int(data[offset + 3]) << 24
            offset += 4
            return value
        }

        let vendorLength = readUInt32LE()
        let vendorEnd = min(offset + max(vendorLength, 0), data.count)
        let vendor = Array(data[offset..<vendorEnd])
        offset = vendorEnd

        let commentCount = readUInt32LE()
        var comments: [String] = []
        if commentCount > 0 {
            for _ in 0..<commentCount {
                let commentLength = readUInt32LE()
                let end = min(offset + max(commentLength, 0), data.count)
                guard offset <= end else { break }
                if let string = String(bytes: data[offset..<end], encoding: .utf8) {
                    comments.append(string)
                }
                offset = end
            }
        }
        return (vendor, comments)
    }
}
