//
//  LibraryScannerResetTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
import AVFoundation
@testable import CleanMyDigital

/// Verifies `LibraryScanner.reset()` — used when the category picker
/// changes, so a scan performed under the *old* category's rules can't
/// keep showing on screen mislabeled as if it matched the new one.
/// Checks that every piece of state `scan(folder:category:artistOverride:)`
/// populates (including the category-specific pieces that motivated this:
/// `category`, `artistOverride`, `artistOverrideAutoDetected`) is back to
/// its pre-scan default afterward — the same set of fields `scan()`'s own
/// opening lines clear, plus `albumCompletenessResults`, which `scan()`
/// deliberately leaves alone across a rescan of the *same* folder but
/// `reset()` clears too since a category change is a different scan
/// context entirely.
struct LibraryScannerResetTests {
    @Test func resetReturnsToIdleAndClearsScanIdentityIncludingAutoDetectedOverride() async throws {
        let artistFolder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: artistFolder) }
        for album in ["2Pac - 1996 - All Eyez on Me", "2Pac - 1998 - Greatest Hits"] {
            let albumFolder = artistFolder.appendingPathComponent(album)
            try FileManager.default.createDirectory(at: albumFolder, withIntermediateDirectories: true)
            try Data().write(to: albumFolder.appendingPathComponent("track.mp3"))
        }

        let scanner = LibraryScanner()
        await scanner.scan(folder: artistFolder, category: .albums)

        // Confirm the category-specific state this test cares about is
        // actually populated before resetting, including the
        // auto-detected artist-folder override — not just an
        // explicitly-requested one.
        #expect(scanner.state == .finished)
        #expect(!scanner.files.isEmpty)
        #expect(scanner.scannedFolder == artistFolder)
        #expect(scanner.category == .albums)
        #expect(scanner.artistOverride == artistFolder.lastPathComponent)
        #expect(scanner.artistOverrideAutoDetected)
        #expect(scanner.totalCount > 0)
        #expect(scanner.scannedCount > 0)

        scanner.reset()

        #expect(scanner.state == .idle)
        #expect(scanner.files.isEmpty)
        #expect(scanner.scannedFolder == nil)
        #expect(scanner.category == nil)
        #expect(scanner.artistOverride == nil)
        #expect(!scanner.artistOverrideAutoDetected)
        #expect(scanner.scannedCount == 0)
        #expect(scanner.totalCount == 0)
    }

    @Test func resetClearsAlbumCompletenessResultsUnlikeARescanOfTheSameFolder() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)
        scanner.recordAlbumCompletenessResult(.confirmedComplete, for: folder)
        #expect(scanner.albumCompletenessResults[folder] == .confirmedComplete)

        // A rescan of the same folder deliberately leaves this alone (see
        // `AlbumCompletenessOnlineResultTests.albumCompletenessResultsSurviveARescan`).
        await scanner.scan(folder: folder, category: .albums)
        #expect(scanner.albumCompletenessResults[folder] == .confirmedComplete)

        // But reset() — a wholesale category change, not a rescan — clears
        // it, since there's no reason a confirmation from one scan context
        // should silently apply under a completely different one.
        scanner.reset()
        #expect(scanner.albumCompletenessResults.isEmpty)
    }

    @Test func resetClearsLookupResultsAndItsCounters() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)
        let file = try #require(scanner.files.first)
        #expect(file.hasIssues) // an empty file is missing every field — a lookup target

        // Empty tokens mean `findAllMetadata` never actually reaches the
        // network (see `LibraryScanner.lookupOutcome`'s early-return when
        // both are empty) — a `.noMatch` outcome is available almost
        // immediately, same trick `LibraryScannerFolderAccessTests` uses
        // to populate `spectralResults` deterministically without a slow
        // real analysis.
        scanner.findAllMetadata(discogsToken: "", musicBrainzContact: "")
        var attempts = 0
        while scanner.isLookingUp, attempts < 100 {
            try await Task.sleep(nanoseconds: 20_000_000)
            attempts += 1
        }
        guard case .noMatch = scanner.lookupResults[file.url] else {
            Issue.record("Expected a .noMatch outcome, got \(String(describing: scanner.lookupResults[file.url]))")
            return
        }
        #expect(scanner.lookupTotalCount == 1)
        #expect(scanner.lookupCompletedCount == 1)

        scanner.reset()

        #expect(scanner.lookupResults.isEmpty)
        #expect(!scanner.isLookingUp)
        #expect(scanner.lookupCompletedCount == 0)
        #expect(scanner.lookupTotalCount == 0)
    }

    @Test func resetClearsSpectralResultsAndItsCounters() async throws {
        let folder = try Self.makePlainTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // analyzeSpectrum only targets readable files, so this needs a
        // real playable fixture.
        try Self.makeTestFLAC(at: folder.appendingPathComponent("track.flac"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)
        let file = try #require(scanner.files.first)

        // Taking the folder away after the scan makes the analysis fail
        // immediately with `.folderAccessUnavailable` — same technique as
        // `LibraryScannerFolderAccessTests.analyzeSpectrumSetsFailedOutcomeForEveryTarget`
        // — so this populates `spectralResults` without a slow real FFT.
        try FileManager.default.removeItem(at: folder)
        scanner.analyzeSpectrum()
        var attempts = 0
        while scanner.isAnalyzingSpectrum, attempts < 100 {
            try await Task.sleep(nanoseconds: 20_000_000)
            attempts += 1
        }
        guard case .failed = scanner.spectralResults[file.url] else {
            Issue.record("Expected a .failed outcome, got \(String(describing: scanner.spectralResults[file.url]))")
            return
        }
        #expect(scanner.spectralTotalCount == 1)
        #expect(scanner.spectralCompletedCount == 1)

        scanner.reset()

        #expect(scanner.spectralResults.isEmpty)
        #expect(!scanner.isAnalyzingSpectrum)
        #expect(scanner.spectralCompletedCount == 0)
        #expect(scanner.spectralTotalCount == 0)
    }

    /// `canUndoLastFileOperation`/`lastRenameBatch` aren't exercised with a
    /// genuinely populated batch here — same gap
    /// `LibraryScannerFolderAccessTests` documents for
    /// `undoLastFileOperation`'s folder-access branch: reaching a
    /// successful rename requires `startAccessingSecurityScopedResource()`
    /// to succeed, which a plain temp folder in this sandboxed test host
    /// never does. `reset()` clears `lastRenameBatch` the same
    /// unconditional way it clears everything else above, so this just
    /// confirms the default reads false and stays false across reset().
    @Test func canUndoLastFileOperationStaysFalseAcrossReset() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)
        #expect(!scanner.canUndoLastFileOperation)

        scanner.reset()
        #expect(!scanner.canUndoLastFileOperation)
    }

    @Test func resetOnAnAlreadyIdleScannerIsSafe() {
        let scanner = LibraryScanner()
        #expect(scanner.state == .idle)
        scanner.reset()
        #expect(scanner.state == .idle)
        #expect(scanner.files.isEmpty)
    }

    // MARK: - Fixtures

    private static func makeTempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A plain temp folder — deliberately *not* routed through a
    /// security-scoped bookmark, so `startAccessingSecurityScopedResource()`
    /// on it returns false, same as `LibraryScannerFolderAccessTests`.
    private static func makePlainTempFolder() throws -> URL {
        try makeTempFolder()
    }

    /// Synthesizes a short sine wave, writes it as a WAV, then shells out
    /// to `afconvert` to produce a real, playable FLAC file — same
    /// technique as `LibraryScannerFolderAccessTests`.
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
