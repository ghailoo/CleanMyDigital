//
//  APETagWriterTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

/// Monkey's Audio round-trip on a synthetic file: a real 3.99 header
/// (descriptor + header) followed by filler "audio". No decoder is needed —
/// the app only ever reads the header and rewrites the trailing APEv2 tag.
struct APETagWriterTests {
    @Test func readsDurationAndBitrateFromTheHeader() throws {
        let url = try Self.makeTestAPE()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try APEMetadataReader.read(contentsOf: url)
        // 2 frames: (2 - 1) * 73_728 + 26_272 blocks at 44_100 Hz ≈ 2.27 s
        let duration = try #require(result.duration)
        #expect(abs(duration - 2.267) < 0.01)
        #expect(result.bitrateKbps != nil)
    }

    @Test func writesTagsAndReadsThemBackLeavingTheAudioIntact() throws {
        let url = try Self.makeTestAPE()
        defer { try? FileManager.default.removeItem(at: url) }
        let audioBefore = Array([UInt8](try Data(contentsOf: url)))

        var changes = TagChanges()
        changes.title = "Close To You"
        changes.artist = "Maxi Priest"
        changes.year = "1990"
        try APETagWriter.write(changes, to: url)

        let result = try APEMetadataReader.read(contentsOf: url)
        #expect(result.metadata.title == "Close To You")
        #expect(result.metadata.artist == "Maxi Priest")
        #expect(result.metadata.year == "1990")

        // The audio bytes in front of the new tag are untouched.
        let after = [UInt8](try Data(contentsOf: url))
        #expect(Array(after[0..<audioBefore.count]) == audioBefore)
    }

    @Test func neverOverwritesAnExistingTagUnlessAskedTo() throws {
        let url = try Self.makeTestAPE()
        defer { try? FileManager.default.removeItem(at: url) }

        var first = TagChanges()
        first.title = "Original"
        try APETagWriter.write(first, to: url)

        var second = TagChanges()
        second.title = "Should Not Appear"
        try APETagWriter.write(second, to: url)
        #expect(try APEMetadataReader.read(contentsOf: url).metadata.title == "Original")

        var edit = TagChanges()
        edit.title = "Edited By Hand"
        edit.replacing = [.title]
        try APETagWriter.write(edit, to: url)
        #expect(try APEMetadataReader.read(contentsOf: url).metadata.title == "Edited By Hand")
    }

    @Test func rejectsAFileThatIsNotMonkeysAudio() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("ape")
        try Data(repeating: 0, count: 256).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: TagWriteError.self) { try APETagWriter.write(TagChanges(), to: url) }
    }

    // MARK: - Fixture

    private static func makeTestAPE() throws -> URL {
        var bytes = Array("MAC ".utf8)
        appendUInt16(3990, to: &bytes)          // version 3.99
        appendUInt16(0, to: &bytes)             // padding
        appendUInt32(52, to: &bytes)            // descriptor bytes
        appendUInt32(24, to: &bytes)            // header bytes
        for _ in 0..<8 { appendUInt32(0, to: &bytes) }  // seek table … MD5 filler
        while bytes.count < 52 { bytes.append(0) }

        appendUInt16(2000, to: &bytes)          // compression level
        appendUInt16(0, to: &bytes)             // format flags
        appendUInt32(73_728, to: &bytes)        // blocks per frame
        appendUInt32(26_272, to: &bytes)        // blocks in the final frame
        appendUInt32(2, to: &bytes)             // total frames
        appendUInt16(16, to: &bytes)            // bits per sample
        appendUInt16(2, to: &bytes)             // channels
        appendUInt32(44_100, to: &bytes)        // sample rate

        bytes.append(contentsOf: [UInt8](repeating: 0xAB, count: 4096))  // "audio"

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("ape")
        try Data(bytes).write(to: url)
        return url
    }

    private static func appendUInt16(_ value: UInt16, to bytes: inout [UInt8]) {
        bytes.append(UInt8(value & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
    }

    private static func appendUInt32(_ value: UInt32, to bytes: inout [UInt8]) {
        for shift in stride(from: 0, through: 24, by: 8) {
            bytes.append(UInt8((value >> UInt32(shift)) & 0xFF))
        }
    }
}
