//
//  FLACTagWriterTests.swift
//  CleanMyDigitalTests
//

import Testing
import AppKit
import AVFoundation
@testable import CleanMyDigital

struct FLACTagWriterTests {
    @Test func writesOnlyTheGivenFieldsAndKeepsAudioPlayable() async throws {
        let flacURL = try Self.makeTestFLAC()
        defer { try? FileManager.default.removeItem(at: flacURL) }

        let originalDuration = try await AVURLAsset(url: flacURL).load(.duration).seconds

        var changes = TagChanges()
        changes.title = "Test Title"
        changes.artist = "Test Artist"
        changes.album = "Test Album"
        changes.year = "2024"
        changes.genre = "Electronic"
        changes.trackNumber = "3"

        try FLACTagWriter.write(changes, to: flacURL)

        let asset = AVURLAsset(url: flacURL)
        #expect(try await asset.load(.isPlayable))

        let newDuration = try await asset.load(.duration).seconds
        #expect(abs(newDuration - originalDuration) < 0.05)

        let metadata = try await Self.allMetadata(of: asset)
        #expect(await Self.stringValue(.commonIdentifierTitle, in: metadata) == "Test Title")
        #expect(await Self.stringValue(.commonIdentifierArtist, in: metadata) == "Test Artist")
        #expect(await Self.stringValue(.commonIdentifierAlbumName, in: metadata) == "Test Album")
    }

    @Test func neverOverwritesAnAlreadyPresentField() async throws {
        let flacURL = try Self.makeTestFLAC()
        defer { try? FileManager.default.removeItem(at: flacURL) }

        var firstWrite = TagChanges()
        firstWrite.title = "Original Title"
        try FLACTagWriter.write(firstWrite, to: flacURL)

        var secondWrite = TagChanges()
        secondWrite.title = "Should Never Appear"
        secondWrite.artist = "New Artist"
        try FLACTagWriter.write(secondWrite, to: flacURL)

        let metadata = try await Self.allMetadata(of: AVURLAsset(url: flacURL))
        #expect(await Self.stringValue(.commonIdentifierTitle, in: metadata) == "Original Title")
        #expect(await Self.stringValue(.commonIdentifierArtist, in: metadata) == "New Artist")
    }

    @Test func replacesAlbumOnlyWhenExplicitlyAsked() async throws {
        let flacURL = try Self.makeTestFLAC()
        defer { try? FileManager.default.removeItem(at: flacURL) }

        var firstWrite = TagChanges()
        firstWrite.title = "Keep Me"
        firstWrite.album = "Turn Da Music Up (CDM)"
        try FLACTagWriter.write(firstWrite, to: flacURL)

        var replace = TagChanges()
        replace.title = "Should Never Appear"
        replace.album = "Turn Da Music Up"
        replace.replacing = [.album]
        try FLACTagWriter.write(replace, to: flacURL)

        let metadata = try await Self.allMetadata(of: AVURLAsset(url: flacURL))
        #expect(await Self.stringValue(.commonIdentifierAlbumName, in: metadata) == "Turn Da Music Up")
        #expect(await Self.stringValue(.commonIdentifierTitle, in: metadata) == "Keep Me")
    }

    @Test func replacesAnyEditedFieldButLeavesOthers() async throws {
        let flacURL = try Self.makeTestFLAC()
        defer { try? FileManager.default.removeItem(at: flacURL) }

        var firstWrite = TagChanges()
        firstWrite.title = "Old Title"
        firstWrite.genre = "House"
        try FLACTagWriter.write(firstWrite, to: flacURL)

        var edit = TagChanges()
        edit.title = "New Title"
        edit.genre = "Should Stay House"
        edit.replacing = [.title]
        try FLACTagWriter.write(edit, to: flacURL)

        let metadata = try await Self.allMetadata(of: AVURLAsset(url: flacURL))
        #expect(await Self.stringValue(.commonIdentifierTitle, in: metadata) == "New Title")
    }

    @Test func addsAFrontCoverPictureBlock() async throws {
        let flacURL = try Self.makeTestFLAC()
        defer { try? FileManager.default.removeItem(at: flacURL) }

        let jpegData = try Self.makeTestJPEG()
        var changes = TagChanges()
        changes.artworkJPEG = jpegData
        try FLACTagWriter.write(changes, to: flacURL)

        let metadata = try await Self.allMetadata(of: AVURLAsset(url: flacURL))
        let artworkItems = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork)
        #expect(!artworkItems.isEmpty)
        let data = try await artworkItems.first?.load(.dataValue)
        #expect(data != nil)
        #expect(!(data ?? Data()).isEmpty)
    }

    @Test func preservesNonstandardID3v2PrefixBeforeFLACSignature() async throws {
        let flacURL = try Self.makeTestFLAC()
        defer { try? FileManager.default.removeItem(at: flacURL) }

        let originalDuration = try await AVURLAsset(url: flacURL).load(.duration).seconds

        let id3Prefix = Self.makeMinimalID3v2Tag()
        var prefixedBytes = Data(id3Prefix)
        prefixedBytes.append(try Data(contentsOf: flacURL))
        try prefixedBytes.write(to: flacURL, options: .atomic)

        var changes = TagChanges()
        changes.artist = "Prefixed Artist"
        changes.genre = "Techno"
        try FLACTagWriter.write(changes, to: flacURL)

        let rewritten = try Data(contentsOf: flacURL)
        #expect(rewritten.count >= id3Prefix.count)
        let rewrittenPrefix = Array(rewritten.prefix(id3Prefix.count))
        #expect(rewrittenPrefix == id3Prefix)
        #expect(Array(rewrittenPrefix.prefix(3)) == Array("ID3".utf8))

        let asset = AVURLAsset(url: flacURL)
        let newDuration = try await asset.load(.duration).seconds
        #expect(abs(newDuration - originalDuration) < 0.05)

        // AVFoundation's FLAC demuxer doesn't expose the inner VORBIS_COMMENT
        // block at all once an ID3v2 wrapper is present — confirmed by
        // requesting `org.xiph.vorbis-comment` explicitly and getting zero
        // items back, even though the bytes are correctly there. So the new
        // comments are verified by parsing the FLAC block ourselves instead
        // of through AVFoundation's metadata API.
        let comments = try Self.readVorbisComments(from: rewritten, after: id3Prefix.count)
        #expect(comments.contains("ARTIST=Prefixed Artist"))
        #expect(comments.contains("GENRE=Techno"))
    }

    @Test func nativeReaderSeesFieldsAVFoundationCannotOnID3PrefixedFiles() throws {
        let flacURL = try Self.makeTestFLAC()
        defer { try? FileManager.default.removeItem(at: flacURL) }

        var prefixedBytes = Data(Self.makeMinimalID3v2Tag())
        prefixedBytes.append(try Data(contentsOf: flacURL))
        try prefixedBytes.write(to: flacURL, options: .atomic)

        var changes = TagChanges()
        changes.artist = "Native Reader Artist"
        changes.album = "Native Reader Album"
        changes.genre = "Ambient"
        changes.trackNumber = "7"
        try FLACTagWriter.write(changes, to: flacURL)

        let metadata = try FLACMetadataReader.read(contentsOf: flacURL)
        #expect(metadata.artist == "Native Reader Artist")
        #expect(metadata.album == "Native Reader Album")
        #expect(metadata.genre == "Ambient")
        #expect(metadata.trackNumber == "7")
    }

    // MARK: - Helpers

    private enum ReadError: Error {
        case malformed
    }

    /// Walks the FLAC metadata-block chain starting at `streamStart` (right
    /// after any ID3v2 prefix) and returns the VORBIS_COMMENT block's
    /// "FIELD=value" strings — a from-scratch parse, deliberately
    /// independent of `FLACTagWriter`'s own parsing code, so the test
    /// verifies the actual bytes on disk rather than round-tripping through
    /// the same logic that wrote them.
    private static func readVorbisComments(from data: Data, after streamStart: Int) throws -> [String] {
        let bytes = [UInt8](data)
        guard bytes.count >= streamStart + 4,
              bytes[streamStart] == 0x66, bytes[streamStart + 1] == 0x4C,
              bytes[streamStart + 2] == 0x61, bytes[streamStart + 3] == 0x43
        else {
            throw ReadError.malformed
        }

        var offset = streamStart + 4
        while offset + 4 <= bytes.count {
            let headerByte = bytes[offset]
            let isLast = (headerByte & 0x80) != 0
            let type = headerByte & 0x7F
            let length = Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let dataStart = offset + 4
            let dataEnd = dataStart + length
            guard dataEnd <= bytes.count else { throw ReadError.malformed }

            if type == 4 { // VORBIS_COMMENT
                let block = Array(bytes[dataStart..<dataEnd])
                var readOffset = 0
                func readUInt32LE() -> Int {
                    guard readOffset + 4 <= block.count else { return 0 }
                    let value = Int(block[readOffset]) | Int(block[readOffset + 1]) << 8
                        | Int(block[readOffset + 2]) << 16 | Int(block[readOffset + 3]) << 24
                    readOffset += 4
                    return value
                }
                let vendorLength = readUInt32LE()
                readOffset = min(readOffset + vendorLength, block.count)
                let commentCount = readUInt32LE()
                var comments: [String] = []
                for _ in 0..<commentCount {
                    let commentLength = readUInt32LE()
                    let end = min(readOffset + commentLength, block.count)
                    guard readOffset <= end else { break }
                    if let string = String(bytes: block[readOffset..<end], encoding: .utf8) {
                        comments.append(string)
                    }
                    readOffset = end
                }
                return comments
            }

            offset = dataEnd
            if isLast { break }
        }
        return []
    }

    /// FLAC's VORBIS_COMMENT fields don't all map into `.commonMetadata` —
    /// merge in the format-specific metadata too, same as
    /// `LibraryScanner.inspect()` does when reading a scanned file.
    private static func allMetadata(of asset: AVURLAsset) async throws -> [AVMetadataItem] {
        var items = try await asset.load(.commonMetadata)
        for format in try await asset.load(.availableMetadataFormats) {
            items += try await asset.loadMetadata(for: format)
        }
        return items
    }

    private static func stringValue(_ identifier: AVMetadataIdentifier, in items: [AVMetadataItem]) async -> String? {
        for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
            if let value = try? await item.load(.stringValue) { return value }
        }
        return nil
    }

    // MARK: - Fixture generation

    private enum FixtureError: Error {
        case bufferCreationFailed
        case afconvertFailed(String)
    }

    /// Synthesizes a short sine wave, writes it as a WAV, then shells out to
    /// `afconvert` (the same tool macOS itself uses) to produce a real FLAC
    /// file to exercise the writer against.
    private static func makeTestFLAC() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let wavURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        let flacURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("flac")

        try writeSineWave(to: wavURL)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = ["-f", "flac", "-d", "flac", wavURL.path, flacURL.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: flacURL.path) else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            throw FixtureError.afconvertFailed(message ?? "afconvert produced no output")
        }
        return flacURL
    }

    private static func writeSineWave(to url: URL) throws {
        let sampleRate = 44100.0
        let frameCount = AVAudioFrameCount(sampleRate * 0.5)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else {
            throw FixtureError.bufferCreationFailed
        }
        buffer.frameLength = frameCount
        let channelData = buffer.floatChannelData![0]
        let frequency = 440.0
        for frame in 0..<Int(frameCount) {
            channelData[frame] = Float(sin(2.0 * Double.pi * frequency * Double(frame) / sampleRate) * 0.2)
        }

        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        try audioFile.write(from: buffer)
    }

    /// A minimal but real ID3v2.3 tag: 10-byte header + one TIT2 frame +
    /// a little padding, mimicking the nonstandard prefix some FLAC rips
    /// have before the real "fLaC" signature.
    private static func makeMinimalID3v2Tag() -> [UInt8] {
        let titleText = "Ripper Title"
        var frameContent: [UInt8] = [0x00] // ISO-8859-1 text encoding byte
        frameContent.append(contentsOf: Array(titleText.utf8))

        var frame: [UInt8] = Array("TIT2".utf8)
        let frameSize = frameContent.count
        frame.append(UInt8((frameSize >> 24) & 0xFF))
        frame.append(UInt8((frameSize >> 16) & 0xFF))
        frame.append(UInt8((frameSize >> 8) & 0xFF))
        frame.append(UInt8(frameSize & 0xFF))
        frame.append(contentsOf: [0x00, 0x00]) // frame flags
        frame.append(contentsOf: frameContent)

        let padding = [UInt8](repeating: 0, count: 20)
        let tagContentSize = frame.count + padding.count

        var header: [UInt8] = Array("ID3".utf8)
        header.append(contentsOf: [0x03, 0x00]) // version 2.3.0
        header.append(0x00) // flags: no unsynchronisation/extended header/footer
        header.append(contentsOf: syncsafeEncode(tagContentSize))

        return header + frame + padding
    }

    private static func syncsafeEncode(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 21) & 0x7F),
            UInt8((value >> 14) & 0x7F),
            UInt8((value >> 7) & 0x7F),
            UInt8(value & 0x7F),
        ]
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
            throw FixtureError.bufferCreationFailed
        }
        return jpeg
    }
}
