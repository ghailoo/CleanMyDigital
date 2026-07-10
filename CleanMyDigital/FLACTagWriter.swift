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
    private static let streamInfoType: UInt8 = 0
    private static let paddingType: UInt8 = 1
    private static let vorbisCommentType: UInt8 = 4
    private static let pictureType: UInt8 = 6
    private static let frontCoverPictureType = 3

    static func write(_ changes: TagChanges, to url: URL) throws {
        let bytes = [UInt8](try Data(contentsOf: url))

        let streamStart = id3PrefixLength(in: bytes) ?? 0
        guard bytes.count >= streamStart + 4,
              bytes[streamStart] == 0x66, bytes[streamStart + 1] == 0x4C,
              bytes[streamStart + 2] == 0x61, bytes[streamStart + 3] == 0x43
        else {
            throw TagWriteError.malformedFile("Missing fLaC signature")
        }
        let id3Prefix = Array(bytes[0..<streamStart])

        var blocks: [(type: UInt8, data: [UInt8])] = []
        var offset = streamStart + 4
        var audioStart: Int?
        while offset + 4 <= bytes.count {
            let headerByte = bytes[offset]
            let isLast = (headerByte & 0x80) != 0
            let type = headerByte & 0x7F
            let length = Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let dataStart = offset + 4
            let dataEnd = dataStart + length
            guard dataEnd <= bytes.count else {
                throw TagWriteError.malformedFile("Truncated metadata block")
            }
            blocks.append((type: type, data: Array(bytes[dataStart..<dataEnd])))
            offset = dataEnd
            if isLast {
                audioStart = offset
                break
            }
        }
        guard let audioStart else {
            throw TagWriteError.malformedFile("Metadata block chain never terminated")
        }
        let audioData = Array(bytes[audioStart...])

        var streamInfo: [UInt8]?
        var vorbisComment: [UInt8]?
        var pictures: [[UInt8]] = []
        var others: [(type: UInt8, data: [UInt8])] = []

        for block in blocks {
            switch block.type {
            case streamInfoType:
                streamInfo = block.data
            case vorbisCommentType:
                vorbisComment = block.data
            case pictureType:
                pictures.append(block.data)
            case paddingType:
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
           !pictures.contains(where: { picturePictureType(of: $0) == frontCoverPictureType }) {
            newPictures.append(makePictureBlock(jpeg: artworkJPEG))
        }

        // STREAMINFO must be first per spec; order after that doesn't
        // matter, so keep VORBIS_COMMENT/PICTUREs up front and preserve
        // everything else (SEEKTABLE, CUESHEET, APPLICATION…) as-is.
        var outputBlocks: [(type: UInt8, data: [UInt8])] = [(streamInfoType, streamInfo), (vorbisCommentType, newVorbisComment)]
        outputBlocks.append(contentsOf: newPictures.map { (pictureType, $0) })
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

    // MARK: - Nonstandard prepended ID3v2 tag

    /// If `bytes` starts with "ID3", returns the byte length of that ID3v2
    /// tag (header + content + optional footer) so the FLAC stream can be
    /// located right after it. Returns nil for a standard file that starts
    /// straight with "fLaC".
    private static func id3PrefixLength(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 10, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 else {
            return nil
        }
        // bytes[3...4] = version, unused here since we never parse the content.
        let flags = bytes[5]
        let hasFooter = (flags & 0x10) != 0
        // Tag size is a syncsafe 28-bit integer: 4 bytes, 7 significant bits each.
        let size = bytes[6...9].reduce(0) { ($0 << 7) | Int($1 & 0x7F) }
        let length = 10 + size + (hasFooter ? 10 : 0)
        guard length >= 10, bytes.count >= length else { return nil }
        return length
    }

    // MARK: - VORBIS_COMMENT (little-endian, unlike the rest of FLAC)

    private static func parseVorbisComment(_ data: [UInt8]) -> (vendor: [UInt8], comments: [String]) {
        var offset = 0
        func readUInt32LE() -> Int {
            guard offset + 4 <= data.count else { return 0 }
            let value = Int(data[offset]) | Int(data[offset + 1]) << 8
                | Int(data[offset + 2]) << 16 | Int(data[offset + 3]) << 24
            offset += 4
            return value
        }

        let vendorLength = readUInt32LE()
        let vendorEnd = min(offset + max(vendorLength, 0), data.count)
        let vendor = Array(data[offset..<vendorEnd])
        offset = vendorEnd

        let commentCount = readUInt32LE()
        var comments: [String] = []
        if commentCount > 0 {
            for _ in 0..<commentCount {
                let commentLength = readUInt32LE()
                let end = min(offset + max(commentLength, 0), data.count)
                guard offset <= end else { break }
                if let string = String(bytes: data[offset..<end], encoding: .utf8) {
                    comments.append(string)
                }
                offset = end
            }
        }
        return (vendor, comments)
    }

    private static func mergeVorbisComment(existing: [UInt8]?, changes: TagChanges) -> [UInt8] {
        var vendor: [UInt8]
        var comments: [String]
        if let existing {
            (vendor, comments) = parseVorbisComment(existing)
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
        appendUInt32BE(frontCoverPictureType)
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

    private static func picturePictureType(of block: [UInt8]) -> Int? {
        guard block.count >= 4 else { return nil }
        return Int(block[0]) << 24 | Int(block[1]) << 16 | Int(block[2]) << 8 | Int(block[3])
    }
}
