//
//  WavPackTagWriterTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
import AppKit
@testable import CleanMyDigital

/// Standard macOS tools can't produce a WavPack file, so — same as
/// `DSFTagWriterTests` for DSF — these tests hand-construct a minimal but
/// spec-valid .wv file directly: a single 32-byte "wvpk" block header
/// (stereo, 16-bit, 44100 Hz, lossless) followed by a small dummy
/// compressed-audio payload. AVFoundation can't open WavPack at all (see
/// `WavPackMetadataReader`'s doc comment), so there's no
/// `AVURLAsset.load(.isPlayable)`/duration check to fall back on — every
/// assertion here goes through this app's own `WavPackStream`/
/// `WavPackMetadataReader`/`APEv2Tag`, plus `LibraryScanner` end-to-end.
struct WavPackTagWriterTests {
    @Test func writesFieldsIntoAPEv2TagAndPreservesAudioBytes() throws {
        let wvURL = try Self.makeTestWavPack()
        defer { try? FileManager.default.removeItem(at: wvURL) }
        let originalBlockBytes = try Data(contentsOf: wvURL)

        let jpeg = try Self.makeTestJPEG()
        var changes = TagChanges()
        changes.title = "WV Title"
        changes.artist = "WV Artist"
        changes.album = "WV Album"
        changes.year = "2022"
        changes.genre = "Trip Hop"
        changes.trackNumber = "3"
        changes.artworkJPEG = jpeg

        try WavPackTagWriter.write(changes, to: wvURL)

        let newBytes = [UInt8](try Data(contentsOf: wvURL))
        let located = try #require(try APEv2Tag.locate(in: newBytes))

        // The entire "wvpk" block — the one thing that must never be
        // touched — survives byte-for-byte, immediately before the tag.
        #expect(Array(newBytes[0..<located.range.lowerBound]) == [UInt8](originalBlockBytes))

        #expect(APEv2TagBuilder.textValue("Title", in: located.items) == "WV Title")
        #expect(APEv2TagBuilder.textValue("Artist", in: located.items) == "WV Artist")
        #expect(APEv2TagBuilder.textValue("Album", in: located.items) == "WV Album")
        #expect(APEv2TagBuilder.textValue("Year", in: located.items) == "2022")
        #expect(APEv2TagBuilder.textValue("Genre", in: located.items) == "Trip Hop")
        #expect(APEv2TagBuilder.textValue("Track", in: located.items) == "3")

        let coverItem = try #require(located.items.first {
            $0.key.caseInsensitiveCompare(APEv2TagBuilder.coverArtFrontKey) == .orderedSame
        })
        #expect(coverItem.isBinary)
        #expect(coverItem.coverArtPayload?.data.isEmpty == false)
    }

    @Test func neverOverwritesAnAlreadyPresentField() throws {
        let wvURL = try Self.makeTestWavPack()
        defer { try? FileManager.default.removeItem(at: wvURL) }

        var firstWrite = TagChanges()
        firstWrite.title = "Original WV Title"
        try WavPackTagWriter.write(firstWrite, to: wvURL)

        var secondWrite = TagChanges()
        secondWrite.title = "Should Never Appear"
        secondWrite.artist = "New WV Artist"
        try WavPackTagWriter.write(secondWrite, to: wvURL)

        let bytes = [UInt8](try Data(contentsOf: wvURL))
        let located = try #require(try APEv2Tag.locate(in: bytes))
        #expect(APEv2TagBuilder.textValue("Title", in: located.items) == "Original WV Title")
        #expect(APEv2TagBuilder.textValue("Artist", in: located.items) == "New WV Artist")
    }

    @Test func secondWriteReplacesTheFirstTagRatherThanAppendingAnotherOne() throws {
        let wvURL = try Self.makeTestWavPack()
        defer { try? FileManager.default.removeItem(at: wvURL) }

        var firstWrite = TagChanges()
        firstWrite.title = "Short"
        try WavPackTagWriter.write(firstWrite, to: wvURL)
        let afterFirst = [UInt8](try Data(contentsOf: wvURL))

        var secondWrite = TagChanges()
        secondWrite.artist = "A Considerably Longer Artist Name For A Bigger Tag"
        try WavPackTagWriter.write(secondWrite, to: wvURL)
        let afterSecond = [UInt8](try Data(contentsOf: wvURL))

        let locatedFirst = try #require(try APEv2Tag.locate(in: afterFirst))
        let locatedSecond = try #require(try APEv2Tag.locate(in: afterSecond))
        // Same audio prefix boundary both times — only the tag after it
        // grew, it wasn't left behind with a second one appended.
        #expect(locatedFirst.range.lowerBound == locatedSecond.range.lowerBound)
        #expect(locatedSecond.items.count == 2) // Title (preserved) + Artist (new)
        #expect(afterSecond.count > afterFirst.count)
    }

    @Test func preservesATrailingID3v1TagAndKeepsItLast() throws {
        let wvURL = try Self.makeTestWavPack()
        defer { try? FileManager.default.removeItem(at: wvURL) }

        var bytes = [UInt8](try Data(contentsOf: wvURL))
        var id3v1 = Array("TAG".utf8)
        id3v1.append(contentsOf: Array("Legacy Title".utf8))
        id3v1.append(contentsOf: [UInt8](repeating: 0, count: 128 - id3v1.count))
        bytes.append(contentsOf: id3v1)
        try Data(bytes).write(to: wvURL)

        var changes = TagChanges()
        changes.artist = "2Pac"
        try WavPackTagWriter.write(changes, to: wvURL)

        let newBytes = [UInt8](try Data(contentsOf: wvURL))
        // The ID3v1 block is still the last 128 bytes, untouched.
        #expect(Array(newBytes.suffix(128)) == id3v1)

        let located = try #require(try APEv2Tag.locate(in: newBytes))
        #expect(located.range.upperBound == newBytes.count - 128)
        #expect(APEv2TagBuilder.textValue("Artist", in: located.items) == "2Pac")
    }

    @Test func nativeReaderSeesWrittenFieldsAndComputesDurationAndBitrate() throws {
        let wvURL = try Self.makeTestWavPack(sampleByteCount: 4096, totalSamples: 44100, sampleRateIndex: 9)
        defer { try? FileManager.default.removeItem(at: wvURL) }
        let audioPrefixSize = try Data(contentsOf: wvURL).count

        var changes = TagChanges()
        changes.title = "Native WV Title"
        changes.artist = "Native WV Artist"
        changes.album = "Native WV Album"
        changes.year = "2020"
        changes.genre = "Downtempo"
        changes.trackNumber = "7"
        try WavPackTagWriter.write(changes, to: wvURL)

        let result = try WavPackMetadataReader.read(contentsOf: wvURL)
        #expect(result.metadata.title == "Native WV Title")
        #expect(result.metadata.artist == "Native WV Artist")
        #expect(result.metadata.album == "Native WV Album")
        #expect(result.metadata.year == "2020")
        #expect(result.metadata.genre == "Downtempo")
        #expect(result.metadata.trackNumber == "7")

        // 44100 samples at 44100 Hz = exactly 1 second.
        #expect(try #require(result.duration).isApproximatelyEqual(to: 1.0))
        // Bitrate is the audio prefix's compressed byte size (unaffected
        // by the tag written after it) * 8 / duration / 1000.
        let expectedBitrate = Int((Double(audioPrefixSize) * 8 / 1000).rounded())
        #expect(result.bitrateKbps == expectedBitrate)
    }

    @Test func libraryScannerReadsAWavPackFileEndToEnd() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let wvURL = folder.appendingPathComponent("track.wv")
        try Self.writeTestWavPack(to: wvURL)

        var changes = TagChanges()
        changes.artist = "2Pac"
        changes.title = "Changes"
        try WavPackTagWriter.write(changes, to: wvURL)

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)

        let file = try #require(scanner.files.first)
        #expect(file.isReadable)
        #expect(file.artist == "2Pac")
        #expect(file.title == "Changes")
        #expect(file.duration != nil)
        #expect(file.bitrateKbps != nil)
    }

    @Test func writeThrowsMalformedFileWhenTheWvpkSignatureIsMissing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("wv")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05]).write(to: url)

        var changes = TagChanges()
        changes.artist = "2Pac"

        #expect(throws: TagWriteError.self) {
            try WavPackTagWriter.write(changes, to: url)
        }
    }

    @Test func readThrowsMalformedFileWhenTheWvpkSignatureIsMissing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("wv")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05]).write(to: url)

        #expect(throws: TagWriteError.self) {
            try WavPackMetadataReader.read(contentsOf: url)
        }
    }

    // MARK: - Helpers

    private static func makeTempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: - Fixture generation

    private static func makeTestWavPack(
        sampleByteCount: Int = 2048, totalSamples: UInt32 = 44100, sampleRateIndex: UInt32 = 9
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("wv")
        try writeTestWavPack(to: url, sampleByteCount: sampleByteCount,
                              totalSamples: totalSamples, sampleRateIndex: sampleRateIndex)
        return url
    }

    /// Hand-builds a minimal, spec-valid WavPack file: one "wvpk" block —
    /// 32-byte header (stereo, 16-bit, lossless, `sampleRateIndex`'s rate,
    /// `totalSamples` samples, both INITIAL_BLOCK and FINAL_BLOCK set as a
    /// single-block file requires) followed by `sampleByteCount` bytes of a
    /// distinctive repeating pattern standing in for the compressed
    /// bitstream — no tag yet, matching a freshly-ripped file. `flags`'
    /// bit layout is WavPack5FileFormat.pdf §2.0's; `sampleRateIndex`
    /// defaults to 9 (44100 Hz) per its 15-entry standard-rate table.
    private static func writeTestWavPack(
        to url: URL, sampleByteCount: Int = 2048, totalSamples: UInt32 = 44100, sampleRateIndex: UInt32 = 9
    ) throws {
        var bytes = [UInt8]()

        func appendLE16(_ value: UInt16) {
            for i in 0..<2 { bytes.append(UInt8((value >> (8 * UInt16(i))) & 0xFF)) }
        }
        func appendLE32(_ value: UInt32) {
            for i in 0..<4 { bytes.append(UInt8((value >> (8 * UInt32(i))) & 0xFF)) }
        }

        let payload = (0..<sampleByteCount).map { UInt8(($0 * 53 + 7) % 256) }

        bytes.append(contentsOf: Array("wvpk".utf8))
        appendLE32(UInt32(24 + payload.count)) // ckSize: whole block minus the ckID/ckSize fields themselves
        appendLE16(0x407) // version (arbitrary value within the spec's valid-to-decode range)
        bytes.append(0) // block_index_u8 (upper 8 bits of block_index — 0)
        bytes.append(0) // total_samples_u8 (upper 8 bits of total_samples — 0)
        appendLE32(totalSamples)
        appendLE32(0) // block_index (lower 32 bits) — 0, this is the first block
        appendLE32(totalSamples) // block_samples — this one block covers the whole (tiny) file

        var flags: UInt32 = 0
        flags |= 0b01 // bits 1,0: 2 bytes/sample (16-bit)
        flags |= 1 << 11 // INITIAL_BLOCK
        flags |= 1 << 12 // FINAL_BLOCK
        flags |= UInt32(15) << 18 // magnitude (unused by this app's reader)
        flags |= sampleRateIndex << 23
        appendLE32(flags)

        appendLE32(0) // crc (unused/unverified by this app's reader)
        bytes.append(contentsOf: payload)

        try Data(bytes).write(to: url)
    }

    private static func makeTestJPEG() throws -> Data {
        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [:])
        else {
            struct BufferCreationFailed: Error {}
            throw BufferCreationFailed()
        }
        return jpeg
    }
}

private extension Double {
    func isApproximatelyEqual(to other: Double, tolerance: Double = 0.001) -> Bool {
        abs(self - other) < tolerance
    }
}
