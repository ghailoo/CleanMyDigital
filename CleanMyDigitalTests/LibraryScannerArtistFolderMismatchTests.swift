//
//  LibraryScannerArtistFolderMismatchTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

/// Verifies `LibraryScanner.possibleArtistFolderMismatch` /
/// `misrootedArtistFolderExample` catch the real case of scanning an
/// artist's own album folder directly instead of its parent — every
/// file's `expectedArtist` (the first path component under the scanned
/// root) is derived purely from the folder structure, so an empty/garbage
/// audio file is enough to exercise it without synthesizing real audio.
struct LibraryScannerArtistFolderMismatchTests {
    @Test func flagsAScanRootedAtAnAlbumFolderInsteadOfItsParent() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let albumLikeFolder = folder.appendingPathComponent("2Pac - 1998 - Greatest Hits (Bootleg)")
        try FileManager.default.createDirectory(at: albumLikeFolder, withIntermediateDirectories: true)
        try Data().write(to: albumLikeFolder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)

        #expect(scanner.possibleArtistFolderMismatch)
        #expect(scanner.misrootedArtistFolderExample == "2Pac - 1998 - Greatest Hits (Bootleg)")
    }

    @Test func doesNotFlagACorrectlyRootedArtistFolder() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let artistFolder = folder.appendingPathComponent("2Pac")
        let albumFolder = artistFolder.appendingPathComponent("Greatest Hits")
        try FileManager.default.createDirectory(at: albumFolder, withIntermediateDirectories: true)
        try Data().write(to: albumFolder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)

        #expect(!scanner.possibleArtistFolderMismatch)
        #expect(scanner.misrootedArtistFolderExample == nil)
    }

    @Test func doesNotFlagOutsideOfAlbumsCategoryEvenWithAnAlbumLikeFolderName() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let albumLikeFolder = folder.appendingPathComponent("2Pac - 1998 - Greatest Hits (Bootleg)")
        try FileManager.default.createDirectory(at: albumLikeFolder, withIntermediateDirectories: true)
        try Data().write(to: albumLikeFolder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .compilations)

        #expect(!scanner.possibleArtistFolderMismatch)
        #expect(scanner.misrootedArtistFolderExample == nil)
    }

    private static func makeTempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
