//
//  WAVTagWriterTests.swift
//  CleanMyDigitalTests
//

import Testing
import AppKit
import AVFoundation
import ID3TagEditor
@testable import CleanMyDigital

struct WAVTagWriterTests {
    @Test func writesFieldsIntoBothListInfoAndID3ChunksAndKeepsAudioPlayable() async throws {
        let wavURL = try Self.makeTestWAV()
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let originalDuration = try await AVURLAsset(url: wavURL).load(.duration).seconds
        let originalDataChunk = try Self.dataChunk(of: wavURL)

        let jpeg = try Self.makeTestJPEG()
        var changes = TagChanges()
        changes.title = "WAV Title"
        changes.artist = "WAV Artist"
        changes.album = "WAV Album"
        changes.year = "2024"
        changes.genre = "House"
        changes.trackNumber = "5"
        changes.artworkJPEG = jpeg

        try WAVTagWriter.write(changes, to: wavURL)

        // Audio bytes untouched.
        #expect(try Self.dataChunk(of: wavURL) == originalDataChunk)

        // LIST/INFO chunk has all six fields.
        let info = try Self.listInfoFields(of: wavURL)
        #expect(info["INAM"] == "WAV Title")
        #expect(info["IART"] == "WAV Artist")
        #expect(info["IPRD"] == "WAV Album")
        #expect(info["ICRD"] == "2024")
        #expect(info["IGNR"] == "House")
        #expect(info["ITRK"] == "5")

        // id3 chunk has the same fields plus artwork, readable by ID3TagEditor.
        let id3Tag = try #require(try Self.id3Tag(of: wavURL))
        #expect((id3Tag.frames[.title] as? ID3FrameWithStringContent)?.content == "WAV Title")
        #expect((id3Tag.frames[.artist] as? ID3FrameWithStringContent)?.content == "WAV Artist")
        #expect((id3Tag.frames[.album] as? ID3FrameWithStringContent)?.content == "WAV Album")
        #expect((id3Tag.frames[.recordingYear] as? ID3FrameWithIntegerContent)?.value == 2024)
        #expect((id3Tag.frames[.genre] as? ID3FrameGenre)?.description == "House")
        #expect((id3Tag.frames[.trackPosition] as? ID3FramePartOfTotal)?.part == 5)
        let picture = id3Tag.frames[.attachedPicture(.frontCover)] as? ID3FrameAttachedPicture
        #expect(picture != nil)
        #expect(picture?.picture.isEmpty == false)

        // Still a valid, playable WAV.
        let asset = AVURLAsset(url: wavURL)
        #expect(try await asset.load(.isPlayable))
        let newDuration = try await asset.load(.duration).seconds
        #expect(abs(newDuration - originalDuration) < 0.05)
    }

    @Test func neverOverwritesAnAlreadyPresentField() async throws {
        let wavURL = try Self.makeTestWAV()
        defer { try? FileManager.default.removeItem(at: wavURL) }

        var firstWrite = TagChanges()
        firstWrite.title = "Original WAV Title"
        try WAVTagWriter.write(firstWrite, to: wavURL)

        var secondWrite = TagChanges()
        secondWrite.title = "Should Never Appear"
        secondWrite.artist = "New WAV Artist"
        try WAVTagWriter.write(secondWrite, to: wavURL)

        let info = try Self.listInfoFields(of: wavURL)
        #expect(info["INAM"] == "Original WAV Title")
        #expect(info["IART"] == "New WAV Artist")

        let id3Tag = try #require(try Self.id3Tag(of: wavURL))
        #expect((id3Tag.frames[.title] as? ID3FrameWithStringContent)?.content == "Original WAV Title")
        #expect((id3Tag.frames[.artist] as? ID3FrameWithStringContent)?.content == "New WAV Artist")
    }

    @Test func updatesAnExistingID32ChunkInsteadOfAddingASecondID3Chunk() throws {
        let wavURL = try Self.makeTestWAV()
        defer { try? FileManager.default.removeItem(at: wavURL) }

        // Some taggers name the chunk "ID32" rather than "id3 ".
        var genreOnly = TagChanges()
        genreOnly.genre = "Tech House"
        let id3Data = try ID3TagEditor().write(tag: ID3TagBuilder.build(changes: genreOnly, existing: nil), mp3: Data())
        var chunks = try RIFFStream.parseChunks(in: [UInt8](try Data(contentsOf: wavURL)))
        chunks.append(RIFFChunk(id: "ID32", data: [UInt8](id3Data)))
        try RIFFStream.buildFile(chunks: chunks).write(to: wavURL, options: .atomic)

        var changes = TagChanges()
        changes.album = "New Album"
        try WAVTagWriter.write(changes, to: wavURL)

        let newChunks = try RIFFStream.parseChunks(in: [UInt8](try Data(contentsOf: wavURL)))
        #expect(newChunks.filter { RIFFStream.isID3Chunk($0) }.map(\.id) == ["ID32"])
        let id3Tag = try #require(try Self.id3Tag(of: wavURL))
        #expect((id3Tag.frames[.genre] as? ID3FrameGenre)?.description == "Tech House")
        #expect((id3Tag.frames[.album] as? ID3FrameWithStringContent)?.content == "New Album")
    }

    @Test func preservesAudioBytesAndOtherChunksExactly() throws {
        let wavURL = try Self.makeTestWAV()
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let originalBytes = [UInt8](try Data(contentsOf: wavURL))
        let originalChunks = try RIFFStream.parseChunks(in: originalBytes)
        let originalNonTagChunks = originalChunks.filter {
            $0.id.uppercased() != "LIST" && $0.id.trimmingCharacters(in: .whitespaces).lowercased() != "id3"
        }

        var changes = TagChanges()
        changes.artist = "Chunk Preservation Artist"
        try WAVTagWriter.write(changes, to: wavURL)

        let newBytes = [UInt8](try Data(contentsOf: wavURL))
        let newChunks = try RIFFStream.parseChunks(in: newBytes)
        let newNonTagChunks = newChunks.filter {
            $0.id.uppercased() != "LIST" && $0.id.trimmingCharacters(in: .whitespaces).lowercased() != "id3"
        }

        #expect(newNonTagChunks.count == originalNonTagChunks.count)
        for (original, new) in zip(originalNonTagChunks, newNonTagChunks) {
            #expect(original.id == new.id)
            #expect(original.data == new.data)
        }
    }

    @Test func nativeReaderSeesWrittenFields() throws {
        let wavURL = try Self.makeTestWAV()
        defer { try? FileManager.default.removeItem(at: wavURL) }

        var changes = TagChanges()
        changes.title = "Native WAV Title"
        changes.artist = "Native WAV Artist"
        changes.album = "Native WAV Album"
        changes.year = "2023"
        changes.genre = "Ambient"
        changes.trackNumber = "9"
        try WAVTagWriter.write(changes, to: wavURL)

        let metadata = try RIFFMetadataReader.read(contentsOf: wavURL)
        #expect(metadata.title == "Native WAV Title")
        #expect(metadata.artist == "Native WAV Artist")
        #expect(metadata.album == "Native WAV Album")
        #expect(metadata.year == "2023")
        #expect(metadata.genre == "Ambient")
        #expect(metadata.trackNumber == "9")
    }

    @Test func nativeReaderHandlesInfoOnlyFilesWithNoID3Chunk() throws {
        // A WAV tagged with only a LIST/INFO chunk (no "id3 ") is a common
        // convention on its own. AVFoundation's translation of INFO fields
        // is incomplete/undocumented (confirmed empirically — non-standard
        // tags like ITRK aren't exposed at all), so this is exactly the
        // case the native reader exists to cover deterministically.
        let wavURL = try Self.makeTestWAV()
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let bytes = [UInt8](try Data(contentsOf: wavURL))
        var chunks = try RIFFStream.parseChunks(in: bytes)
        var infoData = Array("INFO".utf8)
        for (id, value) in [("INAM", "Info Only Title"), ("ITRK", "3")] {
            infoData.append(contentsOf: RIFFStream.fourCC(id))
            var valueBytes = Array(value.utf8)
            valueBytes.append(0)
            RIFFStream.appendUInt32LE(valueBytes.count, to: &infoData)
            infoData.append(contentsOf: valueBytes)
            if valueBytes.count % 2 == 1 { infoData.append(0) }
        }
        chunks.append(RIFFChunk(id: "LIST", data: infoData))
        try RIFFStream.buildFile(chunks: chunks).write(to: wavURL, options: .atomic)

        let metadata = try RIFFMetadataReader.read(contentsOf: wavURL)
        #expect(metadata.title == "Info Only Title")
        #expect(metadata.trackNumber == "3")
    }

    // MARK: - Helpers

    private static func dataChunk(of url: URL) throws -> [UInt8] {
        let bytes = [UInt8](try Data(contentsOf: url))
        let chunks = try RIFFStream.parseChunks(in: bytes)
        return chunks.first { $0.id.lowercased() == "data" }?.data ?? []
    }

    private static func listInfoFields(of url: URL) throws -> [String: String] {
        let bytes = [UInt8](try Data(contentsOf: url))
        let chunks = try RIFFStream.parseChunks(in: bytes)
        guard let list = chunks.first(where: { RIFFStream.isListInfoChunk($0) }) else { return [:] }
        var fields: [String: String] = [:]
        for field in RIFFStream.parseListInfoFields(list.data) {
            fields[field.id] = field.value
        }
        return fields
    }

    private static func id3Tag(of url: URL) throws -> ID3Tag? {
        let bytes = [UInt8](try Data(contentsOf: url))
        let chunks = try RIFFStream.parseChunks(in: bytes)
        guard let id3Chunk = chunks.first(where: { RIFFStream.isID3Chunk($0) }) else { return nil }
        return try ID3TagEditor().read(mp3: Data(id3Chunk.data))
    }

    // MARK: - Fixture generation

    private enum FixtureError: Error {
        case bufferCreationFailed
        case afconvertFailed(String)
    }

    /// Synthesizes a short sine wave and shells out to `afconvert` to
    /// produce a canonical 16-bit PCM WAV to exercise the writer against.
    private static func makeTestWAV() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let rawURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        let wavURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")

        try writeSineWave(to: rawURL)
        defer { try? FileManager.default.removeItem(at: rawURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = ["-f", "WAVE", "-d", "LEI16", rawURL.path, wavURL.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: wavURL.path) else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            throw FixtureError.afconvertFailed(message ?? "afconvert produced no output")
        }
        return wavURL
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

/// Field case: WAVs whose last chunk's size field runs past the end of the
/// file (interrupted download, or a rip whose `data` size was written before
/// recording finished). Every player reads these; the app used to reject the
/// whole file with "Truncated RIFF chunk", hiding its tags and blocking writes.
struct TruncatedRIFFTests {
    @Test func clampsAFinalChunkThatOverrunsTheFile() throws {
        var bytes = Array("RIFF".utf8)
        bytes += [0, 0, 0, 0]
        bytes += Array("WAVE".utf8)
        bytes += Array("data".utf8)
        bytes += [0x00, 0x10, 0x00, 0x00]          // claims 4096 bytes…
        bytes += [UInt8](repeating: 0xAB, count: 100)  // …but only 100 are here

        let chunks = try RIFFStream.parseChunks(in: bytes)
        #expect(chunks.count == 1)
        #expect(chunks.first?.id == "data")
        #expect(chunks.first?.data.count == 100)
    }

    @Test func rebuildingWritesAnHonestSizeField() throws {
        var bytes = Array("RIFF".utf8)
        bytes += [0, 0, 0, 0]
        bytes += Array("WAVE".utf8)
        bytes += Array("data".utf8)
        bytes += [0x00, 0x10, 0x00, 0x00]
        bytes += [UInt8](repeating: 0xAB, count: 100)

        let rebuilt = [UInt8](RIFFStream.buildFile(chunks: try RIFFStream.parseChunks(in: bytes)))
        let reparsed = try RIFFStream.parseChunks(in: rebuilt)
        #expect(reparsed.first?.data.count == 100)
        // The audio bytes survive the repair untouched.
        #expect(reparsed.first?.data.allSatisfy { $0 == 0xAB } == true)
    }
}

/// The 1.2.2 crash: once truncated WAVs started parsing, a damaged "ID3 "
/// chunk reached ID3TagEditor, which traps instead of throwing — taking the
/// whole scan down. The structure is now checked before handing it over.
struct ID3ChunkValidationTests {
    @Test func rejectsALocalizedFrameTooShortForItsLanguageCode() {
        var tag = Array("ID3".utf8) + [0x03, 0x00, 0x00]
        tag += [0x00, 0x00, 0x00, 0x0C]            // syncsafe size: 12
        tag += Array("COMM".utf8)
        tag += [0x00, 0x00, 0x00, 0x02, 0x00, 0x00] // 2-byte body: too short
        tag += [0x00, 0x00]
        #expect(!ID3ChunkMetadata.isWellFormed(tag))
    }

    @Test func rejectsGarbageAndOverlongFrames() {
        #expect(!ID3ChunkMetadata.isWellFormed([UInt8](repeating: 0xAB, count: 64)))
        #expect(!ID3ChunkMetadata.isWellFormed(Array("ID3".utf8) + [0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7F]))
    }

    @Test func acceptsAWellFormedTag() {
        var tag = Array("ID3".utf8) + [0x03, 0x00, 0x00]
        tag += [0x00, 0x00, 0x00, 0x10]            // syncsafe size: 16
        tag += Array("TIT2".utf8)
        tag += [0x00, 0x00, 0x00, 0x06, 0x00, 0x00]
        tag += [0x00] + Array("Hello".utf8)        // encoding byte + text
        #expect(ID3ChunkMetadata.isWellFormed(tag))
    }
}
