//
//  MP3TagWriter.swift
//  CleanMyDigital
//

import Foundation
import ID3TagEditor

/// Writes tags into an MP3's ID3v2.3 tag using ID3TagEditor and
/// `ID3TagBuilder`'s existing-frame-preserving merge.
enum MP3TagWriter {
    static func write(_ changes: TagChanges, to url: URL) throws {
        let originalData = try Data(contentsOf: url)
        let editor = ID3TagEditor()

        let existingTag: ID3Tag?
        do {
            existingTag = try editor.read(mp3: originalData)
        } catch {
            throw TagWriteError.malformedFile("Existing ID3 tag couldn't be parsed")
        }

        let newTag = ID3TagBuilder.build(changes: changes, existing: existingTag)

        let newData: Data
        do {
            newData = try editor.write(tag: newTag, mp3: originalData)
        } catch {
            throw TagWriteError.underlying(error)
        }
        try TagWriteHelpers.atomicReplace(newData, at: url)
    }
}
