//
//  BackupFailureReportingTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
import AVFoundation
@testable import CleanMyDigital

/// Verifies a failure in the pre-write backup step (`BackupManager`) is
/// reported distinctly from a tag-write failure — `TagWriteError.backupFailed`
/// — rather than both surfacing as the same generic message, and that it no
/// longer blocks the tag write itself: `applyTagChanges` writes the fields
/// anyway and returns the backup failure as a value instead of throwing it.
struct BackupFailureReportingTests {
    @Test func backupFailedErrorDescriptionMentionsBackupSpecifically() {
        struct DummyError: LocalizedError {
            var errorDescription: String? { "permission denied" }
        }
        let error = TagWriteError.backupFailed(DummyError())
        #expect(error.errorDescription == "Backup failed: permission denied")
    }

    @Test func applyTagChangesWritesTheTagAnywayAndReturnsTheBackupFailure() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let flacURL = folder.appendingPathComponent("track.flac")
        try Self.makeTestFLAC(at: flacURL)

        // Occupy the backup folder's own path with a regular file, so
        // BackupManager's `createDirectory` fails — simulates a backup-step
        // failure without needing an actually permission-restricted volume.
        let backupFolderPath = folder.appendingPathComponent(BackupManager.backupFolderName)
        try Data().write(to: backupFolderPath)

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)
        let file = try #require(scanner.files.first)

        var changes = TagChanges()
        changes.artist = "2Pac"

        let backupFailure = try await scanner.applyTagChanges(changes, to: file, backupFirst: true)

        guard case .backupFailed = backupFailure else {
            Issue.record("Expected a .backupFailed result, got \(String(describing: backupFailure))")
            return
        }

        // The tag write still goes through despite the backup failure.
        #expect(scanner.files.first?.artist == "2Pac")
        // No backup ever actually landed, since the folder path was occupied.
        #expect(!FileManager.default.fileExists(atPath: backupFolderPath.appendingPathComponent("track.flac").path))
    }

    @Test func applyTagChangesReturnsNilWhenBackupSucceeds() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let flacURL = folder.appendingPathComponent("track.flac")
        try Self.makeTestFLAC(at: flacURL)

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)
        let file = try #require(scanner.files.first)

        var changes = TagChanges()
        changes.artist = "2Pac"

        let backupFailure = try await scanner.applyTagChanges(changes, to: file, backupFirst: true)

        #expect(backupFailure == nil)
        #expect(scanner.files.first?.artist == "2Pac")
    }

    // MARK: - Fixture

    private static func makeTempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Synthesizes a short sine wave, writes it as a WAV, then shells out to
    /// `afconvert` to produce a real FLAC file — same technique as
    /// `FLACTagWriterTests`.
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
            struct AfconvertFailed: Error { let message: String }
            throw AfconvertFailed(message: message ?? "afconvert produced no output")
        }
    }

    private static func writeSineWave(to url: URL) throws {
        let sampleRate = 44100.0
        let frameCount = AVAudioFrameCount(sampleRate * 0.5)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else {
            struct BufferCreationFailed: Error {}
            throw BufferCreationFailed()
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
}
