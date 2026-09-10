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

    // MARK: - changeSummaryText: an arrow only where a value will actually change

    /// The bug: "Artist: Barraka → Ben Lost" and "Year: - → 2014" used the
    /// same arrow for two opposite meanings — one meant "differs, and is
    /// ignored", the other "becomes". This confirms the fix: only
    /// `.willFill` gets an arrow at all.
    @Test func willFillUsesAnArrowAndIsLabeledWillFill() {
        let comparison = MatchComparison(
            field: .year, currentValue: nil, matchValue: "2014", unavailableNote: nil, outcome: .willFill)
        let (text, label) = ApplyFoundMatchesSheetView.changeSummaryText(comparison, provider: .discogs)
        #expect(text == "Year: – → 2014")
        #expect(label == "will fill")
    }

    @Test func differsButKeptNeverContainsAnArrow() {
        let comparison = MatchComparison(
            field: .artist, currentValue: "Barraka", matchValue: "Ben Lost",
            unavailableNote: nil, outcome: .differsButKept)
        let (text, _) = ApplyFoundMatchesSheetView.changeSummaryText(comparison, provider: .discogs)
        #expect(!text.contains("→"))
    }

    /// Names which provider is making the differing claim, since "Barraka —
    /// says Ben Lost" alone doesn't say whose claim it is.
    @Test func differsButKeptNamesTheProviderMakingTheDifferingClaim() {
        let comparison = MatchComparison(
            field: .artist, currentValue: "Barraka", matchValue: "Ben Lost",
            unavailableNote: nil, outcome: .differsButKept)
        let (discogsText, _) = ApplyFoundMatchesSheetView.changeSummaryText(comparison, provider: .discogs)
        let (mbText, _) = ApplyFoundMatchesSheetView.changeSummaryText(comparison, provider: .musicBrainz)
        #expect(discogsText.contains("Discogs"))
        #expect(mbText.contains("MusicBrainz"))
    }

    @Test func differsButKeptStillNamesBothRealValues() {
        let comparison = MatchComparison(
            field: .artist, currentValue: "Barraka", matchValue: "Ben Lost",
            unavailableNote: nil, outcome: .differsButKept)
        let (text, label) = ApplyFoundMatchesSheetView.changeSummaryText(comparison, provider: .discogs)
        #expect(text.contains("Barraka"))
        #expect(text.contains("Ben Lost"))
        #expect(label == "kept (already set)")
    }

    // MARK: - displayValue

    @Test func displayValueShowsAnEmDashForAMissingNonArtworkValue() {
        let comparison = MatchComparison(
            field: .year, currentValue: nil, matchValue: "2014", unavailableNote: nil, outcome: .willFill)
        #expect(ApplyFoundMatchesSheetView.displayValue(comparison, isMatch: false) == "–")
    }

    @Test func displayValueUsesPresenceWordsForArtwork() {
        let present = MatchComparison(
            field: .artwork, currentValue: "Present", matchValue: nil, unavailableNote: nil, outcome: .noMatchData)
        #expect(ApplyFoundMatchesSheetView.displayValue(present, isMatch: false) == "cover")
        #expect(ApplyFoundMatchesSheetView.displayValue(present, isMatch: true) == "none")
    }

    // MARK: - Fixtures

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
