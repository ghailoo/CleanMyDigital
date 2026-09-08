//
//  LibraryScannerMultiFolderTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

/// Verifies scanning several roots as one library — Singles are commonly
/// filed one folder per artist, and scanning their shared parent instead
/// would mean walking everything else underneath it.
///
/// The load-bearing part isn't the enumeration (a flat-map of what already
/// worked) but that each file stays attached to the root it came from:
/// backups, duplicate moves and expected-artist derivation are all defined
/// *relative to a root*, and once several are in play there's no single
/// "the scanned folder" to measure against.
/// `@MainActor` because `LibraryScanner` is — reading its state from a
/// nonisolated test body is only a warning today but an error under the
/// Swift 6 language mode.
@MainActor
struct LibraryScannerMultiFolderTests {
    @Test func scansEveryChosenFolderIntoOneFileList() async throws {
        let artistA = try Self.makeTempFolder()
        let artistB = try Self.makeTempFolder()
        defer {
            try? FileManager.default.removeItem(at: artistA)
            try? FileManager.default.removeItem(at: artistB)
        }
        try Data().write(to: artistA.appendingPathComponent("one.mp3"))
        try Data().write(to: artistA.appendingPathComponent("two.mp3"))
        try Data().write(to: artistB.appendingPathComponent("three.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folders: [artistA, artistB], category: .singles)

        #expect(scanner.state == .finished)
        #expect(scanner.files.count == 3)
        #expect(scanner.totalCount == 3)
        #expect(scanner.scannedFolders == [artistA, artistB])
        #expect(scanner.hasScannedFolder)
    }

    /// `scannedFolder` answers "the one root" and so has to be nil for a
    /// multi-folder scan — the single-folder-only actions that read it
    /// ("Treat This Folder as the Artist") would otherwise silently act on
    /// whichever folder happened to be chosen first.
    @Test func singleFolderAccessorIsNilForAMultiFolderScanButSetForOne() async throws {
        let artistA = try Self.makeTempFolder()
        let artistB = try Self.makeTempFolder()
        defer {
            try? FileManager.default.removeItem(at: artistA)
            try? FileManager.default.removeItem(at: artistB)
        }
        try Data().write(to: artistA.appendingPathComponent("one.mp3"))
        try Data().write(to: artistB.appendingPathComponent("two.mp3"))

        let scanner = LibraryScanner()

        await scanner.scan(folders: [artistA, artistB], category: .singles)
        #expect(scanner.scannedFolder == nil)
        #expect(scanner.hasScannedFolder)

        await scanner.scan(folders: [artistA], category: .singles)
        #expect(scanner.scannedFolder == artistA)
    }

    @Test func resolvesEachFileToTheRootItCameFrom() async throws {
        let artistA = try Self.makeTempFolder()
        let artistB = try Self.makeTempFolder()
        defer {
            try? FileManager.default.removeItem(at: artistA)
            try? FileManager.default.removeItem(at: artistB)
        }
        let inA = artistA.appendingPathComponent("one.mp3")
        let inB = artistB.appendingPathComponent("two.mp3")
        try Data().write(to: inA)
        try Data().write(to: inB)

        let scanner = LibraryScanner()
        await scanner.scan(folders: [artistA, artistB], category: .singles)

        #expect(scanner.root(containing: inA) == artistA)
        #expect(scanner.root(containing: inB) == artistB)
    }

    /// Nested selections resolve to the nearest enclosing root, so a
    /// backup or duplicate move lands beside the file rather than at the
    /// top of an outer folder that also happened to be selected.
    @Test func resolvesToTheDeepestRootWhenSelectionsAreNested() async throws {
        let outer = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: outer) }
        let inner = outer.appendingPathComponent("Artist")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let track = inner.appendingPathComponent("one.mp3")
        try Data().write(to: track)

        let scanner = LibraryScanner()
        await scanner.scan(folders: [outer, inner], category: .singles)

        #expect(scanner.root(containing: track) == inner)
    }

    @Test func hasNoRootForAFileOutsideEveryScannedFolder() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("one.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folders: [folder], category: .singles)

        #expect(scanner.root(containing: URL(fileURLWithPath: "/Elsewhere/other.mp3")) == nil)
    }

    /// The artist-folder override answers "was a single artist's own
    /// folder scanned directly", which a multi-folder scan doesn't pose —
    /// and each chosen folder here *is* album-like, exactly the shape that
    /// trips detection when there's only one root.
    @Test func doesNotAutoDetectAnArtistFolderOverrideAcrossSeveralRoots() async throws {
        let artistA = try Self.makeTempFolder()
        let artistB = try Self.makeTempFolder()
        defer {
            try? FileManager.default.removeItem(at: artistA)
            try? FileManager.default.removeItem(at: artistB)
        }
        for root in [artistA, artistB] {
            for album in ["2Pac - 1996 - All Eyez on Me", "2Pac - 1998 - Greatest Hits"] {
                let albumFolder = root.appendingPathComponent(album)
                try FileManager.default.createDirectory(at: albumFolder, withIntermediateDirectories: true)
                try Data().write(to: albumFolder.appendingPathComponent("track.mp3"))
            }
        }

        let scanner = LibraryScanner()
        await scanner.scan(folders: [artistA, artistB], category: .albums)

        #expect(scanner.artistOverride == nil)
        #expect(!scanner.artistOverrideAutoDetected)

        // The same folder alone still detects, so this is the multi-root
        // guard doing the work rather than the fixture failing to qualify.
        await scanner.scan(folders: [artistA], category: .albums)
        #expect(scanner.artistOverride == artistA.lastPathComponent)
        #expect(scanner.artistOverrideAutoDetected)
    }

    @Test func resetClearsEveryScannedFolder() async throws {
        let artistA = try Self.makeTempFolder()
        let artistB = try Self.makeTempFolder()
        defer {
            try? FileManager.default.removeItem(at: artistA)
            try? FileManager.default.removeItem(at: artistB)
        }
        try Data().write(to: artistA.appendingPathComponent("one.mp3"))
        try Data().write(to: artistB.appendingPathComponent("two.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folders: [artistA, artistB], category: .singles)
        #expect(scanner.scannedFolders.count == 2)

        scanner.reset()

        #expect(scanner.scannedFolders.isEmpty)
        #expect(!scanner.hasScannedFolder)
        #expect(scanner.scannedFolder == nil)
    }

    private static func makeTempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
