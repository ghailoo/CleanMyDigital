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

    // MARK: - Proactive auto-detection

    /// The motivating everyday case: an artist's own folder scanned
    /// directly, containing several album subfolders that all look like
    /// album names. Detection should fire on its own — no warning banner,
    /// no manual click needed — stamping every file's `expectedArtist` with
    /// the scanned root's own name, exactly as if the user had clicked
    /// "Treat This Folder as the Artist" themselves.
    @Test func autoDetectsAnArtistFolderFullOfAlbumLikeSubfolders() async throws {
        let artistFolder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: artistFolder) }

        for album in ["2Pac - 1996 - All Eyez on Me", "2Pac - 1998 - Greatest Hits", "2Pac - 1999 - Still I Rise"] {
            let albumFolder = artistFolder.appendingPathComponent(album)
            try FileManager.default.createDirectory(at: albumFolder, withIntermediateDirectories: true)
            try Data().write(to: albumFolder.appendingPathComponent("track.mp3"))
        }

        let scanner = LibraryScanner()
        await scanner.scan(folder: artistFolder, category: .albums)

        #expect(scanner.artistOverrideAutoDetected)
        #expect(scanner.artistOverride == artistFolder.lastPathComponent)
        #expect(scanner.files.allSatisfy { $0.expectedArtist == artistFolder.lastPathComponent })
        #expect(!scanner.possibleArtistFolderMismatch)
        #expect(scanner.misrootedArtistFolderExample == nil)
    }

    /// One oddly-named folder ("Live") among several genuine album folders
    /// shouldn't block detection — two of the three distinct subfolder
    /// names look album-like, meeting the two-thirds threshold.
    @Test func autoDetectionToleratesOneOddlyNamedFolderAmongAlbumLikeOnes() async throws {
        let artistFolder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: artistFolder) }

        for album in ["2Pac - 1996 - All Eyez on Me", "2Pac - 1998 - Greatest Hits", "Live"] {
            let albumFolder = artistFolder.appendingPathComponent(album)
            try FileManager.default.createDirectory(at: albumFolder, withIntermediateDirectories: true)
            try Data().write(to: albumFolder.appendingPathComponent("track.mp3"))
        }

        let scanner = LibraryScanner()
        await scanner.scan(folder: artistFolder, category: .albums)

        #expect(scanner.artistOverrideAutoDetected)
        #expect(scanner.artistOverride == artistFolder.lastPathComponent)
    }

    /// A single album-like subfolder is genuinely ambiguous (see
    /// `LibraryScanner.detectArtistFolderOverride`'s doc comment) and isn't
    /// enough evidence on its own — detection requires at least 2 distinct
    /// folder names. This is also exactly
    /// `LibraryScannerArtistFolderMismatchTests.flagsAScanRootedAtAnAlbumFolderInsteadOfItsParent`'s
    /// fixture, confirming the reactive banner still fires unchanged for it.
    @Test func doesNotAutoDetectFromASingleAlbumLikeSubfolder() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let albumLikeFolder = folder.appendingPathComponent("2Pac - 1998 - Greatest Hits (Bootleg)")
        try FileManager.default.createDirectory(at: albumLikeFolder, withIntermediateDirectories: true)
        try Data().write(to: albumLikeFolder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)

        #expect(!scanner.artistOverrideAutoDetected)
        #expect(scanner.artistOverride == nil)
        #expect(scanner.possibleArtistFolderMismatch)
    }

    /// A normal multi-artist parent folder — each subfolder is an artist
    /// name, none of which look like an album name — must not trigger
    /// detection.
    @Test func doesNotAutoDetectAnOrdinaryMultiArtistParentFolder() async throws {
        let parentFolder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: parentFolder) }

        for artist in ["2Pac", "Notorious B.I.G.", "Nas"] {
            let artistAlbumFolder = parentFolder.appendingPathComponent(artist).appendingPathComponent("Album")
            try FileManager.default.createDirectory(at: artistAlbumFolder, withIntermediateDirectories: true)
            try Data().write(to: artistAlbumFolder.appendingPathComponent("track.mp3"))
        }

        let scanner = LibraryScanner()
        await scanner.scan(folder: parentFolder, category: .albums)

        #expect(!scanner.artistOverrideAutoDetected)
        #expect(scanner.artistOverride == nil)
    }

    /// Below the two-thirds threshold: only 1 of 3 distinct subfolder names
    /// looks album-like, so detection must not fire even though the count
    /// requirement (>= 2 distinct names) is met.
    @Test func doesNotAutoDetectBelowTheTwoThirdsThreshold() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        for name in ["2Pac - 1998 - Greatest Hits", "Studio Sessions", "Extras"] {
            let subfolder = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
            try Data().write(to: subfolder.appendingPathComponent("track.mp3"))
        }

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)

        #expect(!scanner.artistOverrideAutoDetected)
        #expect(scanner.artistOverride == nil)
    }

    /// An explicitly passed override (e.g. a rescan forwarding
    /// `scanner.artistOverride`) always wins outright — detection must not
    /// run, and `artistOverrideAutoDetected` must stay false, even though
    /// the folder structure would otherwise qualify.
    @Test func explicitOverrideSuppressesAutoDetectionEvenWhenTheHeuristicWouldMatch() async throws {
        let artistFolder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: artistFolder) }

        for album in ["2Pac - 1996 - All Eyez on Me", "2Pac - 1998 - Greatest Hits"] {
            let albumFolder = artistFolder.appendingPathComponent(album)
            try FileManager.default.createDirectory(at: albumFolder, withIntermediateDirectories: true)
            try Data().write(to: albumFolder.appendingPathComponent("track.mp3"))
        }

        let scanner = LibraryScanner()
        await scanner.scan(folder: artistFolder, category: .albums, artistOverride: "2Pac")

        #expect(!scanner.artistOverrideAutoDetected)
        #expect(scanner.artistOverride == "2Pac")
    }

    /// Only Albums scans auto-detect — Compilations/Singles keep the normal
    /// folder-depth calculation even with an album-like folder structure.
    @Test func autoDetectionDoesNotApplyOutsideOfAlbumsCategory() async throws {
        let artistFolder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: artistFolder) }

        for album in ["2Pac - 1996 - All Eyez on Me", "2Pac - 1998 - Greatest Hits"] {
            let albumFolder = artistFolder.appendingPathComponent(album)
            try FileManager.default.createDirectory(at: albumFolder, withIntermediateDirectories: true)
            try Data().write(to: albumFolder.appendingPathComponent("track.mp3"))
        }

        let scanner = LibraryScanner()
        await scanner.scan(folder: artistFolder, category: .compilations)

        #expect(!scanner.artistOverrideAutoDetected)
        #expect(scanner.artistOverride == nil)
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

    // MARK: - hasArtistMismatch's one-directional fuzzy match

    /// The case this fuzzy match fixes: a trio billing for one release,
    /// correctly tagged, filed under the artist's overall folder — `artist`
    /// extends `expectedArtist`, so this is no longer flagged.
    @Test func hasArtistMismatchIsFalseWhenTheArtistTagExtendsTheExpectedArtist() {
        let file = Self.makeFile(artist: "Anouar Brahem Trio", expectedArtist: "Anouar Brahem")
        #expect(!file.hasArtistMismatch)
    }

    /// The case this fuzzy match must NOT swallow: a scan rooted at an
    /// album folder instead of its artist parent produces a garbled
    /// `expectedArtist` like "1995 - C + C Music Factory", which also
    /// contains the real artist name as a substring — but in the *reverse*
    /// direction from the trio case above. Accepting that direction too
    /// would silently stop flagging exactly the mismatch
    /// `possibleArtistFolderMismatch`/the "Treat as Artist" banner exists to
    /// catch, so this must still be flagged.
    @Test func hasArtistMismatchStillFlagsAGarbledExpectedArtistThatIsASupersetOfTheRealArtist() {
        let file = Self.makeFile(artist: "C + C Music Factory", expectedArtist: "1995 - C + C Music Factory")
        #expect(file.hasArtistMismatch)
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
