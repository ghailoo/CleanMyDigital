//
//  APETagWriter.swift
//  CleanMyDigital
//

import Foundation

/// Rewrites a Monkey's Audio (.ape) file's trailing APEv2 tag, leaving the
/// audio and any trailing ID3v1 block byte-for-byte intact — the same shape
/// as `WavPackTagWriter`, since both formats are "audio, then an APEv2 tag,
/// then optionally ID3v1".
enum APETagWriter {
    static func write(_ changes: TagChanges, to url: URL) throws {
        let bytes = [UInt8](try Data(contentsOf: url))

        // Confirms this really is a Monkey's Audio file before rewriting
        // anything, the same up-front check WavPack/DSF make.
        _ = try APEStream.parseHeader(in: bytes)

        let located = try APEv2Tag.locate(in: bytes)
        let id3v1Range = APEv2Tag.trailingID3v1Range(in: bytes)

        let audioPrefixEnd = located?.range.lowerBound ?? id3v1Range?.lowerBound ?? bytes.count
        var output = Array(bytes[0..<audioPrefixEnd])
        output.append(contentsOf: APEv2Tag.build(
            items: APEv2TagBuilder.build(changes: changes, existing: located?.items ?? [])))
        output.append(contentsOf: id3v1Range.map { Array(bytes[$0]) } ?? [])

        try TagWriteHelpers.atomicReplace(Data(output), at: url)
    }
}
