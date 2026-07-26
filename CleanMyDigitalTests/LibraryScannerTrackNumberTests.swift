//
//  LibraryScannerTrackNumberTests.swift
//  CleanMyDigitalTests
//

import Testing
import AVFoundation
@testable import CleanMyDigital

/// Verifies `LibraryScanner` surfaces "x/y" (position/total) track numbers
/// for formats beyond MP3's ID3 TRCK frame — FLAC's separate TRACKTOTAL
/// Vorbis comment and M4A's packed `trkn` atom.
struct LibraryScannerTrackNumberTests {
    @Test func flacWithTrackTotalCommentProducesXOverYTrackNumber() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let flacURL = folder.appendingPathComponent("track.flac")
        try Self.makeTestFLAC(at: flacURL)
        try Self.setVorbisComments(["TRACKNUMBER=3", "TRACKTOTAL=12"], in: flacURL)

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)

        let file = try #require(scanner.files.first)
        #expect(file.trackNumber == "3/12")
    }

    @Test func flacWithoutTrackTotalStillReadsJustThePosition() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let flacURL = folder.appendingPathComponent("track.flac")
        try Self.makeTestFLAC(at: flacURL)
        try Self.setVorbisComments(["TRACKNUMBER=3"], in: flacURL)

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)

        let file = try #require(scanner.files.first)
        #expect(file.trackNumber == "3")
    }

    @Test func m4aWithTrknTotalProducesXOverYTrackNumber() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let m4aURL = folder.appendingPathComponent("track.m4a")
        try await Self.makeTestM4A(at: m4aURL)

        var changes = TagChanges()
        changes.trackNumber = "2/12"
        try await M4ATagWriter.write(changes, to: m4aURL)

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)

        let file = try #require(scanner.files.first)
        #expect(file.trackNumber == "2/12")
    }

    @Test func m4aWithoutTrknTotalStillReadsJustThePosition() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let m4aURL = folder.appendingPathComponent("track.m4a")
        try await Self.makeTestM4A(at: m4aURL)

        var changes = TagChanges()
        changes.trackNumber = "2"
        try await M4ATagWriter.write(changes, to: m4aURL)

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)

        let file = try #require(scanner.files.first)
        #expect(file.trackNumber == "2")
    }

    // MARK: - Helpers

    private enum FixtureError: Error {
        case bufferCreationFailed
        case afconvertFailed(String)
    }

    private static func makeTempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Synthesizes a short sine wave, writes it as a WAV, then shells out to
    /// `afconvert` (the same tool macOS itself uses) to produce a real FLAC
    /// file at `url` — same technique as `FLACTagWriterTests`.
    private static func makeTestFLAC(at url: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory
        let wavURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")

        try writeSineWave(to: wavURL)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = ["-f", "flac", "-d", "flac", wavURL.path, url.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            throw FixtureError.afconvertFailed(message ?? "afconvert produced no output")
        }
    }

    /// Synthesizes a short sine wave WAV, then exports it to M4A/AAC via
    /// `AVAssetExportSession` — same technique as `M4ATagWriterTests`.
    private static func makeTestM4A(at url: URL) async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let wavURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")

        try writeSineWave(to: wavURL)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        guard let exportSession = AVAssetExportSession(
            asset: AVURLAsset(url: wavURL), presetName: AVAssetExportPresetAppleM4A)
        else { throw FixtureError.bufferCreationFailed }

        try await exportSession.export(to: url, as: .m4a)
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

    /// Replaces (or adds) the FLAC's VORBIS_COMMENT block with exactly
    /// `comments`, preserving every other metadata block and the audio
    /// frames byte-for-byte — a from-scratch write, deliberately independent
    /// of `FLACTagWriter`'s own merging logic, so the test exercises
    /// `FLACMetadataReader` against bytes it didn't help produce.
    private static func setVorbisComments(_ comments: [String], in url: URL) throws {
        let bytes = [UInt8](try Data(contentsOf: url))
        let streamStart = try FLACStream.streamStart(in: bytes)
        let (blocks, audioStart) = try FLACStream.parseBlocks(in: bytes, streamStart: streamStart)
        let id3Prefix = Array(bytes[0..<streamStart])
        let audioData = Array(bytes[audioStart...])

        let newVorbisComment = FLACMetadataBlock(type: FLACBlockType.vorbisComment, data: makeVorbisCommentData(comments))
        var outputBlocks: [FLACMetadataBlock] = []
        var replacedExisting = false
        for block in blocks {
            if block.type == FLACBlockType.vorbisComment {
                outputBlocks.append(newVorbisComment)
                replacedExisting = true
            } else {
                outputBlocks.append(block)
            }
        }
        if !replacedExisting {
            outputBlocks.append(newVorbisComment)
        }

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

        try Data(output).write(to: url, options: .atomic)
    }

    private static func makeVorbisCommentData(_ comments: [String]) -> [UInt8] {
        var output = [UInt8]()
        func appendUInt32LE(_ value: Int) {
            output.append(UInt8(value & 0xFF))
            output.append(UInt8((value >> 8) & 0xFF))
            output.append(UInt8((value >> 16) & 0xFF))
            output.append(UInt8((value >> 24) & 0xFF))
        }
        let vendor = Array("CleanMyDigital".utf8)
        appendUInt32LE(vendor.count)
        output.append(contentsOf: vendor)
        appendUInt32LE(comments.count)
        for comment in comments {
            let commentBytes = Array(comment.utf8)
            appendUInt32LE(commentBytes.count)
            output.append(contentsOf: commentBytes)
        }
        return output
    }
}
