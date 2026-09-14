//
//  AfterApplyPresentationTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

/// Verifies `AfterApplyPresentation` — given a `MatchComparison`, what
/// `ApplyFoundMatchesSheetView`'s After Apply pane should actually show for
/// each outcome, and the single merged VoiceOver label that spans both
/// panes for that field. `MatchComparison.outcome` itself is
/// `MatchComparisonBuilder`'s job (see `MatchComparisonBuilderTests`) — this
/// only checks the presentation built from an already-classified outcome.
struct AfterApplyPresentationTests {
    // MARK: - forField: willFill shows the incoming value, marked new

    @Test func willFillShowsTheIncomingValueMarkedNew() {
        let comparison = Self.makeComparison(.year, current: nil, match: "1997", outcome: .willFill)
        let presentation = AfterApplyPresentation.forField(comparison, providerLabel: "Discogs")
        #expect(presentation.displayValue == "1997")
        #expect(presentation.marker == .new)
        #expect(presentation.note == nil)
    }

    // MARK: - forField: differsButKept shows the unchanged current value, with a note

    @Test func differsButKeptShowsTheCurrentValueUnchangedWithANote() {
        let comparison = Self.makeComparison(.artist, current: "Barraka", match: "Ben Lost", outcome: .differsButKept)
        let presentation = AfterApplyPresentation.forField(comparison, providerLabel: "Discogs")
        #expect(presentation.displayValue == "Barraka")
        #expect(presentation.marker == .none)
        #expect(presentation.note == "Discogs: \"Ben Lost\" — not applied")
    }

    /// A defensive edge case `MatchComparisonBuilder` never actually
    /// produces (`.differsButKept` implies both values are non-nil) — the
    /// pure presentation logic still shouldn't crash or fabricate a note
    /// with an empty quote.
    @Test func differsButKeptWithNoMatchValueHasNoNote() {
        let comparison = Self.makeComparison(.artist, current: "Barraka", match: nil, outcome: .differsButKept)
        let presentation = AfterApplyPresentation.forField(comparison, providerLabel: "Discogs")
        #expect(presentation.note == nil)
    }

    // MARK: - forField: agrees shows the value, marked confirmed

    @Test func agreesShowsTheValueMarkedConfirmed() {
        let comparison = Self.makeComparison(.genre, current: "Electronic", match: "Electronic", outcome: .agrees)
        let presentation = AfterApplyPresentation.forField(comparison, providerLabel: "Discogs")
        #expect(presentation.displayValue == "Electronic")
        #expect(presentation.marker == .confirmed)
        #expect(presentation.note == nil)
    }

    // MARK: - forField: noMatchData shows the current value, unmarked

    @Test func noMatchDataShowsTheCurrentValueWithNoMarker() {
        let comparison = Self.makeComparison(.trackNumber, current: "5", match: nil, outcome: .noMatchData)
        let presentation = AfterApplyPresentation.forField(comparison, providerLabel: "Discogs")
        #expect(presentation.displayValue == "5")
        #expect(presentation.marker == .none)
        #expect(presentation.note == nil)
    }

    @Test func noMatchDataWithAnEmptyCurrentValueShowsNil() {
        let comparison = Self.makeComparison(.trackNumber, current: nil, match: nil, outcome: .noMatchData)
        let presentation = AfterApplyPresentation.forField(comparison, providerLabel: "Discogs")
        #expect(presentation.displayValue == nil)
    }

    // MARK: - accessibilityLabel: matches the spoken phrasing the redesign specifies

    @Test func accessibilityLabelForWillFillNamesWhatItWillBecome() {
        let comparison = Self.makeComparison(.year, current: nil, match: "1997", outcome: .willFill)
        let presentation = AfterApplyPresentation.forField(comparison, providerLabel: "Discogs")
        let label = AfterApplyPresentation.accessibilityLabel(
            field: .year, comparison: comparison, presentation: presentation, providerLabel: "Discogs")
        #expect(label == "Year: empty, will become 1997")
    }

    @Test func accessibilityLabelForDiffersButKeptNamesBothSides() {
        let comparison = Self.makeComparison(.artist, current: "Barraka", match: "Ben Lost", outcome: .differsButKept)
        let presentation = AfterApplyPresentation.forField(comparison, providerLabel: "Discogs")
        let label = AfterApplyPresentation.accessibilityLabel(
            field: .artist, comparison: comparison, presentation: presentation, providerLabel: "Discogs")
        #expect(label == "Artist: Barraka, unchanged, Discogs suggests Ben Lost")
    }

    @Test func accessibilityLabelForAgreesSaysConfirmed() {
        let comparison = Self.makeComparison(.genre, current: "Electronic", match: "Electronic", outcome: .agrees)
        let presentation = AfterApplyPresentation.forField(comparison, providerLabel: "Discogs")
        let label = AfterApplyPresentation.accessibilityLabel(
            field: .genre, comparison: comparison, presentation: presentation, providerLabel: "Discogs")
        #expect(label == "Genre: Electronic, confirmed")
    }

    @Test func accessibilityLabelForNoMatchDataNamesNoDataToCompare() {
        let comparison = Self.makeComparison(.trackNumber, current: "5", match: nil, outcome: .noMatchData)
        let presentation = AfterApplyPresentation.forField(comparison, providerLabel: "Discogs")
        let label = AfterApplyPresentation.accessibilityLabel(
            field: .trackNumber, comparison: comparison, presentation: presentation, providerLabel: "Discogs")
        #expect(label == "Track Number: 5, no data to compare")
    }

    /// Artwork's real values are presence markers ("Present"), not display
    /// text — the label is worded around presence instead of quoting it.
    @Test func accessibilityLabelForArtworkWillFillNamesNewArtworkNotThePresenceMarker() {
        let comparison = Self.makeComparison(.artwork, current: nil, match: "Present", outcome: .willFill)
        let presentation = AfterApplyPresentation.forField(comparison, providerLabel: "Discogs")
        let label = AfterApplyPresentation.accessibilityLabel(
            field: .artwork, comparison: comparison, presentation: presentation, providerLabel: "Discogs")
        #expect(label == "Artwork: none, will become new artwork")
    }

    @Test func accessibilityLabelForArtworkAgreesNamesPresence() {
        let comparison = Self.makeComparison(.artwork, current: "Present", match: "Present", outcome: .agrees)
        let presentation = AfterApplyPresentation.forField(comparison, providerLabel: "Discogs")
        let label = AfterApplyPresentation.accessibilityLabel(
            field: .artwork, comparison: comparison, presentation: presentation, providerLabel: "Discogs")
        #expect(label == "Artwork: present, confirmed")
    }

    // MARK: - orderedComparisons: fixed field order, Track Number dropped for Singles

    @Test func orderedComparisonsPutsFieldsInTitleArtistAlbumYearGenreTrackArtworkOrder() {
        // Deliberately shuffled input, mirroring Discogs' own comparison order.
        let comparisons = [
            Self.makeComparison(.artist, outcome: .agrees),
            Self.makeComparison(.album, outcome: .agrees),
            Self.makeComparison(.year, outcome: .agrees),
            Self.makeComparison(.genre, outcome: .agrees),
            Self.makeComparison(.title, outcome: .agrees),
            Self.makeComparison(.trackNumber, outcome: .agrees),
            Self.makeComparison(.artwork, outcome: .agrees),
        ]
        let ordered = AfterApplyPresentation.orderedComparisons(comparisons, category: .albums)
        #expect(ordered.map(\.field) == [.title, .artist, .album, .year, .genre, .trackNumber, .artwork])
    }

    @Test func orderedComparisonsDropsTrackNumberEntirelyForSingles() {
        let comparisons = [
            Self.makeComparison(.title, outcome: .agrees),
            Self.makeComparison(.trackNumber, outcome: .agrees),
            Self.makeComparison(.artwork, outcome: .agrees),
        ]
        let ordered = AfterApplyPresentation.orderedComparisons(comparisons, category: .singles)
        #expect(!ordered.map(\.field).contains(.trackNumber))
    }

    @Test func orderedComparisonsKeepsTrackNumberForCompilations() {
        let comparisons = [
            Self.makeComparison(.title, outcome: .agrees),
            Self.makeComparison(.trackNumber, outcome: .agrees),
        ]
        let ordered = AfterApplyPresentation.orderedComparisons(comparisons, category: .compilations)
        #expect(ordered.map(\.field).contains(.trackNumber))
    }

    // MARK: - hasAnyChange: only willFill counts as a real change

    @Test func hasAnyChangeIsTrueWhenAnyFieldWillFill() {
        let comparisons = [
            Self.makeComparison(.artist, outcome: .agrees),
            Self.makeComparison(.year, outcome: .willFill),
        ]
        #expect(AfterApplyPresentation.hasAnyChange(comparisons))
    }

    /// The exact "collapse to No changes" condition: agreements and kept
    /// disagreements don't write anything, so neither counts as a change —
    /// only `.willFill` does.
    @Test func hasAnyChangeIsFalseForAgreesAndDiffersButKeptAndNoMatchData() {
        let comparisons = [
            Self.makeComparison(.artist, outcome: .agrees),
            Self.makeComparison(.album, outcome: .differsButKept),
            Self.makeComparison(.year, outcome: .noMatchData),
        ]
        #expect(!AfterApplyPresentation.hasAnyChange(comparisons))
    }

    @Test func hasAnyChangeIsFalseForAnEmptyList() {
        #expect(!AfterApplyPresentation.hasAnyChange([]))
    }

    // MARK: - Fixtures

    private static func makeComparison(
        _ field: MetadataField, current: String? = "Current", match: String? = "Match",
        outcome: MatchComparison.Outcome
    ) -> MatchComparison {
        MatchComparison(field: field, currentValue: current, matchValue: match, unavailableNote: nil, outcome: outcome)
    }
}

struct FormatSuffixRemovalTests {
    @Test func stripsCommonFormatMarkers() {
        #expect(MetadataQuery.strippingFormatSuffix(from: "Turn Da Music Up (CDM)") == "Turn Da Music Up")
        #expect(MetadataQuery.strippingFormatSuffix(from: "Can't Help Myself [CDS]") == "Can't Help Myself")
        #expect(MetadataQuery.strippingFormatSuffix(from: "Ride Like The Wind (Maxi-Single)") == "Ride Like The Wind")
        #expect(MetadataQuery.strippingFormatSuffix(from: "Freed From Desire (12\") (Promo)") == "Freed From Desire")
        #expect(MetadataQuery.strippingFormatSuffix(from: "Sweet Harmony - Single") == "Sweet Harmony")
    }

    @Test func leavesRealTitlePartsAlone() {
        #expect(MetadataQuery.strippingFormatSuffix(from: "Turn Da Music Up (Remixes)") == nil)
        #expect(MetadataQuery.strippingFormatSuffix(from: "Discovery (Deluxe Edition)") == nil)
        #expect(MetadataQuery.strippingFormatSuffix(from: "EP") == nil)
        #expect(MetadataQuery.strippingFormatSuffix(from: nil) == nil)
    }

    @Test func removalTurnsASuffixedAlbumIntoAWillFillOfTheCleanedTitle() {
        let kept = MatchComparison(
            field: .album, currentValue: "Turn Da Music Up (CDM)", matchValue: "Turn Da Music Up",
            unavailableNote: nil, outcome: .agrees)
        let result = AfterApplyPresentation.applyingFormatSuffixRemoval(to: [kept])
        #expect(result.first?.outcome == .willFill)
        #expect(result.first?.matchValue == "Turn Da Music Up")
    }

    @Test func removalLeavesAnAlbumWithoutASuffixUnchanged() {
        let plain = MatchComparison(
            field: .album, currentValue: "Turn Da Music Up", matchValue: "Turn Da Music Up",
            unavailableNote: nil, outcome: .agrees)
        #expect(AfterApplyPresentation.applyingFormatSuffixRemoval(to: [plain]) == [plain])
    }
}
