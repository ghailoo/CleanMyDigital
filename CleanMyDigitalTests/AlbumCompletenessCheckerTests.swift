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

    // MARK: - Fixture

    private static func makeFile(path: String, album: String?, year: String?) -> AudioFile {
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
            category: .albums,
            expectedArtist: "Artist",
            isReadable: true
        )
    }
}
