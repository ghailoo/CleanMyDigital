//
//  FLACTagWriter.swift
//  CleanMyDigital
//

import Foundation

/// Writes tags into a FLAC file by editing its metadata-block chain
/// directly — no dependency needed, and it guarantees the audio frames are
/// preserved byte-for-byte, since we never touch anything past the last
/// metadata block.
///
/// FLAC layout: "fLaC" magic, then a sequence of METADATA_BLOCKs (1 byte
/// type + last-block flag, 3-byte big-endian length, then the block data),
/// terminated by the block with its last-block bit set, followed by the
/// audio frames. A minority of files in the wild (depending on rip source)
/// have a nonstandard ID3v2 tag prepended before the "fLaC" signature —
/// that whole prefix is preserved byte-for-byte and never parsed, since
/// AVFoundation already reads it and we'd rather not touch data we don't
/// need to understand.
enum FLACTagWriter {
    static func write(_ changes: TagChanges, to url: URL) throws {
        let bytes = [UInt8](try Data(contentsOf: url))

        let streamStart = try FLACStream.streamStart(in: bytes)
        let id3Prefix = Array(bytes[0..<streamStart])
        let (blocks, audioStart) = try FLACStream.parseBlocks(in: bytes, streamStart: streamStart)
        let audioData = Array(bytes[audioStart...])

        var streamInfo: [UInt8]?
        var vorbisComment: [UInt8]?
        var pictures: [[UInt8]] = []
        var others: [FLACMetadataBlock] = []

        for block in blocks {
            switch block.type {
            case FLACBlockType.streamInfo:
                streamInfo = block.data
            case FLACBlockType.vorbisComment:
                vorbisComment = block.data
            case FLACBlockType.picture:
                pictures.append(block.data)
            case FLACBlockType.padding:
                continue // dropped — sizes change anyway, no need to preserve reserve space
            default:
                others.append(block)
            }
        }

        guard let streamInfo else {
            throw TagWriteError.malformedFile("Missing STREAMINFO block")
        }

        let newVorbisComment = mergeVorbisComment(existing: vorbisComment, changes: changes)

        var newPictures = pictures
        if let artworkJPEG = changes.artworkJPEG,
           !pictures.contains(where: { FLACStream.pictureType(of: $0) == FLACBlockType.frontCoverPictureType }) {
            newPictures.append(makePictureBlock(jpeg: artworkJPEG))
        }

        // STREAMINFO must be first per spec; order after that doesn't
        // matter, so keep VORBIS_COMMENT/PICTUREs up front and preserve
        // everything else (SEEKTABLE, CUESHEET, APPLICATION…) as-is.
        var outputBlocks: [FLACMetadataBlock] = [
            FLACMetadataBlock(type: FLACBlockType.streamInfo, data: streamInfo),
            FLACMetadataBlock(type: FLACBlockType.vorbisComment, data: newVorbisComment),
        ]
        outputBlocks.append(contentsOf: newPictures.map { FLACMetadataBlock(type: FLACBlockType.picture, data: $0) })
        outputBlocks.append(contentsOf: others)

        var output = [UInt8]()
        output.append(contentsOf: id3Prefix)
        output.append(contentsOf: [0x66, 0x4C, 0x61, 0x43])
        for (index, block) in outputBlocks.enumerated() {
            let isLast = index == outputBlocks.count - 1
            output.append(isLast ? (block.type | 0x80) : block.type)
            let length = block.data.count
            output.append(UInt8((length >> 16) & 0xFF))
            output.append(UInt8((length >> 8) & 0xFF))
            output.append(UInt8(length & 0xFF))
            output.append(contentsOf: block.data)
        }
        output.append(contentsOf: audioData)

        try TagWriteHelpers.atomicReplace(Data(output), at: url)
    }

    private static func mergeVorbisComment(existing: [UInt8]?, changes: TagChanges) -> [UInt8] {
        var vendor: [UInt8]
        var comments: [String]
        if let existing {
            (vendor, comments) = FLACStream.parseVorbisComment(existing)
        } else {
            vendor = Array("CleanMyDigital".utf8)
            comments = []
        }

        func hasField(_ name: String) -> Bool {
            comments.contains { $0.uppercased().hasPrefix(name.uppercased() + "=") }
        }
        func addIfMissing(_ name: String, _ value: String?) {
            guard let value, !value.isEmpty, !hasField(name) else { return }
            comments.append("\(name)=\(value)")
        }

        addIfMissing("TITLE", changes.title)
        addIfMissing("ARTIST", changes.artist)
        if changes.replacesAlbum, changes.album?.isEmpty == false {
            comments.removeAll { $0.uppercased().hasPrefix("ALBUM=") }
        }
        addIfMissing("ALBUM", changes.album)
        addIfMissing("DATE", changes.year)
        addIfMissing("GENRE", changes.genre)
        addIfMissing("TRACKNUMBER", changes.trackNumber)

        var output = [UInt8]()
        func appendUInt32LE(_ value: Int) {
            output.append(UInt8(value & 0xFF))
            output.append(UInt8((value >> 8) & 0xFF))
            output.append(UInt8((value >> 16) & 0xFF))
            output.append(UInt8((value >> 24) & 0xFF))
        }
        appendUInt32LE(vendor.count)
        output.append(contentsOf: vendor)
        appendUInt32LE(comments.count)
        for comment in comments {
            let bytes = Array(comment.utf8)
            appendUInt32LE(bytes.count)
            output.append(contentsOf: bytes)
        }
        return output
    }

    // MARK: - PICTURE (big-endian)

    private static func makePictureBlock(jpeg: Data) -> [UInt8] {
        var output = [UInt8]()
        func appendUInt32BE(_ value: Int) {
            output.append(UInt8((value >> 24) & 0xFF))
            output.append(UInt8((value >> 16) & 0xFF))
            output.append(UInt8((value >> 8) & 0xFF))
            output.append(UInt8(value & 0xFF))
        }
        appendUInt32BE(FLACBlockType.frontCoverPictureType)
        let mime = Array("image/jpeg".utf8)
        appendUInt32BE(mime.count)
        output.append(contentsOf: mime)
        appendUInt32BE(0) // description
        appendUInt32BE(0) // width unknown
        appendUInt32BE(0) // height unknown
        appendUInt32BE(0) // color depth unknown
        appendUInt32BE(0) // colors used (non-indexed)
        let jpegBytes = [UInt8](jpeg)
        appendUInt32BE(jpegBytes.count)
        output.append(contentsOf: jpegBytes)
        return output
    }
}
