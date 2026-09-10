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

    // MARK: - collapsedSummaryText: one concrete line naming only what will change

    /// The bug: the collapsed state listed every changed field — five
    /// lines for a file with Artist/Album kept and Year/Genre/Artwork
    /// filled — which at 85 files was over 400 lines before anyone
    /// expanded anything. This confirms the fix: the collapsed line names
    /// only the `.willFill` fields, nothing else.
    @Test func namesOnlyTheFieldsThatWillActuallyBeWritten() {
        #expect(ApplyFoundMatchesSheetView.collapsedSummaryText(willFillFields: ["Year", "Genre", "Artwork"])
                == "Will fill: Year, Genre, Artwork")
    }

    /// Still concrete, not a bare verdict — an earlier version of this view
    /// showed only field names and abstract verdicts with no real values
    /// anywhere, which was the original complaint the field-by-field
    /// comparison exists to fix. Naming the exact fields (even without
    /// their values, which stay in the expanded table) keeps this from
    /// walking back into that abstraction.
    @Test func collapsedTextNamesTheActualFieldsNotJustACount() {
        let text = ApplyFoundMatchesSheetView.collapsedSummaryText(willFillFields: ["Year"])
        #expect(text.contains("Year"))
    }

    @Test func collapsedTextForNoWillFillFieldsSaysNoChanges() {
        #expect(ApplyFoundMatchesSheetView.collapsedSummaryText(willFillFields: []).hasPrefix("No changes"))
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

    private static func makeComparison(_ field: MetadataField, outcome: MatchComparison.Outcome) -> MatchComparison {
        MatchComparison(field: field, currentValue: "Current", matchValue: "Match", unavailableNote: nil, outcome: outcome)
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
