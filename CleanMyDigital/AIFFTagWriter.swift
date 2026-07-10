//
//  AIFFTagWriter.swift
//  CleanMyDigital
//

import Foundation
import ID3TagEditor

/// Writes tags into an AIFF/AIFC file. Unlike WAV there's no established
/// INFO-chunk convention worth writing for AIFF — the convention is a
/// single "ID3 " chunk holding a full ID3v2.3 tag, built the same way
/// `WAVTagWriter` builds its "id3 " chunk. Every other chunk (COMM, SSND,
/// and anything else) is preserved byte-for-byte.
enum AIFFTagWriter {
    static func write(_ changes: TagChanges, to url: URL) throws {
        let bytes = [UInt8](try Data(contentsOf: url))
        let (formType, originalChunks) = try AIFFStream.parseChunks(in: bytes)
        var chunks = originalChunks

        let id3Index = chunks.firstIndex { AIFFStream.isID3Chunk($0) }
        let editor = ID3TagEditor()
        let existingTag: ID3Tag?
        if let id3Index {
            existingTag = try? editor.read(mp3: Data(chunks[id3Index].data))
        } else {
            existingTag = nil
        }
        let newTag = ID3TagBuilder.build(changes: changes, existing: existingTag)
        let newID3Data: Data
        do {
            // No audio bytes to hand it — `mp3: Data()` makes ID3TagEditor
            // emit just the raw tag (header + frames), which is exactly
            // what an "ID3 " AIFF chunk holds.
            newID3Data = try editor.write(tag: newTag, mp3: Data())
        } catch {
            throw TagWriteError.underlying(error)
        }
        if let id3Index {
            chunks[id3Index] = AIFFChunk(id: chunks[id3Index].id, data: [UInt8](newID3Data))
        } else {
            chunks.append(AIFFChunk(id: "ID3 ", data: [UInt8](newID3Data)))
        }

        try TagWriteHelpers.atomicReplace(AIFFStream.buildFile(chunks: chunks, formType: formType), at: url)
    }
}
