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

    /// `DiscogsQuery.album` goes through `MetadataQuery.albumSearchTerm(for:)`
    /// — an empty Album tag falls back to the file's own containing folder
    /// name ("Greatest Hits" for this fixture's path), not an empty string.
    @Test func queryAlbumFallsBackToTheContainingFolderNameWhenFileHasNoAlbumTag() {
        let file = Self.makeFile(album: nil)
        #expect(DiscogsQuery(for: file).album == "Greatest Hits")
    }

    // MARK: - DiscogsQuery per-category seeding

    /// The real case that motivated the "Various" artist rule: Discogs
    /// credits a compilation release to "Various", never to any one
    /// track's artist — searching "Apollo Four Forty" (or Discogs' own
    /// canonical "Apollo 440") plus the track title returns nothing, but
    /// "Various" plus the release title (this file's Album tag) finds the
    /// actual release.
    ///
    /// `track` *is* populated here, unlike an earlier version of this rule
    /// — leaving it empty was itself an over-correction from a single
    /// probe that doesn't generalize (see `DiscogsQuery`'s doc comment);
    /// `DiscogsClient.searchCompilation` is what actually falls back to
    /// dropping it, only if a search with it comes back empty.
    @Test func compilationsHardcodeArtistToVariousButStillPopulateTrack() {
        let file = Self.makeFile(
            category: .compilations,
            fileName: "03 Apollo Four Forty - Ain't Talkin' Bout Dub.mp3",
            artist: "Apollo Four Forty",
            expectedArtist: "DJ Hits '97-1",
            album: "DJ Hits '97-1")

        let query = DiscogsQuery(for: file)
        #expect(query.artist == "Various")
        // Compilations skip the Singles-only " - " split (see
        // `cleanedTrackTitle`'s doc comment), so the dash-joined filename
        // survives intact once the leading track number is stripped.
        #expect(query.track == "Apollo Four Forty - Ain't Talkin' Bout Dub")
        #expect(query.album == "DJ Hits '97-1")
    }

    /// The bracketed-artist convention, end to end through `DiscogsQuery`:
    /// the real case from the field ("(01) [Ice MC] It's A Rainy Day (Euro
    /// Club Mix).flac", Album tag "Maxi Power Best Of 94 (CD-1)"). Confirms
    /// the bracketed per-track artist is stripped from `track` (unlike the
    /// dash-joined case above) and the disc marker is stripped from `album`.
    @Test func compilationsStripTheBracketedArtistFromTrackAndTheDiscMarkerFromAlbum() {
        let file = Self.makeFile(
            category: .compilations,
            fileName: "(01) [Ice MC] It's A Rainy Day (Euro Club Mix).flac",
            artist: "Ice MC",
            expectedArtist: "Maxi Power Best Of 94 (CD-1)",
            album: "Maxi Power Best Of 94 (CD-1)")

        let query = DiscogsQuery(for: file)
        #expect(query.artist == "Various")
        #expect(query.track == "It's A Rainy Day (Euro Club Mix)")
        #expect(query.album == "Maxi Power Best Of 94")
    }

    /// Confirms the "Various" rule holds even when the file has no Artist
    /// tag at all — `.compilations` never falls through to any per-track
    /// derivation, unlike `MetadataQuery.artist(for:)`'s own `artist ?? ""`
    /// fallback — while `track` is still populated from the filename alone.
    @Test func compilationsUseVariousEvenWithNoArtistTag() {
        let file = Self.makeFile(category: .compilations, artist: nil, expectedArtist: "DJ Hits '97-1", album: nil)
        let query = DiscogsQuery(for: file)
        #expect(query.artist == "Various")
        #expect(query.track == "Changes")
    }

    @Test func albumsStillDeriveArtistAndTrackNormally() {
        let file = Self.makeFile(
            category: .albums, fileName: "01 - Changes.mp3", artist: "Wrong Tag",
            expectedArtist: "2Pac", album: "Greatest Hits")

        let query = DiscogsQuery(for: file)
        #expect(query.artist == "2Pac") // expectedArtist still preferred
        #expect(query.track == "Changes") // leading track number stripped as before
    }

    @Test func singlesStillDeriveArtistAndTrackNormally() {
        let file = Self.makeFile(
            category: .singles, fileName: "2Pac - Changes.mp3", artist: "2Pac",
            expectedArtist: "2Pac", album: nil)

        let query = DiscogsQuery(for: file)
        #expect(query.artist == "2Pac")
        #expect(query.track == "Changes") // "Artist - " prefix still stripped, unlike Compilations
    }

    // MARK: - searchURL for the compilation shape

    @Test func searchURLForTheCompilationShapeSendsArtistAndReleaseTitleButNoTrack() throws {
        let url = try #require(DiscogsClient.searchURL(artist: "Various", track: "", album: "DJ Hits '97-1"))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(query.contains(URLQueryItem(name: "artist", value: "Various")))
        #expect(query.contains(URLQueryItem(name: "release_title", value: "DJ Hits '97-1")))
        #expect(!query.contains { $0.name == "track" })
        #expect(!query.contains { $0.name == "q" })
    }

    // MARK: - DiscogsAlbumQuery per-category seeding

    /// Same "Various" rule as `DiscogsQuery`, at the whole-folder level —
    /// `AlbumMetadataLookupView`'s search field must not prefill with the
    /// compilation's folder name as if it were an artist.
    @Test func albumQueryUsesVariousForACompilationGroup() {
        let group = Self.makeGroup(category: .compilations, artist: "DJ Hits '97-1", albumTitle: "DJ Hits '97-1")
        #expect(DiscogsAlbumQuery(for: group).artist == "Various")
    }

    @Test func albumQueryUsesTheGroupsArtistForAnAlbumGroup() {
        let group = Self.makeGroup(category: .albums, artist: "2Pac", albumTitle: "Greatest Hits")
        #expect(DiscogsAlbumQuery(for: group).artist == "2Pac")
    }

    @Test func albumQueryKeepsAlbumTitleRegardlessOfCategory() {
        let group = Self.makeGroup(category: .compilations, artist: "DJ Hits '97-1", albumTitle: "DJ Hits '97-1")
        #expect(DiscogsAlbumQuery(for: group).album == "DJ Hits '97-1")
    }

    // MARK: - Fixture

    private static func makeGroup(category: LibraryCategory, artist: String?, albumTitle: String?) -> AlbumGroup {
        AlbumGroup(
            folderURL: URL(fileURLWithPath: "/Music/\(albumTitle ?? "Folder")"),
            category: category,
            artist: artist,
            albumTitle: albumTitle,
            year: nil,
            files: [],
            expectedTotalFromTags: nil,
            presentPositions: []
        )
    }

    private static func makeFile(
        category: LibraryCategory = .albums,
        fileName: String = "01 Changes.mp3",
        artist: String? = "2Pac",
        expectedArtist: String? = "2Pac",
        album: String?
    ) -> AudioFile {
        let url = URL(fileURLWithPath: "/Music/2Pac/Greatest Hits/\(fileName)")
        return AudioFile(
            url: url,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            sizeBytes: 1024,
            duration: 180,
            bitrateKbps: nil,
            title: "Changes",
            artist: artist,
            album: album,
            artworkThumbnail: nil,
            year: "1998",
            genre: "Hip Hop",
            trackNumber: "1",
            category: category,
            expectedArtist: expectedArtist,
            isReadable: true
        )
    }
}
