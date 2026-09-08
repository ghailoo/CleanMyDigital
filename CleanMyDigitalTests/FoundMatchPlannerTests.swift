//
//  FoundMatchPlannerTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

/// Verifies `FoundMatchPlanner.groups(targets:albumGroups:)` — the
/// folder-grouping behind `ApplyFoundMatchesSheetView`, including which
/// folders get a group-level `AlbumGroup` (the "re-match this whole
/// folder" control) and which don't.
struct FoundMatchPlannerTests {
    @Test func groupsFilesByTheirContainingFolder() throws {
        let trackA = Self.makeFile(path: "/Music/Artist/Album/01 Track A.mp3")
        let trackB = Self.makeFile(path: "/Music/Artist/Album/02 Track B.mp3")
        let other = Self.makeFile(path: "/Music/Other Artist/Other Album/01 Track.mp3")

        let groups = FoundMatchPlanner.groups(targets: [trackA, trackB, other], albumGroups: [])

        #expect(groups.count == 2)
        let albumFolder = try #require(groups.first { $0.folderURL.lastPathComponent == "Album" })
        #expect(albumFolder.files.count == 2)
    }

    @Test func groupsPreserveFirstSeenFolderOrder() {
        let first = Self.makeFile(path: "/Music/B Artist/Album/01 Track.mp3")
        let second = Self.makeFile(path: "/Music/A Artist/Album/01 Track.mp3")

        let groups = FoundMatchPlanner.groups(targets: [first, second], albumGroups: [])

        #expect(groups.map(\.folderURL.lastPathComponent) == ["Album", "Album"])
        // Distinguish the two same-named-leaf folders by their full path
        // instead, since `lastPathComponent` collides here.
        #expect(groups.first?.folderURL.path.contains("B Artist") == true)
        #expect(groups.last?.folderURL.path.contains("A Artist") == true)
    }

    // MARK: - albumGroup: present for Albums/Compilations, nil for Singles

    @Test func albumGroupIsAttachedWhenAnAlbumCompletenessGroupExistsForTheFolder() {
        let file = Self.makeFile(path: "/Music/Artist/Album/01 Track.mp3", category: .albums)
        // Derived the same way `FoundMatchPlanner`/`AlbumCompletenessChecker`
        // themselves derive a folder key, rather than a separately
        // hand-built `URL(fileURLWithPath:)` — otherwise a trailing-slash
        // ("directory-hinted" vs. not) difference between the two makes
        // them compare unequal as dictionary keys even though they denote
        // the same folder.
        let folder = file.url.deletingLastPathComponent().standardizedFileURL
        let albumGroup = Self.makeAlbumGroup(folderURL: folder, category: .albums)

        let groups = FoundMatchPlanner.groups(targets: [file], albumGroups: [albumGroup])

        #expect(groups.first?.albumGroup?.folderURL == folder)
        #expect(groups.first?.albumGroup?.category == .albums)
    }

    @Test func albumGroupIsAttachedForACompilationFolderToo() {
        let file = Self.makeFile(path: "/Music/Compilations/DJ Hits 97-1/01 Track.mp3", category: .compilations)
        let folder = file.url.deletingLastPathComponent().standardizedFileURL
        let albumGroup = Self.makeAlbumGroup(folderURL: folder, category: .compilations)

        let groups = FoundMatchPlanner.groups(targets: [file], albumGroups: [albumGroup])

        #expect(groups.first?.albumGroup?.category == .compilations)
    }

    /// The real case this exists for: Singles has no `AlbumCompletenessChecker`
    /// group at all (it only ever produces Albums/Compilations groups), so
    /// passing an empty `albumGroups` — exactly what a Singles scan
    /// produces — naturally leaves every Singles folder's `albumGroup` nil.
    /// No per-category branching needed in the planner itself.
    @Test func albumGroupIsNilWhenNoMatchingAlbumCompletenessGroupExists() {
        let file = Self.makeFile(path: "/Music/Loose Singles/track.mp3", category: .singles)

        let groups = FoundMatchPlanner.groups(targets: [file], albumGroups: [])

        #expect(groups.first?.albumGroup == nil)
    }

    /// A folder-name coincidence elsewhere shouldn't attach the wrong
    /// group — `albumGroup` is looked up by exact folder URL.
    @Test func albumGroupDoesNotLeakAcrossDifferentFolders() {
        let file = Self.makeFile(path: "/Music/Artist/Album/01 Track.mp3", category: .albums)
        let unrelatedGroup = Self.makeAlbumGroup(
            folderURL: URL(fileURLWithPath: "/Music/Someone Else/Album"), category: .albums)

        let groups = FoundMatchPlanner.groups(targets: [file], albumGroups: [unrelatedGroup])

        #expect(groups.first?.albumGroup == nil)
    }

    // MARK: - Fixtures

    private static func makeFile(path: String, category: LibraryCategory = .albums) -> AudioFile {
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

    private static func makeAlbumGroup(folderURL: URL, category: LibraryCategory) -> AlbumGroup {
        AlbumGroup(
            folderURL: folderURL,
            category: category,
            artist: "Artist",
            albumTitle: "Album",
            year: "1998",
            files: [],
            expectedTotalFromTags: nil,
            presentPositions: []
        )
    }
}
