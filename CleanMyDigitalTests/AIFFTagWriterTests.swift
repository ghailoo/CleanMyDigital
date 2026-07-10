//
//  AIFFTagWriterTests.swift
//  CleanMyDigitalTests
//

import Testing
import AppKit
import AVFoundation
import ID3TagEditor
@testable import CleanMyDigital

struct AIFFTagWriterTests {
    @Test func writesFieldsIntoID3ChunkAndKeepsAudioPlayable() async throws {
        let aiffURL = try Self.makeTestAIFF()
        defer { try? FileManager.default.removeItem(at: aiffURL) }

        let originalDuration = try await AVURLAsset(url: aiffURL).load(.duration).seconds
        let originalSoundChunk = try Self.chunk(of: aiffURL, id: "SSND")

        let jpeg = try Self.makeTestJPEG()
        var changes = TagChanges()
        changes.title = "AIFF Title"
        changes.artist = "AIFF Artist"
        changes.album = "AIFF Album"
        changes.year = "2022"
        changes.genre = "Downtempo"
        changes.trackNumber = "2"
        changes.artworkJPEG = jpeg

        try AIFFTagWriter.write(changes, to: aiffURL)

        // Audio bytes untouched.
        #expect(try Self.chunk(of: aiffURL, id: "SSND") == originalSoundChunk)

        let id3Tag = try #require(try Self.id3Tag(of: aiffURL))
        #expect((id3Tag.frames[.title] as? ID3FrameWithStringContent)?.content == "AIFF Title")
        #expect((id3Tag.frames[.artist] as? ID3FrameWithStringContent)?.content == "AIFF Artist")
        #expect((id3Tag.frames[.album] as? ID3FrameWithStringContent)?.content == "AIFF Album")
        #expect((id3Tag.frames[.recordingYear] as? ID3FrameWithIntegerContent)?.value == 2022)
        #expect((id3Tag.frames[.genre] as? ID3FrameGenre)?.description == "Downtempo")
        #expect((id3Tag.frames[.trackPosition] as? ID3FramePartOfTotal)?.part == 2)
        let picture = id3Tag.frames[.attachedPicture(.frontCover)] as? ID3FrameAttachedPicture
        #expect(picture != nil)
        #expect(picture?.picture.isEmpty == false)

        // AVFoundation reads the ID3 chunk's frames directly (confirmed
        // empirically, same as it does for WAV's "id3 " chunk) under the
        // standard TIT2/TPE1/TALB/... keys our scanner already looks for,
        // so no native AIFF reader is needed the way FLAC/WAV needed one.
        let asset = AVURLAsset(url: aiffURL)
        #expect(try await asset.load(.isPlayable))
        let newDuration = try await asset.load(.duration).seconds
        #expect(abs(newDuration - originalDuration) < 0.05)
    }

    @Test func neverOverwritesAnAlreadyPresentField() throws {
        let aiffURL = try Self.makeTestAIFF()
        defer { try? FileManager.default.removeItem(at: aiffURL) }

        var firstWrite = TagChanges()
        firstWrite.title = "Original AIFF Title"
        try AIFFTagWriter.write(firstWrite, to: aiffURL)

        var secondWrite = TagChanges()
        secondWrite.title = "Should Never Appear"
        secondWrite.artist = "New AIFF Artist"
        try AIFFTagWriter.write(secondWrite, to: aiffURL)

        let id3Tag = try #require(try Self.id3Tag(of: aiffURL))
        #expect((id3Tag.frames[.title] as? ID3FrameWithStringContent)?.content == "Original AIFF Title")
        #expect((id3Tag.frames[.artist] as? ID3FrameWithStringContent)?.content == "New AIFF Artist")
    }

    @Test func nativeReaderSeesWrittenFields() throws {
        let aiffURL = try Self.makeTestAIFF()
        defer { try? FileManager.default.removeItem(at: aiffURL) }

        let jpeg = try Self.makeTestJPEG()
        var changes = TagChanges()
        changes.title = "Native AIFF Title"
        changes.artist = "Native AIFF Artist"
        changes.album = "Native AIFF Album"
        changes.year = "2021"
        changes.genre = "IDM"
        changes.trackNumber = "4"
        changes.artworkJPEG = jpeg
        try AIFFTagWriter.write(changes, to: aiffURL)

        let metadata = try AIFFMetadataReader.read(contentsOf: aiffURL)
        #expect(metadata.title == "Native AIFF Title")
        #expect(metadata.artist == "Native AIFF Artist")
        #expect(metadata.album == "Native AIFF Album")
        #expect(metadata.year == "2021")
        #expect(metadata.genre == "IDM")
        #expect(metadata.trackNumber == "4")
        #expect(metadata.artworkData?.isEmpty == false)
    }

    @Test func preservesOtherChunksExactly() throws {
        let aiffURL = try Self.makeTestAIFF()
        defer { try? FileManager.default.removeItem(at: aiffURL) }

        let originalBytes = [UInt8](try Data(contentsOf: aiffURL))
        let (_, originalChunks) = try AIFFStream.parseChunks(in: originalBytes)
        let originalNonID3Chunks = originalChunks.filter { !AIFFStream.isID3Chunk($0) }

        var changes = TagChanges()
        changes.artist = "Chunk Preservation Artist"
        try AIFFTagWriter.write(changes, to: aiffURL)

        let newBytes = [UInt8](try Data(contentsOf: aiffURL))
        let (_, newChunks) = try AIFFStream.parseChunks(in: newBytes)
        let newNonID3Chunks = newChunks.filter { !AIFFStream.isID3Chunk($0) }

        #expect(newNonID3Chunks.count == originalNonID3Chunks.count)
        for (original, new) in zip(originalNonID3Chunks, newNonID3Chunks) {
            #expect(original.id == new.id)
            #expect(original.data == new.data)
        }
    }

    // MARK: - Helpers

    private static func chunk(of url: URL, id: String) throws -> [UInt8] {
        let bytes = [UInt8](try Data(contentsOf: url))
        let (_, chunks) = try AIFFStream.parseChunks(in: bytes)
        return chunks.first { $0.id == id }?.data ?? []
    }

    private static func id3Tag(of url: URL) throws -> ID3Tag? {
        let bytes = [UInt8](try Data(contentsOf: url))
        let (_, chunks) = try AIFFStream.parseChunks(in: bytes)
        guard let id3Chunk = chunks.first(where: { AIFFStream.isID3Chunk($0) }) else { return nil }
        return try ID3TagEditor().read(mp3: Data(id3Chunk.data))
    }

    // MARK: - Fixture generation

    private enum FixtureError: Error {
        case bufferCreationFailed
        case afconvertFailed(String)
    }

    /// Synthesizes a short sine wave and shells out to `afconvert` to
    /// produce a canonical 16-bit big-endian PCM AIFF to exercise the
    /// writer against.
    private static func makeTestAIFF() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let rawURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        let aiffURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("aiff")

        try writeSineWave(to: rawURL)
        defer { try? FileManager.default.removeItem(at: rawURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = ["-f", "AIFF", "-d", "BEI16", rawURL.path, aiffURL.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: aiffURL.path) else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            throw FixtureError.afconvertFailed(message ?? "afconvert produced no output")
        }
        return aiffURL
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
