//
//  AlbumCompletenessCheckerTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

struct AlbumCompletenessCheckerTests {
    @Test func yearIsFirstNonEmptyYearAmongGroupFiles() {
        let noYear = Self.makeFile(
            path: "/Library/Albums/Artist/Album/01 track.flac", album: "Album", year: nil)
        let withYear = Self.makeFile(
            path: "/Library/Albums/Artist/Album/02 track.flac", album: "Album", year: "1995")

        let groups = AlbumCompletenessChecker.groups(for: [noYear, withYear])
        #expect(groups.first?.year == "1995")
    }

    @Test func yearIsNilWhenNoFileHasOne() {
        let file = Self.makeFile(
            path: "/Library/Albums/Artist/Album/01 track.flac", album: "Album", year: nil)

        let groups = AlbumCompletenessChecker.groups(for: [file])
        #expect(groups.first?.year == nil)
    }

    // MARK: - Category: Albums and Compilations are grouped, Singles is not

    /// `groups(for:)` was widened to include Compilations so
    /// `ApplyFoundMatchesSheetView`'s section-level "re-match this whole
    /// folder" control could reach them too (see its own doc comment) — a
    /// compilation is exactly as much "one release with a tracklist" as an
    /// album is.
    @Test func groupsIncludeCompilationsFiles() {
        let file = Self.makeFile(
            path: "/Library/Compilations/DJ Hits 97-1/01 track.mp3", album: "DJ Hits 97-1", year: nil,
            category: .compilations)

        let groups = AlbumCompletenessChecker.groups(for: [file])
        #expect(groups.count == 1)
        #expect(groups.first?.category == .compilations)
    }

    @Test func groupsExcludeSinglesFiles() {
        let file = Self.makeFile(
            path: "/Library/Singles/Artist/track.mp3", album: nil, year: nil, category: .singles)

        #expect(AlbumCompletenessChecker.groups(for: [file]).isEmpty)
    }

    @Test func groupsCategoryDefaultsToAlbumsForAlbumsFiles() {
        let file = Self.makeFile(
            path: "/Library/Albums/Artist/Album/01 track.flac", album: "Album", year: nil, category: .albums)

        #expect(AlbumCompletenessChecker.groups(for: [file]).first?.category == .albums)
    }

    /// A folder mixing Albums and Compilations files can't actually occur
    /// in practice — a single scan is always one category throughout (see
    /// `LibraryScanner.scan`) — but confirms `groups(for:)` doesn't crash
    /// and reads the category from whichever file happens to be first in
    /// that (impossible) case, rather than silently dropping the folder.
    @Test func eachGroupIsIndependentAcrossCategories() {
        let albumFile = Self.makeFile(
            path: "/Library/Albums/Artist/Album/01 track.flac", album: "Album", year: nil, category: .albums)
        let compilationFile = Self.makeFile(
            path: "/Library/Compilations/DJ Hits/01 track.mp3", album: "DJ Hits", year: nil,
            category: .compilations)

        let groups = AlbumCompletenessChecker.groups(for: [albumFile, compilationFile])
        #expect(groups.count == 2)
        #expect(groups.first { $0.folderURL.lastPathComponent == "Album" }?.category == .albums)
        #expect(groups.first { $0.folderURL.lastPathComponent == "DJ Hits" }?.category == .compilations)
    }

    // MARK: - Fixture

    private static func makeFile(
        path: String, album: String?, year: String?, category: LibraryCategory = .albums
    ) -> AudioFile {
        let url = URL(fileURLWithPath: path)
        return AudioFile(
            url: url,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            sizeBytes: 1024,
            duration: 180,
            bitrateKbps: nil,
            title: "Title",
            artist: "Artist",
            album: album,
            artworkThumbnail: nil,
            year: year,
            genre: "Electronic",
            trackNumber: nil,
            category: category,
            expectedArtist: "Artist",
            isReadable: true
        )
    }
}
