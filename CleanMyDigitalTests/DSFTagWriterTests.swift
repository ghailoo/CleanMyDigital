//
//  DSFTagWriterTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
import AppKit
import ID3TagEditor
@testable import CleanMyDigital

/// `afconvert` (used elsewhere in this suite to synthesize WAV/FLAC/AIFF
/// fixtures) can't produce a DSD/DSF file from PCM, so these tests
/// hand-construct a minimal but spec-valid DSF file directly: a 28-byte
/// "DSD " chunk, a 52-byte "fmt " chunk, and a "data" chunk holding a small
/// dummy DSD payload — no ID3v2 tag yet, matching a freshly-ripped file.
/// AVFoundation can't open DSF at all (see `DSFMetadataReader`'s doc
/// comment), so unlike the other writer tests there's no
/// `AVURLAsset.load(.isPlayable)`/duration check to fall back on here —
/// everything checkable about this fixture goes through this app's own
/// `DSFStream`/`DSFMetadataReader`, plus `LibraryScanner` end-to-end.
struct DSFTagWriterTests {
    @Test func writesFieldsIntoID3TagAndPreservesAudioBytes() throws {
        let dsfURL = try Self.makeTestDSF()
        defer { try? FileManager.default.removeItem(at: dsfURL) }

        let originalSampleBytes = try Self.sampleBytes(of: dsfURL)

        let jpeg = try Self.makeTestJPEG()
        var changes = TagChanges()
        changes.title = "DSF Title"
        changes.artist = "DSF Artist"
        changes.album = "DSF Album"
        changes.year = "2023"
        changes.genre = "Ambient"
        changes.trackNumber = "5"
        changes.artworkJPEG = jpeg

        try DSFTagWriter.write(changes, to: dsfURL)

        // The DSD sample payload — the one thing that must never be
        // touched — survives byte-for-byte.
        #expect(try Self.sampleBytes(of: dsfURL) == originalSampleBytes)

        let id3Tag = try #require(try Self.id3Tag(of: dsfURL))
        #expect((id3Tag.frames[.title] as? ID3FrameWithStringContent)?.content == "DSF Title")
        #expect((id3Tag.frames[.artist] as? ID3FrameWithStringContent)?.content == "DSF Artist")
        #expect((id3Tag.frames[.album] as? ID3FrameWithStringContent)?.content == "DSF Album")
        #expect((id3Tag.frames[.recordingYear] as? ID3FrameWithIntegerContent)?.value == 2023)
        #expect((id3Tag.frames[.genre] as? ID3FrameGenre)?.description == "Ambient")
        #expect((id3Tag.frames[.trackPosition] as? ID3FramePartOfTotal)?.part == 5)
        let picture = id3Tag.frames[.attachedPicture(.frontCover)] as? ID3FrameAttachedPicture
        #expect(picture != nil)
        #expect(picture?.picture.isEmpty == false)
    }

    @Test func neverOverwritesAnAlreadyPresentField() throws {
        let dsfURL = try Self.makeTestDSF()
        defer { try? FileManager.default.removeItem(at: dsfURL) }

        var firstWrite = TagChanges()
        firstWrite.title = "Original DSF Title"
        try DSFTagWriter.write(firstWrite, to: dsfURL)

        var secondWrite = TagChanges()
        secondWrite.title = "Should Never Appear"
        secondWrite.artist = "New DSF Artist"
        try DSFTagWriter.write(secondWrite, to: dsfURL)

        let id3Tag = try #require(try Self.id3Tag(of: dsfURL))
        #expect((id3Tag.frames[.title] as? ID3FrameWithStringContent)?.content == "Original DSF Title")
        #expect((id3Tag.frames[.artist] as? ID3FrameWithStringContent)?.content == "New DSF Artist")
    }

    @Test func updatesTheHeadersTotalFileSizeAndMetadataPointerFields() throws {
        let dsfURL = try Self.makeTestDSF()
        defer { try? FileManager.default.removeItem(at: dsfURL) }

        let originalLength = [UInt8](try Data(contentsOf: dsfURL)).count
        let originalHeader = try DSFStream.parseHeader(in: [UInt8](try Data(contentsOf: dsfURL)))
        #expect(originalHeader.metadataPointer == nil)
        #expect(originalHeader.totalFileSize == originalLength)

        var changes = TagChanges()
        changes.artist = "2Pac"
        try DSFTagWriter.write(changes, to: dsfURL)

        let newBytes = [UInt8](try Data(contentsOf: dsfURL))
        let header = try DSFStream.parseHeader(in: newBytes)
        #expect(header.totalFileSize == newBytes.count)
        #expect(header.metadataPointer == originalLength)
        #expect(newBytes.count > originalLength)
    }

    @Test func secondWriteMovesTheMetadataPointerToTheGrownTag() throws {
        let dsfURL = try Self.makeTestDSF()
        defer { try? FileManager.default.removeItem(at: dsfURL) }

        var firstWrite = TagChanges()
        firstWrite.title = "Short"
        try DSFTagWriter.write(firstWrite, to: dsfURL)
        let afterFirst = [UInt8](try Data(contentsOf: dsfURL))
        let headerAfterFirst = try DSFStream.parseHeader(in: afterFirst)

        var secondWrite = TagChanges()
        secondWrite.artist = "A Considerably Longer Artist Name For A Bigger Tag"
        try DSFTagWriter.write(secondWrite, to: dsfURL)
        let afterSecond = [UInt8](try Data(contentsOf: dsfURL))
        let headerAfterSecond = try DSFStream.parseHeader(in: afterSecond)

        // The audio prefix length never changes across writes — only the
        // ID3 tag after it grows — so the metadata pointer stays the same
        // even though the file as a whole got bigger.
        #expect(headerAfterFirst.metadataPointer == headerAfterSecond.metadataPointer)
        #expect(headerAfterSecond.totalFileSize == afterSecond.count)
        #expect(afterSecond.count > afterFirst.count)
    }

    @Test func nativeReaderSeesWrittenFieldsAndComputesDurationAndBitrate() throws {
        let dsfURL = try Self.makeTestDSF(sampleByteCount: 4096)
        defer { try? FileManager.default.removeItem(at: dsfURL) }

        var changes = TagChanges()
        changes.title = "Native DSF Title"
        changes.artist = "Native DSF Artist"
        changes.album = "Native DSF Album"
        changes.year = "2021"
        changes.genre = "IDM"
        changes.trackNumber = "4"
        try DSFTagWriter.write(changes, to: dsfURL)

        let result = try DSFMetadataReader.read(contentsOf: dsfURL)
        #expect(result.metadata.title == "Native DSF Title")
        #expect(result.metadata.artist == "Native DSF Artist")
        #expect(result.metadata.album == "Native DSF Album")
        #expect(result.metadata.year == "2021")
        #expect(result.metadata.genre == "IDM")
        #expect(result.metadata.trackNumber == "4")

        // DSD64 stereo, 1 bit/sample: 2,822,400 * 1 * 2 / 1000 = 5,644.8 kbps.
        #expect(result.bitrateKbps == 5645)
        // 4096 sample bytes * 8 bits, at 2,822,400 Hz.
        let expectedDuration = Double(4096 * 8) / 2_822_400
        #expect(try #require(result.duration).isApproximatelyEqual(to: expectedDuration))
    }

    @Test func libraryScannerReadsADSFFileEndToEnd() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let dsfURL = folder.appendingPathComponent("track.dsf")
        try Self.writeTestDSF(to: dsfURL)

        var changes = TagChanges()
        changes.artist = "2Pac"
        changes.title = "Changes"
        try DSFTagWriter.write(changes, to: dsfURL)

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)

        let file = try #require(scanner.files.first)
        #expect(file.isReadable)
        #expect(file.artist == "2Pac")
        #expect(file.title == "Changes")
        #expect(file.duration != nil)
        #expect(file.bitrateKbps != nil)
    }

    @Test func writeThrowsMalformedFileWhenTheDSDSignatureIsMissing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("dsf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05]).write(to: url)

        var changes = TagChanges()
        changes.artist = "2Pac"

        #expect(throws: TagWriteError.self) {
            try DSFTagWriter.write(changes, to: url)
        }
    }

    // MARK: - Helpers

    private static func sampleBytes(of url: URL) throws -> [UInt8] {
        let bytes = [UInt8](try Data(contentsOf: url))
        let header = try DSFStream.parseHeader(in: bytes)
        let audioPrefixEnd = header.metadataPointer ?? bytes.count
        // Sample payload starts 12 bytes into the data chunk (4-byte magic
        // + 8-byte size field) and runs to the end of the audio prefix.
        return Array(bytes[(header.dataChunkStart + 12)..<audioPrefixEnd])
    }

    private static func id3Tag(of url: URL) throws -> ID3Tag? {
        let bytes = [UInt8](try Data(contentsOf: url))
        let header = try DSFStream.parseHeader(in: bytes)
        guard let pointer = header.metadataPointer else { return nil }
        return try ID3TagEditor().read(mp3: Data(bytes[pointer...]))
    }

    private static func makeTempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: - Fixture generation

    private static func makeTestDSF(sampleByteCount: Int = 4096) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("dsf")
        try writeTestDSF(to: url, sampleByteCount: sampleByteCount)
        return url
    }

    /// Hand-builds a minimal, spec-valid DSF file: "DSD " chunk (28 bytes),
    /// "fmt " chunk (52 bytes, DSD64 stereo/1-bit), "data" chunk holding
    /// `sampleByteCount` bytes of a distinctive repeating pattern (so a
    /// "preserved byte-for-byte" check is actually meaningful, not just
    /// confirming zeros stay zero) — no metadata chunk yet.
    private static func writeTestDSF(to url: URL, sampleByteCount: Int = 4096) throws {
        var bytes = [UInt8]()

        func appendLE32(_ value: UInt32) {
            for i in 0..<4 { bytes.append(UInt8((value >> (8 * UInt32(i))) & 0xFF)) }
        }
        func appendLE64(_ value: UInt64) {
            for i in 0..<8 { bytes.append(UInt8((value >> (8 * UInt64(i))) & 0xFF)) }
        }

        // DSD chunk
        bytes.append(contentsOf: Array("DSD ".utf8))
        appendLE64(28)
        let totalFileSizeFieldOffset = bytes.count
        appendLE64(0) // total file size — patched below
        appendLE64(0) // metadata pointer — none yet

        // fmt chunk: DSD raw, stereo, DSD64 (2,822,400 Hz), 1 bit/sample
        bytes.append(contentsOf: Array("fmt ".utf8))
        appendLE64(52)
        appendLE32(1) // format version
        appendLE32(0) // format ID: DSD raw
        appendLE32(2) // channel type: stereo
        appendLE32(2) // channel num: stereo
        appendLE32(2_822_400) // sampling frequency
        appendLE32(1) // bits per sample
        appendLE64(UInt64(sampleByteCount * 8)) // sample count (1 bit/sample)
        appendLE32(4096) // block size per channel
        appendLE32(0) // reserved

        // data chunk
        bytes.append(contentsOf: Array("data".utf8))
        appendLE64(UInt64(sampleByteCount + 12))
        bytes.append(contentsOf: (0..<sampleByteCount).map { UInt8(($0 * 37 + 11) % 256) })

        let totalSize = UInt64(bytes.count)
        for i in 0..<8 {
            bytes[totalFileSizeFieldOffset + i] = UInt8((totalSize >> (8 * UInt64(i))) & 0xFF)
        }

        try Data(bytes).write(to: url)
    }

    private static func makeTestJPEG() throws -> Data {
        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemBlue.setFill()
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
