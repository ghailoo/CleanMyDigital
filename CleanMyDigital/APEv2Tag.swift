//
//  APEv2Tag.swift
//  CleanMyDigital
//

import Foundation

/// A minimal APEv2 tag reader/writer, built from the Hydrogenaudio APEv2
/// specification (wiki.hydrogenaudio.org, "APEv2 specification") and
/// cross-checked against Mutagen's `apev2.py` reference implementation for
/// the exact bit assignments.
///
/// Deliberately format-agnostic: everything here operates purely on a
/// tag's own bytes — `locate(in:)` takes the raw bytes of a *file* only
/// because that's the only way to find where a trailing tag begins (by
/// scanning backward from EOF), but nothing here knows anything about
/// WavPack's block structure. APEv2 is also the native tag format for
/// Monkey's Audio (.ape) and Musepack (.mpc), so keeping this separate
/// from `WavPackStream`/`WavPackTagWriter` means a native .ape reader/
/// writer later is mostly just container work (finding where its audio
/// ends) — this module should be reusable as-is.
///
/// Binary layout (every multi-byte field little-endian):
///
/// A 32-byte header and/or footer, identical shape whichever one it is —
/// a reader tells them apart only by the `isHeader` flag bit:
/// ```
/// preamble    [8]  "APETAGEX"
/// version     u32  2000 for APEv2 (1000 = old APEv1, never written here)
/// tagSize     u32  bytes from the first item through the end of the
///                  footer — i.e. everything in the tag except a
///                  preceding header, on both the header's and the
///                  footer's own copy of this field
/// itemCount   u32  number of items
/// flags       u32  global flags — `hasHeader` (bit 31), `hasNoFooter`
///                  (bit 30), `isHeader` (bit 29); the rest are per-item
///                  default flags/reserved and unused here
/// reserved    [8]  must be zero
/// ```
/// Each item:
/// ```
/// valueSize   u32  length of the value, in bytes
/// flags       u32  bit 0 read-only (never set here); bits 2-1 value
///                  kind (0 = UTF-8 text, 1 = binary, 2 = external
///                  locator, 3 = reserved) — see `Item.isBinary`
/// key         …    ASCII/UTF-8, NUL-terminated (terminator not counted
///                  in valueSize)
/// value       …    `valueSize` raw bytes
/// ```
///
/// Placement: an APEv2 tag belongs at the end of the file, footer last;
/// this module always writes both a header and a footer, for maximum
/// compatibility reading it back from either direction. If a legacy
/// ID3v1 tag (a fixed 128-byte block starting "TAG") is also present, it
/// comes after the APE tag, right at the true end of file — so locating
/// the APE tag from EOF means checking for, and skipping over, a trailing
/// ID3v1 block first. This module assumes the common, WavPack/APE-tools
/// case of a tag living at the *end* of the file with no leading tag
/// before the audio — the "legal but strongly unrecommended" header-only,
/// no-footer placement at the *start* of a file is not supported.
enum APEv2Tag {
    // MARK: - Items

    /// One key/value pair. `isBinary` mirrors the item's declared value
    /// kind — UTF-8 text vs. everything else; this app only ever produces
    /// binary items for embedded cover art (see the `coverArt` convention
    /// below), never an external locator.
    struct Item: Sendable, Equatable {
        var key: String
        var isBinary: Bool
        var valueBytes: [UInt8]

        var textValue: String? {
            guard !isBinary else { return nil }
            return String(bytes: valueBytes, encoding: .utf8)
        }
    }

    /// An APEv2 tag found within some file's bytes.
    struct Located {
        var items: [Item]
        /// Byte range, within the buffer passed to `locate(in:)`, spanned
        /// by the APE tag itself — header (if present) through the
        /// footer's last byte. Deliberately excludes a trailing ID3v1
        /// block, if any (see `trailingID3v1Range(in:)`) — everything at
        /// or after `range.upperBound` is either that ID3v1 block or the
        /// true end of file, never part of the APE tag.
        var range: Range<Int>
    }

    // MARK: - Locating

    private static let descriptorSize = 32
    private static let preamble: [UInt8] = Array("APETAGEX".utf8)
    private static let id3v1Size = 128
    private static let id3v1Signature: [UInt8] = Array("TAG".utf8)

    private enum HeaderFlags {
        static let hasHeader: UInt32 = 1 << 31
        static let hasNoFooter: UInt32 = 1 << 30
        static let isHeader: UInt32 = 1 << 29
    }

    private enum ItemFlags {
        static let kindMask: UInt32 = 0b110 // bits 2-1
        static let kindBinary: UInt32 = 1 << 1
    }

    /// The trailing 128-byte ID3v1 block's range, if `bytes` ends with
    /// one — independent of whether an APE tag precedes it, so a writer
    /// can preserve it even when there's no existing APE tag to anchor to
    /// (a bare ID3v1-only file).
    static func trailingID3v1Range(in bytes: [UInt8]) -> Range<Int>? {
        guard bytes.count >= id3v1Size else { return nil }
        let start = bytes.count - id3v1Size
        return matches(bytes, at: start, id3v1Signature) ? start..<bytes.count : nil
    }

    /// Scans backward from the end of `bytes` for an APEv2 tag — skipping
    /// a trailing ID3v1 block first, if present — and parses it. Returns
    /// nil when there's simply no APE tag (a freshly-ripped file); throws
    /// only once something that looks like a tag (a valid "APETAGEX"
    /// footer) turns out to be internally inconsistent, since silently
    /// guessing at a broken offset from there risks corrupting the file
    /// on write.
    static func locate(in bytes: [UInt8]) throws -> Located? {
        let tailEnd = trailingID3v1Range(in: bytes)?.lowerBound ?? bytes.count
        guard tailEnd >= descriptorSize else { return nil }

        let footerStart = tailEnd - descriptorSize
        guard matches(bytes, at: footerStart, preamble) else { return nil }

        guard let footer = try parseDescriptor(in: bytes, at: footerStart) else {
            throw TagWriteError.malformedFile("Truncated APEv2 footer")
        }
        guard footer.flags & HeaderFlags.isHeader == 0 else {
            throw TagWriteError.malformedFile("APEv2 footer has the header flag set")
        }

        let itemsBytesLength = Int(footer.tagSize) - descriptorSize
        guard itemsBytesLength >= 0 else {
            throw TagWriteError.malformedFile("Implausible APEv2 tag size")
        }
        let itemsStart = footerStart - itemsBytesLength
        guard itemsStart >= 0 else {
            throw TagWriteError.malformedFile("APEv2 tag size runs past the start of the file")
        }

        let hasHeader = footer.flags & HeaderFlags.hasHeader != 0
        let tagStart: Int
        if hasHeader {
            let headerStart = itemsStart - descriptorSize
            guard headerStart >= 0, matches(bytes, at: headerStart, preamble),
                  let header = try parseDescriptor(in: bytes, at: headerStart),
                  header.flags & HeaderFlags.isHeader != 0
            else {
                throw TagWriteError.malformedFile("APEv2 header flagged present but missing or invalid")
            }
            tagStart = headerStart
        } else {
            tagStart = itemsStart
        }

        guard let items = parseItems(in: bytes, from: itemsStart, to: footerStart,
                                      expectedCount: Int(footer.itemCount))
        else {
            throw TagWriteError.malformedFile("APEv2 tag items couldn't be parsed")
        }

        return Located(items: items, range: tagStart..<tailEnd)
    }

    private struct Descriptor {
        let tagSize: UInt32
        let itemCount: UInt32
        let flags: UInt32
    }

    private static func parseDescriptor(in bytes: [UInt8], at offset: Int) throws -> Descriptor? {
        guard offset + descriptorSize <= bytes.count else { return nil }
        return Descriptor(
            tagSize: readUInt32LE(bytes, at: offset + 12),
            itemCount: readUInt32LE(bytes, at: offset + 16),
            flags: readUInt32LE(bytes, at: offset + 20))
    }

    private static func parseItems(
        in bytes: [UInt8], from start: Int, to end: Int, expectedCount: Int
    ) -> [Item]? {
        var items: [Item] = []
        var cursor = start
        while cursor < end {
            guard cursor + 8 <= end else { return nil }
            let valueSize = Int(readUInt32LE(bytes, at: cursor))
            let flags = readUInt32LE(bytes, at: cursor + 4)
            cursor += 8

            guard let nulIndex = bytes[cursor..<end].firstIndex(of: 0) else { return nil }
            guard let key = String(bytes: bytes[cursor..<nulIndex], encoding: .utf8), !key.isEmpty else {
                return nil
            }
            cursor = nulIndex + 1

            guard valueSize >= 0, cursor + valueSize <= end else { return nil }
            let valueBytes = Array(bytes[cursor..<(cursor + valueSize)])
            cursor += valueSize

            let kind = (flags & ItemFlags.kindMask) >> 1
            items.append(Item(key: key, isBinary: kind != 0, valueBytes: valueBytes))
        }
        guard cursor == end, items.count == expectedCount else { return nil }
        return items
    }

    // MARK: - Building

    /// Serializes `items` into a complete APEv2 tag — header, items,
    /// footer, in that order — ready to be appended directly after a
    /// file's audio data (and before any preserved trailing ID3v1 block).
    static func build(items: [Item]) -> [UInt8] {
        var itemsData: [UInt8] = []
        for item in items {
            appendUInt32LE(UInt32(item.valueBytes.count), to: &itemsData)
            appendUInt32LE(item.isBinary ? ItemFlags.kindBinary : 0, to: &itemsData)
            itemsData.append(contentsOf: Array(item.key.utf8))
            itemsData.append(0)
            itemsData.append(contentsOf: item.valueBytes)
        }

        let tagSize = UInt32(itemsData.count + descriptorSize)
        let itemCount = UInt32(items.count)
        // Both copies advertise a header and a footer (neither
        // `hasNoFooter` is set); only `isHeader` distinguishes which copy
        // is which.
        let sharedFlags = HeaderFlags.hasHeader

        var output = descriptor(tagSize: tagSize, itemCount: itemCount, flags: sharedFlags | HeaderFlags.isHeader)
        output.append(contentsOf: itemsData)
        output.append(contentsOf: descriptor(tagSize: tagSize, itemCount: itemCount, flags: sharedFlags))
        return output
    }

    private static func descriptor(tagSize: UInt32, itemCount: UInt32, flags: UInt32) -> [UInt8] {
        var bytes = preamble
        appendUInt32LE(2000, to: &bytes)
        appendUInt32LE(tagSize, to: &bytes)
        appendUInt32LE(itemCount, to: &bytes)
        appendUInt32LE(flags, to: &bytes)
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 8))
        return bytes
    }

    // MARK: - Byte helpers

    private static func matches(_ bytes: [UInt8], at offset: Int, _ signature: [UInt8]) -> Bool {
        guard offset >= 0, offset + signature.count <= bytes.count else { return false }
        return Array(bytes[offset..<(offset + signature.count)]) == signature
    }

    private static func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<4 { value |= UInt32(bytes[offset + i]) << (8 * i) }
        return value
    }

    private static func appendUInt32LE(_ value: UInt32, to bytes: inout [UInt8]) {
        for i in 0..<4 { bytes.append(UInt8((value >> (8 * i)) & 0xFF)) }
    }
}

// MARK: - Cover art convention

/// APEv2 itself has no dedicated picture field — the "Cover Art (Front)"/
/// "Cover Art (Back)" keys WavPack, Monkey's Audio, and every common
/// tagger (foobar2000, Mp3tag, MusicBrainz Picard, …) use by convention
/// store a binary item shaped as a NUL-terminated filename followed
/// immediately by the raw image bytes. Not part of the core spec, but
/// universal enough in practice to belong alongside it rather than in a
/// WavPack-specific file.
extension APEv2Tag.Item {
    static func coverArt(key: String, filename: String, data: Data) -> APEv2Tag.Item {
        var valueBytes = Array(filename.utf8)
        valueBytes.append(0)
        valueBytes.append(contentsOf: [UInt8](data))
        return APEv2Tag.Item(key: key, isBinary: true, valueBytes: valueBytes)
    }

    /// Decodes the filename+NUL+data convention back out of a binary
    /// item's value bytes. Nil if this isn't a binary item, or its value
    /// has no NUL separator to split on.
    var coverArtPayload: (filename: String, data: Data)? {
        guard isBinary, let nulIndex = valueBytes.firstIndex(of: 0) else { return nil }
        let filename = String(bytes: valueBytes[..<nulIndex], encoding: .utf8) ?? ""
        return (filename, Data(valueBytes[(nulIndex + 1)...]))
    }
}
