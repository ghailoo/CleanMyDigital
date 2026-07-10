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
        guard let tag = try? ID3TagEditor().read(mp3: Data(id3ChunkData)) else { return }

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
}
