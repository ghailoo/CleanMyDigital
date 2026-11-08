//
//  MetadataQueryArtistTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

/// Verifies `MetadataQuery.artist(for:)` — the search-artist derivation
/// shared by `DiscogsQuery`/`MusicBrainzQuery` (both just call through to
/// this). Only Albums are genuinely organized by artist folder, so only
/// there is `expectedArtist` (the containing folder's name) preferred.
///
/// Singles used to share Albums' preference for `expectedArtist`, which was
/// a real bug: per the README, Singles files may sit loose in any folder,
/// so the folder carries no reliable artist signal. The real case this
/// guards against: a Singles file "1. The KLF - 3 A.M. Eternal (Live At The
/// S.S.L.).flac" sitting in a folder named "1991 - 3 A.M. Eternal (CDM)" (a
/// release identifier, not an artist) — treating that folder as the artist
/// sent Discogs an artist term that doesn't exist and found nothing.
///
/// Compilations were already excluded from `expectedArtist` before this fix
/// (a compilation folder is the release's own name, e.g. "DJ Hits 100%
/// '97-1", never a track's artist) and stay excluded.
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

    @Test func albumsFallsBackToTheFileNameWhenNeitherTagNorExpectedArtistIsAvailable() {
        let file = Self.makeFile(
            category: .albums, fileName: "2Pac - Changes.mp3", artist: nil, expectedArtist: nil)
        #expect(MetadataQuery.artist(for: file) == "2Pac")
    }

    @Test func albumsReturnsEmptyWhenNothingIsAvailable() {
        let file = Self.makeFile(category: .albums, fileName: "Changes.mp3", artist: nil, expectedArtist: nil)
        #expect(MetadataQuery.artist(for: file) == "")
    }

    // MARK: - Singles: the fix — the Artist tag wins, expectedArtist never used

    @Test func singlesUseTheArtistTagEvenWhenExpectedArtistIsPresent() {
        // The motivating real case: a Singles file whose containing folder
        // is a release identifier ("1991 - 3 A.M. Eternal (CDM)"), not an
        // artist. `expectedArtist` there must be ignored entirely in favor
        // of the track's own Artist tag.
        let file = Self.makeFile(
            category: .singles,
            fileName: "1. The KLF - 3 A.M. Eternal (Live At The S.S.L.).flac",
            artist: "The KLF",
            expectedArtist: "1991 - 3 A.M. Eternal (CDM)")
        #expect(MetadataQuery.artist(for: file) == "The KLF")
    }

    @Test func singlesFallBackToParsingTheArtistFromTheFileNameWhenTheArtistTagIsMissing() {
        let file = Self.makeFile(
            category: .singles,
            fileName: "1. The KLF - 3 A.M. Eternal (Live At The S.S.L.).flac",
            artist: nil,
            expectedArtist: "1991 - 3 A.M. Eternal (CDM)")
        #expect(MetadataQuery.artist(for: file) == "The KLF")
    }

    @Test func singlesReturnEmptyWhenNeitherTheArtistTagNorTheFileNameHasOne() {
        let file = Self.makeFile(
            category: .singles, fileName: "3 A.M. Eternal.flac", artist: nil,
            expectedArtist: "1991 - 3 A.M. Eternal (CDM)")
        #expect(MetadataQuery.artist(for: file) == "")
    }

    // MARK: - Compilations: the Artist tag always wins, expectedArtist never used

    @Test func compilationsUseTheArtistTagEvenWhenExpectedArtistIsPresent() {
        // The motivating real case: a "DJ Hits 100% '97-1" compilation
        // folder holding a Madonna track. `expectedArtist` here is the
        // compilation's own name — never a real artist — so it must be
        // ignored entirely in favor of the track's own Artist tag.
        let file = Self.makeFile(
            category: .compilations, artist: "Madonna", expectedArtist: "DJ Hits 100% '97-1")
        #expect(MetadataQuery.artist(for: file) == "Madonna")
    }

    @Test func compilationsFallBackToParsingTheArtistFromTheFileNameWhenTheArtistTagIsMissing() {
        let file = Self.makeFile(
            category: .compilations, fileName: "03 Madonna - Vogue.mp3", artist: nil,
            expectedArtist: "DJ Hits 100% '97-1")
        #expect(MetadataQuery.artist(for: file) == "Madonna")
    }

    @Test func compilationsUseTheArtistTagWhenExpectedArtistIsAlreadyNil() {
        let file = Self.makeFile(category: .compilations, artist: "Gala", expectedArtist: nil)
        #expect(MetadataQuery.artist(for: file) == "Gala")
    }

    // MARK: - artistParsedFromFileName

    @Test func artistParsedFromFileNameReadsTheTextBeforeTheDash() {
        #expect(MetadataQuery.artistParsedFromFileName("The KLF - 3 A.M. Eternal.flac") == "The KLF")
    }

    @Test func artistParsedFromFileNameStripsALeadingTrackNumberFirst() {
        #expect(MetadataQuery.artistParsedFromFileName("1. The KLF - 3 A.M. Eternal.flac") == "The KLF")
    }

    @Test func artistParsedFromFileNameReturnsNilWithNoDashSeparator() {
        #expect(MetadataQuery.artistParsedFromFileName("3 A.M. Eternal.flac") == nil)
    }

    // MARK: - Ripper track-number prefix on the Artist tag

    @Test func stripsATrackNumberPrefixFromTheArtistTag() {
        let file = Self.makeFile(category: .singles, artist: "02_Real McCoy", expectedArtist: nil)
        #expect(MetadataQuery.artist(for: file) == "Real McCoy")
    }

    @Test func keepsAnArtistThatGenuinelyStartsWithANumber() {
        #expect(MetadataQuery.strippingTrackNumberPrefix(from: "2 Unlimited") == "2 Unlimited")
        #expect(MetadataQuery.strippingTrackNumberPrefix(from: "2-4 Grooves") == "2-4 Grooves")
        #expect(MetadataQuery.strippingTrackNumberPrefix(from: "3 Doors Down") == "3 Doors Down")
    }

    // MARK: - Fixtures

    private static func makeFile(
        category: LibraryCategory, fileName: String = "01 Track.mp3", artist: String?, expectedArtist: String?
    ) -> AudioFile {
        let url = URL(fileURLWithPath: "/Music/Compilation Folder/\(fileName)")
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
