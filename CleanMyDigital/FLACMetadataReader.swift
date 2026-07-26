//
//  FLACMetadataReader.swift
//  CleanMyDigital
//

import Foundation

/// Reads a FLAC's VORBIS_COMMENT and PICTURE blocks natively.
///
/// AVFoundation can't see any of this for FLACs with a nonstandard ID3v2
/// prefix — confirmed empirically: it reports the file's only available
/// metadata format as `org.id3` and returns zero items even when
/// `org.xiph.vorbis-comment` is requested explicitly. It treats the whole
/// file as ID3-only and never looks past the wrapper at the FLAC-native
/// blocks. This reader exists so scanning (and post-write re-inspection)
/// stays accurate for those files instead of leaving them flagged forever.
enum FLACMetadataReader {
    static func read(contentsOf url: URL) throws -> NativeAudioMetadata {
        let bytes = [UInt8](try Data(contentsOf: url))
        let streamStart = try FLACStream.streamStart(in: bytes)
        let (blocks, audioStart) = try FLACStream.parseBlocks(in: bytes, streamStart: streamStart)

        var vorbisComment: [UInt8]?
        var pictures: [[UInt8]] = []
        for block in blocks {
            switch block.type {
            case FLACBlockType.vorbisComment:
                vorbisComment = block.data
            case FLACBlockType.picture:
                pictures.append(block.data)
            default:
                break
            }
        }

        var metadata = NativeAudioMetadata()
        metadata.audioDataSize = Int64(bytes.count - audioStart)
        if let vorbisComment {
            let (_, comments) = FLACStream.parseVorbisComment(vorbisComment)
            func value(for field: String) -> String? {
                let prefix = field.uppercased() + "="
                for comment in comments where comment.uppercased().hasPrefix(prefix) {
                    return String(comment.dropFirst(prefix.count))
                }
                return nil
            }
            metadata.title = value(for: "TITLE")
            metadata.artist = value(for: "ARTIST")
            metadata.album = value(for: "ALBUM")
            metadata.year = value(for: "DATE")
            metadata.genre = value(for: "GENRE")
            if let position = value(for: "TRACKNUMBER") {
                if let total = value(for: "TRACKTOTAL") ?? value(for: "TOTALTRACKS"), !total.isEmpty {
                    metadata.trackNumber = "\(position)/\(total)"
                } else {
                    metadata.trackNumber = position
                }
            }
        }

        let frontCover = pictures.first { FLACStream.pictureType(of: $0) == FLACBlockType.frontCoverPictureType }
            ?? pictures.first
        if let frontCover {
            metadata.artworkData = imageData(fromPictureBlock: frontCover)
        }

        return metadata
    }

    /// Extracts the raw image bytes from a PICTURE block: 4 fields
    /// (type, MIME length + string, description length + string), then
    /// width/height/depth/colors (4 bytes each, unused here), then the
    /// image data length + bytes.
    private static func imageData(fromPictureBlock block: [UInt8]) -> Data? {
        var offset = 0
        func readUInt32BE() -> Int? {
            guard offset + 4 <= block.count else { return nil }
            let value = Int(block[offset]) << 24 | Int(block[offset + 1]) << 16
                | Int(block[offset + 2]) << 8 | Int(block[offset + 3])
            offset += 4
            return value
        }

        guard readUInt32BE() != nil else { return nil } // picture type
        guard let mimeLength = readUInt32BE(), offset + mimeLength <= block.count else { return nil }
        offset += mimeLength
        guard let descriptionLength = readUInt32BE(), offset + descriptionLength <= block.count else { return nil }
        offset += descriptionLength
        guard readUInt32BE() != nil else { return nil } // width
        guard readUInt32BE() != nil else { return nil } // height
        guard readUInt32BE() != nil else { return nil } // color depth
        guard readUInt32BE() != nil else { return nil } // colors used
        guard let dataLength = readUInt32BE(), offset + dataLength <= block.count else { return nil }
        return Data(block[offset..<(offset + dataLength)])
    }
}
