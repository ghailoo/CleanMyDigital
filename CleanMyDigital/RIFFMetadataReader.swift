//
//  RIFFMetadataReader.swift
//  CleanMyDigital
//

import Foundation

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
        if let dataChunk = chunks.first(where: { $0.id.uppercased() == "DATA" }) {
            metadata.audioDataSize = Int64(dataChunk.data.count)
        }

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
        if let id3Chunk = chunks.first(where: { RIFFStream.isID3Chunk($0) }) {
            ID3ChunkMetadata.merge(id3ChunkData: id3Chunk.data, into: &metadata)
        }

        return metadata
    }
}
