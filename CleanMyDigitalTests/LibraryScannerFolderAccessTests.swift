//
//  LibraryScannerFolderAccessTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
import AVFoundation
@testable import CleanMyDigital

/// Verifies every write/move method on `LibraryScanner` surfaces a clear
/// `TagWriteError.folderAccessUnavailable` (instead of proceeding into an
/// operation guaranteed to fail with a confusing "no such file" error) when
/// `startAccessingSecurityScopedResource()` on the scanned folder returns
/// false.
///
/// A plain, non-bookmarked temp-directory URL reliably reproduces exactly
/// that condition in this sandboxed test host: it isn't a security-scoped
/// resource at all, so the call returns false — the same false this app
/// would see for a genuinely stale bookmark to a real user-chosen folder in
/// production, even though the *specific* reason differs (never-scoped vs.
/// gone-stale). `scan(folder:)` itself still succeeds against such a URL —
/// real file I/O on a path inside the app's own sandbox container doesn't
/// actually need security scoping — which is exactly what makes this
/// reproducible without a real external volume or a live stale bookmark:
/// only the methods this change touches gate on the scope check.
///
/// `undoLastFileOperation`'s new branch isn't covered here: reaching it
/// requires `lastRenameBatch` already populated by a prior successful
/// rename/move against the *same* `scannedFolder` — but that prior
/// operation would itself hit the same gate and never populate the batch
/// if the folder never had access to begin with. The code change there is
/// the same shape as `renameFiles`/`collectIntoFolders`/`moveDuplicates`,
/// each independently verified below.
struct LibraryScannerFolderAccessTests {
    @Test func applyTagChangesThrowsFolderAccessUnavailable() async throws {
        let folder = try Self.makePlainTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)
        let file = try #require(scanner.files.first)

        var changes = TagChanges()
        changes.artist = "2Pac"

        do {
            try await scanner.applyTagChanges(changes, to: file, backupFirst: false)
            Issue.record("Expected applyTagChanges to throw .folderAccessUnavailable")
        } catch let error as TagWriteError {
            guard case .folderAccessUnavailable = error else {
                Issue.record("Expected .folderAccessUnavailable, got \(error)")
                return
            }
        }
    }

    @Test func renameFilesReturnsFolderAccessUnavailablePerProposal() async throws {
        let folder = try Self.makePlainTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)
        let file = try #require(scanner.files.first)

        let proposal = RenameProposal(
            file: file, currentName: "track.mp3", proposedName: "renamed.mp3", isCaseOnlyChange: false)
        let results = await scanner.renameFiles([proposal])

        let result = try #require(results.first)
        #expect(!result.succeeded)
        #expect(result.errorDescription == TagWriteError.folderAccessUnavailable.errorDescription)
    }

    @Test func collectIntoFoldersReturnsFolderAccessUnavailablePerProposal() async throws {
        let folder = try Self.makePlainTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .singles)
        let file = try #require(scanner.files.first)

        let proposal = CollectionProposal(
            file: file, songTitle: "Some Release", pressingName: nil,
            proposedFileName: "track.mp3", proposedRelativePath: "Some Release/track.mp3",
            hasOddExtension: false)
        let plan = ArtistCollectionPlan(
            artistFolderName: folder.lastPathComponent, artistRoot: folder,
            proposals: [proposal], sourceFoldersToClean: [])
        let results = await scanner.collectIntoFolders([plan])

        let result = try #require(results.first)
        #expect(!result.succeeded)
        #expect(result.errorDescription == TagWriteError.folderAccessUnavailable.errorDescription)
    }

    @Test func moveDuplicatesReturnsFolderAccessUnavailablePerProposal() async throws {
        let folder = try Self.makePlainTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)
        let file = try #require(scanner.files.first)

        let proposal = DuplicateMoveProposal(file: file, proposedRelativePath: "_CleanMyDigital Duplicates/track.mp3")
        let results = await scanner.moveDuplicates([proposal])

        let result = try #require(results.first)
        #expect(!result.succeeded)
        #expect(result.errorDescription == TagWriteError.folderAccessUnavailable.errorDescription)
    }

    @Test func renameAlbumFoldersReturnsFolderAccessUnavailablePerProposal() async throws {
        let folder = try Self.makePlainTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let albumFolder = folder.appendingPathComponent("Original Folder")
        try FileManager.default.createDirectory(at: albumFolder, withIntermediateDirectories: true)
        try Data().write(to: albumFolder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)
        let groups = AlbumCompletenessChecker.groups(for: scanner.files)
        let group = try #require(groups.first)

        let proposal = AlbumFolderRenameProposal(
            group: group, currentFolderName: "Original Folder", proposedFolderName: "Album (1995)")
        let results = await scanner.renameAlbumFolders([proposal])

        let result = try #require(results.first)
        #expect(!result.succeeded)
        #expect(result.errorDescription == TagWriteError.folderAccessUnavailable.errorDescription)
    }

    @Test func analyzeSpectrumSetsFailedOutcomeForEveryTarget() async throws {
        let folder = try Self.makePlainTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // analyzeSpectrum only targets readable files, so this needs a real
        // playable fixture — an empty/garbage file is filtered out before
        // ever reaching the folder-access check.
        try Self.makeTestFLAC(at: folder.appendingPathComponent("track.flac"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)
        let file = try #require(scanner.files.first)

        scanner.analyzeSpectrum()

        var attempts = 0
        while scanner.isAnalyzingSpectrum, attempts < 100 {
            try await Task.sleep(nanoseconds: 20_000_000)
            attempts += 1
        }

        guard case .failed(let message) = scanner.spectralResults[file.url] else {
            Issue.record("Expected a .failed outcome, got \(String(describing: scanner.spectralResults[file.url]))")
            return
        }
        #expect(message == TagWriteError.folderAccessUnavailable.errorDescription)
    }

    // MARK: - Fixture

    /// A plain temp folder — deliberately *not* routed through a
    /// security-scoped bookmark, so `startAccessingSecurityScopedResource()`
    /// on it returns false, reproducing the condition under test.
    private static func makePlainTempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Synthesizes a short sine wave, writes it as a WAV, then shells out to
    /// `afconvert` to produce a real, playable FLAC file — same technique
    /// as `FLACTagWriterTests`/`BackupFailureReportingTests`.
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
