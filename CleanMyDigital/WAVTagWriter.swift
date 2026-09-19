//
//  WAVTagWriter.swift
//  CleanMyDigital
//

import Foundation
import ID3TagEditor

/// Writes tags into a WAV file the way taggers like Mp3tag do, for maximum
/// compatibility: once into a LIST/INFO chunk (plain text sub-chunks) and
/// once into an embedded "id3 " chunk (a full ID3v2.3 tag, which is also
/// where artwork goes — RIFF INFO has no picture field). All other chunks
/// (fmt , data, and anything else) are preserved byte-for-byte.
enum WAVTagWriter {
    private static let infoTitle = "INAM"
    private static let infoArtist = "IART"
    private static let infoAlbum = "IPRD"
    private static let infoYear = "ICRD"
    private static let infoGenre = "IGNR"
    private static let infoTrackNumber = "ITRK"

    static func write(_ changes: TagChanges, to url: URL) throws {
        let bytes = [UInt8](try Data(contentsOf: url))
        var chunks = try RIFFStream.parseChunks(in: bytes)

        let listIndex = chunks.firstIndex { RIFFStream.isListInfoChunk($0) }
        let newListData = mergeListInfo(existing: listIndex.map { chunks[$0].data }, changes: changes)
        if let listIndex {
            chunks[listIndex] = RIFFChunk(id: chunks[listIndex].id, data: newListData)
        } else {
            chunks.append(RIFFChunk(id: "LIST", data: newListData))
        }

        let id3Index = chunks.firstIndex { RIFFStream.isID3Chunk($0) }
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
            // what an "id3 " RIFF chunk holds.
            newID3Data = try editor.write(tag: newTag, mp3: Data())
        } catch {
            throw TagWriteError.underlying(error)
        }
        if let id3Index {
            chunks[id3Index] = RIFFChunk(id: chunks[id3Index].id, data: [UInt8](newID3Data))
        } else {
            chunks.append(RIFFChunk(id: "id3 ", data: [UInt8](newID3Data)))
        }

        try TagWriteHelpers.atomicReplace(RIFFStream.buildFile(chunks: chunks), at: url)
    }

    // MARK: - LIST/INFO

    private static func mergeListInfo(existing: [UInt8]?, changes: TagChanges) -> [UInt8] {
        var fields = existing.map(RIFFStream.parseListInfoFields) ?? []

        func hasField(_ id: String) -> Bool { fields.contains { $0.id == id } }
        func addIfMissing(_ id: String, _ value: String?) {
            guard let value, !value.isEmpty, !hasField(id) else { return }
            fields.append((id: id, value: value))
        }

        let ids: [(MetadataField, String)] = [
            (.title, infoTitle), (.artist, infoArtist), (.album, infoAlbum),
            (.year, infoYear), (.genre, infoGenre), (.trackNumber, infoTrackNumber),
        ]
        for (field, id) in ids where changes.replaces(field) {
            fields.removeAll { $0.id == id }
        }
        addIfMissing(infoTitle, changes.title)
        addIfMissing(infoArtist, changes.artist)
        addIfMissing(infoAlbum, changes.album)
        addIfMissing(infoYear, changes.year)
        addIfMissing(infoGenre, changes.genre)
        addIfMissing(infoTrackNumber, changes.trackNumber)

        var data = Array("INFO".utf8)
        for field in fields {
            data.append(contentsOf: RIFFStream.fourCC(field.id))
            var valueBytes = Array(field.value.utf8)
            valueBytes.append(0) // NUL-terminated, per RIFF INFO convention
            RIFFStream.appendUInt32LE(valueBytes.count, to: &data)
            data.append(contentsOf: valueBytes)
            if valueBytes.count % 2 == 1 { data.append(0) }
        }
        return data
    }
}
