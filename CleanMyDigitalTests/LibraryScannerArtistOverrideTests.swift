//
//  LibraryScannerArtistOverrideTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

/// Verifies the "treat this folder as the artist" scan mode:
/// `LibraryScanner.scan(folder:category:artistOverride:)` stamps every
/// file's `expectedArtist` with the fixed override instead of computing it
/// from folder depth, only for Albums scans, persists the override for a
/// subsequent explicit rescan the same way `category` already does, and
/// clears it on a fresh scan that doesn't pass one. Uses empty/garbage
/// audio files — `expectedArtist` is derived purely from folder structure
/// and the override, same technique as
/// `LibraryScannerArtistFolderMismatchTests`.
struct LibraryScannerArtistOverrideTests {
    @Test func overrideBecomesEveryFilesExpectedArtistRegardlessOfSubfolderDepth() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let shallow = folder.appendingPathComponent("Greatest Hits")
        try FileManager.default.createDirectory(at: shallow, withIntermediateDirectories: true)
        try Data().write(to: shallow.appendingPathComponent("track1.mp3"))

        let deep = folder.appendingPathComponent("Bonus").appendingPathComponent("Disc 2")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try Data().write(to: deep.appendingPathComponent("track2.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums, artistOverride: "2Pac")

        #expect(scanner.files.count == 2)
        #expect(scanner.files.allSatisfy { $0.expectedArtist == "2Pac" })
    }

    @Test func overrideDoesNotApplyOutsideOfAlbumsCategory() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let subfolder = folder.appendingPathComponent("Greatest Hits")
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        try Data().write(to: subfolder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .compilations, artistOverride: "2Pac")

        // Override is only honored for Albums scans — Compilations still
        // gets the normal folder-depth calculation.
        #expect(scanner.files.first?.expectedArtist == "Greatest Hits")
    }

    @Test func rescanExplicitlyForwardingTheStoredOverrideReappliesIt() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let subfolder = folder.appendingPathComponent("Greatest Hits")
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        try Data().write(to: subfolder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums, artistOverride: "2Pac")
        #expect(scanner.artistOverride == "2Pac")

        // Mirrors ContentView's "Rescan" button, which explicitly forwards
        // `scanner.artistOverride` rather than letting it default to nil.
        let category = try #require(scanner.category)
        await scanner.scan(folder: folder, category: category, artistOverride: scanner.artistOverride)

        #expect(scanner.artistOverride == "2Pac")
        #expect(scanner.files.allSatisfy { $0.expectedArtist == "2Pac" })
    }

    @Test func aFreshScanWithNoOverrideArgumentClearsAPreviouslyStoredOne() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let subfolder = folder.appendingPathComponent("Greatest Hits")
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        try Data().write(to: subfolder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums, artistOverride: "2Pac")
        #expect(scanner.artistOverride == "2Pac")

        await scanner.scan(folder: folder, category: .albums)

        #expect(scanner.artistOverride == nil)
        #expect(scanner.files.first?.expectedArtist == "Greatest Hits")
    }

    @Test func overrideSuppressesTheMisrootedFolderWarning() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let albumLikeFolder = folder.appendingPathComponent("2Pac - 1998 - Greatest Hits (Bootleg)")
        try FileManager.default.createDirectory(at: albumLikeFolder, withIntermediateDirectories: true)
        try Data().write(to: albumLikeFolder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums, artistOverride: folder.lastPathComponent)

        #expect(!scanner.possibleArtistFolderMismatch)
        #expect(scanner.misrootedArtistFolderExample == nil)
        #expect(scanner.files.first?.expectedArtist == folder.lastPathComponent)
    }

    /// The motivating case for always-available "Treat This Folder as the
    /// Artist" toolbar button (as opposed to only the auto-detected
    /// mis-rooted-scan banner): an extra category-level folder like
    /// "Studio Albums" produces an `expectedArtist` that doesn't look like
    /// an album name to `AudioFile.looksLikeAlbumFolderName` (no year, no
    /// " - " separators) — so `possibleArtistFolderMismatch` never fires
    /// and the banner never appears — yet the override still resolves the
    /// resulting Artist Mismatch correctly once triggered.
    @Test func overrideFixesArtistMismatchBehindAnExtraCategoryLevelFolderTheHeuristicMisses() async throws {
        let folder = try Self.makeTempFolder()
        let artistFolder = folder.appendingPathComponent("Pink Floyd")
        defer { try? FileManager.default.removeItem(at: folder) }

        let albumFolder = artistFolder.appendingPathComponent("Studio Albums").appendingPathComponent("The Wall")
        try FileManager.default.createDirectory(at: albumFolder, withIntermediateDirectories: true)
        try Data().write(to: albumFolder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: artistFolder, category: .albums)

        // Confirms the motivating gap: the heuristic-driven banner would
        // not have appeared for this folder structure.
        #expect(scanner.files.first?.expectedArtist == "Studio Albums")
        #expect(!scanner.possibleArtistFolderMismatch)

        // Same call the toolbar button (and the banner's own fix button)
        // makes: rescan with the scanned folder's own name as the override.
        await scanner.scan(folder: artistFolder, category: scanner.category ?? .albums,
                            artistOverride: artistFolder.lastPathComponent)

        #expect(scanner.files.allSatisfy { $0.expectedArtist == "Pink Floyd" })
    }

    // MARK: - hasArtistMismatch under an override-sourced expectedArtist

    /// `AudioFile.hasArtistMismatch` only ever reads `expectedArtist` —
    /// it has no idea whether that value came from folder-depth or from
    /// `artistOverride`, so constructing it directly (no real scan needed)
    /// is enough to confirm the override case behaves the same as any other.
    @Test func hasArtistMismatchFlagsAFileWhoseRealArtistTagDiffersFromTheOverride() {
        let file = Self.makeFile(artist: "Wrong Artist", expectedArtist: "2Pac")
        #expect(file.hasArtistMismatch)
    }

    @Test func hasArtistMismatchIsFalseWhenTheRealArtistTagMatchesTheOverride() {
        let file = Self.makeFile(artist: "2Pac", expectedArtist: "2Pac")
        #expect(!file.hasArtistMismatch)
    }

    // MARK: - Fixtures

    private static func makeTempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func makeFile(artist: String?, expectedArtist: String?) -> AudioFile {
        let url = URL(fileURLWithPath: "/Music/2Pac/Greatest Hits/01 Changes.mp3")
        return AudioFile(
            url: url,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            sizeBytes: 1024,
            duration: 180,
            bitrateKbps: nil,
            title: "Changes",
            artist: artist,
            album: "Greatest Hits",
            artworkThumbnail: nil,
            year: "1998",
            genre: "Hip Hop",
            trackNumber: "1",
            category: .albums,
            expectedArtist: expectedArtist,
            isReadable: true
        )
    }
}
