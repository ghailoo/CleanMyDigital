//
//  AIFFMetadataReader.swift
//  CleanMyDigital
//

import Foundation

/// Reads an AIFF/AIFC's "ID3 " chunk natively.
///
/// AVFoundation reads AIFF's ID3 chunk fine on a freshly-opened file
/// (confirmed empirically, same as WAV's "id3 " chunk) — but it can serve
/// stale metadata when re-reading a URL it already opened earlier in the
/// same process, which is exactly what happens right after "Apply to File"
/// writes new tags and `LibraryScanner` re-inspects that same file. This
/// reader gives that re-inspection (and scanning in general) a source that
/// always reflects what's actually on disk.
enum AIFFMetadataReader {
    static func read(contentsOf url: URL) throws -> NativeAudioMetadata {
        let bytes = [UInt8](try Data(contentsOf: url))
        let (_, chunks) = try AIFFStream.parseChunks(in: bytes)

        var metadata = NativeAudioMetadata()
        if let id3Chunk = chunks.first(where: { AIFFStream.isID3Chunk($0) }) {
            ID3ChunkMetadata.merge(id3ChunkData: id3Chunk.data, into: &metadata)
        }
        if let soundChunk = chunks.first(where: { $0.id.uppercased() == "SSND" }) {
            metadata.audioDataSize = Int64(soundChunk.data.count)
        }
        return metadata
    }
}
