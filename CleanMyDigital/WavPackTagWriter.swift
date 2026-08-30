//
//  WavPackTagWriter.swift
//  CleanMyDigital
//

import Foundation

/// Writes tags into a WavPack (.wv) file by rewriting its trailing APEv2
/// tag — same "find/replace an embedded metadata block, preserve
/// everything else byte-for-byte" shape as `DSFTagWriter`, except the tag
/// format itself is APEv2 rather than ID3 (see `APEv2Tag`/
/// `APEv2TagBuilder`). The run of "wvpk" audio blocks before the tag —
/// however many there are — is never parsed here beyond confirming the
/// file actually starts with one; it's carried over as one opaque byte
/// range, exactly like DSF's DSD+fmt+data prefix. Unlike DSF, there's no
/// header field anywhere that needs patching afterward (no "total file
/// size" or "metadata pointer" to update) — a WavPack file's tag is purely
/// self-delimiting from the end of file, so appending the new tag (and any
/// preserved ID3v1 trailer) after the unchanged audio prefix is the entire
/// operation.
enum WavPackTagWriter {
    static func write(_ changes: TagChanges, to url: URL) throws {
        let bytes = [UInt8](try Data(contentsOf: url))

        // Confirms this is actually a WavPack file before touching
        // anything — same up-front sanity check `DSFTagWriter` makes via
        // `DSFStream.parseHeader` for DSF. The header's fields themselves
        // aren't needed for writing, only for reading (duration/bitrate).
        _ = try WavPackStream.parseFirstBlockHeader(in: bytes)

        let located = try APEv2Tag.locate(in: bytes)
        // A bare trailing ID3v1 block (no APE tag) is possible too — the
        // spec supports either tag independently — and must still be
        // preserved and kept last even when there's no existing APE tag
        // to anchor its position against.
        let id3v1Range = APEv2Tag.trailingID3v1Range(in: bytes)

        let audioPrefixEnd = located?.range.lowerBound ?? id3v1Range?.lowerBound ?? bytes.count
        let audioPrefix = Array(bytes[0..<audioPrefixEnd])
        let id3v1Trailer = id3v1Range.map { Array(bytes[$0]) } ?? []

        let newItems = APEv2TagBuilder.build(changes: changes, existing: located?.items ?? [])
        let newTagBytes = APEv2Tag.build(items: newItems)

        var output = audioPrefix
        output.append(contentsOf: newTagBytes)
        output.append(contentsOf: id3v1Trailer)

        try TagWriteHelpers.atomicReplace(Data(output), at: url)
    }
}
