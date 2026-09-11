//
//  ApplyFoundMatchesSheetViewTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

/// Verifies the pure logic behind `ApplyFoundMatchesSheetView`'s per-section
/// match identity and per-comparison summary text — pulled out of the view
/// as `static func`s specifically so they're testable without a live
/// `LibraryScanner` or a rendered `List`, same pattern as
/// `ContentView.fileMatches`.
struct ApplyFoundMatchesSheetViewTests {
    // MARK: - sectionShowsSharedMatchIdentity / headerSubtitle
    //
    // The bug: a Singles section header rendered one release identity above
    // ten unrelated files, on the assumption (true for Albums/Compilations,
    // never for Singles) that a folder's files converge on one release.

    @Test func sectionShowsSharedMatchIdentityIsTrueForAnAlbumGroup() {
        let group = Self.makeGroup(hasAlbumGroup: true)
        #expect(ApplyFoundMatchesSheetView.sectionShowsSharedMatchIdentity(for: group))
    }

    @Test func sectionShowsSharedMatchIdentityIsFalseForASinglesGroup() {
        let group = Self.makeGroup(hasAlbumGroup: false)
        #expect(!ApplyFoundMatchesSheetView.sectionShowsSharedMatchIdentity(for: group))
    }

    @Test func headerSubtitleMentionsRematchWhenAnyGroupHasOne() {
        let groups = [Self.makeGroup(hasAlbumGroup: false), Self.makeGroup(hasAlbumGroup: true)]
        #expect(ApplyFoundMatchesSheetView.headerSubtitle(groups: groups).contains("Re-match"))
    }

    /// The real case: a batch made entirely of Singles has no group-level
    /// "Re-match…" control anywhere in it — describing one would point at a
    /// button that doesn't exist.
    @Test func headerSubtitleOmitsRematchWhenNoGroupHasOne() {
        let groups = [Self.makeGroup(hasAlbumGroup: false), Self.makeGroup(hasAlbumGroup: false)]
        #expect(!ApplyFoundMatchesSheetView.headerSubtitle(groups: groups).contains("Re-match"))
    }

    @Test func headerSubtitleOmitsRematchForAnEmptyGroupList() {
        #expect(!ApplyFoundMatchesSheetView.headerSubtitle(groups: []).contains("Re-match"))
    }

    // MARK: - sectionSubtitle: pluralization and per-category wording

    @Test func sectionSubtitleForASinglesFolderWithOneFileIsSingular() {
        let group = Self.makeGroup(hasAlbumGroup: false, fileCount: 1)
        #expect(ApplyFoundMatchesSheetView.sectionSubtitle(for: group) == "1 file in this folder")
    }

    @Test func sectionSubtitleForASinglesFolderWithSeveralFilesIsPlural() {
        let group = Self.makeGroup(hasAlbumGroup: false, fileCount: 10)
        #expect(ApplyFoundMatchesSheetView.sectionSubtitle(for: group) == "10 files in this folder")
    }

    @Test func sectionSubtitleForAnAlbumGroupNamesTheAlbumAndIsPlural() {
        let group = Self.makeGroup(hasAlbumGroup: true, category: .albums, fileCount: 12)
        let subtitle = ApplyFoundMatchesSheetView.sectionSubtitle(for: group)
        #expect(subtitle.hasPrefix("12 files matched"))
        #expect(subtitle.contains("album"))
    }

    @Test func sectionSubtitleForACompilationGroupSaysCompilationNotAlbum() {
        let group = Self.makeGroup(hasAlbumGroup: true, category: .compilations, fileCount: 13)
        #expect(ApplyFoundMatchesSheetView.sectionSubtitle(for: group).contains("compilation"))
    }

    // MARK: - fillsLineText: the incoming value only, never an empty "before"

    /// The bug this replaces: the collapsed line named every changed field
    /// but no *value* — "Will fill: Year, Genre, Artwork" — spending a
    /// whole line saying nothing concrete for the common case where a
    /// `.willFill` field's "before" is always empty by definition. This
    /// confirms the fix: real incoming values, joined, no arrows.
    @Test func fillsLineNamesFieldAndIncomingValueForEachWillFillField() {
        let comparisons = [
            Self.makeComparison(.year, current: nil, match: "1997", outcome: .willFill),
            Self.makeComparison(.genre, current: nil, match: "Electronic, Garage House", outcome: .willFill),
        ]
        let text = ApplyFoundMatchesSheetView.fillsLineText(comparisons)
        #expect(text == "Year 1997 · Genre Electronic, Garage House")
    }

    /// Artwork's comparison values are presence markers ("Present"), not
    /// real display text — a checkmark reads better than "Artwork Present".
    @Test func fillsLineShowsACheckmarkForArtworkRatherThanItsPresenceMarker() {
        let comparisons = [Self.makeComparison(.artwork, current: nil, match: "Present", outcome: .willFill)]
        #expect(ApplyFoundMatchesSheetView.fillsLineText(comparisons) == "Artwork ✓")
    }

    /// `nil`, not an empty string, so the view can tell "nothing to fill"
    /// apart from "a line with no content" and fall through to "No changes".
    @Test func fillsLineIsNilWhenNothingWillFill() {
        #expect(ApplyFoundMatchesSheetView.fillsLineText([]) == nil)
    }

    // MARK: - keepsLineText: the one line where both sides matter

    /// The canonical case: exactly one differing field, both sides shown,
    /// the provider named once rather than repeating "Discogs" per field.
    @Test func keepsLineShowsBothSidesForASingleDifferingField() {
        let comparisons = [
            Self.makeComparison(.artist, current: "Byron Stingily", match: "Byron Stingily Featuring Leee John", outcome: .differsButKept),
        ]
        let text = ApplyFoundMatchesSheetView.keepsLineText(comparisons, providerLabel: "Discogs")
        #expect(text == "Artist \"Byron Stingily\" · Discogs says \"Byron Stingily Featuring Leee John\"")
    }

    /// Several differing fields join on each side in the same order, so the
    /// two lists stay lined up — this isn't rare: Year and Genre commonly
    /// differ together even when Artist/Album agree (the `matchLooksLikelyWrong`
    /// flag is specifically about the Artist+Album combination, not this one).
    @Test func keepsLineJoinsSeveralDifferingFieldsInOrderOnBothSides() {
        let comparisons = [
            Self.makeComparison(.year, current: "1996", match: "1997", outcome: .differsButKept),
            Self.makeComparison(.genre, current: "House", match: "Garage House", outcome: .differsButKept),
        ]
        let text = ApplyFoundMatchesSheetView.keepsLineText(comparisons, providerLabel: "Discogs")
        #expect(text == "Year \"1996\", Genre \"House\" · Discogs says \"1997\", \"Garage House\"")
    }

    @Test func keepsLineIsNilWhenNothingDiffers() {
        #expect(ApplyFoundMatchesSheetView.keepsLineText([], providerLabel: "Discogs") == nil)
    }

    // MARK: - Combinations the collapsed state can actually show

    /// A file that fills some fields and keeps a differing one shows both
    /// lines — the two outcomes are rendered independently, not merged or
    /// treated as mutually exclusive.
    @Test func fillsAndKeepsCanBothBePresentAtOnce() {
        let comparisons = [
            Self.makeComparison(.year, current: nil, match: "1997", outcome: .willFill),
            Self.makeComparison(.artist, current: "Byron Stingily", match: "Byron Stingily Featuring Leee John", outcome: .differsButKept),
        ]
        let fills = comparisons.filter { $0.outcome == .willFill }
        let keeps = comparisons.filter { $0.outcome == .differsButKept }
        #expect(ApplyFoundMatchesSheetView.fillsLineText(fills) == "Year 1997")
        #expect(ApplyFoundMatchesSheetView.keepsLineText(keeps, providerLabel: "Discogs") != nil)
    }

    /// Only agreements/no-data: both lines are nil, which is exactly the
    /// condition the view uses to fall back to the "No changes" line.
    @Test func onlyAgreementsMeansNoFillsAndNoKeepsLines() {
        let comparisons = [
            Self.makeComparison(.artist, current: "Byron Stingily", match: "Byron Stingily", outcome: .agrees),
            Self.makeComparison(.trackNumber, current: nil, match: nil, outcome: .noMatchData),
        ]
        let fills = comparisons.filter { $0.outcome == .willFill }
        let keeps = comparisons.filter { $0.outcome == .differsButKept }
        #expect(ApplyFoundMatchesSheetView.fillsLineText(fills) == nil)
        #expect(ApplyFoundMatchesSheetView.keepsLineText(keeps, providerLabel: "Discogs") == nil)
    }

    // MARK: - footerStatusText: coherent while a selection is being consumed

    /// The bug: "130 of 108 selected" — a frozen selection count divided by
    /// a live, shrinking `targets` count while `applySelected()` writes
    /// files one at a time. Idle, it's the ordinary selection count.
    @Test func footerStatusTextShowsSelectionCountWhenIdle() {
        let text = ApplyFoundMatchesSheetView.footerStatusText(
            isApplying: false, selectedCount: 5, targetCount: 8, completed: 0, total: 0)
        #expect(text == "5 of 8 selected")
    }

    /// While applying, progress is reported against the run's own fixed
    /// snapshot instead of the live, shrinking `targets` — never able to
    /// show a numerator larger than its denominator.
    @Test func footerStatusTextShowsRunProgressWhileApplying() {
        let text = ApplyFoundMatchesSheetView.footerStatusText(
            isApplying: true, selectedCount: 130, targetCount: 108, completed: 22, total: 130)
        #expect(text == "Applying 22 of 130…")
    }

    // MARK: - matchLooksLikelyWrong: the one warning colour in this window

    /// The genuine red flag: Artist AND Album both differ-but-kept at once
    /// — the strongest available signal the match is the wrong release
    /// entirely, not just missing a field.
    @Test func looksLikelyWrongWhenArtistAndAlbumBothDiffer() {
        let comparisons = [
            Self.makeComparison(.artist, outcome: .differsButKept),
            Self.makeComparison(.album, outcome: .differsButKept),
        ]
        #expect(ApplyFoundMatchesSheetView.matchLooksLikelyWrong(comparisons))
    }

    /// A single differing field is the routine, harmless case every match
    /// can show (the app never overwrites) — it must NOT trip the warning
    /// alone, or the rare signal stops meaning anything.
    @Test func doesNotLookLikelyWrongWhenOnlyOneFieldDiffers() {
        let onlyArtist = [
            Self.makeComparison(.artist, outcome: .differsButKept),
            Self.makeComparison(.album, outcome: .agrees),
        ]
        #expect(!ApplyFoundMatchesSheetView.matchLooksLikelyWrong(onlyArtist))

        let onlyAlbum = [
            Self.makeComparison(.artist, outcome: .willFill),
            Self.makeComparison(.album, outcome: .differsButKept),
        ]
        #expect(!ApplyFoundMatchesSheetView.matchLooksLikelyWrong(onlyAlbum))
    }

    @Test func doesNotLookLikelyWrongWhenBothAgree() {
        let comparisons = [
            Self.makeComparison(.artist, outcome: .agrees),
            Self.makeComparison(.album, outcome: .agrees),
        ]
        #expect(!ApplyFoundMatchesSheetView.matchLooksLikelyWrong(comparisons))
    }

    /// Other fields differing (Year, Genre, …) don't factor in at all —
    /// this is specifically about the two core identity fields.
    @Test func otherDifferingFieldsDoNotTripTheWarning() {
        let comparisons = [
            Self.makeComparison(.artist, outcome: .agrees),
            Self.makeComparison(.album, outcome: .agrees),
            Self.makeComparison(.year, outcome: .differsButKept),
            Self.makeComparison(.genre, outcome: .differsButKept),
        ]
        #expect(!ApplyFoundMatchesSheetView.matchLooksLikelyWrong(comparisons))
    }

    // MARK: - Fixtures

    private static func makeComparison(
        _ field: MetadataField, current: String? = "Current", match: String? = "Match",
        outcome: MatchComparison.Outcome
    ) -> MatchComparison {
        MatchComparison(field: field, currentValue: current, matchValue: match, unavailableNote: nil, outcome: outcome)
    }

    private static func makeGroup(
        hasAlbumGroup: Bool, category: LibraryCategory = .albums, fileCount: Int = 1
    ) -> FoundMatchGroup {
        let folderURL = URL(fileURLWithPath: "/Music/Folder")
        let files = (0..<fileCount).map { index in
            Self.makeFile(path: "/Music/Folder/\(index) Track.mp3", category: category)
        }
        let albumGroup: AlbumGroup? = hasAlbumGroup
            ? AlbumGroup(
                folderURL: folderURL, category: category, artist: "Artist", albumTitle: "Album", year: "1998",
                files: [], expectedTotalFromTags: nil, presentPositions: [])
            : nil
        return FoundMatchGroup(folderURL: folderURL, files: files, albumGroup: albumGroup)
    }

    private static func makeFile(path: String, category: LibraryCategory) -> AudioFile {
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
            album: "Album",
            artworkThumbnail: nil,
            year: "1998",
            genre: "Electronic",
            trackNumber: "1",
            category: category,
            expectedArtist: "Artist",
            isReadable: true
        )
    }
}
