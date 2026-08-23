//
//  AlbumFolderRenamePlannerTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

struct AlbumFolderRenamePlannerTests {
    @Test func proposesAlbumTitleAndYearAsFolderName() {
        let group = Self.makeGroup(
            path: "/Library/Albums/C + C Music Factory/1995 - C + C Music Factory",
            albumTitle: "C+C Music Factory", year: "1995")

        let proposals = AlbumFolderRenamePlanner.plan(for: [group])
        #expect(proposals.count == 1)
        #expect(proposals.first?.currentFolderName == "1995 - C + C Music Factory")
        #expect(proposals.first?.proposedFolderName == "C+C Music Factory (1995)")
    }

    @Test func missingAlbumTitleGetsNoProposal() {
        let group = Self.makeGroup(
            path: "/Library/Albums/Artist/Folder", albumTitle: nil, year: "1995")
        #expect(AlbumFolderRenamePlanner.plan(for: [group]).isEmpty)
    }

    @Test func missingYearGetsNoProposal() {
        let group = Self.makeGroup(
            path: "/Library/Albums/Artist/Folder", albumTitle: "Album", year: nil)
        #expect(AlbumFolderRenamePlanner.plan(for: [group]).isEmpty)
    }

    @Test func alreadyCorrectlyNamedFolderGetsNoProposal() {
        let group = Self.makeGroup(
            path: "/Library/Albums/Artist/Album (1995)", albumTitle: "Album", year: "1995")
        #expect(AlbumFolderRenamePlanner.plan(for: [group]).isEmpty)
    }

    @Test func sanitizesSlashesColonsAndWhitespace() {
        let group = Self.makeGroup(
            path: "/Library/Albums/AC-DC/Folder",
            albumTitle: "Rock  /  Roll:   Ain't    Noise   Pollution", year: "1979")

        let proposals = AlbumFolderRenamePlanner.plan(for: [group])
        #expect(proposals.first?.proposedFolderName == "Rock - Roll- Ain't Noise Pollution (1979)")
    }

    @Test func collidingProposalsFromTwoSiblingFoldersGetSuffixed() {
        let pressingA = Self.makeGroup(
            path: "/Library/Albums/Artist/Pressing A", albumTitle: "Album", year: "1995")
        let pressingB = Self.makeGroup(
            path: "/Library/Albums/Artist/Pressing B", albumTitle: "Album", year: "1995")

        let proposals = AlbumFolderRenamePlanner.plan(for: [pressingA, pressingB])
            .sorted { $0.currentFolderName < $1.currentFolderName }
        #expect(proposals.count == 2)
        #expect(proposals[0].currentFolderName == "Pressing A")
        #expect(proposals[0].proposedFolderName == "Album (1995)")
        #expect(proposals[1].currentFolderName == "Pressing B")
        #expect(proposals[1].proposedFolderName == "Album (1995) (2)")
    }

    @Test func collidesWithAnAlreadyCorrectlyNamedSibling() {
        // "Album (1995)" already exists and keeps its name (its own tags
        // already match); the other folder's proposal must not clobber it.
        let alreadyNamed = Self.makeGroup(
            path: "/Library/Albums/Artist/Album (1995)", albumTitle: "Album", year: "1995")
        let toRename = Self.makeGroup(
            path: "/Library/Albums/Artist/Original Folder", albumTitle: "Album", year: "1995")

        let proposals = AlbumFolderRenamePlanner.plan(for: [alreadyNamed, toRename])
        #expect(proposals.count == 1)
        #expect(proposals.first?.currentFolderName == "Original Folder")
        #expect(proposals.first?.proposedFolderName == "Album (1995) (2)")
    }

    @Test func differentParentFoldersDoNotCollideWithEachOther() {
        let groupA = Self.makeGroup(
            path: "/Library/Albums/Artist1/Folder", albumTitle: "Album", year: "1995")
        let groupB = Self.makeGroup(
            path: "/Library/Albums/Artist2/Folder", albumTitle: "Album", year: "1995")

        let proposals = AlbumFolderRenamePlanner.plan(for: [groupA, groupB])
        #expect(proposals.count == 2)
        #expect(proposals.allSatisfy { $0.proposedFolderName == "Album (1995)" })
    }

    // MARK: - Fixture

    private static func makeGroup(path: String, albumTitle: String?, year: String?) -> AlbumGroup {
        AlbumGroup(
            folderURL: URL(fileURLWithPath: path),
            artist: "Artist",
            albumTitle: albumTitle,
            year: year,
            files: [],
            expectedTotalFromTags: nil,
            presentPositions: []
        )
    }
}
