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

    @Test func searchesAlbumAsQWhenArtistAndTrackAreEmpty() throws {
        let url = try #require(DiscogsClient.searchURL(artist: "", track: "", album: "Hotel Costes 10"))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(query.contains(URLQueryItem(name: "q", value: "Hotel Costes 10")))
    }

    // MARK: - releaseArtist(of:matches:) (title-only fallback)

    private static func release(_ title: String) -> DiscogsRelease {
        DiscogsRelease(id: 1, title: title, year: nil, genre: nil, style: nil,
                       label: nil, format: nil, thumb: nil, coverImage: nil)
    }

    @Test func releaseArtistMatchesIgnoringFeatCreditsAndDiscogsSuffixes() {
        #expect(DiscogsClient.releaseArtist(of: Self.release("Wareband - A Better Day (Remix)"), matches: "Wareband"))
        #expect(DiscogsClient.releaseArtist(of: Self.release("Wareband Featuring Tad Robinson - A Better Day"), matches: "Wareband"))
        #expect(DiscogsClient.releaseArtist(of: Self.release("The Donald* - A Better Day"), matches: "The Donald"))
        #expect(DiscogsClient.releaseArtist(of: Self.release("Crisis (2) - Kollectiv"), matches: "Crisis"))
    }

    /// The real file: "01 Kings Of Tommorow feat. Julie McKnight - Finally
    /// (DJ Meri Mix).flac" — the tag misspells the artist, so the right
    /// release was being shown as a title-only match.
    @Test func releaseArtistToleratesATypoInTheFilesOwnTag() {
        #expect(DiscogsClient.releaseArtist(
            of: Self.release("Kings Of Tomorrow Feat. Julie McKnight - Finally"),
            matches: "Kings Of Tommorow"))
    }

    @Test func releaseArtistStillRejectsShortLookalikes() {
        // Seven characters, one edit apart, and two different artists.
        #expect(!DiscogsClient.releaseArtist(of: Self.release("Shooter - Song"), matches: "Scooter"))
        #expect(!DiscogsClient.releaseArtist(of: Self.release("Kings Of Leon - Song"), matches: "Kings Of Tommorow"))
    }

    @Test func releaseArtistRejectsSomeoneElse() {
        #expect(!DiscogsClient.releaseArtist(of: Self.release("Taborah Adams - A Better Day"), matches: "Wareband"))
        #expect(!DiscogsClient.releaseArtist(of: Self.release("Xavier - Song"), matches: "X"))
    }

    @Test func queryArtistDropsTheFeatCredit() {
        let file = Self.makeFile(category: .singles, fileName: "02 - A Better Day (Garage Remix).mp3",
                                 artist: "Wareband Feat. Tad Robinson", expectedArtist: nil, album: nil)
        #expect(DiscogsQuery(for: file).artist == "Wareband")
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

    /// Compilations are searched by release title alone, so `artist` stays
    /// blank; `track` is still populated for the tracklist match afterwards.
    @Test func compilationsLeaveArtistBlankButStillPopulateTrack() {
        let file = Self.makeFile(
            category: .compilations,
            fileName: "03 Apollo Four Forty - Ain't Talkin' Bout Dub.mp3",
            artist: "Apollo Four Forty",
            expectedArtist: "DJ Hits '97-1",
            album: "DJ Hits '97-1")

        let query = DiscogsQuery(for: file)
        #expect(query.artist.isEmpty)
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
        #expect(query.artist.isEmpty)
        #expect(query.track == "It's A Rainy Day (Euro Club Mix)")
        #expect(query.album == "Maxi Power Best Of 94")
    }

    /// Blank artist holds with no Artist tag too; `track` comes from the filename.
    @Test func compilationsLeaveArtistBlankWithNoArtistTag() {
        let file = Self.makeFile(category: .compilations, artist: nil, expectedArtist: "DJ Hits '97-1", album: nil)
        let query = DiscogsQuery(for: file)
        #expect(query.artist.isEmpty)
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

    /// The fix, at the `DiscogsQuery` level: a Singles file's containing
    /// folder is a release identifier ("1991 - 3 A.M. Eternal (CDM)"), not
    /// an artist — `query.artist` must come from the Artist tag, never
    /// `expectedArtist`, unlike Albums (see `albumsStillDeriveArtistAndTrackNormally`
    /// above, where `expectedArtist` IS preferred). The mix name also
    /// survives in `track` — see `MetadataQueryCleanedTrackTitleTests`.
    @Test func singlesUseTheArtistTagNotTheExpectedArtistFolderName() {
        let file = Self.makeFile(
            category: .singles,
            fileName: "1. The KLF - 3 A.M. Eternal (Live At The S.S.L.).flac",
            artist: "The KLF",
            expectedArtist: "1991 - 3 A.M. Eternal (CDM)",
            album: nil)

        let query = DiscogsQuery(for: file)
        #expect(query.artist == "The KLF")
        #expect(query.track == "3 A.M. Eternal (Live At The S.S.L.)")
    }

    // MARK: - combinedQuery (searchTrack's free-text term builder)

    @Test func combinedQueryJoinsArtistAndTrackWithADash() {
        #expect(DiscogsClient.combinedQuery(artist: "The KLF", track: "3 A.M. Eternal (Live At The S.S.L.)")
                == "The KLF - 3 A.M. Eternal (Live At The S.S.L.)")
    }

    @Test func combinedQueryIsJustTheTrackWhenArtistIsEmpty() {
        #expect(DiscogsClient.combinedQuery(artist: "", track: "3 A.M. Eternal") == "3 A.M. Eternal")
    }

    @Test func combinedQueryIsJustTheArtistWhenTrackIsEmpty() {
        #expect(DiscogsClient.combinedQuery(artist: "The KLF", track: "") == "The KLF")
    }

    @Test func combinedQueryIsEmptyWhenBothAreEmpty() {
        #expect(DiscogsClient.combinedQuery(artist: "", track: "") == "")
    }

    // MARK: - searchTrack (offline-testable edge cases — the tiered network
    // retries themselves are verified against the live API; see its doc comment)

    @Test func searchTrackThrowsMissingTokenWhenTokenIsEmpty() async {
        await #expect(throws: DiscogsError.self) {
            _ = try await DiscogsClient.searchTrack(artist: "The KLF", track: "3 A.M. Eternal", token: "")
        }
    }

    @Test func searchTrackReturnsEmptyImmediatelyWithNoArtistOrTrack() async throws {
        // Nothing to search for — no network call should even be attempted.
        let result = try await DiscogsClient.searchTrack(artist: "", track: "", token: "fake-token")
        #expect(result.releases.isEmpty)
        #expect(!result.usedBroaderTitleOnlyFallback)
    }

    // MARK: - Genre backfill

    @Test func firstGenreSkipsUngenredResultsAndJoinsGenreWithStyle() {
        func release(_ genre: [String]?, _ style: [String]?) -> DiscogsRelease {
            DiscogsRelease(
                id: 1, title: "A - B", year: nil, genre: genre, style: style,
                label: nil, format: nil, thumb: nil, coverImage: nil)
        }

        let results = [release(nil, nil), release([], []), release(["Electronic"], ["Deep House"])]
        #expect(DiscogsClient.firstGenre(in: results) == "Electronic, Deep House")
    }

    @Test func firstGenreIsNilWhenNoResultHasOne() {
        let bare = DiscogsRelease(
            id: 1, title: "A - B", year: nil, genre: nil, style: nil,
            label: nil, format: nil, thumb: nil, coverImage: nil)

        #expect(DiscogsClient.firstGenre(in: [bare, bare]) == nil)
        #expect(DiscogsClient.firstGenre(in: []) == nil)
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

    /// Same blank-artist rule as `DiscogsQuery`, at the whole-folder level —
    /// the folder name must never be sent as if it were an artist.
    @Test func albumQueryLeavesArtistBlankForACompilationGroup() {
        let group = Self.makeGroup(category: .compilations, artist: "DJ Hits '97-1", albumTitle: "DJ Hits '97-1")
        #expect(DiscogsAlbumQuery(for: group).artist.isEmpty)
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
        album: String?,
        // nil by default so these tests exercise the filename parsing they
        // are about; `trackSearchTerm` prefers a Title tag when there is one.
        title: String? = nil
    ) -> AudioFile {
        let url = URL(fileURLWithPath: "/Music/2Pac/Greatest Hits/\(fileName)")
        return AudioFile(
            url: url,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            sizeBytes: 1024,
            duration: 180,
            bitrateKbps: nil,
            title: title,
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

    // MARK: - The Title tag leads, the filename backs it up

    @Test func theTitleTagIsPreferredOverTheParsedFileName() {
        let file = Self.makeFile(
            category: .singles,
            fileName: "207-offer_nissim_feat_maya-first_time__jose_spinnin_cortex_remix-nvs.mp3",
            artist: "Offer Nissim Feat Maya",
            expectedArtist: nil,
            album: nil,
            title: "First Time (Jose Spinnin Cortex Remix)")

        let query = DiscogsQuery(for: file)
        #expect(query.artist == "Offer Nissim")
        #expect(query.track == "First Time (Jose Spinnin Cortex Remix)")
        // The filename's own reading is kept for the retry tier.
        #expect(query.fileNameTrack == "first time jose spinnin cortex remix")
    }

    @Test func aPlaceholderTitleTagIsIgnoredInFavourOfTheFileName() {
        let file = Self.makeFile(
            category: .singles, fileName: "The KLF - 3 A.M. Eternal.flac",
            artist: "The KLF", expectedArtist: nil, album: nil, title: "Track 03")

        #expect(DiscogsQuery(for: file).track == "3 A.M. Eternal")
    }

    @Test func thereIsNoFallbackTrackWhenBothReadingsAgree() {
        let file = Self.makeFile(
            category: .singles, fileName: "The KLF - 3 A.M. Eternal.flac",
            artist: "The KLF", expectedArtist: nil, album: nil, title: "3 A.M. Eternal")

        #expect(DiscogsQuery(for: file).fileNameTrack == nil)
    }

    @Test func aTitleTagKeepsALeadingNumberTheFileNameRulesWouldHaveEaten() {
        let file = Self.makeFile(
            category: .singles, fileName: "Youssou N'Dour - 7 Seconds.mp3",
            artist: "Youssou N'Dour", expectedArtist: nil, album: nil, title: "7 Seconds")

        #expect(DiscogsQuery(for: file).track == "7 Seconds")
    }

    @Test func aCodecMarkerInTheTitleTagIsStrippedToo() {
        let file = Self.makeFile(
            category: .singles, fileName: "Artist - Title.wav",
            artist: "Artist", expectedArtist: nil, album: nil, title: "Come & Get Your Love DTS")

        #expect(DiscogsQuery(for: file).track == "Come & Get Your Love")
    }
}
