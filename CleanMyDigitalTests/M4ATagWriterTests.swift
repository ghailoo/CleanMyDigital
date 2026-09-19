//
//  M4ATagWriterTests.swift
//  CleanMyDigitalTests
//

import Testing
import AVFoundation
@testable import CleanMyDigital

struct M4ATagWriterTests {
    @Test func writesFieldsAndKeepsAudioPlayable() async throws {
        let m4aURL = try await Self.makeTestM4A()
        defer { try? FileManager.default.removeItem(at: m4aURL) }

        let originalDuration = try await AVURLAsset(url: m4aURL).load(.duration).seconds

        var changes = TagChanges()
        changes.title = "M4A Title"
        changes.artist = "M4A Artist"
        changes.album = "M4A Album"
        changes.year = "2022"
        changes.genre = "Downtempo"
        changes.trackNumber = "2"

        try await M4ATagWriter.write(changes, to: m4aURL)

        let metadata = try await AVURLAsset(url: m4aURL).load(.metadata)
        #expect(await Self.stringValue(metadata, .iTunesMetadataSongName) == "M4A Title")
        #expect(await Self.stringValue(metadata, .iTunesMetadataArtist) == "M4A Artist")
        #expect(await Self.stringValue(metadata, .iTunesMetadataAlbum) == "M4A Album")
        #expect(await Self.stringValue(metadata, .iTunesMetadataReleaseDate) == "2022")
        #expect(await Self.stringValue(metadata, .iTunesMetadataUserGenre) == "Downtempo")

        let asset = AVURLAsset(url: m4aURL)
        #expect(try await asset.load(.isPlayable))
        let newDuration = try await asset.load(.duration).seconds
        #expect(abs(newDuration - originalDuration) < 0.05)
    }

    @Test func neverOverwritesAnAlreadyPresentField() async throws {
        let m4aURL = try await Self.makeTestM4A()
        defer { try? FileManager.default.removeItem(at: m4aURL) }

        var firstWrite = TagChanges()
        firstWrite.title = "Original M4A Title"
        try await M4ATagWriter.write(firstWrite, to: m4aURL)

        var secondWrite = TagChanges()
        secondWrite.title = "Should Never Appear"
        secondWrite.artist = "New M4A Artist"
        try await M4ATagWriter.write(secondWrite, to: m4aURL)

        let metadata = try await AVURLAsset(url: m4aURL).load(.metadata)
        #expect(await Self.stringValue(metadata, .iTunesMetadataSongName) == "Original M4A Title")
        #expect(await Self.stringValue(metadata, .iTunesMetadataArtist) == "New M4A Artist")
    }

    /// Isolates just the fixture precondition: does the export actually
    /// preserve a whitespace-only metadata item as a real, present atom?
    /// If this fails, the fixture technique itself is the problem, not
    /// the writer.
    @Test func fixtureActuallyHasAnEmptyButPresentYearAtom() async throws {
        let m4aURL = try await Self.makeTestM4A(withEmptyYearAndGenre: true)
        defer { try? FileManager.default.removeItem(at: m4aURL) }

        let beforeMetadata = try await AVURLAsset(url: m4aURL).load(.metadata)
        let existingYearItems = AVMetadataItem.metadataItems(
            from: beforeMetadata, filteredByIdentifier: .iTunesMetadataReleaseDate)
        #expect(!existingYearItems.isEmpty)

        let existingYearValue = await Self.stringValue(beforeMetadata, .iTunesMetadataReleaseDate)
        #expect(existingYearValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
    }

    /// The exact bug reported in production: a file whose Year/Genre atoms
    /// are already *present* but empty (as some sources leave them) should
    /// still be writable — matching the scanner's own definition of
    /// "missing" (empty value), not mere atom presence.
    @Test func writesOverAnEmptyButPresentExistingAtom() async throws {
        let m4aURL = try await Self.makeTestM4A(withEmptyYearAndGenre: true)
        defer { try? FileManager.default.removeItem(at: m4aURL) }

        var changes = TagChanges()
        changes.year = "1996"
        changes.genre = "Electronic, Euro House"

        try await M4ATagWriter.write(changes, to: m4aURL)

        let afterMetadata = try await AVURLAsset(url: m4aURL).load(.metadata)
        #expect(await Self.stringValue(afterMetadata, .iTunesMetadataReleaseDate) == "1996")
        #expect(await Self.stringValue(afterMetadata, .iTunesMetadataUserGenre) == "Electronic, Euro House")
    }

    @Test func replacesAlbumWithExactlyOneAlbumItem() async throws {
        let m4aURL = try await Self.makeTestM4A()
        defer { try? FileManager.default.removeItem(at: m4aURL) }

        var firstWrite = TagChanges()
        firstWrite.album = "Dreams (Will Come Alive) (CDM)"
        try await M4ATagWriter.write(firstWrite, to: m4aURL)

        var replace = TagChanges()
        replace.album = "Dreams (Will Come Alive)"
        replace.replacing = [.album]
        try await M4ATagWriter.write(replace, to: m4aURL)

        let metadata = try await AVURLAsset(url: m4aURL).load(.metadata)
        #expect(AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .iTunesMetadataAlbum).count == 1)
        #expect(await Self.stringValue(metadata, .iTunesMetadataAlbum) == "Dreams (Will Come Alive)")
    }

    /// Year and Genre in an M4A must be visible to the scanner's lookup —
    /// AVFoundation reports iTunes keys as numbers, so the name-based match
    /// alone found neither (every M4A showed them as missing).
    @Test func scannerLookupSeesM4AYearAndGenre() async throws {
        let m4aURL = try await Self.makeTestM4A()
        defer { try? FileManager.default.removeItem(at: m4aURL) }

        var changes = TagChanges()
        changes.year = "1991"
        changes.genre = "Euro-House, Euro-Dance"
        try await M4ATagWriter.write(changes, to: m4aURL)

        let items = try await AVURLAsset(url: m4aURL).load(.metadata)
        #expect(await LibraryScanner.stringValue(
            in: items, identifiers: [.commonIdentifierCreationDate, .iTunesMetadataReleaseDate],
            keys: ["TYER", "TDRC", "©day", "year", "YEAR"]) == "1991")
        #expect(await LibraryScanner.stringValue(
            in: items, identifiers: [.iTunesMetadataUserGenre],
            keys: ["TCON", "©gen", "gnre", "genre", "GENRE"]) == "Euro-House, Euro-Dance")
    }

    @Test func throwsNoChangesWhenEveryFieldAlreadyHasARealValue() async throws {
        let m4aURL = try await Self.makeTestM4A()
        defer { try? FileManager.default.removeItem(at: m4aURL) }

        var firstWrite = TagChanges()
        firstWrite.year = "2020"
        try await M4ATagWriter.write(firstWrite, to: m4aURL)

        var secondWrite = TagChanges()
        secondWrite.year = "1999"

        await #expect(throws: TagWriteError.self) {
            try await M4ATagWriter.write(secondWrite, to: m4aURL)
        }
    }

    // MARK: - Helpers

    private static func stringValue(_ items: [AVMetadataItem], _ identifier: AVMetadataIdentifier) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first else {
            return nil
        }
        return try? await item.load(.stringValue)
    }

    // MARK: - Fixture generation

    private enum FixtureError: Error {
        case bufferCreationFailed
        case exportSessionCreationFailed
        case exportFailed(String)
    }

    /// Synthesizes a short sine wave WAV, then exports it to M4A/AAC via
    /// `AVAssetExportSession` — the same encoder path `M4ATagWriter` itself
    /// uses. When `withEmptyYearAndGenre` is true, the export carries
    /// empty-string Year/Genre metadata items, simulating a file whose
    /// atoms are present but blank (the real-world scenario that exposed
    /// the bug).
    private static func makeTestM4A(withEmptyYearAndGenre: Bool = false) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let wavURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        let m4aURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")

        try writeSineWave(to: wavURL)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        guard let exportSession = AVAssetExportSession(
            asset: AVURLAsset(url: wavURL), presetName: AVAssetExportPresetAppleM4A)
        else { throw FixtureError.exportSessionCreationFailed }

        if withEmptyYearAndGenre {
            func emptyItem(_ identifier: AVMetadataIdentifier) -> AVMetadataItem {
                let item = AVMutableMetadataItem()
                item.identifier = identifier
                item.value = " " as NSString
                item.extendedLanguageTag = "und"
                return item
            }
            exportSession.metadata = [
                emptyItem(.iTunesMetadataReleaseDate),
                emptyItem(.iTunesMetadataUserGenre),
            ]
        }

        do {
            try await exportSession.export(to: m4aURL, as: .m4a)
        } catch {
            throw FixtureError.exportFailed(error.localizedDescription)
        }
        return m4aURL
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
}
