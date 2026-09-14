//
//  MatchComparisonBuilderTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
import AppKit
@testable import CleanMyDigital

/// Verifies `MatchComparisonBuilder`'s per-field outcome classification —
/// the distinction `ApplyFoundMatchesSheetView`'s before/after comparison
/// exists to surface: a field that will genuinely be written (`.willFill`)
/// looks nothing like one that's already set and left untouched
/// (`.differsButKept`), which in turn is a very different signal from both
/// sides already agreeing (`.agrees`) or there being nothing to compare at
/// all (`.noMatchData`).
struct MatchComparisonBuilderTests {
    // MARK: - willFill: driven by the authoritative `fillable` set

    @Test func fieldIsWillFillWhenItIsInTheFillableSet() {
        let file = Self.makeFile(artist: nil)
        let release = Self.makeRelease(artist: "2Pac")
        let comparisons = MatchComparisonBuilder.comparisons(file: file, candidate: .discogs(release), fillable: [.artist])

        let artist = comparisons.first { $0.field == .artist }
        #expect(artist?.outcome == .willFill)
        // The outcome alone doesn't tell a UI what to display — the review
        // sheet needs the real values on both sides, not just the verdict.
        #expect(artist?.currentValue == nil)
        #expect(artist?.matchValue == "2Pac")
    }

    /// `.willFill` is read from `fillable`, not re-derived from "is the
    /// current value empty" — so even a field whose raw values would
    /// otherwise suggest a fill (current empty, match present) reads as
    /// `.noMatchData` if the caller's `fillable` set (the actual, already-
    /// computed truth of what `buildChanges` will write) doesn't include
    /// it. This is exactly `MusicBrainzRecording.fillableFields`'s
    /// deliberate Artwork omission — see `MatchComparisonBuilder`'s doc
    /// comment — so this test doubles as confirming that specific
    /// don't-overpromise behavior.
    @Test func musicBrainzArtworkNeverReadsAsWillFillEvenWithACoverArtURL() {
        let file = Self.makeFile(hasArtwork: false)
        let recording = Self.makeRecording(releaseID: "some-id") // → non-nil coverArtURL
        let comparisons = MatchComparisonBuilder.comparisons(file: file, candidate: .musicBrainz(recording), fillable: [])

        let artwork = comparisons.first { $0.field == .artwork }
        #expect(artwork?.outcome == .noMatchData)
        // The model still records that a cover *is* available — a UI can
        // still render the actual thumbnail for reference even though the
        // outcome says this batch apply won't use it.
        #expect(artwork?.matchValue == "Present")
        #expect(artwork?.currentValue == nil)
    }

    // MARK: - agrees / differsButKept: only when the field is NOT fillable

    @Test func fieldsThatAgreeReadAsAgrees() {
        let file = Self.makeFile(artist: "2Pac")
        let release = Self.makeRelease(artist: "2Pac")
        let comparisons = MatchComparisonBuilder.comparisons(file: file, candidate: .discogs(release), fillable: [])

        let artist = comparisons.first { $0.field == .artist }
        #expect(artist?.outcome == .agrees)
        // Even an "agrees" outcome carries the real values — a condensed
        // confirmation row still shows what actually agreed, not just that
        // something did.
        #expect(artist?.currentValue == "2Pac")
        #expect(artist?.matchValue == "2Pac")
    }

    /// The exact case that motivated showing real values instead of just a
    /// verdict: "Differs, kept" alone doesn't say the file holds "Maxi
    /// Power Best Of 94 (CD-2)" while the match holds "Maxi Power Best Of
    /// '94" — the whole point of a comparison is being able to read both.
    @Test func albumAgreesPastAFormatSuffix() {
        let file = Self.makeFile(album: "Turn Da Music Up (CDM)")
        let release = Self.makeRelease(album: "Turn Da Music Up")
        let comparisons = MatchComparisonBuilder.comparisons(file: file, candidate: .discogs(release), fillable: [])
        #expect(comparisons.first { $0.field == .album }?.outcome == .agrees)
    }

    @Test func differsButKeptCarriesBothRealValuesForDisplay() {
        let file = Self.makeFile(album: "Maxi Power Best Of 94 (CD-2)")
        let release = Self.makeRelease(album: "Maxi Power Best Of '94")
        let comparisons = MatchComparisonBuilder.comparisons(file: file, candidate: .discogs(release), fillable: [])

        let album = comparisons.first { $0.field == .album }
        #expect(album?.outcome == .differsButKept)
        #expect(album?.currentValue == "Maxi Power Best Of 94 (CD-2)")
        #expect(album?.matchValue == "Maxi Power Best Of '94")
    }

    @Test func agreementIsCaseAndWhitespaceInsensitive() {
        let file = Self.makeFile(artist: "  2pac  ")
        let release = Self.makeRelease(artist: "2Pac")
        let comparisons = MatchComparisonBuilder.comparisons(file: file, candidate: .discogs(release), fillable: [])

        #expect(comparisons.first { $0.field == .artist }?.outcome == .agrees)
    }

    /// The motivating real example: a file's own Genre tag and a Discogs
    /// release's combined genre/style list can be thematically related
    /// without being the same string — this must still read as "differs,
    /// kept," not "agrees," since the comparison is deliberately literal
    /// rather than fuzzy.
    @Test func thematicallyRelatedButDifferentGenresReadAsDiffersButKept() {
        let file = Self.makeFile(genre: "Eurodance")
        let release = Self.makeRelease(genre: ["Electronic", "Euro House", "Italodance"])
        let comparisons = MatchComparisonBuilder.comparisons(file: file, candidate: .discogs(release), fillable: [])

        let genre = comparisons.first { $0.field == .genre }
        #expect(genre?.outcome == .differsButKept)
        #expect(genre?.currentValue == "Eurodance")
        #expect(genre?.matchValue == "Electronic, Euro House, Italodance")
    }

    // MARK: - noMatchData: with and without a structural-unavailability note

    @Test func discogsTitleIsNoMatchDataWithAnUnavailabilityNote() {
        let file = Self.makeFile(title: nil)
        let release = Self.makeRelease()
        let comparisons = MatchComparisonBuilder.comparisons(file: file, candidate: .discogs(release), fillable: [])

        let title = comparisons.first { $0.field == .title }
        #expect(title?.outcome == .noMatchData)
        #expect(title?.currentValue == nil)
        #expect(title?.matchValue == nil)
        #expect(title?.unavailableNote != nil)
    }

    @Test func discogsTrackNumberIsNoMatchDataWithAnUnavailabilityNote() {
        let file = Self.makeFile(trackNumber: "5")
        let release = Self.makeRelease()
        let comparisons = MatchComparisonBuilder.comparisons(file: file, candidate: .discogs(release), fillable: [])

        let trackNumber = comparisons.first { $0.field == .trackNumber }
        #expect(trackNumber?.outcome == .noMatchData)
        #expect(trackNumber?.currentValue == "5")
        #expect(trackNumber?.unavailableNote != nil)
    }

    /// Distinguishes "this provider never carries this field" (gets a
    /// note) from "this particular result just has nothing for it" (no
    /// note — an ordinary dash covers it).
    @Test func aFieldThatsMerelyMissingThisTimeHasNoUnavailabilityNote() {
        let file = Self.makeFile(year: "1998")
        let release = Self.makeRelease(year: nil)
        let comparisons = MatchComparisonBuilder.comparisons(file: file, candidate: .discogs(release), fillable: [])

        let year = comparisons.first { $0.field == .year }
        #expect(year?.outcome == .noMatchData)
        #expect(year?.currentValue == "1998")
        #expect(year?.matchValue == nil)
        #expect(year?.unavailableNote == nil)
    }

    @Test func musicBrainzGenreAndTrackNumberAreAlwaysNoMatchDataWithANote() {
        let file = Self.makeFile(genre: "Electronic", trackNumber: "5")
        let recording = Self.makeRecording()
        let comparisons = MatchComparisonBuilder.comparisons(file: file, candidate: .musicBrainz(recording), fillable: [])

        let genre = comparisons.first { $0.field == .genre }
        #expect(genre?.outcome == .noMatchData)
        #expect(genre?.currentValue == "Electronic")
        #expect(genre?.unavailableNote != nil)

        let trackNumber = comparisons.first { $0.field == .trackNumber }
        #expect(trackNumber?.outcome == .noMatchData)
        #expect(trackNumber?.currentValue == "5")
        #expect(trackNumber?.unavailableNote != nil)
    }

    // MARK: - Artwork: presence-based, not value-based

    @Test func artworkFillsWhenFileHasNoneAndFillableIncludesIt() {
        let file = Self.makeFile(hasArtwork: false)
        let release = Self.makeRelease(thumb: "https://example.com/thumb.jpg")
        let comparisons = MatchComparisonBuilder.comparisons(file: file, candidate: .discogs(release), fillable: [.artwork])

        let artwork = comparisons.first { $0.field == .artwork }
        #expect(artwork?.outcome == .willFill)
        #expect(artwork?.currentValue == nil)
        #expect(artwork?.matchValue == "Present")
    }

    @Test func artworkAgreesWhenBothSidesHaveSomeAndItIsNotFillable() {
        let file = Self.makeFile(hasArtwork: true)
        let release = Self.makeRelease(thumb: "https://example.com/thumb.jpg")
        let comparisons = MatchComparisonBuilder.comparisons(file: file, candidate: .discogs(release), fillable: [])

        let artwork = comparisons.first { $0.field == .artwork }
        #expect(artwork?.outcome == .agrees)
        #expect(artwork?.currentValue == "Present")
        #expect(artwork?.matchValue == "Present")
    }

    @Test func artworkIsNoMatchDataWhenTheFileHasArtworkAndTheMatchDoesNot() {
        let file = Self.makeFile(hasArtwork: true)
        let release = Self.makeRelease(thumb: nil, coverImage: nil)
        let comparisons = MatchComparisonBuilder.comparisons(file: file, candidate: .discogs(release), fillable: [])

        let artwork = comparisons.first { $0.field == .artwork }
        #expect(artwork?.outcome == .noMatchData)
        #expect(artwork?.currentValue == "Present")
        #expect(artwork?.matchValue == nil)
    }

    @Test func artworkIsNoMatchDataWhenNeitherSideHasAny() {
        let file = Self.makeFile(hasArtwork: false)
        let release = Self.makeRelease(thumb: nil, coverImage: nil)
        let comparisons = MatchComparisonBuilder.comparisons(file: file, candidate: .discogs(release), fillable: [])

        let artwork = comparisons.first { $0.field == .artwork }
        #expect(artwork?.outcome == .noMatchData)
        #expect(artwork?.currentValue == nil)
        #expect(artwork?.matchValue == nil)
    }

    // MARK: - Fixtures

    private static func makeFile(
        title: String? = "Title", artist: String? = "Artist", album: String? = "Album",
        year: String? = "1998", genre: String? = "Electronic", trackNumber: String? = "1",
        hasArtwork: Bool = false
    ) -> AudioFile {
        AudioFile(
            url: URL(fileURLWithPath: "/Music/Artist/Album/01 Title.mp3"),
            fileName: "01 Title.mp3",
            fileExtension: "mp3",
            sizeBytes: 1024,
            duration: 180,
            bitrateKbps: nil,
            title: title,
            artist: artist,
            album: album,
            artworkThumbnail: hasArtwork ? NSImage() : nil,
            year: year,
            genre: genre,
            trackNumber: trackNumber,
            category: .albums,
            expectedArtist: "Artist",
            isReadable: true
        )
    }

    private static func makeRelease(
        artist: String? = "Artist", album: String? = "Album", year: String? = "1998",
        genre: [String]? = ["Electronic"], thumb: String? = "https://example.com/thumb.jpg",
        coverImage: String? = nil
    ) -> DiscogsRelease {
        let title = [artist, album].compactMap { $0 }.joined(separator: " - ")
        return DiscogsRelease(
            id: 1, title: title.isEmpty ? "Unknown" : title, year: year, genre: genre, style: nil,
            label: nil, format: nil, thumb: thumb, coverImage: coverImage)
    }

    private static func makeRecording(
        title: String = "Title", artistNames: String = "Artist", releaseTitle: String? = "Album",
        releaseDate: String? = "1998-01-01", releaseID: String? = nil
    ) -> MusicBrainzRecording {
        MusicBrainzRecording(
            id: "1", title: title, artistNames: artistNames,
            releaseTitle: releaseTitle, releaseDate: releaseDate, releaseID: releaseID)
    }
}
