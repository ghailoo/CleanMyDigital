//
//  MusicBrainzClientSearchTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

struct MusicBrainzClientSearchTests {
    @Test func includesReleaseTermAlongsideArtistAndRecordingWhenAlbumIsNonEmpty() throws {
        let query = try #require(MusicBrainzClient.searchQuery(artist: "2Pac", recording: "Changes", album: "Greatest Hits"))

        #expect(query.contains(#"artist:"2Pac""#))
        #expect(query.contains(#"recording:"Changes""#))
        #expect(query.contains(#"release:"Greatest Hits""#))
        #expect(query.contains(" AND "))
    }

    @Test func omitsReleaseTermWhenAlbumIsEmpty() throws {
        let query = try #require(MusicBrainzClient.searchQuery(artist: "2Pac", recording: "Changes", album: ""))

        #expect(!query.contains("release:"))
    }

    @Test func returnsNilWhenEveryTermIsEmpty() {
        #expect(MusicBrainzClient.searchQuery(artist: "", recording: "", album: "") == nil)
    }

    @Test func queryDerivesAlbumFromTheFilesAlbumTag() {
        let file = Self.makeFile(album: "Greatest Hits")
        #expect(MusicBrainzQuery(for: file).album == "Greatest Hits")
    }

    @Test func queryAlbumIsEmptyWhenFileHasNoAlbumTag() {
        let file = Self.makeFile(album: nil)
        #expect(MusicBrainzQuery(for: file).album == "")
    }

    // MARK: - Fixture

    private static func makeFile(album: String?) -> AudioFile {
        let url = URL(fileURLWithPath: "/Music/2Pac/Greatest Hits/01 Changes.mp3")
        return AudioFile(
            url: url,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            sizeBytes: 1024,
            duration: 180,
            bitrateKbps: nil,
            title: "Changes",
            artist: "2Pac",
            album: album,
            artworkThumbnail: nil,
            year: "1998",
            genre: "Hip Hop",
            trackNumber: "1",
            category: .albums,
            expectedArtist: "2Pac",
            isReadable: true
        )
    }
}
