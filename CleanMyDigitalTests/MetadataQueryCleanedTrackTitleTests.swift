//
//  MetadataQueryCleanedTrackTitleTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

/// Verifies `MetadataQuery.cleanedTrackTitle(from:artist:category:)` — the
/// filename-cleaning heuristics shared by `DiscogsQuery`/`MusicBrainzQuery`
/// (per-track search) and the album-completeness track-matching
/// (`AlbumComparisonView.loadDetail()`'s calls into
/// `DiscogsReleaseDetail.autoMatchedTrack`/`allMatchedTracks`).
struct MetadataQueryCleanedTrackTitleTests {

    // MARK: - Leading track number, bare forms

    @Test func stripsABareTrackNumberFollowedBySpaceHyphenSpace() {
        let cleaned = MetadataQuery.cleanedTrackTitle(from: "01 - Title.mp3", artist: "Artist", category: .albums)
        #expect(cleaned == "Title")
    }

    @Test func stripsABareTrackNumberFollowedByADot() {
        let cleaned = MetadataQuery.cleanedTrackTitle(from: "3. Title.mp3", artist: "Artist", category: .albums)
        #expect(cleaned == "Title")
    }

    @Test func stripsABareTrackNumberFollowedByAnUnderscore() {
        let cleaned = MetadataQuery.cleanedTrackTitle(from: "07_Title.mp3", artist: "Artist", category: .albums)
        #expect(cleaned == "Title")
    }

    @Test func stripsABareTrackNumberFollowedByAClosingParenthesis() {
        let cleaned = MetadataQuery.cleanedTrackTitle(from: "12) Title.mp3", artist: "Artist", category: .albums)
        #expect(cleaned == "Title")
    }

    // MARK: - Leading track number, wrapped in parentheses

    @Test func stripsATrackNumberWrappedInParenthesesFollowedBySpace() {
        let cleaned = MetadataQuery.cleanedTrackTitle(from: "(01) Title.mp3", artist: "Artist", category: .albums)
        #expect(cleaned == "Title")
    }

    @Test func stripsATrackNumberWrappedInParenthesesWithNoTrailingSeparator() {
        // The closing ")" is itself one of the trailing-separator characters
        // the bare-form regex already accepts, so this needs no space after
        // the parenthesized number to strip correctly.
        let cleaned = MetadataQuery.cleanedTrackTitle(from: "(12)Title.mp3", artist: "Artist", category: .albums)
        #expect(cleaned == "Title")
    }

    // MARK: - Leading "[Artist Name] " prefix

    @Test func stripsABracketedArtistPrefixThatExactlyMatchesTheKnownArtist() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "[Anouar Brahem] Raf Raf.flac", artist: "Anouar Brahem", category: .albums)
        #expect(cleaned == "Raf Raf")
    }

    @Test func bracketedArtistStrippingAppliesToEveryCategoryNotJustSingles() {
        for category: LibraryCategory in [.singles, .albums, .compilations] {
            let cleaned = MetadataQuery.cleanedTrackTitle(
                from: "[Anouar Brahem] Raf Raf.flac", artist: "Anouar Brahem", category: category)
            #expect(cleaned == "Raf Raf")
        }
    }

    @Test func bracketedArtistMatchIsFuzzyAndCaseInsensitiveLikeTheDashCase() {
        // Bracket content is a substring of the known artist — same
        // either-direction contains comparison the Singles dash-stripping
        // logic already uses (e.g. covering collaborations).
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "[brahem] Raf Raf.flac", artist: "Anouar Brahem", category: .albums)
        #expect(cleaned == "Raf Raf")
    }

    @Test func bracketedTextThatDoesNotMatchTheArtistIsLeftAlone() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "[Live] Raf Raf.flac", artist: "Anouar Brahem", category: .albums)
        #expect(cleaned == "[Live] Raf Raf")
    }

    @Test func bracketedArtistIsLeftAloneWhenNoArtistIsKnown() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "[Anouar Brahem] Raf Raf.flac", artist: "", category: .albums)
        #expect(cleaned == "[Anouar Brahem] Raf Raf")
    }

    /// The real-world case this fixes: for `.compilations`, `artist` is
    /// forced to "Various" (see `DiscogsQuery`'s doc comment), which could
    /// never fuzzily match a real per-track artist like "Ice MC" — so the
    /// fuzzy-match gate the other categories use would leave the bracket
    /// in place forever. Compilations strip it unconditionally instead,
    /// since a leading "[Artist Name]" there is the per-track artist by
    /// convention.
    @Test func compilationsStripTheBracketedPrefixUnconditionallyEvenWhenItDoesNotMatchTheArtist() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "(01) [Ice MC] It's A Rainy Day (Euro Club Mix).flac", artist: "Various", category: .compilations)
        #expect(cleaned == "It's A Rainy Day (Euro Club Mix)")
    }

    /// Regression: only `.compilations` strips unconditionally — the other
    /// categories must still leave a non-matching bracket alone.
    @Test func singlesAndAlbumsStillGateTheBracketStripOnAFuzzyArtistMatch() {
        for category: LibraryCategory in [.singles, .albums] {
            let cleaned = MetadataQuery.cleanedTrackTitle(
                from: "[Ice MC] It's A Rainy Day.flac", artist: "Various", category: category)
            #expect(cleaned == "[Ice MC] It's A Rainy Day")
        }
    }

    @Test func bracketedTextIsOnlyStrippedNearTheStartNotLaterInTheTitle() {
        // "near the start" — anchored to the very beginning of the
        // (track-number-stripped) name, not matched anywhere in the string,
        // so a legitimate bracketed suffix elsewhere is left alone.
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "Raf Raf [Anouar Brahem].flac", artist: "Anouar Brahem", category: .albums)
        #expect(cleaned == "Raf Raf [Anouar Brahem]")
    }

    // MARK: - The real-world failing example

    @Test func cleansTheRealWorldParenthesizedTrackNumberAndBracketedArtistExample() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "(01) [Anouar Brahem] Raf Raf.flac", artist: "Anouar Brahem", category: .albums)
        #expect(cleaned == "Raf Raf")
    }

    // MARK: - Existing Singles-only "Artist - " stripping still holds

    @Test func singlesStripsALeadingArtistDashPrefixThatMatchesTheKnownArtist() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "Anouar Brahem - Raf Raf (Extended Mix).mp3", artist: "Anouar Brahem", category: .singles)
        #expect(cleaned == "Raf Raf (Extended Mix)")
    }

    @Test func albumsAndCompilationsKeepADashInTheTitleIntact() {
        for category: LibraryCategory in [.albums, .compilations] {
            let cleaned = MetadataQuery.cleanedTrackTitle(
                from: "01 - Track - Reprise.mp3", artist: "Artist", category: category)
            #expect(cleaned == "Track - Reprise")
        }
    }

    @Test func combinedParenthesizedTrackNumberAndBracketedArtistWorksAlongsideTheSinglesDashSplit() {
        // The bracket step runs before the Singles dash split, so a
        // bracketed-artist prefix doesn't get misread as the "Artist" side
        // of an "Artist - Title" split once it's already been removed.
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "(02) [Anouar Brahem] Track - Reprise.mp3", artist: "Anouar Brahem", category: .singles)
        #expect(cleaned == "Track - Reprise")
    }

    // MARK: - Never strips a trailing mix/version parenthetical (the fix)

    /// The real-world case that motivated this: "The KLF - 3 A.M. Eternal
    /// (Live At The S.S.L.)" found the exact pressing on Discogs with the
    /// mix name kept; stripping it down to "3 A.M. Eternal" found only
    /// generic, wrong pressings. For a maxi single, the mix/version name is
    /// often the single most identifying part of the title, not noise —
    /// `cleanedTrackTitle` must never remove or truncate it.
    @Test func neverStripsATrailingMixParentheticalFromASinglesFileName() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "1. The KLF - 3 A.M. Eternal (Live At The S.S.L.).flac", artist: "The KLF", category: .singles)
        #expect(cleaned == "3 A.M. Eternal (Live At The S.S.L.)")
    }

    @Test func neverStripsATrailingMixParentheticalRegardlessOfCategory() {
        for category: LibraryCategory in [.singles, .albums, .compilations] {
            let cleaned = MetadataQuery.cleanedTrackTitle(
                from: "Track Title (Euro Club Mix).mp3", artist: "Artist", category: category)
            #expect(cleaned == "Track Title (Euro Club Mix)")
        }
    }

    /// `strippingTrailingParenthetical` — the function that WOULD strip a
    /// mix name — still exists and still works; this just confirms
    /// `cleanedTrackTitle` never calls it, by checking its output would
    /// have differed if it had.
    @Test func strippingTrailingParentheticalRemainsAvailableButUnusedByCleanedTrackTitle() {
        let title = "3 A.M. Eternal (Live At The S.S.L.)"
        #expect(MetadataQuery.strippingTrailingParenthetical(from: title) == "3 A.M. Eternal")

        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "The KLF - \(title).flac", artist: "The KLF", category: .singles)
        #expect(cleaned == title)
    }
}
