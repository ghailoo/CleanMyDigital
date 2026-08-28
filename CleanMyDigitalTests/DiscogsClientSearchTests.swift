//
//  DiscogsClientSearchTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

struct DiscogsClientSearchTests {
    @Test func includesReleaseTitleAlongsideArtistAndTrackWhenAlbumIsNonEmpty() throws {
        let url = try #require(DiscogsClient.searchURL(artist: "2Pac", track: "Changes", album: "Greatest Hits"))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(query.contains(URLQueryItem(name: "artist", value: "2Pac")))
        #expect(query.contains(URLQueryItem(name: "track", value: "Changes")))
        #expect(query.contains(URLQueryItem(name: "release_title", value: "Greatest Hits")))
    }

    @Test func omitsReleaseTitleWhenAlbumIsEmpty() throws {
        let url = try #require(DiscogsClient.searchURL(artist: "2Pac", track: "Changes", album: ""))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(!query.contains { $0.name == "release_title" })
    }

    @Test func fallsBackToQParamWhenArtistIsEmptyRegardlessOfAlbum() throws {
        let url = try #require(DiscogsClient.searchURL(artist: "", track: "Changes", album: "Greatest Hits"))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(query.contains(URLQueryItem(name: "q", value: "Changes")))
        #expect(!query.contains { $0.name == "artist" })
        #expect(!query.contains { $0.name == "release_title" })
    }

    // MARK: - shouldAttemptArtistOnlyFallback (search's third retry tier)

    @Test func attemptsArtistOnlyFallbackWhenAllowedWithBothArtistAndTrack() {
        #expect(DiscogsClient.shouldAttemptArtistOnlyFallback(
            artist: "Anouar Brahem", track: "En souvenir d'Iram", allowArtistOnlyFallback: true))
    }

    @Test func skipsArtistOnlyFallbackWhenTheCallerDisallowsIt() {
        // The automated batch lookup's case — see `search`'s doc comment on
        // why it passes `allowArtistOnlyFallback: false`.
        #expect(!DiscogsClient.shouldAttemptArtistOnlyFallback(
            artist: "Anouar Brahem", track: "En souvenir d'Iram", allowArtistOnlyFallback: false))
    }

    @Test func skipsArtistOnlyFallbackWhenArtistIsEmpty() {
        // The q-based free-text fallback already covers a missing artist.
        #expect(!DiscogsClient.shouldAttemptArtistOnlyFallback(
            artist: "", track: "En souvenir d'Iram", allowArtistOnlyFallback: true))
    }

    @Test func skipsArtistOnlyFallbackWhenTrackIsAlreadyEmpty() {
        // The first attempt was already effectively artist-only — retrying
        // would just repeat the same request.
        #expect(!DiscogsClient.shouldAttemptArtistOnlyFallback(
            artist: "Anouar Brahem", track: "", allowArtistOnlyFallback: true))
    }

    @Test func artistOnlySearchURLOmitsTheTrackParamButKeepsArtist() throws {
        // What `search`'s third tier actually sends — matches the confirmed
        // real-world case: "Anouar Brahem" + "En souvenir d'Iram" finds
        // nothing, but "Anouar Brahem" alone correctly finds the release.
        let url = try #require(DiscogsClient.searchURL(artist: "Anouar Brahem", track: "", album: ""))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(query.contains(URLQueryItem(name: "artist", value: "Anouar Brahem")))
        #expect(!query.contains { $0.name == "track" })
    }

    @Test func queryDerivesAlbumFromTheFilesAlbumTag() {
        let file = Self.makeFile(album: "Greatest Hits")
        #expect(DiscogsQuery(for: file).album == "Greatest Hits")
    }

    @Test func queryAlbumIsEmptyWhenFileHasNoAlbumTag() {
        let file = Self.makeFile(album: nil)
        #expect(DiscogsQuery(for: file).album == "")
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
