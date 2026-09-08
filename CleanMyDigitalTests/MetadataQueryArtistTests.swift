//
//  MetadataQueryArtistTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

/// Verifies `MetadataQuery.artist(for:)` — the search-artist derivation
/// shared by `DiscogsQuery`/`MusicBrainzQuery` (both just call through to
/// this). Singles and Albums are genuinely organized by artist, so
/// `expectedArtist` (the containing folder's name) is preferred there.
/// Compilations are organized by *release*, not by artist — the folder is
/// the compilation's own name, never a track's artist — so this must never
/// prefer `expectedArtist` for that category, only ever the file's own
/// Artist tag. The real case this guards against: a folder like
/// "DJ Hits 100% '97-1" holding tracks by Madonna, Gala, Apollo 440, etc. —
/// treating the folder name as the artist sent every Discogs/MusicBrainz
/// search out asking for an artist that doesn't exist, for every track.
struct MetadataQueryArtistTests {
    // MARK: - Albums: expectedArtist preferred (unchanged behavior)

    @Test func albumsPrefersExpectedArtistOverTheArtistTag() {
        let file = Self.makeFile(category: .albums, artist: "Wrong Tag", expectedArtist: "2Pac")
        #expect(MetadataQuery.artist(for: file) == "2Pac")
    }

    @Test func albumsFallsBackToTheArtistTagWhenExpectedArtistIsNil() {
        let file = Self.makeFile(category: .albums, artist: "2Pac", expectedArtist: nil)
        #expect(MetadataQuery.artist(for: file) == "2Pac")
    }

    @Test func albumsReturnsEmptyWhenNeitherIsAvailable() {
        let file = Self.makeFile(category: .albums, artist: nil, expectedArtist: nil)
        #expect(MetadataQuery.artist(for: file) == "")
    }

    // MARK: - Singles: same preference order as Albums (unchanged behavior)

    @Test func singlesPrefersExpectedArtistOverTheArtistTag() {
        let file = Self.makeFile(category: .singles, artist: "Wrong Tag", expectedArtist: "2Pac")
        #expect(MetadataQuery.artist(for: file) == "2Pac")
    }

    @Test func singlesFallsBackToTheArtistTagWhenExpectedArtistIsNil() {
        let file = Self.makeFile(category: .singles, artist: "2Pac", expectedArtist: nil)
        #expect(MetadataQuery.artist(for: file) == "2Pac")
    }

    @Test func singlesReturnsEmptyWhenNeitherIsAvailable() {
        let file = Self.makeFile(category: .singles, artist: nil, expectedArtist: nil)
        #expect(MetadataQuery.artist(for: file) == "")
    }

    // MARK: - Compilations: the fix — the Artist tag always wins, expectedArtist never used

    @Test func compilationsUseTheArtistTagEvenWhenExpectedArtistIsPresent() {
        // The motivating real case: a "DJ Hits 100% '97-1" compilation
        // folder holding a Madonna track. `expectedArtist` here is the
        // compilation's own name — never a real artist — so it must be
        // ignored entirely in favor of the track's own Artist tag.
        let file = Self.makeFile(
            category: .compilations, artist: "Madonna", expectedArtist: "DJ Hits 100% '97-1")
        #expect(MetadataQuery.artist(for: file) == "Madonna")
    }

    @Test func compilationsReturnEmptyWhenTheArtistTagIsMissingRegardlessOfExpectedArtist() {
        let file = Self.makeFile(
            category: .compilations, artist: nil, expectedArtist: "DJ Hits 100% '97-1")
        #expect(MetadataQuery.artist(for: file) == "")
    }

    @Test func compilationsUseTheArtistTagWhenExpectedArtistIsAlreadyNil() {
        let file = Self.makeFile(category: .compilations, artist: "Gala", expectedArtist: nil)
        #expect(MetadataQuery.artist(for: file) == "Gala")
    }

    // MARK: - Fixtures

    private static func makeFile(category: LibraryCategory, artist: String?, expectedArtist: String?) -> AudioFile {
        let url = URL(fileURLWithPath: "/Music/Compilation Folder/01 Track.mp3")
        return AudioFile(
            url: url,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            sizeBytes: 1024,
            duration: 180,
            bitrateKbps: nil,
            title: "Track",
            artist: artist,
            album: "Some Album",
            artworkThumbnail: nil,
            year: "1997",
            genre: "Dance",
            trackNumber: "1",
            category: category,
            expectedArtist: expectedArtist,
            isReadable: true
        )
    }
}
