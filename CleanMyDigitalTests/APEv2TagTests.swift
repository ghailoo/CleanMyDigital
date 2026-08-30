//
//  APEv2TagTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

/// Exercises `APEv2Tag` directly, independent of any container format —
/// it operates purely on byte buffers, so these tests build and locate
/// tags without needing a real WavPack (or Monkey's Audio) file at all.
/// `WavPackTagWriterTests` covers the container-level integration.
struct APEv2TagTests {
    @Test func roundTripsTextItemsThroughBuildAndLocate() throws {
        let items = [
            APEv2Tag.Item(key: "Title", isBinary: false, valueBytes: Array("Changes".utf8)),
            APEv2Tag.Item(key: "Artist", isBinary: false, valueBytes: Array("2Pac".utf8)),
        ]
        let tagBytes = APEv2Tag.build(items: items)

        // No audio prefix at all here — the tag itself is the whole buffer.
        let located = try #require(try APEv2Tag.locate(in: tagBytes))
        #expect(located.range == 0..<tagBytes.count)
        #expect(located.items.count == 2)
        #expect(located.items.first { $0.key == "Title" }?.textValue == "Changes")
        #expect(located.items.first { $0.key == "Artist" }?.textValue == "2Pac")
    }

    @Test func roundTripsAfterAnAudioPrefix() throws {
        var bytes = Array("pretend-audio-bytes-not-really-parsed".utf8)
        let audioPrefixLength = bytes.count
        let items = [APEv2Tag.Item(key: "Album", isBinary: false, valueBytes: Array("Greatest Hits".utf8))]
        bytes.append(contentsOf: APEv2Tag.build(items: items))

        let located = try #require(try APEv2Tag.locate(in: bytes))
        #expect(located.range.lowerBound == audioPrefixLength)
        #expect(located.range.upperBound == bytes.count)
        #expect(located.items.first?.textValue == "Greatest Hits")
    }

    @Test func roundTripsABinaryCoverArtItemWithTheFilenameConvention() throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xD9]) // fake JPEG-ish bytes
        let items = [APEv2Tag.Item.coverArt(key: "Cover Art (Front)", filename: "cover.jpg", data: imageData)]
        let tagBytes = APEv2Tag.build(items: items)

        let located = try #require(try APEv2Tag.locate(in: tagBytes))
        let coverItem = try #require(located.items.first)
        #expect(coverItem.isBinary)
        let payload = try #require(coverItem.coverArtPayload)
        #expect(payload.filename == "cover.jpg")
        #expect(payload.data == imageData)
    }

    @Test func keyLookupIsCaseInsensitive() throws {
        let tagBytes = APEv2Tag.build(items: [
            APEv2Tag.Item(key: "TITLE", isBinary: false, valueBytes: Array("Changes".utf8)),
        ])
        let located = try #require(try APEv2Tag.locate(in: tagBytes))
        #expect(APEv2TagBuilder.textValue("title", in: located.items) == "Changes")
        #expect(APEv2TagBuilder.textValue("Title", in: located.items) == "Changes")
    }

    @Test func locateReturnsNilWhenThereIsNoTagAtAll() throws {
        let bytes = Array("just some bytes with no APE tag anywhere in them".utf8)
        #expect(try APEv2Tag.locate(in: bytes) == nil)
    }

    @Test func locateThrowsWhenTheFooterClaimsToBeAHeader() throws {
        var tagBytes = APEv2Tag.build(items: [APEv2Tag.Item(key: "Title", isBinary: false, valueBytes: [0x41])])
        // Corrupt the footer's flags word (last 32 bytes, flags at
        // offset 20 within that descriptor) by also setting the isHeader
        // bit (1 << 29), which a valid footer must never have set.
        let footerStart = tagBytes.count - 32
        let flagsOffset = footerStart + 20
        var flags: UInt32 = 0
        for i in 0..<4 { flags |= UInt32(tagBytes[flagsOffset + i]) << (8 * i) }
        flags |= 1 << 29
        for i in 0..<4 { tagBytes[flagsOffset + i] = UInt8((flags >> (8 * i)) & 0xFF) }

        #expect(throws: TagWriteError.self) {
            try APEv2Tag.locate(in: tagBytes)
        }
    }

    @Test func trailingID3v1RangeFindsABareID3v1BlockWithNoAPETag() {
        var bytes = Array("audio bytes here".utf8)
        var id3v1 = Array("TAG".utf8)
        id3v1.append(contentsOf: [UInt8](repeating: 0, count: 125)) // pad to 128 bytes total
        let audioLength = bytes.count
        bytes.append(contentsOf: id3v1)

        let range = APEv2Tag.trailingID3v1Range(in: bytes)
        #expect(range == audioLength..<bytes.count)
    }

    @Test func trailingID3v1RangeIsNilWhenTheFileIsTooShortOrHasNoTag() {
        #expect(APEv2Tag.trailingID3v1Range(in: Array("short".utf8)) == nil)
        #expect(APEv2Tag.trailingID3v1Range(in: [UInt8](repeating: 0, count: 128)) == nil)
    }

    @Test func locateSkipsATrailingID3v1BlockToFindThePrecedingAPETag() throws {
        var bytes = Array("audio".utf8)
        let audioLength = bytes.count
        let items = [APEv2Tag.Item(key: "Genre", isBinary: false, valueBytes: Array("Hip Hop".utf8))]
        let tagBytes = APEv2Tag.build(items: items)
        bytes.append(contentsOf: tagBytes)
        let tagEnd = bytes.count

        var id3v1 = Array("TAG".utf8)
        id3v1.append(contentsOf: [UInt8](repeating: 0, count: 125))
        bytes.append(contentsOf: id3v1)

        let located = try #require(try APEv2Tag.locate(in: bytes))
        #expect(located.range == audioLength..<tagEnd)
        #expect(located.items.first?.textValue == "Hip Hop")
    }
}
