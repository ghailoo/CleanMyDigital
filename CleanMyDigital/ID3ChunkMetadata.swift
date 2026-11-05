//
//  ID3ChunkMetadata.swift
//  CleanMyDigital
//

import Foundation
import ID3TagEditor

/// Maps a standalone ID3v2 tag blob (an "id3 "/"ID3 " chunk's raw bytes, no
/// audio attached) into `NativeAudioMetadata`. Shared by `RIFFMetadataReader`
/// (WAV) and `AIFFMetadataReader` (AIFF/AIFC), since both formats embed the
/// exact same kind of ID3v2.3 tag via `ID3TagBuilder`.
enum ID3ChunkMetadata {
    /// Parses `id3ChunkData` and merges its frames into `metadata` — id3
    /// values win over whatever `metadata` already has, matching how the
    /// WAV/AIFF writers treat the id3 chunk as the richer, more standard
    /// source (e.g. over WAV's LIST/INFO).
    static func merge(id3ChunkData: [UInt8], into metadata: inout NativeAudioMetadata) {
        // `ID3TagEditor` traps (rather than throwing) on a malformed tag, so
        // `try?` can't catch it — a damaged "ID3 " chunk in a WAV crashed the
        // whole scan. Structure is checked here first; anything suspect is
        // skipped, leaving the file's other metadata sources untouched.
        guard isWellFormed(id3ChunkData),
              let tag = try? ID3TagEditor().read(mp3: Data(id3ChunkData)) else { return }

        if let f = tag.frames[.title] as? ID3FrameWithStringContent { metadata.title = f.content }
        if let f = tag.frames[.artist] as? ID3FrameWithStringContent { metadata.artist = f.content }
        if let f = tag.frames[.album] as? ID3FrameWithStringContent { metadata.album = f.content }
        if let f = tag.frames[.recordingYear] as? ID3FrameWithIntegerContent, let value = f.value {
            metadata.year = String(value)
        }
        if let f = tag.frames[.contentGrouping] as? ID3FrameWithStringContent {
            metadata.grouping = f.content
        }
        if let f = tag.frames[.genre] as? ID3FrameGenre {
            metadata.genre = f.description ?? f.identifier.map { String(describing: $0) }
        }
        if let f = tag.frames[.trackPosition] as? ID3FramePartOfTotal {
            metadata.trackNumber = f.total.map { "\(f.part)/\($0)" } ?? String(f.part)
        }
        if let picture = tag.frames[.attachedPicture(.frontCover)] as? ID3FrameAttachedPicture {
            metadata.artworkData = picture.picture
        }
    }

    /// Walks the tag header and every frame header, checking that each one
    /// fits inside the data. Deliberately conservative: a tag this rejects
    /// is one the parser might trap on, and the cost of skipping it is a few
    /// missing fields, not a crash.
    static func isWellFormed(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 10, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 else { return false }
        let majorVersion = bytes[3]
        guard majorVersion >= 2, majorVersion <= 4 else { return false }

        // Size is syncsafe: 7 bits per byte.
        var tagSize = 0
        for byte in bytes[6..<10] {
            guard byte < 0x80 else { return false }
            tagSize = (tagSize << 7) | Int(byte)
        }
        let tagEnd = 10 + tagSize
        guard tagSize > 0, tagEnd <= bytes.count else { return false }

        // v2.2 frames have a 3-byte id and a 3-byte size; v2.3/v2.4 use 4 and 4
        // plus two flag bytes.
        let idLength = majorVersion == 2 ? 3 : 4
        let headerLength = majorVersion == 2 ? 6 : 10

        var offset = 10
        while offset + headerLength <= tagEnd {
            if bytes[offset] == 0 { return true }   // padding: the frames are done

            let idBytes = Array(bytes[offset..<(offset + idLength)])
            guard idBytes.allSatisfy({ ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x30 && $0 <= 0x39) }) else {
                return false
            }

            var frameSize = 0
            for byte in bytes[(offset + idLength)..<(offset + idLength + (majorVersion == 2 ? 3 : 4))] {
                // v2.4 sizes are syncsafe too, but a plain-byte read of a
                // syncsafe size is never larger, so this stays valid for both.
                frameSize = (frameSize << 8) | Int(byte)
            }
            let bodyStart = offset + headerLength
            guard frameSize > 0, bodyStart + frameSize <= tagEnd else { return false }

            // The frames that crashed: a language-tagged text frame whose body
            // is too short for its encoding byte plus 3-byte language code.
            let id = String(decoding: idBytes, as: UTF8.self)
            if ["COMM", "USLT", "COM", "ULT"].contains(id), frameSize < 5 { return false }

            offset = bodyStart + frameSize
        }
        return true
    }
}
