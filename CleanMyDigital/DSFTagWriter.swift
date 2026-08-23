//
//  DSFTagWriter.swift
//  CleanMyDigital
//

import Foundation
import ID3TagEditor

/// Writes tags into a DSF (DSD Stream File) by editing its trailing ID3v2
/// metadata chunk directly — same "find/replace an embedded metadata
/// chunk, preserve everything else byte-for-byte" shape as
/// `WAVTagWriter`/`AIFFTagWriter`, not the FLAC/M4A writers' full-file
/// re-export approach. This matters more here than anywhere else in the
/// app: DSD audio must never be re-encoded or even touched, only copied —
/// so the DSD/fmt/data chunks are handled as one opaque byte range that's
/// never parsed beyond its own header, just carried over unchanged.
enum DSFTagWriter {
    static func write(_ changes: TagChanges, to url: URL) throws {
        let bytes = [UInt8](try Data(contentsOf: url))
        let header = try DSFStream.parseHeader(in: bytes)

        // Everything up to the existing metadata chunk (or, if there isn't
        // one yet, the whole current file) is the DSD+fmt+data audio
        // prefix — copied verbatim, never re-parsed or re-encoded.
        let audioPrefixEnd = header.metadataPointer ?? bytes.count
        guard audioPrefixEnd <= bytes.count else {
            throw TagWriteError.malformedFile("Metadata chunk pointer out of range")
        }
        var audioPrefix = Array(bytes[0..<audioPrefixEnd])

        let editor = ID3TagEditor()
        let existingTag: ID3Tag?
        if let pointer = header.metadataPointer {
            existingTag = try? editor.read(mp3: Data(bytes[pointer...]))
        } else {
            existingTag = nil
        }

        let newTag = ID3TagBuilder.build(changes: changes, existing: existingTag)
        let newID3Data: Data
        do {
            // No audio bytes to hand it — `mp3: Data()` makes ID3TagEditor
            // emit just the raw tag (header + frames), which is exactly
            // what a DSF metadata chunk holds.
            newID3Data = try editor.write(tag: newTag, mp3: Data())
        } catch {
            throw TagWriteError.underlying(error)
        }

        // Patch the DSD chunk's two mutable fields in place — total file
        // size and the metadata pointer, which now always points right
        // after the (unchanged-length) audio prefix.
        let newTotalFileSize = audioPrefix.count + newID3Data.count
        DSFStream.writeUInt64LE(UInt64(newTotalFileSize), into: &audioPrefix, at: 12)
        DSFStream.writeUInt64LE(UInt64(audioPrefix.count), into: &audioPrefix, at: 20)

        var output = audioPrefix
        output.append(contentsOf: [UInt8](newID3Data))

        try TagWriteHelpers.atomicReplace(Data(output), at: url)
    }
}
