//
//  RIFFMetadataReader.swift
//  CleanMyDigital
//

import Foundation
import ID3TagEditor

/// Reads a WAV's LIST/INFO and "id3 " chunks natively.
///
/// AVFoundation's WAV support is inconsistent, confirmed empirically: it
/// reads an "id3 " chunk's frames just fine, but LIST/INFO fields surface
/// under an undocumented "caaf/info-*" identifier namespace scanning
/// doesn't look for, and non-standard INFO tags like ITRK may not be
/// exposed at all. This reader gives scanning (and post-write
/// re-inspection) a reliable, deterministic source for both chunk types
/// instead of depending on AVFoundation's partial translation.
enum RIFFMetadataReader {
    static func read(contentsOf url: URL) throws -> NativeAudioMetadata {
        let bytes = [UInt8](try Data(contentsOf: url))
        let chunks = try RIFFStream.parseChunks(in: bytes)

        var metadata = NativeAudioMetadata()

        if let list = chunks.first(where: { RIFFStream.isListInfoChunk($0) }) {
            let fields = RIFFStream.parseListInfoFields(list.data)
            func value(for id: String) -> String? { fields.first { $0.id == id }?.value }
            metadata.title = value(for: "INAM")
            metadata.artist = value(for: "IART")
            metadata.album = value(for: "IPRD")
            metadata.year = value(for: "ICRD")
            metadata.genre = value(for: "IGNR")
            metadata.trackNumber = value(for: "ITRK")
        }

        // The id3 chunk is the richer, more standard source — its values
        // win over LIST/INFO wherever both are present.
        if let id3Chunk = chunks.first(where: { RIFFStream.isID3Chunk($0) }),
           let tag = try? ID3TagEditor().read(mp3: Data(id3Chunk.data)) {
            if let f = tag.frames[.title] as? ID3FrameWithStringContent { metadata.title = f.content }
            if let f = tag.frames[.artist] as? ID3FrameWithStringContent { metadata.artist = f.content }
            if let f = tag.frames[.album] as? ID3FrameWithStringContent { metadata.album = f.content }
            if let f = tag.frames[.recordingYear] as? ID3FrameWithIntegerContent, let value = f.value {
                metadata.year = String(value)
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

        return metadata
    }
}
